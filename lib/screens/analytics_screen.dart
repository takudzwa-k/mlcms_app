import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/fridge.dart';
import '../services/fridge_service.dart';
import '../services/history.dart';
import '../theme/app_theme.dart';
import '../widgets/history_builder.dart';
import '../widgets/motion.dart';
import '../widgets/screen_header.dart';
import '../widgets/surfaces.dart';
import 'fridge_detail_screen.dart';

bool _isOnline(Fridge f) {
  if (f.lastSeen == 0) return false;
  final seen = DateTime.fromMillisecondsSinceEpoch(f.lastSeen);
  return DateTime.now().difference(seen).inMinutes < 5;
}

// green when healthy, amber when slipping, red when poor
Color _uptimeColor(double pct) {
  if (pct >= 95) return AppColors.ok;
  if (pct >= 85) return AppColors.warn;
  return AppColors.danger;
}

String _signed(double v) => '${v >= 0 ? '+' : ''}${v.toStringAsFixed(1)}';

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  late final Stream<List<Fridge>> _stream = FridgeService().fridgesStream;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          const ScreenHeader(
            title: 'Analytics',
            subtitle: '24-hour operational overview',
          ),
          Expanded(
            child: StreamBuilder<List<Fridge>>(
              stream: _stream,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting &&
                    !snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final fridges = snapshot.data ?? <Fridge>[];
                if (fridges.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: Text(
                        'No fridges yet.\nAdd a unit from the Dashboard first.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }

                return HistoryBuilder(
                  fridges: fridges,
                  builder: (context, history, loading) {
                    if (loading) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    return _Content(fridges: fridges, history: history);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ---------- Content ----------

class _Content extends StatelessWidget {
  final List<Fridge> fridges;
  final Map<String, List<Reading>> history;

  const _Content({required this.fridges, required this.history});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now().millisecondsSinceEpoch;

    final stats = [
      for (final f in fridges)
        computeStats(f, history[f.id] ?? const <Reading>[], now),
    ];
    final withHistory = stats.where((s) => s.hasHistory).toList();

    final uptime = withHistory.isEmpty
        ? null
        : withHistory.fold<double>(0, (a, s) => a + s.percentInRange) /
            withHistory.length;

    final incidents = [for (final s in stats) ...s.incidents];
    final open = incidents.where((i) => i.open).length;
    final resolved = incidents.length - open;

    final alerts = fridges.where((f) => f.isBreaching).length;
    final online = fridges.where(_isOnline).length;
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 32),
      children: [
        FadeSlideIn(
          index: 0,
          child: Row(
            children: [
              Expanded(
                child: _StatTile(
                  icon: Icons.check_circle_outline,
                  label: 'FLEET UPTIME',
                  value: '--',
                  countTo: uptime,
                  suffix: '%',
                  color: uptime == null ? Colors.grey : _uptimeColor(uptime),
                  caption: uptime == null ? 'no history yet' : 'avg time in range',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StatTile(
                  icon: Icons.warning_amber_rounded,
                  label: 'INCIDENTS',
                  value: '${incidents.length}',
                  color: onSurface,
                  caption: incidents.isEmpty
                      ? 'none in 24 h'
                      : '$resolved resolved · $open open',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        FadeSlideIn(
          index: 1,
          child: Row(
            children: [
              Expanded(
                child: _StatTile(
                  icon: Icons.trending_up,
                  label: 'ACTIVE ALERTS',
                  value: '$alerts',
                  color: alerts > 0 ? AppColors.danger : AppColors.ok,
                  caption: alerts > 0 ? 'currently breaching' : 'all clear',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StatTile(
                  icon: Icons.schedule,
                  label: 'UNITS ONLINE',
                  value: '$online',
                  color: onSurface,
                  caption: online == fridges.length
                      ? 'all transmitting'
                      : 'of ${fridges.length} transmitting',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        FadeSlideIn(index: 2, child: _SafeRangeChart(stats: withHistory)),
        const SizedBox(height: 18),
        FadeSlideIn(index: 3, child: _Breakdown(stats: stats)),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            'Calculated from the readings stored in the last 24 hours, '
            'against each unit\'s current safe range.',
            style: TextStyle(fontSize: 12, height: 1.35, color: Colors.grey.shade600),
          ),
        ),
      ],
    );
  }
}

// ---------- Stat tile ----------

class _StatTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final double? countTo; // when set, the number counts up to this value
  final String suffix;
  final Color color;
  final String caption;

  const _StatTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    required this.caption,
    this.countTo,
    this.suffix = '',
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: appSurface(context),
        borderRadius: BorderRadius.circular(16),
        boxShadow: softShadow(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 15, color: Colors.grey.shade600),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.1,
                    color: Colors.grey.shade600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          countTo != null
              ? TweenAnimationBuilder<double>(
                  tween: Tween<double>(begin: 0, end: countTo),
                  duration: const Duration(milliseconds: 900),
                  curve: Curves.easeOutCubic,
                  builder: (context, v, _) => Text(
                    '${v.toStringAsFixed(1)}$suffix',
                    style: AppTheme.mono(size: 30, color: color),
                  ),
                )
              : Text(value, style: AppTheme.mono(size: 30, color: color)),
          const SizedBox(height: 2),
          Text(caption, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
        ],
      ),
    );
  }
}

// ---------- Bar chart ----------

class _SafeRangeChart extends StatefulWidget {
  final List<UnitStats> stats;

  const _SafeRangeChart({required this.stats});

  @override
  State<_SafeRangeChart> createState() => _SafeRangeChartState();
}

class _SafeRangeChartState extends State<_SafeRangeChart> {
  static const double _chartH = 140;
  int? _selected;

  @override
  Widget build(BuildContext context) {
    final stats = widget.stats;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final grid = dark ? Colors.white12 : const Color(0xFFE6EAE6);

    final picked = (_selected != null && _selected! < stats.length)
        ? stats[_selected!]
        : null;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(
        color: appSurface(context),
        borderRadius: BorderRadius.circular(16),
        boxShadow: softShadow(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '% TIME IN SAFE RANGE (24 H)',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.1,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 18,
            child: Text(
              picked == null
                  ? (stats.isEmpty ? '' : 'Tap a bar for details')
                  : '${picked.fridge.name} · ${picked.percentInRange.toStringAsFixed(1)}%',
              style: AppTheme.mono(
                size: 12,
                weight: FontWeight.w500,
                color: picked == null
                    ? Colors.grey.shade500
                    : _uptimeColor(picked.percentInRange),
              ),
            ),
          ),
          const SizedBox(height: 10),
          if (stats.isEmpty)
            Container(
              height: 110,
              alignment: Alignment.center,
              child: Text(
                'No history yet.\nReadings will appear here once your units report.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
              ),
            )
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 36,
                  height: _chartH,
                  child: Stack(
                    children: [
                      for (final v in const [100, 75, 50, 25, 0])
                        Positioned(
                          right: 6,
                          top: _chartH * (1 - v / 100) - 6,
                          child: Text(
                            '$v%',
                            style: AppTheme.mono(
                              size: 9,
                              weight: FontWeight.w500,
                              color: Colors.grey.shade500,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    children: [
                      SizedBox(
                        height: _chartH,
                        child: Stack(
                          children: [
                            for (final v in const [100, 75, 50, 25, 0])
                              Positioned(
                                left: 0,
                                right: 0,
                                top: v == 0 ? _chartH - 1 : _chartH * (1 - v / 100),
                                child: Container(height: 1, color: grid),
                              ),
                            Positioned.fill(
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  for (var i = 0; i < stats.length; i++)
                                    Expanded(
                                      child: GestureDetector(
                                        behavior: HitTestBehavior.opaque,
                                        onTap: () {
                                          HapticFeedback.selectionClick();
                                          setState(() =>
                                              _selected = _selected == i ? null : i);
                                        },
                                        child: Align(
                                          alignment: Alignment.bottomCenter,
                                          child: _Bar(
                                            percent: stats[i].percentInRange,
                                            height: _chartH,
                                            dimmed: _selected != null && _selected != i,
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final s in stats)
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 2),
                                child: Text(
                                  s.fridge.name,
                                  textAlign: TextAlign.center,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTheme.mono(
                                    size: 10,
                                    weight: FontWeight.w500,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  final double percent;
  final double height;
  final bool dimmed;

  const _Bar({
    required this.percent,
    required this.height,
    required this.dimmed,
  });

  @override
  Widget build(BuildContext context) {
    final color = _uptimeColor(percent);

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = (constraints.maxWidth * 0.6).clamp(10.0, 34.0).toDouble();

        return TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0, end: percent / 100 * height),
          duration: const Duration(milliseconds: 800),
          curve: Curves.easeOutCubic,
          builder: (context, h, _) => AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: width,
            height: h,
            decoration: BoxDecoration(
              color: dimmed ? color.withAlpha(80) : color,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
            ),
          ),
        );
      },
    );
  }
}

// ---------- Unit breakdown ----------

class _Breakdown extends StatelessWidget {
  final List<UnitStats> stats;

  const _Breakdown({required this.stats});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: appSurface(context),
        borderRadius: BorderRadius.circular(16),
        boxShadow: softShadow(context),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 6),
              child: Text(
                'UNIT BREAKDOWN',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.1,
                  color: Colors.grey.shade600,
                ),
              ),
            ),
            for (var i = 0; i < stats.length; i++) ...[
              _BreakdownRow(stat: stats[i]),
              if (i != stats.length - 1)
                const Divider(height: 1, indent: 18, endIndent: 18),
            ],
          ],
        ),
      ),
    );
  }
}

class _BreakdownRow extends StatelessWidget {
  final UnitStats stat;

  const _BreakdownRow({required this.stat});

  @override
  Widget build(BuildContext context) {
    final n = stat.incidents.length;
    final color = stat.hasHistory ? _uptimeColor(stat.percentInRange) : Colors.grey;

    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => FridgeDetailScreen(fridge: stat.fridge),
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    stat.fridge.name,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    stat.hasHistory
                        ? 'avg ${_signed(stat.avgTemp)}°C · $n ${n == 1 ? 'incident' : 'incidents'}'
                        : 'No history yet',
                    style: AppTheme.mono(
                      size: 11.5,
                      weight: FontWeight.w500,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  stat.hasHistory ? '${stat.percentInRange.toStringAsFixed(1)}%' : '--',
                  style: AppTheme.mono(size: 18, color: color),
                ),
                const SizedBox(height: 2),
                Text(
                  stat.hasHistory ? 'in range' : '',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}