import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/fridge_service.dart';
import '../services/auth_service.dart';
import '../models/fridge.dart';
import '../theme/app_theme.dart';
import '../widgets/app_drawer.dart';
import '../widgets/motion.dart';
import '../widgets/surfaces.dart';
import 'fridge_detail_screen.dart';
import 'add_fridge_screen.dart';

enum _UnitState { alert, ok, waiting }

bool _isOnline(Fridge f) {
  if (f.lastSeen == 0) return false;
  final seen = DateTime.fromMillisecondsSinceEpoch(f.lastSeen);
  return DateTime.now().difference(seen).inMinutes < 5;
}

// +4.6 / -12.0 (always shows the sign, like the Figma)
String _formatTemp(double t) => '${t >= 0 ? '+' : ''}${t.toStringAsFixed(1)}';

// +2°C / -25°C (drops the decimal when it's a whole number)
String _formatLimit(double v) {
  final text = v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
  return '${v >= 0 ? '+' : ''}$text°C';
}

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final fridgeService = FridgeService();

    return Scaffold(
      drawer: const AppDrawer(),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AddFridgeScreen()),
          );
        },
        child: const Icon(Icons.add),
      ),
      body: StreamBuilder<List<Fridge>>(
        stream: fridgeService.fridgesStream,
        builder: (context, snapshot) {
          final fridges = snapshot.data ?? <Fridge>[];
          final live = snapshot.hasData ? fridges.any(_isOnline) : null;

          return Column(
            children: [
              _Header(live: live),
              Expanded(child: _Body(snapshot: snapshot)),
            ],
          );
        },
      ),
    );
  }
}

// ---------- Body ----------

class _Body extends StatelessWidget {
  final AsyncSnapshot<List<Fridge>> snapshot;

  const _Body({required this.snapshot});

  @override
  Widget build(BuildContext context) {
    if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
      return const Center(child: CircularProgressIndicator());
    }
    if (snapshot.hasError) {
      return const Center(child: Text('Could not load your fridges.'));
    }

    final fridges = snapshot.data ?? <Fridge>[];
    if (fridges.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'No fridges yet.\nTap + to add your first unit.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final alerts = fridges.where((f) => f.isBreaching).toList();
    final others = fridges.where((f) => !f.isBreaching).toList();
    final inRange = fridges.where((f) => f.hasData && f.inRange).length;

    var i = 0; // position in the list, used to stagger the entrance animation

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 96),
      children: [
        _SummaryRow(
          total: fridges.length,
          breaching: alerts.length,
          inRange: inRange,
        ),
        if (alerts.isNotEmpty) ...[
          const SizedBox(height: 24),
          const _SectionLabel(
            label: 'ACTIVE ALERTS',
            icon: Icons.warning_amber_rounded,
            color: AppColors.danger,
          ),
          const SizedBox(height: 12),
          ...alerts.map(
            (f) => FadeSlideIn(
              key: ValueKey(f.id),
              index: i++,
              child: _UnitCard(fridge: f, state: _UnitState.alert),
            ),
          ),
        ],
        if (others.isNotEmpty) ...[
          const SizedBox(height: 10),
          const _SectionLabel(label: 'ALL UNITS', icon: Icons.grid_view_rounded),
          const SizedBox(height: 12),
          ...others.map(
            (f) => FadeSlideIn(
              key: ValueKey(f.id),
              index: i++,
              child: _UnitCard(
                fridge: f,
                state: f.hasData ? _UnitState.ok : _UnitState.waiting,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

// ---------- Header ----------

class _Header extends StatelessWidget {
  final bool? live;

  const _Header({required this.live});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        // a teal-tinted panel, clearly different from the cream body
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: dark
              ? const [Color(0xFF15383B), Color(0xFF112A2D)]
              : const [Color(0xFFD3E9E3), Color(0xFFE6F3EF)],
        ),
        // the thin divider line under the header
        border: Border(
          bottom: BorderSide(color: AppColors.teal.withAlpha(dark ? 70 : 45)),
        ),
      ),
      child: Stack(
        children: [
          const Positioned.fill(child: _HeaderArt()),
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Builder(
                        builder: (ctx) => _RoundButton(
                          icon: Icons.menu,
                          onTap: () => Scaffold.of(ctx).openDrawer(),
                        ),
                      ),
                      Image.asset(
                        'assets/images/logo_fridge.png',
                        height: 42,
                        errorBuilder: (context, error, stack) => const Icon(
                          Icons.kitchen_rounded,
                          size: 34,
                          color: AppColors.teal,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _GreetingRow(live: live),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The artwork behind the header. It is clipped to the header,
/// so nothing can ever spill over the divider line.
class _HeaderArt extends StatefulWidget {
  const _HeaderArt();

  @override
  State<_HeaderArt> createState() => _HeaderArtState();
}

class _HeaderArtState extends State<_HeaderArt>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final topInset = MediaQuery.of(context).padding.top;
    final still = MediaQuery.of(context).disableAnimations;

    return IgnorePointer(
      child: ClipRect(
        child: RepaintBoundary(
          child: CustomPaint(
            painter: _HeaderArtPainter(
              progress: still
                  ? const AlwaysStoppedAnimation<double>(0.35)
                  : _controller,
              topInset: topInset,
              dark: dark,
            ),
          ),
        ),
      ),
    );
  }
}

class _HeaderArtPainter extends CustomPainter {
  final Animation<double> progress;
  final double topInset;
  final bool dark;

  _HeaderArtPainter({
    required this.progress,
    required this.topInset,
    required this.dark,
  }) : super(repaint: progress);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final ink = dark ? Colors.white : AppColors.teal;
    final rowY = topInset + 8 + 23; // vertical centre of the menu / logo row

    // soft light from the top-left corner, for depth
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = RadialGradient(
          colors: [
            Colors.white.withAlpha(dark ? 16 : 170),
            Colors.white.withAlpha(0),
          ],
        ).createShader(
          Rect.fromCircle(center: Offset(w * 0.1, 0), radius: w * 0.75),
        ),
    );

    // quiet rings around the logo
    final logoCenter = Offset(w - 31, rowY);
    final ringAlphas = dark ? [34, 22, 12] : [56, 38, 22];
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    for (var i = 0; i < 3; i++) {
      ring.color = ink.withAlpha(ringAlphas[i]);
      canvas.drawCircle(logoCenter, 38.0 + i * 28, ring);
    }

    // a ring that spreads out from the logo, like a sensor ping
    final p = progress.value;
    canvas.drawCircle(
      logoCenter,
      24 + 110 * p,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = ink.withAlpha(((1 - p) * (dark ? 70 : 100)).round()),
    );

    // a live temperature trace between the menu button and the logo
    const x0 = 70.0;
    final x1 = w - 64;
    final span = x1 - x0;
    if (span > 60) {
      final path = Path();
      const steps = 80;
      for (var i = 0; i <= steps; i++) {
        final t = i / steps;
        final bump = math.exp(-math.pow((t - 0.68) / 0.045, 2));
        final y = rowY +
            4 * math.sin(t * math.pi * 5) +
            2 * math.sin(t * math.pi * 12 + 1) -
            15 * bump;
        final x = x0 + span * t;
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }

      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..shader = LinearGradient(
            colors: [
              ink.withAlpha(0),
              ink.withAlpha(dark ? 110 : 150),
              ink.withAlpha(0),
            ],
            stops: const [0.0, 0.5, 1.0],
          ).createShader(Rect.fromLTWH(x0, 0, span, 1)),
      );
    }
  }

  @override
  bool shouldRepaint(_HeaderArtPainter old) =>
      old.topInset != topInset || old.dark != dark;
}

class _RoundButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _RoundButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: appSurface(context),
        shape: BoxShape.circle,
        boxShadow: softShadow(context),
      ),
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(width: 46, height: 46, child: Icon(icon)),
        ),
      ),
    );
  }
}

class _GreetingRow extends StatefulWidget {
  final bool? live;

  const _GreetingRow({required this.live});

  @override
  State<_GreetingRow> createState() => _GreetingRowState();
}

class _GreetingRowState extends State<_GreetingRow> {
  late final Future<Map<String, dynamic>?> _userFuture;

  static const _titles = {'dr', 'dr.', 'mr', 'mr.', 'mrs', 'mrs.', 'ms', 'ms.', 'prof', 'prof.'};

  @override
  void initState() {
    super.initState();
    final user = FirebaseAuth.instance.currentUser;
    _userFuture = user == null ? Future.value(null) : AuthService().getUserData(user.uid);
  }

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  // Splits "Dr. Kwame Asante" into [Kwame, Asante], skipping titles
  List<String> _nameParts(String fullName) {
    return fullName
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty && !_titles.contains(p.toLowerCase()))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>?>(
      future: _userFuture,
      builder: (context, snapshot) {
        final data = snapshot.data;
        final email = FirebaseAuth.instance.currentUser?.email ?? '';
        final parts = _nameParts((data?['name'] ?? '').toString().trim());
        final role = (data?['role'] ?? '').toString();

        final firstName = parts.isNotEmpty ? parts.first : email.split('@').first;
        final initials = parts.isNotEmpty
            ? parts.take(3).map((p) => p[0].toUpperCase()).join()
            : (email.isNotEmpty
                ? email.substring(0, email.length >= 2 ? 2 : 1).toUpperCase()
                : '?');
        final roleLabel = role.isEmpty ? '' : role[0].toUpperCase() + role.substring(1);

        return Row(
          children: [
            Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
              child: CircleAvatar(
                radius: 22,
                backgroundColor: AppColors.teal,
                child: Text(
                  initials,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${_greeting()}, $firstName',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                  ),
                  if (roleLabel.isNotEmpty)
                    Text(
                      roleLabel,
                      style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                    ),
                ],
              ),
            ),
            if (widget.live != null)
              Row(
                children: [
                  Icon(
                    widget.live! ? Icons.wifi : Icons.wifi_off,
                    size: 16,
                    color: widget.live! ? AppColors.ok : Colors.grey,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    widget.live! ? 'Live' : 'Offline',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: widget.live! ? AppColors.ok : Colors.grey,
                    ),
                  ),
                ],
              ),
          ],
        );
      },
    );
  }
}

// ---------- Summary boxes ----------

class _SummaryRow extends StatelessWidget {
  final int total;
  final int breaching;
  final int inRange;

  const _SummaryRow({
    required this.total,
    required this.breaching,
    required this.inRange,
  });

  @override
  Widget build(BuildContext context) {
    final hasBreach = breaching > 0;

    return Row(
      children: [
        Expanded(
          child: _SummaryBox(
            value: '$total',
            label: 'Total units',
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _SummaryBox(
            value: '$breaching',
            label: 'Breaching',
            color: hasBreach ? AppColors.danger : Colors.grey,
            alert: hasBreach,
            icon: hasBreach ? Icons.warning_amber_rounded : null,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _SummaryBox(
            value: '$inRange',
            label: 'In range',
            color: AppColors.ok,
          ),
        ),
      ],
    );
  }
}

class _SummaryBox extends StatelessWidget {
  final String value;
  final String label;
  final Color color;
  final bool alert;
  final IconData? icon;

  const _SummaryBox({
    required this.value,
    required this.label,
    required this.color,
    this.alert = false,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
      decoration: BoxDecoration(
        // pure white, except the breaching tile which fades from soft red
        color: alert ? null : appSurface(context),
        gradient: alert ? alertGradient(context, fadeTo: 1.0) : null,
        borderRadius: BorderRadius.circular(16),
        boxShadow: softShadow(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(value, style: AppTheme.mono(size: 32, color: color)),
              if (icon != null) ...[
                const SizedBox(width: 6),
                PulsingIcon(icon: icon!, color: color, size: 16),
              ],
            ],
          ),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color? color;

  const _SectionLabel({required this.label, required this.icon, this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? Colors.grey.shade600;
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Row(
        children: [
          Icon(icon, size: 14, color: c),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
              color: c,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------- Unit card ----------

class _UnitCard extends StatelessWidget {
  final Fridge fridge;
  final _UnitState state;

  const _UnitCard({required this.fridge, required this.state});

  String _advice() {
    if (fridge.temperature > fridge.maxTemp) {
      return 'Increase compressor cooling one notch. If no improvement in 5 min, transfer samples.';
    }
    return 'Reduce cooling one notch to avoid freezing the contents. If no improvement in 5 min, move samples.';
  }

  @override
  Widget build(BuildContext context) {
    final alert = state == _UnitState.alert;
    final waiting = state == _UnitState.waiting;
    final statusColor =
        alert ? AppColors.danger : (waiting ? Colors.grey : AppColors.ok);

    final span = fridge.maxTemp - fridge.minTemp;
    double fill;
    if (waiting) {
      fill = 0.0;
    } else if (alert) {
      fill = fridge.temperature > fridge.maxTemp ? 1.0 : 0.04;
    } else {
      fill = span <= 0
          ? 0.0
          : ((fridge.temperature - fridge.minTemp) / span).clamp(0.0, 1.0).toDouble();
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: DecoratedBox(
        decoration: BoxDecoration(
          // pure white, except alert cards which fade from soft red at the top
          color: alert ? null : appSurface(context),
          gradient: alert ? alertGradient(context, fadeTo: 0.42) : null,
          borderRadius: BorderRadius.circular(18),
          boxShadow: softShadow(context),
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () {
              HapticFeedback.selectionClick();
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => FridgeDetailScreen(fridge: fridge)),
              );
            },
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (alert) ...[
                        const PulsingIcon(
                          icon: Icons.warning_amber_rounded,
                          color: AppColors.danger,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                      ],
                      Expanded(
                        child: Text(
                          fridge.name,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                        ),
                      ),
                      _StatusPill(state: state),
                      const SizedBox(width: 4),
                      Icon(Icons.chevron_right, color: Colors.grey.shade500),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Padding(
                    padding: EdgeInsets.only(left: alert ? 28 : 0),
                    child: Text(
                      fridge.location,
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Icon(Icons.thermostat, size: 18, color: Colors.grey.shade600),
                      const SizedBox(width: 4),
                      waiting
                          ? Text('--.-', style: AppTheme.mono(size: 34, color: statusColor))
                          : TweenAnimationBuilder<double>(
                              tween: Tween<double>(end: fridge.temperature),
                              duration: const Duration(milliseconds: 700),
                              curve: Curves.easeOutCubic,
                              builder: (context, value, _) => Text(
                                _formatTemp(value),
                                style: AppTheme.mono(size: 34, color: statusColor),
                              ),
                            ),
                      if (!waiting)
                        Padding(
                          padding: const EdgeInsets.only(left: 4, top: 8),
                          child: Text('°C', style: TextStyle(fontSize: 14, color: statusColor)),
                        ),
                      const Spacer(),
                      Icon(Icons.water_drop_outlined, size: 15, color: Colors.grey.shade600),
                      const SizedBox(width: 4),
                      Text(
                        waiting ? '--%' : '${fridge.humidity.toStringAsFixed(0)}%',
                        style: AppTheme.mono(
                          size: 14,
                          weight: FontWeight.w500,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TweenAnimationBuilder<double>(
                    tween: Tween<double>(end: fill),
                    duration: const Duration(milliseconds: 700),
                    curve: Curves.easeOutCubic,
                    builder: (context, value, _) => ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: value,
                        minHeight: 6,
                        backgroundColor: Colors.grey.withAlpha(50),
                        valueColor: AlwaysStoppedAnimation(statusColor),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _formatLimit(fridge.minTemp),
                        style: AppTheme.mono(size: 11, weight: FontWeight.w500, color: Colors.grey.shade600),
                      ),
                      Text(
                        'target range',
                        style: AppTheme.mono(size: 11, weight: FontWeight.w500, color: Colors.grey.shade500),
                      ),
                      Text(
                        _formatLimit(fridge.maxTemp),
                        style: AppTheme.mono(size: 11, weight: FontWeight.w500, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                  if (alert) ...[
                    const SizedBox(height: 12),
                    const Divider(height: 1),
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.bolt, size: 18, color: AppColors.warn),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _advice(),
                            style: TextStyle(
                              fontSize: 13,
                              height: 1.35,
                              color: Colors.grey.shade700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final _UnitState state;

  const _StatusPill({required this.state});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final Color c;
    final String label;
    switch (state) {
      case _UnitState.alert:
        c = AppColors.danger;
        label = 'Breaching';
      case _UnitState.ok:
        c = AppColors.ok;
        label = 'In range';
      case _UnitState.waiting:
        c = Colors.grey;
        label = 'Awaiting data';
    }

    // On the pink alert fade, a white pill reads more clearly
    final bg = state == _UnitState.alert
        ? (dark ? c.withAlpha(60) : Colors.white)
        : c.withAlpha(30);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: c, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(color: c, fontSize: 12, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}