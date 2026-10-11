import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/fridge.dart';
import '../services/auth_service.dart';
import '../services/fridge_service.dart';
import '../theme/app_theme.dart';
import '../widgets/screen_header.dart';
import '../widgets/surfaces.dart';

// +2°C / -25°C (drops the decimal when it's a whole number)
String _limit(double v) {
  final text = v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
  return '${v >= 0 ? '+' : ''}$text°C';
}

// +2.0°C / -25.5°C (always one decimal, for the slider read-outs)
String _precise(double v) => '${v >= 0 ? '+' : ''}${v.toStringAsFixed(1)}°C';

// Snap to the nearest half degree
double _half(double v) => (v * 2).round() / 2;

class ThresholdsScreen extends StatefulWidget {
  const ThresholdsScreen({super.key});

  @override
  State<ThresholdsScreen> createState() => _ThresholdsScreenState();
}

class _ThresholdsScreenState extends State<ThresholdsScreen> {
  final _fridgeService = FridgeService();
  late final Stream<List<Fridge>> _stream = _fridgeService.fridgesStream;

  bool? _isSupervisor; // null while we check the role
  String? _selectedId;

  // The values being edited. Nothing is saved until Save is tapped.
  double _minT = 0, _maxT = 0, _minH = 0, _maxH = 0;
  bool _dirty = false;
  bool _saving = false;
  String? _message;
  bool _messageIsError = false;

  @override
  void initState() {
    super.initState();
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _isSupervisor = false;
    } else {
      AuthService().getUserRole(user.uid).then((role) {
        if (mounted) setState(() => _isSupervisor = role == 'supervisor');
      }).catchError((_) {
        if (mounted) setState(() => _isSupervisor = false);
      });
    }
  }

  void _select(Fridge f) {
    if (f.id == _selectedId) return;
    HapticFeedback.selectionClick();
    setState(() {
      _selectedId = f.id;
      _dirty = false;
      _message = null;
    });
  }

  void _touch(VoidCallback change) {
    setState(() {
      change();
      _dirty = true;
      _message = null;
    });
  }

  Future<void> _save(Fridge f) async {
    setState(() {
      _saving = true;
      _message = null;
    });
    try {
      await _fridgeService.updateThresholds(
        id: f.id,
        minTemp: _minT,
        maxTemp: _maxT,
        minHumidity: _minH,
        maxHumidity: _maxH,
      );
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      setState(() {
        _saving = false;
        _dirty = false;
        _messageIsError = false;
        _message = 'Thresholds saved for ${f.name}.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _messageIsError = true;
        _message = 'Could not save. Check your connection and try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          const ScreenHeader(
            title: 'Threshold Config',
            subtitle: 'Set safe operating ranges per unit.',
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

                final selected = fridges.firstWhere(
                  (f) => f.id == _selectedId,
                  orElse: () => fridges.first,
                );
                _selectedId = selected.id;

                // Keep the sliders in step with the database until the
                // supervisor starts editing.
                if (!_dirty) {
                  _minT = selected.minTemp;
                  _maxT = selected.maxTemp;
                  _minH = selected.minHumidity;
                  _maxH = selected.maxHumidity;
                }

                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 32),
                  children: [
                    _RoleBanner(isSupervisor: _isSupervisor),
                    const SizedBox(height: 22),
                    const _Label('SELECT UNIT'),
                    const SizedBox(height: 10),
                    ...fridges.map(
                      (f) => _UnitTile(
                        fridge: f,
                        selected: f.id == selected.id,
                        onTap: () => _select(f),
                      ),
                    ),
                    const SizedBox(height: 10),
                    _editor(context, selected),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _editor(BuildContext context, Fridge f) {
    final canEdit = _isSupervisor == true && !_saving;

    // Slider bounds: a freezer and a fridge need very different scales.
    // The saved values always fit inside the bounds.
    final freezer = f.maxTemp <= 0;
    final lo = math.min(freezer ? -40.0 : -5.0, f.minTemp.floorToDouble());
    final hi = math.max(freezer ? 5.0 : 25.0, f.maxTemp.ceilToDouble());
    final tempDivisions = ((hi - lo) * 2).round();

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: appSurface(context),
        borderRadius: BorderRadius.circular(18),
        boxShadow: softShadow(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  f.name,
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                ),
              ),
              if (_dirty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.warn.withAlpha(30),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'Unsaved',
                    style: TextStyle(
                      color: AppColors.warn,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 2),
          Text(f.location, style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
          const SizedBox(height: 22),
          _LimitSlider(
            label: 'MIN TEMPERATURE',
            value: _minT,
            min: lo,
            max: hi,
            divisions: tempDivisions,
            display: _precise(_minT),
            onChanged: canEdit
                ? (v) => _touch(() {
                      final r = _half(v);
                      _minT = r > _maxT - 0.5 ? _maxT - 0.5 : r;
                    })
                : null,
          ),
          const SizedBox(height: 14),
          _LimitSlider(
            label: 'MAX TEMPERATURE',
            value: _maxT,
            min: lo,
            max: hi,
            divisions: tempDivisions,
            display: _precise(_maxT),
            onChanged: canEdit
                ? (v) => _touch(() {
                      final r = _half(v);
                      _maxT = r < _minT + 0.5 ? _minT + 0.5 : r;
                    })
                : null,
          ),
          const SizedBox(height: 14),
          const Divider(height: 1),
          const SizedBox(height: 14),
          _LimitSlider(
            label: 'MIN HUMIDITY',
            value: _minH,
            min: 0,
            max: 100,
            divisions: 100,
            display: '${_minH.round()}%',
            onChanged: canEdit
                ? (v) => _touch(() {
                      final r = v.roundToDouble();
                      _minH = r > _maxH - 5 ? _maxH - 5 : r;
                    })
                : null,
          ),
          const SizedBox(height: 14),
          _LimitSlider(
            label: 'MAX HUMIDITY',
            value: _maxH,
            min: 0,
            max: 100,
            divisions: 100,
            display: '${_maxH.round()}%',
            onChanged: canEdit
                ? (v) => _touch(() {
                      final r = v.roundToDouble();
                      _maxH = r < _minH + 5 ? _minH + 5 : r;
                    })
                : null,
          ),
          const SizedBox(height: 8),
          Text(
            'Humidity limits are saved for each unit. Alerts currently trigger on temperature only.',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
          if (_message != null) ...[
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: _messageIsError ? AppColors.dangerLight : AppColors.okLight,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _message!,
                style: TextStyle(
                  color: _messageIsError ? AppColors.danger : AppColors.ok,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
          ],
          if (_isSupervisor == true) ...[
            const SizedBox(height: 18),
            ElevatedButton(
              onPressed: (canEdit && _dirty) ? () => _save(f) : null,
              child: _saving
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Save thresholds'),
            ),
            if (_dirty && !_saving)
              Center(
                child: TextButton(
                  onPressed: () => setState(() {
                    _dirty = false;
                    _message = null;
                  }),
                  child: const Text('Reset changes'),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

// ---------- Small pieces ----------

class _Label extends StatelessWidget {
  final String text;

  const _Label(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
          color: Colors.grey.shade600,
        ),
      ),
    );
  }
}

class _RoleBanner extends StatelessWidget {
  final bool? isSupervisor;

  const _RoleBanner({required this.isSupervisor});

  @override
  Widget build(BuildContext context) {
    if (isSupervisor == null) return const SizedBox.shrink();

    final sup = isSupervisor!;
    final color = sup ? AppColors.teal : AppColors.warn;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: appSurface(context),
        borderRadius: BorderRadius.circular(16),
        boxShadow: softShadow(context),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: color.withAlpha(30),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              sup ? Icons.verified_user_outlined : Icons.lock_outline,
              size: 20,
              color: color,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  sup ? 'Supervisor controls active' : 'View only',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                ),
                const SizedBox(height: 2),
                Text(
                  sup
                      ? 'Changes apply to the selected unit as soon as you save.'
                      : 'Only supervisors can change safe ranges.',
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

class _UnitTile extends StatelessWidget {
  final Fridge fridge;
  final bool selected;
  final VoidCallback onTap;

  const _UnitTile({
    required this.fridge,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final fill = selected
        ? (dark ? AppColors.teal.withAlpha(60) : AppColors.selected)
        : appSurface(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(16),
          boxShadow: softShadow(context),
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          fridge.name,
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          fridge.location,
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '${_limit(fridge.minTemp)} - ${_limit(fridge.maxTemp)}',
                    style: AppTheme.mono(
                      size: 12,
                      weight: FontWeight.w500,
                      color: selected ? AppColors.teal : Colors.grey.shade700,
                    ),
                  ),
                  if (selected) ...[
                    const SizedBox(width: 10),
                    const Icon(Icons.check_circle, size: 20, color: AppColors.teal),
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

class _LimitSlider extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String display;
  final ValueChanged<double>? onChanged;

  const _LimitSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.display,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.1,
            color: Colors.grey.shade600,
          ),
        ),
        Row(
          children: [
            Expanded(
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 6,
                  activeTrackColor: AppColors.teal,
                  inactiveTrackColor: AppColors.teal.withAlpha(40),
                  thumbColor: AppColors.teal,
                  overlayColor: AppColors.teal.withAlpha(30),
                  disabledActiveTrackColor: Colors.grey.shade400,
                  disabledInactiveTrackColor: Colors.grey.withAlpha(50),
                  disabledThumbColor: Colors.grey.shade500,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
                ),
                child: Slider(
                  value: value.clamp(min, max).toDouble(),
                  min: min,
                  max: max,
                  divisions: divisions,
                  onChanged: onChanged,
                ),
              ),
            ),
            SizedBox(
              width: 86,
              child: Text(
                display,
                textAlign: TextAlign.right,
                style: AppTheme.mono(size: 16),
              ),
            ),
          ],
        ),
      ],
    );
  }
}