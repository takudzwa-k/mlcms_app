import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/fridge.dart';
import '../services/auth_service.dart';
import '../services/fridge_service.dart';
import '../services/history.dart';
import '../theme/app_theme.dart';
import '../widgets/history_builder.dart';
import '../widgets/motion.dart';
import '../widgets/surfaces.dart';
import 'edit_fridge_screen.dart';

// ---------- Formatting helpers ----------

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String _signed(double v, {int digits = 1}) =>
    '${v >= 0 ? '+' : ''}${v.toStringAsFixed(digits)}';

// +2°C / -25°C (drops the decimal when it's a whole number)
String _limit(double v) {
  final text = v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
  return '${v >= 0 ? '+' : ''}$text°C';
}

String _two(int n) => n.toString().padLeft(2, '0');

String _hhmm(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  return '${_two(d.hour)}:${_two(d.minute)}';
}

String _dateTime(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  return '${d.day} ${_months[d.month - 1]}, ${_hhmm(ms)}';
}

// 47m / 2h 5m
String _durationShort(int minutes) {
  if (minutes < 1) return '<1m';
  if (minutes < 60) return '${minutes}m';
  final h = minutes ~/ 60;
  final m = minutes % 60;
  return m == 0 ? '${h}h' : '${h}h ${m}m';
}

// just now / 12s ago / 3 min ago / 2 h ago
String _agoSeconds(int s) {
  if (s < 5) return 'just now';
  if (s < 60) return '${s}s ago';
  final m = s ~/ 60;
  if (m < 60) return '$m min ago';
  final h = m ~/ 60;
  if (h < 24) return '$h h ago';
  return '${h ~/ 24} d ago';
}

// 27 min ago / 1 h 12 min ago
String _agoMinutes(int m) {
  if (m < 1) return 'less than a minute ago';
  if (m < 60) return '$m min ago';
  final rest = m % 60;
  return rest == 0 ? '${m ~/ 60} h ago' : '${m ~/ 60} h $rest min ago';
}

String _stageLabel(BreachStage s) => switch (s) {
      BreachStage.detect => 'Detected',
      BreachStage.respond => 'Responding',
      BreachStage.escalate => 'Escalated',
      BreachStage.diagnose => 'Diagnose',
    };

Color _stageColor(BreachStage s) =>
    s == BreachStage.diagnose ? AppColors.purple : AppColors.warn;

String _advice(Fridge f) {
  if (f.temperature > f.maxTemp) {
    return 'Increase compressor cooling one notch. If no improvement in 5 min, transfer samples.';
  }
  return 'Reduce cooling one notch to avoid freezing the contents. If no improvement in 5 min, move samples.';
}

String _levelLabel(int l) {
  if (l == 0) return 'Neutral';
  return l < 0 ? 'Cooling ${-l}/3' : 'Warming $l/3';
}

int _clampLevel(int v) => v < -3 ? -3 : (v > 3 ? 3 : v);

// ---------- The screen ----------

class FridgeDetailScreen extends StatefulWidget {
  final Fridge fridge;

  const FridgeDetailScreen({super.key, required this.fridge});

  @override
  State<FridgeDetailScreen> createState() => _FridgeDetailScreenState();
}

class _FridgeDetailScreenState extends State<FridgeDetailScreen> {
  late final Stream<Fridge?> _stream =
      FridgeService().fridgeStream(widget.fridge.id);
  Timer? _tick;
  String _userName = '';
  bool _isSupervisor = false;

  @override
  void initState() {
    super.initState();
    // Re-draws once a second so "synced 3s ago" and durations stay current
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    _loadUser();
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _loadUser() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final data = await AuthService().getUserData(user.uid);
      final name = (data?['name'] ?? '').toString().trim();
      final role = (data?['role'] ?? '').toString();
      if (!mounted) return;
      setState(() {
        _userName = name.isNotEmpty ? name : (user.email ?? 'Unknown').split('@').first;
        _isSupervisor = role == 'supervisor';
      });
    } catch (_) {
      // leave the defaults: no name, view-only
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Fridge?>(
      stream: _stream,
      initialData: widget.fridge,
      builder: (context, snapshot) {
        final f = snapshot.data;
        if (f == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const Center(child: Text('This unit no longer exists.')),
          );
        }

        return HistoryBuilder(
          fridges: [f],
          builder: (context, history, loading) => _buildContent(
            context,
            f,
            history[f.id] ?? const <Reading>[],
            loading,
          ),
        );
      },
    );
  }

  Widget _buildContent(
    BuildContext context,
    Fridge f,
    List<Reading> readings,
    bool loadingHistory,
  ) {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final stats = computeStats(f, readings, nowMs);

    Incident? openIncident;
    for (final i in stats.incidents) {
      if (i.open) openIncident = i;
    }
    final open = openIncident;

    final breaching = f.isBreaching;
    final minutes = open == null ? null : ((nowMs - open.startMs) / 60000).floor();
    final stage = minutes == null ? BreachStage.detect : stageForMinutes(minutes);
    final acked = f.ackAt > 0 && (open == null || f.ackAt >= open.startMs);
    final rate = rateOfChange(readings, nowMs);
    final doorMinutes = doorStateMinutes(readings, f.doorOpen, nowMs);
    final bottom = MediaQuery.of(context).padding.bottom;

    final state = f.doorOpen ? 'Open' : 'Closed';
    String doorCaption;
    if (doorMinutes != null) {
      doorCaption = '$state for ${_durationShort(doorMinutes)}';
    } else if (readings.isNotEmpty) {
      final span = ((nowMs - readings.first.t) / 60000).round();
      doorCaption = '$state for ${_durationShort(span)}+';
    } else {
      doorCaption = loadingHistory ? 'Loading…' : 'No history yet';
    }

    return Scaffold(
      body: Column(
        children: [
          _DetailHeader(
            fridge: f,
            breaching: breaching,
            stage: stage,
            nowMs: nowMs,
            doorCaption: doorCaption,
            onEdit: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => EditFridgeScreen(fridge: f)),
            ),
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.fromLTRB(16, 18, 16, bottom + 32),
              children: [
                if (breaching) ...[
                  FadeSlideIn(
                    key: const ValueKey('escalation'),
                    index: 0,
                    child: _EscalationCard(
                      stage: stage,
                      minutes: minutes,
                      acked: acked,
                      ackBy: f.ackBy,
                    ),
                  ),
                  const SizedBox(height: 16),
                  FadeSlideIn(
                    key: const ValueKey('recommendation'),
                    index: 1,
                    child: _RecommendationCard(fridge: f, rate: rate),
                  ),
                  const SizedBox(height: 16),
                  FadeSlideIn(
                    key: const ValueKey('actions'),
                    index: 2,
                    child: _ActionsCard(
                      fridge: f,
                      userName: _userName,
                      acked: acked,
                      nowMs: nowMs,
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                _CoolingSection(
                  key: const ValueKey('cooling'),
                  fridge: f,
                  userName: _userName,
                  isSupervisor: _isSupervisor,
                  collapsible: !breaching,
                ),
                const SizedBox(height: 16),
                _TrendCard(
                  key: const ValueKey('trend'),
                  fridge: f,
                  readings: readings,
                  nowMs: nowMs,
                  loading: loadingHistory,
                ),
                const SizedBox(height: 16),
                _IncidentLog(
                  key: const ValueKey('incidents'),
                  fridge: f,
                  incidents: stats.incidents,
                  readings: readings,
                  nowMs: nowMs,
                  loading: loadingHistory,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------- Shared building blocks ----------

class _Card extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Gradient? gradient;

  const _Card({
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.gradient,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: gradient == null ? appSurface(context) : null,
        gradient: gradient,
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

class _CardLabel extends StatelessWidget {
  final String text;

  const _CardLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 11.5,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.1,
        color: Colors.grey.shade600,
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String label;
  final Color color;

  const _Pill({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withAlpha(34),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(color: color, fontSize: 12.5, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _SoftButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final IconData? trailing;
  final VoidCallback? onTap;

  const _SoftButton({
    required this.icon,
    required this.label,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;

    return Material(
      color: dark ? Colors.white10 : const Color(0xFFE9ECE6),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: SizedBox(
          height: 50,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 19),
              const SizedBox(width: 8),
              Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
              if (trailing != null) ...[
                const SizedBox(width: 4),
                Icon(trailing, size: 20),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ---------- Header ----------

class _DetailHeader extends StatelessWidget {
  final Fridge fridge;
  final bool breaching;
  final BreachStage stage;
  final int nowMs;
  final String doorCaption;
  final VoidCallback onEdit;

  const _DetailHeader({
    required this.fridge,
    required this.breaching,
    required this.stage,
    required this.nowMs,
    required this.doorCaption,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final f = fridge;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final hasData = f.hasData;
    final seconds = hasData ? ((nowMs - f.lastSeen) / 1000).round() : 0;
    final live = hasData && seconds < 300;
    final statusColor =
        breaching ? AppColors.danger : (hasData ? AppColors.ok : Colors.grey);

    final List<Color> bg;
    if (breaching) {
      bg = dark
          ? const [Color(0xFF3A2528), Color(0xFF2A1C1F)]
          : const [Color(0xFFF8DAD6), Color(0xFFFBEBE8)];
    } else if (hasData) {
      bg = dark
          ? const [Color(0xFF15383B), Color(0xFF112A2D)]
          : const [Color(0xFFD3E9E3), Color(0xFFE6F3EF)];
    } else {
      bg = dark
          ? const [Color(0xFF232B2D), Color(0xFF1B2224)]
          : const [Color(0xFFE4E5DD), Color(0xFFEFEEE8)];
    }

    final String pillLabel;
    final Color pillColor;
    if (breaching) {
      pillLabel = _stageLabel(stage);
      pillColor = _stageColor(stage);
    } else if (hasData) {
      pillLabel = 'In Range';
      pillColor = AppColors.ok;
    } else {
      pillLabel = 'Awaiting data';
      pillColor = Colors.grey;
    }

    final syncText = hasData
        ? 'Synced ${_agoSeconds(seconds)}'
        : 'No data received yet';

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: bg,
        ),
        border: Border(
          bottom: BorderSide(color: statusColor.withAlpha(dark ? 80 : 50)),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => Navigator.maybePop(context),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.arrow_back, size: 18),
                      const SizedBox(width: 6),
                      Text(
                        'Back',
                        style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            f.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Material(
                          color: Colors.white.withAlpha(dark ? 24 : 170),
                          borderRadius: BorderRadius.circular(10),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(10),
                            onTap: onEdit,
                            child: const SizedBox(
                              width: 34,
                              height: 34,
                              child: Icon(Icons.edit_outlined, size: 17),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  _Pill(label: pillLabel, color: pillColor),
                ],
              ),
              const SizedBox(height: 2),
              Text(f.location, style: TextStyle(fontSize: 13.5, color: Colors.grey.shade700)),
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(Icons.sensors, size: 13, color: Colors.grey.shade600),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      'Sensor: ${f.model} · ID ${f.id}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.mono(
                        size: 11,
                        weight: FontWeight.w500,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Icon(Icons.thermostat, size: 22, color: Colors.grey.shade600),
                  ),
                  const SizedBox(width: 2),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          hasData
                              ? TweenAnimationBuilder<double>(
                                  tween: Tween<double>(end: f.temperature),
                                  duration: const Duration(milliseconds: 700),
                                  curve: Curves.easeOutCubic,
                                  builder: (context, v, _) => Text(
                                    _signed(v),
                                    style: AppTheme.mono(size: 54, color: statusColor),
                                  ),
                                )
                              : Text('--.-', style: AppTheme.mono(size: 54, color: statusColor)),
                          Padding(
                            padding: const EdgeInsets.only(top: 12, left: 3),
                            child: Text('°C', style: TextStyle(fontSize: 20, color: statusColor)),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          Icon(Icons.schedule, size: 13, color: Colors.grey.shade600),
                          const SizedBox(width: 5),
                          Text(
                            hasData ? _agoSeconds(seconds) : 'No data yet',
                            style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const Spacer(),
                  Padding(
                    padding: const EdgeInsets.only(top: 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.water_drop_outlined, size: 16, color: Colors.grey.shade600),
                            const SizedBox(width: 4),
                            Text(
                              hasData ? '${f.humidity.round()}%' : '--%',
                              style: AppTheme.mono(size: 18, color: Colors.grey.shade800),
                            ),
                          ],
                        ),
                        Padding(
                          padding: const EdgeInsets.only(left: 20),
                          child: Text(
                            'humidity',
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _InfoChip(
                      leading: Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: live ? AppColors.ok : Colors.grey,
                          shape: BoxShape.circle,
                        ),
                      ),
                      title: live ? 'Live' : 'Offline',
                      titleColor: live ? AppColors.ok : Colors.grey.shade700,
                      caption: syncText,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _InfoChip(
                      leading: Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: (f.doorOpen ? AppColors.warn : AppColors.ok).withAlpha(30),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          f.doorOpen
                              ? Icons.meeting_room_outlined
                              : Icons.door_front_door_outlined,
                          size: 18,
                          color: f.doorOpen ? AppColors.warn : AppColors.ok,
                        ),
                      ),
                      title: f.doorOpen ? 'Door open' : 'Door closed',
                      titleColor: f.doorOpen ? AppColors.warn : null,
                      caption: doorCaption,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 6,
                children: [
                  Text('Threshold:', style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withAlpha(dark ? 20 : 170),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${_limit(f.minTemp)} to ${_limit(f.maxTemp)}',
                      style: AppTheme.mono(size: 12.5),
                    ),
                  ),
                  Text(
                    '· ${f.minHumidity.round()}-${f.maxHumidity.round()}% RH',
                    style: AppTheme.mono(
                      size: 12,
                      weight: FontWeight.w500,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final Widget leading;
  final String title;
  final Color? titleColor;
  final String caption;

  const _InfoChip({
    required this.leading,
    required this.title,
    required this.caption,
    this.titleColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: appSurface(context),
        borderRadius: BorderRadius.circular(14),
        boxShadow: softShadow(context),
      ),
      child: Row(
        children: [
          leading,
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: titleColor,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  caption,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------- Escalation status ----------

class _EscalationCard extends StatelessWidget {
  final BreachStage stage;
  final int? minutes;
  final bool acked;
  final String ackBy;

  const _EscalationCard({
    required this.stage,
    required this.minutes,
    required this.acked,
    required this.ackBy,
  });

  static const _labels = ['DETECT', 'RESPOND', 'ESCALATE', 'DIAGNOSE'];
  static const _captions = [
    'Breach logged',
    'Staff action',
    'Supervisor review',
    'Hardware check',
  ];
  static const _icons = [
    Icons.search,
    Icons.autorenew,
    Icons.trending_up,
    Icons.settings_outlined,
  ];

  Widget _step(BuildContext context, int i, int current) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final done = i < current;
    final now = i == current;
    final idle = dark ? Colors.white30 : const Color(0xFFC9D0CB);

    final Color fill = done
        ? AppColors.teal
        : (now ? AppColors.danger : appSurface(context));
    final Color iconColor = (done || now) ? Colors.white : Colors.grey.shade500;
    final Color labelColor =
        done ? AppColors.teal : (now ? AppColors.danger : Colors.grey.shade500);

    return Column(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: fill,
            shape: BoxShape.circle,
            border: (done || now) ? null : Border.all(color: idle, width: 1.5),
          ),
          child: Icon(_icons[i], size: 18, color: iconColor),
        ),
        const SizedBox(height: 8),
        Text(
          _labels[i],
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
            color: labelColor,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          _captions[i],
          textAlign: TextAlign.center,
          maxLines: 2,
          style: TextStyle(fontSize: 10.5, height: 1.25, color: Colors.grey.shade600),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final current = stage.index;

    final since = minutes == null
        ? 'Breach duration unknown (no history yet)'
        : 'Breach started ${_agoMinutes(minutes!)}';
    final ackText = acked
        ? (ackBy.isEmpty ? 'Acknowledged' : 'Acknowledged by $ackBy')
        : 'Not yet acknowledged';

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CardLabel('ESCALATION STATUS'),
          const SizedBox(height: 18),
          LayoutBuilder(
            builder: (context, c) {
              final colW = c.maxWidth / 4;
              return Stack(
                children: [
                  Positioned(
                    left: colW / 2,
                    right: colW / 2,
                    top: 17,
                    child: Container(
                      height: 2,
                      color: dark ? Colors.white24 : const Color(0xFFD7DDD8),
                    ),
                  ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var i = 0; i < 4; i++)
                        Expanded(child: _step(context, i, current)),
                    ],
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          Center(
            child: Text(
              '$since · $ackText',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, height: 1.35, color: Colors.grey.shade600),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------- Recommendation ----------

class _RecommendationCard extends StatelessWidget {
  final Fridge fridge;
  final double? rate;

  const _RecommendationCard({required this.fridge, required this.rate});

  @override
  Widget build(BuildContext context) {
    final f = fridge;
    final above = f.temperature > f.maxTemp;
    final dev = above ? f.temperature - f.maxTemp : f.minTemp - f.temperature;

    final r = rate;
    var rateText = '';
    if (r != null) {
      final away = above ? r > 0.05 : r < -0.05;
      final toward = above ? r < -0.05 : r > 0.05;
      final trend = away
          ? (above ? 'still climbing' : 'still falling')
          : (toward ? 'recovering' : 'holding steady');
      rateText = ' Rate: ${_signed(r)}°/min, $trend.';
    }

    return _Card(
      gradient: alertGradient(context, fadeTo: 0.55),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const PulsingIcon(
                icon: Icons.warning_amber_rounded,
                color: AppColors.danger,
                size: 20,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Recommendation — Action Required',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppColors.danger,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Temperature ${dev.toStringAsFixed(1)}° ${above ? 'above max' : 'below min'} threshold.$rateText',
            style: const TextStyle(fontSize: 15, height: 1.4),
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: appSurface(context),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.bolt, size: 18, color: AppColors.warn),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _advice(f),
                    style: const TextStyle(fontSize: 14.5, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Text(
                'Rate of change: ',
                style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
              ),
              Text(
                r == null ? '--' : '${_signed(r, digits: 2)}°C/min',
                style: AppTheme.mono(size: 12.5, color: AppColors.danger),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------- Actions: acknowledge and mute ----------

class _ActionsCard extends StatefulWidget {
  final Fridge fridge;
  final String userName;
  final bool acked;
  final int nowMs;

  const _ActionsCard({
    required this.fridge,
    required this.userName,
    required this.acked,
    required this.nowMs,
  });

  @override
  State<_ActionsCard> createState() => _ActionsCardState();
}

class _ActionsCardState extends State<_ActionsCard> {
  bool _busy = false;
  String? _error;

  Future<void> _acknowledge() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await FridgeService().acknowledge(
        widget.fridge.id,
        widget.userName.isEmpty ? 'a team member' : widget.userName,
      );
      HapticFeedback.mediumImpact();
      if (!mounted) return;
      setState(() => _busy = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Could not acknowledge. Check your connection and try again.';
      });
    }
  }

  Future<void> _pickMute() async {
    final minutes = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      backgroundColor: appSurface(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Mute alerts for this unit',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Silences push alerts for this unit. Supervisors are still told if it stays out of range.',
                  style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
                ),
              ),
            ),
            for (final m in const [15, 60, 240])
              ListTile(
                leading: const Icon(Icons.notifications_off_outlined),
                title: Text(
                  m < 60 ? '$m minutes' : '${m ~/ 60} ${m == 60 ? 'hour' : 'hours'}',
                ),
                onTap: () => Navigator.pop(ctx, m),
              ),
          ],
        ),
      ),
    );

    if (minutes == null) return;
    final until = DateTime.now().add(Duration(minutes: minutes)).millisecondsSinceEpoch;
    try {
      await FridgeService().setMute(widget.fridge.id, until);
      HapticFeedback.selectionClick();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Could not save the mute. Try again.');
    }
  }

  Future<void> _unmute() async {
    try {
      await FridgeService().setMute(widget.fridge.id, 0);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Could not clear the mute. Try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.fridge;
    final muted = f.mutedUntil > widget.nowMs;
    final ackAgo = _agoSeconds(((widget.nowMs - f.ackAt) / 1000).round());

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _CardLabel('ACTIONS'),
          const SizedBox(height: 14),
          if (widget.acked)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.ok.withAlpha(28),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle, size: 20, color: AppColors.ok),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Acknowledged by ${f.ackBy.isEmpty ? 'a team member' : f.ackBy} · $ackAgo',
                      style: const TextStyle(
                        color: AppColors.ok,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            ElevatedButton.icon(
              onPressed: _busy ? null : _acknowledge,
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white),
                    )
                  : const Icon(Icons.check_circle_outline, size: 20),
              label: const Text('Acknowledge Alert'),
            ),
          const SizedBox(height: 10),
          if (muted)
            Container(
              padding: const EdgeInsets.fromLTRB(14, 4, 6, 4),
              decoration: BoxDecoration(
                color: AppColors.warn.withAlpha(26),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  const Icon(Icons.notifications_off_outlined, size: 19, color: AppColors.warn),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Muted until ${_hhmm(f.mutedUntil)}',
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                    ),
                  ),
                  TextButton(onPressed: _unmute, child: const Text('Unmute')),
                ],
              ),
            )
          else
            _SoftButton(
              icon: Icons.notifications_off_outlined,
              label: 'Mute Alerts',
              trailing: Icons.keyboard_arrow_down,
              onTap: _pickMute,
            ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(
              _error!,
              style: const TextStyle(
                color: AppColors.danger,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ---------- Manual cooling control ----------

class _CoolingSection extends StatefulWidget {
  final Fridge fridge;
  final String userName;
  final bool isSupervisor;
  final bool collapsible;

  const _CoolingSection({
    super.key,
    required this.fridge,
    required this.userName,
    required this.isSupervisor,
    required this.collapsible,
  });

  @override
  State<_CoolingSection> createState() => _CoolingSectionState();
}

class _CoolingSectionState extends State<_CoolingSection> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final controls = _CoolingControls(
      fridge: widget.fridge,
      userName: widget.userName,
      enabled: widget.isSupervisor,
    );

    if (!widget.collapsible) return controls;

    return Column(
      children: [
        _Card(
          padding: EdgeInsets.zero,
          child: InkWell(
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() => _open = !_open);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Manual Cooling Control',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                    ),
                  ),
                  AnimatedRotation(
                    turns: _open ? 0.5 : 0,
                    duration: const Duration(milliseconds: 220),
                    child: const Icon(Icons.keyboard_arrow_down),
                  ),
                ],
              ),
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
          alignment: Alignment.topCenter,
          child: _open
              ? Padding(padding: const EdgeInsets.only(top: 12), child: controls)
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}

class _CoolingControls extends StatefulWidget {
  final Fridge fridge;
  final String userName;
  final bool enabled;

  const _CoolingControls({
    required this.fridge,
    required this.userName,
    required this.enabled,
  });

  @override
  State<_CoolingControls> createState() => _CoolingControlsState();
}

class _CoolingControlsState extends State<_CoolingControls> {
  final _noteCtrl = TextEditingController();
  final _targetCtrl = TextEditingController();
  bool _busy = false;
  String? _message;
  bool _isError = false;

  @override
  void dispose() {
    _noteCtrl.dispose();
    _targetCtrl.dispose();
    super.dispose();
  }

  String get _by => widget.userName.isEmpty ? 'unknown' : widget.userName;

  Future<void> _send(String type, String label, int level) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await FridgeService().logCommand(
        id: widget.fridge.id,
        type: type,
        by: _by,
        note: _noteCtrl.text.trim(),
        level: level,
      );
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      _noteCtrl.clear();
      setState(() {
        _busy = false;
        _isError = false;
        _message = '$label saved to the command log.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _isError = true;
        _message = 'Could not save. Check your connection and try again.';
      });
    }
  }

  Future<void> _apply() async {
    final f = widget.fridge;
    final v = double.tryParse(_targetCtrl.text.trim().replaceAll(',', '.'));

    if (v == null) {
      setState(() {
        _isError = true;
        _message = 'Enter a temperature in °C.';
      });
      return;
    }
    if (v < f.minTemp || v > f.maxTemp) {
      setState(() {
        _isError = true;
        _message =
            'The target must be inside the safe range (${_limit(f.minTemp)} to ${_limit(f.maxTemp)}).';
      });
      return;
    }

    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await FridgeService().logCommand(
        id: f.id,
        type: 'set_target',
        by: _by,
        note: _noteCtrl.text.trim(),
        target: v,
      );
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      _targetCtrl.clear();
      _noteCtrl.clear();
      setState(() {
        _busy = false;
        _isError = false;
        _message = 'Target of ${_signed(v)}°C saved to the command log.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _isError = true;
        _message = 'Could not save. Check your connection and try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.fridge;
    final canSend = widget.enabled && !_busy;

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(child: _CardLabel('MANUAL COOLING CONTROL')),
              const SizedBox(width: 8),
              Text(_levelLabel(f.coolingLevel), style: AppTheme.mono(size: 12)),
            ],
          ),
          const SizedBox(height: 14),
          _Gauge(level: f.coolingLevel),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _CommandButton(
                  icon: Icons.remove,
                  label: 'More Cooling',
                  color: AppColors.teal,
                  onTap: canSend
                      ? () => _send('more_cooling', 'Cooling request',
                          _clampLevel(f.coolingLevel - 1))
                      : null,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _CommandButton(
                  icon: Icons.bolt,
                  label: 'Emergency Cool',
                  color: AppColors.danger,
                  onTap: canSend
                      ? () => _send('emergency_cool', 'Emergency cooling request', -3)
                      : null,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _CommandButton(
                  icon: Icons.add,
                  label: 'Less Cooling',
                  color: AppColors.warn,
                  onTap: canSend
                      ? () => _send('less_cooling', 'Reduced-cooling request',
                          _clampLevel(f.coolingLevel + 1))
                      : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _noteCtrl,
            enabled: canSend,
            decoration: const InputDecoration(
              hintText: 'Optional note for command log...',
            ),
          ),
          const SizedBox(height: 16),
          const Divider(height: 1),
          const SizedBox(height: 14),
          Row(
            children: [
              Icon(Icons.track_changes, size: 15, color: Colors.grey.shade600),
              const SizedBox(width: 6),
              Text(
                'SET TARGET TEMPERATURE',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.1,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _targetCtrl,
                  enabled: canSend,
                  keyboardType: const TextInputType.numberWithOptions(
                    signed: true,
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    hintText: '${_limit(f.minTemp)} to ${_limit(f.maxTemp)}',
                  ),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 96,
                child: ElevatedButton(
                  onPressed: canSend ? _apply : null,
                  style: ElevatedButton.styleFrom(minimumSize: const Size(96, 52)),
                  child: const Text('Apply'),
                ),
              ),
            ],
          ),
          if (_message != null) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: _isError ? AppColors.dangerLight : AppColors.okLight,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _message!,
                style: TextStyle(
                  color: _isError ? AppColors.danger : AppColors.ok,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          if (!widget.enabled)
            Row(
              children: [
                Icon(Icons.lock_outline, size: 14, color: Colors.grey.shade600),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Only supervisors can send cooling requests.',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                ),
              ],
            ),
          if (!widget.enabled) const SizedBox(height: 6),
          Text(
            'No cooling hardware is connected yet. Requests are saved to the command log.',
            style: TextStyle(fontSize: 12, height: 1.35, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }
}

class _Gauge extends StatelessWidget {
  final int level;

  const _Gauge({required this.level});

  @override
  Widget build(BuildContext context) {
    final labelStyle = AppTheme.mono(
      size: 10,
      weight: FontWeight.w500,
      color: Colors.grey.shade500,
    );
    final knobColor = level == 0
        ? Colors.grey
        : (level < 0 ? AppColors.teal : AppColors.warn);

    return Column(
      children: [
        LayoutBuilder(
          builder: (context, c) {
            const knob = 16.0;
            final pos = (level + 3) / 6;

            return SizedBox(
              height: 18,
              child: Stack(
                children: [
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 5,
                    child: Container(
                      height: 8,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(4),
                        gradient: LinearGradient(
                          colors: [
                            AppColors.teal.withAlpha(110),
                            Colors.grey.withAlpha(40),
                            AppColors.warn.withAlpha(110),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: c.maxWidth / 2 - 0.5,
                    top: 2,
                    child: Container(width: 1, height: 14, color: Colors.grey.shade500),
                  ),
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeOut,
                    left: pos * (c.maxWidth - knob),
                    top: 1,
                    child: Container(
                      width: knob,
                      height: knob,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        border: Border.all(color: knobColor, width: 3),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('← cooling', style: labelStyle),
            Text('neutral', style: labelStyle),
            Text('warming →', style: labelStyle),
          ],
        ),
      ],
    );
  }
}

class _CommandButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  const _CommandButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;

    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: Material(
        color: color.withAlpha(28),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
            child: Column(
              children: [
                Icon(icon, size: 20, color: color),
                const SizedBox(height: 6),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------- Temperature trend ----------

class _TrendCard extends StatefulWidget {
  final Fridge fridge;
  final List<Reading> readings;
  final int nowMs;
  final bool loading;

  const _TrendCard({
    super.key,
    required this.fridge,
    required this.readings,
    required this.nowMs,
    required this.loading,
  });

  @override
  State<_TrendCard> createState() => _TrendCardState();
}

class _TrendCardState extends State<_TrendCard> {
  int _hours = 6;

  @override
  Widget build(BuildContext context) {
    final f = widget.fridge;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final startMs = widget.nowMs - _hours * 3600000;
    final data = widget.readings.where((r) => r.t >= startMs).toList();

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            runSpacing: 10,
            children: [
              const _CardLabel('TEMPERATURE TREND'),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final h in const [1, 3, 6, 12]) ...[
                    _RangeChip(
                      label: '${h}h',
                      selected: h == _hours,
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() => _hours = h);
                      },
                    ),
                    if (h != 12) const SizedBox(width: 6),
                  ],
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 210,
            width: double.infinity,
            child: data.length < 2
                ? Center(
                    child: Text(
                      widget.loading
                          ? 'Loading history…'
                          : 'Not enough readings in this period yet.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                    ),
                  )
                : CustomPaint(
                    painter: _TrendPainter(
                      data: data,
                      minLimit: f.minTemp,
                      maxLimit: f.maxTemp,
                      startMs: startMs,
                      endMs: widget.nowMs,
                      dark: dark,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _RangeChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _RangeChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;

    return Material(
      color: selected
          ? AppColors.teal
          : (dark ? Colors.white10 : const Color(0xFFE9ECE6)),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Text(
            label,
            style: AppTheme.mono(
              size: 11.5,
              color: selected ? Colors.white : Colors.grey.shade700,
            ),
          ),
        ),
      ),
    );
  }
}

class _TrendPainter extends CustomPainter {
  final List<Reading> data;
  final double minLimit;
  final double maxLimit;
  final int startMs;
  final int endMs;
  final bool dark;

  const _TrendPainter({
    required this.data,
    required this.minLimit,
    required this.maxLimit,
    required this.startMs,
    required this.endMs,
    required this.dark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const leftPad = 40.0;
    const rightPad = 8.0;
    const topPad = 8.0;
    const bottomPad = 22.0;
    final plot = Rect.fromLTRB(
      leftPad,
      topPad,
      size.width - rightPad,
      size.height - bottomPad,
    );

    // Vertical scale: always show both limits, plus a little room
    var lo = minLimit;
    var hi = maxLimit;
    for (final r in data) {
      if (r.temp < lo) lo = r.temp;
      if (r.temp > hi) hi = r.temp;
    }
    final pad = math.max((hi - lo) * 0.12, 1.0);
    lo -= pad;
    hi += pad;

    double yOf(double v) => plot.top + (hi - v) / (hi - lo) * plot.height;
    final span = math.max((endMs - startMs).toDouble(), 1.0);
    double xOf(int t) => plot.left + (t - startMs) / span * plot.width;

    final labelColor = dark ? Colors.white54 : Colors.grey.shade600;
    final gridColor = dark ? Colors.white12 : const Color(0xFFE6EAE6);

    void label(String s, double dx, double dy,
        {bool alignRight = false, bool center = false}) {
      final tp = TextPainter(
        text: TextSpan(
          text: s,
          style: AppTheme.mono(size: 9, weight: FontWeight.w500, color: labelColor),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      var x = alignRight ? dx - tp.width : (center ? dx - tp.width / 2 : dx);
      x = x.clamp(0.0, math.max(0.0, size.width - tp.width)).toDouble();
      tp.paint(canvas, Offset(x, dy - tp.height / 2));
    }

    // grid and temperature labels
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (var i = 0; i < 5; i++) {
      final v = hi - (hi - lo) * i / 4;
      final y = yOf(v);
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), gridPaint);
      label('${v.round()}°', leftPad - 6, y, alignRight: true);
    }

    // the safe band
    canvas.drawRect(
      Rect.fromLTRB(plot.left, yOf(maxLimit), plot.right, yOf(minLimit)),
      Paint()..color = AppColors.ok.withAlpha(dark ? 30 : 28),
    );

    // dashed limit lines
    final limitPaint = Paint()
      ..color = AppColors.danger.withAlpha(170)
      ..strokeWidth = 1.2;
    void dashedAt(double y) {
      var dx = plot.left;
      while (dx < plot.right) {
        canvas.drawLine(
          Offset(dx, y),
          Offset(math.min(dx + 5, plot.right), y),
          limitPaint,
        );
        dx += 9;
      }
    }

    dashedAt(yOf(maxLimit));
    dashedAt(yOf(minLimit));

    // the temperature line: teal while in range, red while outside it
    final step = math.max(1, (data.length / 300).ceil());
    final pts = <Reading>[
      for (var i = 0; i < data.length; i += step) data[i],
    ];
    if (!identical(pts.last, data.last)) pts.add(data.last);

    final good = Paint()
      ..color = AppColors.teal
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round;
    final bad = Paint()
      ..color = AppColors.danger
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round;

    for (var i = 1; i < pts.length; i++) {
      final a = pts[i - 1];
      final b = pts[i];
      final mid = (a.temp + b.temp) / 2;
      final ok = mid >= minLimit && mid <= maxLimit;
      canvas.drawLine(
        Offset(xOf(a.t), yOf(a.temp)),
        Offset(xOf(b.t), yOf(b.temp)),
        ok ? good : bad,
      );
    }

    // marker on the newest reading
    final last = data.last;
    final lastOk = last.temp >= minLimit && last.temp <= maxLimit;
    final c = Offset(xOf(last.t), yOf(last.temp));
    canvas.drawCircle(
      c,
      6,
      Paint()..color = dark ? const Color(0xFF16272B) : Colors.white,
    );
    canvas.drawCircle(
      c,
      4,
      Paint()..color = lastOk ? AppColors.teal : AppColors.danger,
    );

    // time labels along the bottom
    for (var i = 0; i < 5; i++) {
      final t = startMs + ((endMs - startMs) * i / 4).round();
      label(_hhmm(t), xOf(t), size.height - 8, center: true);
    }
  }

  @override
  bool shouldRepaint(_TrendPainter old) => true;
}

// ---------- Incident log ----------

class _IncidentLog extends StatelessWidget {
  final Fridge fridge;
  final List<Incident> incidents;
  final List<Reading> readings;
  final int nowMs;
  final bool loading;

  const _IncidentLog({
    super.key,
    required this.fridge,
    required this.incidents,
    required this.readings,
    required this.nowMs,
    required this.loading,
  });

  String _note(Incident i) {
    final doorWasOpen =
        readings.any((r) => r.door && r.t >= i.startMs && r.t <= i.endMs);
    final parts = <String>[];

    if (i.open) {
      final acked = fridge.ackAt > 0 && fridge.ackAt >= i.startMs;
      if (acked) {
        final by = fridge.ackBy.isEmpty ? 'a team member' : fridge.ackBy;
        parts.add('Acknowledged by $by.');
      } else {
        parts.add('Not yet acknowledged.');
      }
    } else {
      parts.add('Temperature returned to the safe range at ${_hhmm(i.endMs)}.');
    }
    if (doorWasOpen) parts.add('The door was open during this period.');
    return parts.join(' ');
  }

  @override
  Widget build(BuildContext context) {
    final list = incidents.reversed.toList();

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CardLabel('INCIDENT LOG'),
          const SizedBox(height: 14),
          if (list.isEmpty)
            Row(
              children: [
                const Icon(Icons.check_circle_outline, size: 20, color: AppColors.ok),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    loading
                        ? 'Loading history…'
                        : 'No incidents in the last 24 hours.',
                    style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
                  ),
                ),
              ],
            )
          else
            for (final i in list) ...[
              _IncidentTile(
                incident: i,
                minutes: i.open ? ((nowMs - i.startMs) / 60000).round() : i.minutes,
                note: _note(i),
              ),
              if (i != list.last) const SizedBox(height: 10),
            ],
        ],
      ),
    );
  }
}

class _IncidentTile extends StatelessWidget {
  final Incident incident;
  final int minutes;
  final String note;

  const _IncidentTile({
    required this.incident,
    required this.minutes,
    required this.note,
  });

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final active = incident.open;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: active ? null : (dark ? Colors.white10 : const Color(0xFFF3F4EF)),
        gradient: active ? alertGradient(context, fadeTo: 1.0) : null,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                active ? 'Active' : 'Resolved',
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                  color: active ? AppColors.danger : Colors.grey.shade700,
                ),
              ),
              const Spacer(),
              Text(
                _dateTime(incident.startMs),
                style: AppTheme.mono(
                  size: 11,
                  weight: FontWeight.w500,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 18,
            runSpacing: 4,
            children: [
              Text.rich(
                TextSpan(
                  children: [
                    const TextSpan(text: 'Peak: '),
                    TextSpan(
                      text: '${_signed(incident.peak)}°C',
                      style: AppTheme.mono(size: 13),
                    ),
                  ],
                ),
                style: const TextStyle(fontSize: 13),
              ),
              Text.rich(
                TextSpan(
                  children: [
                    const TextSpan(text: 'Duration: '),
                    TextSpan(
                      text: '$minutes min',
                      style: AppTheme.mono(size: 13),
                    ),
                  ],
                ),
                style: const TextStyle(fontSize: 13),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            note,
            style: TextStyle(fontSize: 13, height: 1.4, color: Colors.grey.shade700),
          ),
        ],
      ),
    );
  }
}