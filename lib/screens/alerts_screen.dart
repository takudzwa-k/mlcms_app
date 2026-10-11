import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/fridge.dart';
import '../services/alert_state.dart';
import '../services/fridge_service.dart';
import '../services/history.dart';
import '../theme/app_theme.dart';
import '../widgets/history_builder.dart';
import '../widgets/motion.dart';
import '../widgets/surfaces.dart';
import 'fridge_detail_screen.dart';

// ---------- Helpers ----------

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String _two(int n) => n.toString().padLeft(2, '0');

String _dateTime(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  return '${d.day} ${_months[d.month - 1]}, ${_two(d.hour)}:${_two(d.minute)}';
}

String _signed(double v) => '${v >= 0 ? '+' : ''}${v.toStringAsFixed(1)}';

String _stageLabel(BreachStage s) => switch (s) {
      BreachStage.detect => 'Detected',
      BreachStage.respond => 'Responding',
      BreachStage.escalate => 'Escalated',
      BreachStage.diagnose => 'Diagnose',
    };

Color _stageColor(BreachStage s) =>
    s == BreachStage.diagnose ? AppColors.purple : AppColors.warn;

Fridge? _find(List<Fridge> list, String id) {
  for (final f in list) {
    if (f.id == id) return f;
  }
  return null;
}

/// One entry in the Alerts feed.
class _AlertEvent {
  final String id;
  final int t;
  final String fridgeId;
  final bool resolved;
  final String message;

  const _AlertEvent({
    required this.id,
    required this.t,
    required this.fridgeId,
    required this.resolved,
    required this.message,
  });
}

/// Every incident produces a "detected" event, and a "resolved" event once
/// the unit is back inside its safe range. Newest first.
List<_AlertEvent> _eventsFrom(List<Incident> incidents) {
  final out = <_AlertEvent>[];

  for (final i in incidents) {
    out.add(
      _AlertEvent(
        id: '${i.fridgeId}_${i.startMs}_start',
        t: i.startMs,
        fridgeId: i.fridgeId,
        resolved: false,
        message:
            'Breach detected: ${i.fridgeName} went ${i.above ? 'above' : 'below'} its safe range.',
      ),
    );
    if (!i.open) {
      out.add(
        _AlertEvent(
          id: '${i.fridgeId}_${i.startMs}_end',
          t: i.endMs,
          fridgeId: i.fridgeId,
          resolved: true,
          message: 'Breach resolved: ${i.fridgeName} back in safe range.',
        ),
      );
    }
  }

  out.sort((a, b) => b.t.compareTo(a.t));
  return out;
}

// ---------- The screen ----------

class AlertsScreen extends StatefulWidget {
  const AlertsScreen({super.key});

  @override
  State<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends State<AlertsScreen> {
  late final Stream<List<Fridge>> _fridges = FridgeService().fridgesStream;
  late final Stream<int> _readAt = AlertState.readAtStream();
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    // Refreshes durations such as "32 min" while the app stays open
    _tick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  // Tells the tab bar how many alerts are unread
  void _publish(int unread) {
    if (AlertState.unread.value == unread) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) AlertState.unread.value = unread;
    });
  }

  Future<void> _markAllRead() async {
    HapticFeedback.selectionClick();
    try {
      await AlertState.markAllRead();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not update. Check your connection.')),
      );
    }
  }

  Widget _page({required int unread, required Widget body}) {
    return Column(
      children: [
        _AlertsHeader(
          unread: unread,
          onMarkAllRead: unread > 0 ? _markAllRead : null,
        ),
        Expanded(child: body),
      ],
    );
  }

  Widget get _spinner => const Center(child: CircularProgressIndicator());

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        body: StreamBuilder<List<Fridge>>(
          stream: _fridges,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting &&
                !snapshot.hasData) {
              return _page(unread: 0, body: _spinner);
            }

            final fridges = snapshot.data ?? <Fridge>[];
            if (fridges.isEmpty) {
              _publish(0);
              return _page(
                unread: 0,
                body: const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text(
                      'No fridges yet.\nAdd a unit from the Dashboard first.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              );
            }

            return HistoryBuilder(
              fridges: fridges,
              builder: (context, history, loading) {
                if (loading) return _page(unread: 0, body: _spinner);

                return StreamBuilder<int>(
                  stream: _readAt,
                  builder: (context, readSnap) {
                    if (readSnap.connectionState == ConnectionState.waiting &&
                        !readSnap.hasData) {
                      return _page(unread: 0, body: _spinner);
                    }

                    final readAt = readSnap.data ?? 0;
                    final nowMs = DateTime.now().millisecondsSinceEpoch;

                    final stats = [
                      for (final f in fridges)
                        computeStats(f, history[f.id] ?? const <Reading>[], nowMs),
                    ];
                    final incidents = [for (final s in stats) ...s.incidents];
                    final events = _eventsFrom(incidents);
                    final unread = events.where((e) => e.t > readAt).length;
                    final hasHistory = history.values.any((l) => l.isNotEmpty);

                    _publish(unread);

                    return _page(
                      unread: unread,
                      body: TabBarView(
                        children: [
                          _AlertsTab(
                            events: events,
                            readAt: readAt,
                            fridges: fridges,
                            hasHistory: hasHistory,
                          ),
                          _IncidentsTab(
                            incidents: incidents,
                            fridges: fridges,
                            history: history,
                            hasHistory: hasHistory,
                            nowMs: nowMs,
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            );
          },
        ),
      ),
    );
  }
}

// ---------- Header with tabs ----------

class _AlertsHeader extends StatelessWidget {
  final int unread;
  final VoidCallback? onMarkAllRead;

  const _AlertsHeader({required this.unread, required this.onMarkAllRead});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: dark
              ? const [Color(0xFF15383B), Color(0xFF112A2D)]
              : const [Color(0xFFD3E9E3), Color(0xFFE6F3EF)],
        ),
        border: Border(
          bottom: BorderSide(color: AppColors.teal.withAlpha(dark ? 70 : 45)),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 8, 0),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Alerts & Incidents',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                    ),
                  ),
                  SizedBox(
                    height: 40,
                    child: onMarkAllRead == null
                        ? null
                        : TextButton(
                            onPressed: onMarkAllRead,
                            style: TextButton.styleFrom(
                              foregroundColor: AppColors.teal,
                              minimumSize: const Size(0, 36),
                            ),
                            child: const Text(
                              'Mark all read',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                  ),
                ],
              ),
            ),
            Material(
              color: Colors.transparent,
              child: TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                indicatorColor: AppColors.teal,
                indicatorWeight: 3,
                indicatorSize: TabBarIndicatorSize.label,
                labelColor: AppColors.teal,
                unselectedLabelColor: Colors.grey.shade600,
                dividerColor: Colors.transparent,
                labelStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                unselectedLabelStyle:
                    const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                tabs: [
                  Tab(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('Alerts'),
                        if (unread > 0) ...[
                          const SizedBox(width: 6),
                          _CountBadge(unread),
                        ],
                      ],
                    ),
                  ),
                  const Tab(text: 'Incidents'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  final int count;

  const _CountBadge(this.count);

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 18),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
      decoration: BoxDecoration(
        color: AppColors.danger,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        count > 99 ? '99+' : '$count',
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

// ---------- Shared pieces ----------

class _Panel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const _Panel({required this.child, this.padding = const EdgeInsets.all(16)});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: appSurface(context),
        borderRadius: BorderRadius.circular(18),
        boxShadow: softShadow(context),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

class _DashedPainter extends CustomPainter {
  final Color color;

  const _DashedPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;

    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(18),
    ).deflate(1);
    final path = Path()..addRRect(rrect);

    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        canvas.drawPath(
          metric.extractPath(d, math.min(d + 6, metric.length)),
          paint,
        );
        d += 11;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedPainter old) => old.color != color;
}

/// The dashed "all caught up" / empty-state tile.
class _CaughtUp extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _CaughtUp({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;

    return SizedBox(
      width: double.infinity,
      child: CustomPaint(
        painter: _DashedPainter(dark ? Colors.white24 : const Color(0xFFC6CCC4)),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 20),
          child: Column(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: dark ? Colors.white10 : AppColors.selected,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 22, color: AppColors.teal),
              ),
              const SizedBox(height: 12),
              Text(
                title,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, height: 1.35, color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------- Alerts tab ----------

class _AlertsTab extends StatelessWidget {
  final List<_AlertEvent> events;
  final int readAt;
  final List<Fridge> fridges;
  final bool hasHistory;

  const _AlertsTab({
    required this.events,
    required this.readAt,
    required this.fridges,
    required this.hasHistory,
  });

  @override
  Widget build(BuildContext context) {
    final unreadCount = events.where((e) => e.t > readAt).length;

    if (events.isEmpty) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 32),
        children: [
          _CaughtUp(
            icon: Icons.notifications_none,
            title: "You're all caught up",
            subtitle: hasHistory
                ? 'New cold-chain alerts will appear here.'
                : 'No history yet. Alerts appear once your units start reporting.',
          ),
        ],
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 32),
      children: [
        FadeSlideIn(
          index: 0,
          child: _Panel(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (var i = 0; i < events.length; i++) ...[
                  _AlertRow(
                    event: events[i],
                    unread: events[i].t > readAt,
                    onTap: () {
                      final f = _find(fridges, events[i].fridgeId);
                      if (f == null) return;
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => FridgeDetailScreen(fridge: f),
                        ),
                      );
                    },
                  ),
                  if (i != events.length - 1)
                    const Divider(height: 1, indent: 16, endIndent: 16),
                ],
              ],
            ),
          ),
        ),
        if (unreadCount == 0) ...[
          const SizedBox(height: 16),
          const _CaughtUp(
            icon: Icons.notifications_none,
            title: "You're all caught up",
            subtitle: 'New cold-chain alerts will appear here.',
          ),
        ],
      ],
    );
  }
}

class _AlertRow extends StatelessWidget {
  final _AlertEvent event;
  final bool unread;
  final VoidCallback onTap;

  const _AlertRow({
    required this.event,
    required this.unread,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final accent = event.resolved ? AppColors.ok : AppColors.danger;
    final tint = dark ? AppColors.teal.withAlpha(26) : const Color(0xFFF1F8F5);

    return Material(
      color: unread ? tint : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: accent.withAlpha(30),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  event.resolved ? Icons.check_rounded : Icons.warning_amber_rounded,
                  size: 20,
                  color: accent,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      event.message,
                      style: TextStyle(
                        fontSize: 14.5,
                        height: 1.35,
                        fontWeight: unread ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        Icon(Icons.schedule, size: 13, color: Colors.grey.shade600),
                        const SizedBox(width: 4),
                        Text(
                          _dateTime(event.t),
                          style: AppTheme.mono(
                            size: 11.5,
                            weight: FontWeight.w500,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (unread)
                Padding(
                  padding: const EdgeInsets.only(left: 10, top: 6),
                  child: Container(
                    width: 9,
                    height: 9,
                    decoration: const BoxDecoration(
                      color: AppColors.teal,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------- Incidents tab ----------

class _IncidentsTab extends StatefulWidget {
  final List<Incident> incidents;
  final List<Fridge> fridges;
  final Map<String, List<Reading>> history;
  final bool hasHistory;
  final int nowMs;

  const _IncidentsTab({
    required this.incidents,
    required this.fridges,
    required this.history,
    required this.hasHistory,
    required this.nowMs,
  });

  @override
  State<_IncidentsTab> createState() => _IncidentsTabState();
}

class _IncidentsTabState extends State<_IncidentsTab> {
  final _expanded = <String>{};

  String _id(Incident i) => '${i.fridgeId}_${i.startMs}';

  @override
  Widget build(BuildContext context) {
    // Open incidents first, then newest first
    final list = [...widget.incidents]..sort((a, b) {
        if (a.open != b.open) return a.open ? -1 : 1;
        return b.startMs.compareTo(a.startMs);
      });

    if (list.isEmpty) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 32),
        children: [
          _CaughtUp(
            icon: Icons.check_circle_outline,
            title: 'No incidents',
            subtitle: widget.hasHistory
                ? 'Nothing went outside its safe range in the last 24 hours.'
                : 'No history yet. Incidents appear once your units start reporting.',
          ),
        ],
      );
    }

    final openCount = list.where((i) => i.open).length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 32),
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 12),
          child: Text(
            '${list.length} ${list.length == 1 ? 'incident' : 'incidents'} in the last 24 hours · $openCount open',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
          ),
        ),
        for (var n = 0; n < list.length; n++)
          FadeSlideIn(
            key: ValueKey(_id(list[n])),
            index: n,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _IncidentCard(
                incident: list[n],
                fridge: _find(widget.fridges, list[n].fridgeId),
                readings: widget.history[list[n].fridgeId] ?? const <Reading>[],
                nowMs: widget.nowMs,
                expanded: _expanded.contains(_id(list[n])),
                onToggle: () {
                  HapticFeedback.selectionClick();
                  setState(() {
                    final id = _id(list[n]);
                    if (!_expanded.remove(id)) _expanded.add(id);
                  });
                },
              ),
            ),
          ),
      ],
    );
  }
}

class _IncidentCard extends StatelessWidget {
  final Incident incident;
  final Fridge? fridge;
  final List<Reading> readings;
  final int nowMs;
  final bool expanded;
  final VoidCallback onToggle;

  const _IncidentCard({
    required this.incident,
    required this.fridge,
    required this.readings,
    required this.nowMs,
    required this.expanded,
    required this.onToggle,
  });

  Widget _detail(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 104,
            child: Text(
              label,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, height: 1.3),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final open = incident.open;
    final minutes =
        open ? ((nowMs - incident.startMs) / 60000).round() : incident.minutes;
    final stage = stageForMinutes(minutes);
    final pillLabel = open ? _stageLabel(stage) : 'Resolved';
    final pillColor = open ? _stageColor(stage) : AppColors.ok;
    final accent = open ? AppColors.danger : AppColors.ok;

    final f = fridge;
    final doorOpen = readings.any(
      (r) => r.door && r.t >= incident.startMs && r.t <= incident.endMs,
    );

    var peakText = '${_signed(incident.peak)}°C';
    if (f != null) {
      final dev = incident.above
          ? incident.peak - f.maxTemp
          : f.minTemp - incident.peak;
      peakText +=
          ' (${dev.toStringAsFixed(1)}° ${incident.above ? 'above max' : 'below min'})';
    }

    String ackText = 'Not yet acknowledged';
    if (f != null && f.ackAt > 0 && f.ackAt >= incident.startMs) {
      ackText = f.ackBy.isEmpty ? 'Acknowledged' : 'By ${f.ackBy}';
    }

    return Container(
      decoration: BoxDecoration(
        color: open ? null : appSurface(context),
        gradient: open ? alertGradient(context, fadeTo: 0.6) : null,
        borderRadius: BorderRadius.circular(18),
        boxShadow: softShadow(context),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: onToggle,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: open
                            ? Colors.white.withAlpha(190)
                            : accent.withAlpha(30),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        open ? Icons.warning_amber_rounded : Icons.check_rounded,
                        size: 22,
                        color: accent,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  incident.fridgeName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 15.5,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.teal,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: open
                                      ? Colors.white.withAlpha(200)
                                      : pillColor.withAlpha(30),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  pillLabel,
                                  style: TextStyle(
                                    color: pillColor,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 2),
                              AnimatedRotation(
                                turns: expanded ? 0.5 : 0,
                                duration: const Duration(milliseconds: 220),
                                child: Icon(
                                  Icons.keyboard_arrow_down,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 16,
                            runSpacing: 4,
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.thermostat, size: 14, color: Colors.grey.shade600),
                                  const SizedBox(width: 3),
                                  Text(
                                    'Peak: ${_signed(incident.peak)}°C',
                                    style: AppTheme.mono(
                                      size: 12,
                                      weight: FontWeight.w500,
                                      color: Colors.grey.shade700,
                                    ),
                                  ),
                                ],
                              ),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.schedule, size: 14, color: Colors.grey.shade600),
                                  const SizedBox(width: 3),
                                  Text(
                                    '$minutes min',
                                    style: AppTheme.mono(
                                      size: 12,
                                      weight: FontWeight.w500,
                                      color: Colors.grey.shade700,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOut,
              alignment: Alignment.topCenter,
              child: expanded
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Divider(height: 1),
                          const SizedBox(height: 8),
                          _detail('Started', _dateTime(incident.startMs)),
                          _detail('Ended', open ? 'Ongoing' : _dateTime(incident.endMs)),
                          _detail('Peak', peakText),
                          _detail(
                            'Door',
                            doorOpen ? 'Open during this period' : 'Closed throughout',
                          ),
                          if (open) _detail('Acknowledged', ackText),
                          if (f != null) ...[
                            const SizedBox(height: 10),
                            OutlinedButton.icon(
                              onPressed: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => FridgeDetailScreen(fridge: f),
                                ),
                              ),
                              icon: const Icon(Icons.arrow_forward, size: 18),
                              label: const Text('View unit'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.teal,
                                side: BorderSide(color: AppColors.teal.withAlpha(120)),
                                minimumSize: const Size(double.infinity, 46),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    )
                  : const SizedBox(width: double.infinity),
            ),
          ],
        ),
      ),
    );
  }
}