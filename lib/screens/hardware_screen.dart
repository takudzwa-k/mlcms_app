import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/fridge.dart';
import '../services/auth_service.dart';
import '../services/fridge_service.dart';
import '../services/hardware_service.dart';
import '../theme/app_theme.dart';
import '../widgets/motion.dart';
import '../widgets/surfaces.dart';
import 'manage_fridges_screen.dart';

// ---------- Helpers ----------

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String _two(int n) => n.toString().padLeft(2, '0');

String _clock(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  return '${_two(d.hour)}:${_two(d.minute)}:${_two(d.second)}';
}

String _date(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  return '${d.day} ${_months[d.month - 1]} ${d.year}';
}

String _ago(int s) {
  if (s < 5) return 'just now';
  if (s < 60) return '${s}s ago';
  final m = s ~/ 60;
  if (m < 60) return '$m min ago';
  final h = m ~/ 60;
  if (h < 24) return '$h h ago';
  return '${h ~/ 24} d ago';
}

String _uptime(int s) {
  final d = s ~/ 86400;
  final h = (s % 86400) ~/ 3600;
  final m = (s % 3600) ~/ 60;
  if (d > 0) return '${d}d ${h}h';
  if (h > 0) return '${h}h ${m}m';
  return '${m}m';
}

class _Signal {
  final String label;
  final Color color;
  final IconData icon;

  const _Signal(this.label, this.color, this.icon);
}

_Signal _signal(int rssi) {
  if (rssi >= -55) return const _Signal('Excellent', AppColors.ok, Icons.wifi);
  if (rssi >= -67) return const _Signal('Good', AppColors.ok, Icons.wifi);
  if (rssi >= -75) return const _Signal('Fair', AppColors.warn, Icons.wifi_2_bar);
  return const _Signal('Weak', AppColors.danger, Icons.wifi_1_bar);
}

class _Due {
  final String text;
  final Color color;

  const _Due(this.text, this.color);
}

_Due _dueStatus(int dueMs, int nowMs) {
  final due = DateTime.fromMillisecondsSinceEpoch(dueMs);
  final now = DateTime.fromMillisecondsSinceEpoch(nowMs);
  final days = DateTime.utc(due.year, due.month, due.day)
      .difference(DateTime.utc(now.year, now.month, now.day))
      .inDays;

  if (days < 0) {
    return _Due('Overdue by ${-days} ${days == -1 ? 'day' : 'days'}', AppColors.danger);
  }
  if (days == 0) return const _Due('Due today', AppColors.warn);
  if (days <= 2) return _Due('Due in $days ${days == 1 ? 'day' : 'days'}', AppColors.warn);
  return _Due('Due in $days days', AppColors.teal);
}

enum _PingKind { pending, ok, noReply, error }

class _PingState {
  final _PingKind kind;
  final Duration? took;
  final bool simulated;

  const _PingState(this.kind, {this.took, this.simulated = false});
}

String _pingText(_PingState p) => switch (p.kind) {
      _PingKind.pending => 'Waiting for the node to reply…',
      _PingKind.ok =>
        'Replied in ${(p.took!.inMilliseconds / 1000).toStringAsFixed(1)} s${p.simulated ? ' (simulated)' : ''}',
      _PingKind.noReply => 'No reply after 20 s. The node may be offline or asleep.',
      _PingKind.error => 'Could not send the ping. Check your connection.',
    };

Color _pingColor(_PingState p) => switch (p.kind) {
      _PingKind.pending => Colors.grey,
      _PingKind.ok => AppColors.ok,
      _PingKind.noReply => AppColors.warn,
      _PingKind.error => AppColors.danger,
    };

// ---------- The screen ----------

class HardwareScreen extends StatefulWidget {
  const HardwareScreen({super.key});

  @override
  State<HardwareScreen> createState() => _HardwareScreenState();
}

class _HardwareScreenState extends State<HardwareScreen> {
  final _service = HardwareService();
  final _subs = <StreamSubscription<dynamic>>[];
  Timer? _tick;

  List<Fridge>? _fridges;
  Map<String, DeviceInfo> _devices = {};
  Map<String, TaskState> _tasks = {};
  bool _demo = false;
  bool _failed = false;
  String _userName = '';

  final _pings = <String, _PingState>{};
  final _busyTasks = <String>{};
  String? _taskError;

  @override
  void initState() {
    super.initState();

    // keeps "last data 12 s ago" and the due dates fresh
    _tick = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) setState(() {});
    });

    _subs.add(
      FridgeService().fridgesStream.listen(
        (list) {
          if (!mounted) return;
          setState(() {
            _fridges = [...list]
              ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
          });
        },
        onError: (_) {
          if (mounted) setState(() => _failed = true);
        },
      ),
    );
    _subs.add(
      _service.devicesStream.listen(
        (m) {
          if (mounted) setState(() => _devices = m);
        },
        onError: (_) {},
      ),
    );
    _subs.add(
      _service.tasksStream.listen(
        (m) {
          if (mounted) setState(() => _tasks = m);
        },
        onError: (_) {},
      ),
    );
    _subs.add(
      _service.demoStream.listen(
        (v) {
          if (mounted) setState(() => _demo = v);
        },
        onError: (_) {},
      ),
    );

    _service.ensureBaselines();
    _loadUser();
  }

  @override
  void dispose() {
    _tick?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }

  Future<void> _loadUser() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final data = await AuthService().getUserData(user.uid);
      final name = (data?['name'] ?? '').toString().trim();
      if (!mounted) return;
      setState(() {
        _userName = name.isNotEmpty ? name : (user.email ?? '').split('@').first;
      });
    } catch (_) {
      // the check-up log will say "a team member"
    }
  }

  Future<void> _markDone(MaintenanceTask t) async {
    final who = _userName.isEmpty ? 'a team member' : _userName;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Record this check-up?'),
        content: Text('"${t.title}" will be recorded as done by $who, just now.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Record',
              style: TextStyle(color: AppColors.teal, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() {
      _busyTasks.add(t.id);
      _taskError = null;
    });
    try {
      await _service.markDone(t.id, who);
      HapticFeedback.mediumImpact();
    } catch (_) {
      _taskError = 'Could not save the check-up. Check your connection and try again.';
    }
    if (mounted) setState(() => _busyTasks.remove(t.id));
  }

  Future<void> _ping(Fridge f) async {
    HapticFeedback.selectionClick();
    setState(() => _pings[f.id] = const _PingState(_PingKind.pending));

    try {
      if (_demo) {
        // Demo history is loaded, so there is no real node to answer
        final delay = 1400 + (f.id.hashCode.abs() % 1000);
        await Future.delayed(Duration(milliseconds: delay));
        if (!mounted) return;
        setState(() {
          _pings[f.id] = _PingState(
            _PingKind.ok,
            took: Duration(milliseconds: delay),
            simulated: true,
          );
        });
        return;
      }

      final took = await _service.ping(f.id);
      if (!mounted) return;
      setState(() {
        _pings[f.id] = took == null
            ? const _PingState(_PingKind.noReply)
            : _PingState(_PingKind.ok, took: took);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _pings[f.id] = const _PingState(_PingKind.error));
    }
  }

  Widget _message(String text) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(text, textAlign: TextAlign.center),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Hardware')),
      body: _content(context),
    );
  }

  Widget _content(BuildContext context) {
    final fridges = _fridges;

    if (fridges == null) {
      return _failed
          ? _message('Could not load your units.\nCheck your connection and try again.')
          : const Center(child: CircularProgressIndicator());
    }
    if (fridges.isEmpty) {
      return _message('No fridges yet.\nAdd a unit from the Dashboard first.');
    }

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    bool isOnline(Fridge f) => f.hasData && nowMs - f.lastSeen < 5 * 60 * 1000;

    final online = fridges.where(isOnline).length;
    final sensorsOk = fridges.where((f) => _devices[f.id]?.sensorOk == true).length;
    final sensorsReported = fridges.where((f) => _devices[f.id]?.sensorOk != null).length;
    final bottom = MediaQuery.of(context).padding.bottom;
    var i = 0;

    Color ratioColor(int n) =>
        n == fridges.length ? AppColors.ok : (n == 0 ? AppColors.danger : AppColors.warn);

    return ListView(
      padding: EdgeInsets.fromLTRB(16, 4, 16, bottom + 32),
      children: [
        if (_demo) ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.warnLight,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Text(
              'Demo data is loaded, so the hardware details and ping replies on this '
              'screen are simulated. Clear it in Settings once real readings arrive.',
              style: TextStyle(
                color: AppColors.warn,
                fontWeight: FontWeight.w600,
                fontSize: 12.5,
                height: 1.35,
              ),
            ),
          ),
          const SizedBox(height: 14),
        ],
        FadeSlideIn(key: const ValueKey('intro'), index: i++, child: const _IntroCard()),
        const SizedBox(height: 12),
        FadeSlideIn(
          key: const ValueKey('tiles'),
          index: i++,
          child: Row(
            children: [
              Expanded(
                child: _StatTile(
                  icon: Icons.memory,
                  label: 'NODES ONLINE',
                  value: '$online / ${fridges.length}',
                  caption: 'ESP32 nodes',
                  color: ratioColor(online),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StatTile(
                  icon: Icons.sensors,
                  label: 'SENSORS OK',
                  value: sensorsReported == 0 ? '--' : '$sensorsOk / ${fridges.length}',
                  caption: sensorsReported == 0 ? 'no reports yet' : 'DHT22 sensors',
                  color: sensorsReported == 0 ? Colors.grey : ratioColor(sensorsOk),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 26),
        const _SectionLabel(label: 'SCHEDULED CHECK-UPS', trailing: 'Logged with name and time'),
        const SizedBox(height: 12),
        for (final t in maintenanceTasks)
          FadeSlideIn(
            key: ValueKey('task_${t.id}'),
            index: i++,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _TaskCard(
                task: t,
                state: _tasks[t.id] ?? const TaskState(),
                nowMs: nowMs,
                busy: _busyTasks.contains(t.id),
                onDone: () => _markDone(t),
              ),
            ),
          ),
        if (_taskError != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              _taskError!,
              style: const TextStyle(
                color: AppColors.danger,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
        const SizedBox(height: 14),
        const _SectionLabel(label: 'SENSOR NODES'),
        const SizedBox(height: 12),
        for (final f in fridges)
          FadeSlideIn(
            key: ValueKey('node_${f.id}'),
            index: i++,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _NodeCard(
                fridge: f,
                device: _devices[f.id],
                online: isOnline(f),
                nowMs: nowMs,
                ping: _pings[f.id],
                onPing: () => _ping(f),
              ),
            ),
          ),
        const SizedBox(height: 4),
        Center(
          child: TextButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ManageFridgesScreen()),
            ),
            style: TextButton.styleFrom(foregroundColor: AppColors.teal),
            icon: const Icon(Icons.kitchen_outlined, size: 18),
            label: const Text(
              'Add or remove units in Manage Fridges',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ],
    );
  }
}

// ---------- Shared pieces ----------

class _Panel extends StatelessWidget {
  final Widget child;

  const _Panel({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: appSurface(context),
        borderRadius: BorderRadius.circular(18),
        boxShadow: softShadow(context),
      ),
      child: Padding(padding: const EdgeInsets.all(16), child: child),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  final String? trailing;

  const _SectionLabel({required this.label, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
                color: Colors.grey.shade600,
              ),
            ),
          ),
          if (trailing != null)
            Text(
              trailing!,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.teal,
              ),
            ),
        ],
      ),
    );
  }
}

class _MiniPill extends StatelessWidget {
  final String text;
  final Color color;

  const _MiniPill(this.text, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: TextStyle(color: color, fontSize: 11.5, fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _IntroCard extends StatelessWidget {
  const _IntroCard();

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;

    return _Panel(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: dark ? Colors.white10 : AppColors.selected,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.memory, color: AppColors.teal),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'ESP32 + DHT22 HARDWARE TELEMETRY',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.1,
                    color: AppColors.teal,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  "Tracks each node's connection, sensor health and Wi-Fi signal.",
                  style: TextStyle(fontSize: 13.5, height: 1.4, color: Colors.grey.shade700),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String caption;
  final Color color;

  const _StatTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.caption,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return _Panel(
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
          Text(value, style: AppTheme.mono(size: 28, color: color)),
          const SizedBox(height: 2),
          Text(caption, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
        ],
      ),
    );
  }
}

// ---------- Check-up card ----------

class _TaskCard extends StatelessWidget {
  final MaintenanceTask task;
  final TaskState state;
  final int nowMs;
  final bool busy;
  final VoidCallback onDone;

  const _TaskCard({
    required this.task,
    required this.state,
    required this.nowMs,
    required this.busy,
    required this.onDone,
  });

  @override
  Widget build(BuildContext context) {
    final due = state.dueMs(task);
    final status = due > 0 ? _dueStatus(due, nowMs) : null;
    final color = status?.color ?? AppColors.teal;

    final lastDone = state.lastDoneAt > 0
        ? 'Last done ${_date(state.lastDoneAt)}'
            '${state.lastDoneBy.isEmpty ? '' : ' by ${state.lastDoneBy}'}'
        : 'Not done yet';

    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: color.withAlpha(30),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.event_note_outlined, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.title,
                      style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      task.detail,
                      style: TextStyle(fontSize: 12.5, height: 1.3, color: Colors.grey.shade600),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 10,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (due > 0)
                          Text(
                            'Due ${_date(due)} · ${task.cadence}',
                            style: AppTheme.mono(
                              size: 11.5,
                              weight: FontWeight.w500,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        if (status != null) _MiniPill(status.text, status.color),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  lastDone,
                  style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: busy ? null : onDone,
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(0, 44),
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                ),
                child: busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white),
                      )
                    : const Text('Mark as done'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------- Node card ----------

class _Cell extends StatelessWidget {
  final String label;
  final String value;
  final String? sub;
  final IconData icon;
  final Color? color;
  final bool mono;

  const _Cell({
    required this.label,
    required this.value,
    required this.icon,
    this.sub,
    this.color,
    this.mono = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 13, color: color ?? Colors.grey.shade600),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.9,
                  color: Colors.grey.shade600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: mono
              ? AppTheme.mono(size: 12.5, weight: FontWeight.w600, color: color)
              : TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: color),
        ),
        if (sub != null)
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Text(sub!, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
          ),
      ],
    );
  }
}

class _NodeCard extends StatelessWidget {
  final Fridge fridge;
  final DeviceInfo? device;
  final bool online;
  final int nowMs;
  final _PingState? ping;
  final VoidCallback onPing;

  const _NodeCard({
    required this.fridge,
    required this.device,
    required this.online,
    required this.nowMs,
    required this.ping,
    required this.onPing,
  });

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final f = fridge;
    final d = device;
    final seconds = f.hasData ? ((nowMs - f.lastSeen) / 1000).round() : 0;

    final Color pillColor;
    final String pillLabel;
    if (!f.hasData) {
      pillColor = Colors.grey;
      pillLabel = 'Awaiting data';
    } else if (online) {
      pillColor = AppColors.ok;
      pillLabel = 'Online';
    } else {
      pillColor = AppColors.warn;
      pillLabel = 'Offline';
    }

    // sensor health
    String sensorText;
    Color? sensorColor;
    if (d?.sensorOk == true) {
      sensorText = online ? 'OK' : 'OK (last report)';
      sensorColor = AppColors.ok;
    } else if (d?.sensorOk == false) {
      sensorText = 'Fault: no reading';
      sensorColor = AppColors.danger;
    } else {
      sensorText = 'Not reported';
    }

    final rssi = d?.rssi;
    final sig = rssi == null ? null : _signal(rssi);

    final cells = <Widget>[
      _Cell(
        label: 'DHT22 SENSOR',
        value: sensorText,
        icon: Icons.sensors,
        color: sensorColor,
      ),
      _Cell(
        label: 'WI-FI SIGNAL',
        value: rssi == null ? 'Not reported' : '$rssi dBm (${sig!.label})',
        icon: sig?.icon ?? Icons.wifi,
        color: sig?.color,
      ),
      _Cell(
        label: 'LAST DATA',
        value: f.hasData ? _clock(f.lastSeen) : 'Never',
        sub: f.hasData ? _ago(seconds) : null,
        icon: Icons.schedule,
        mono: true,
      ),
      _Cell(
        label: 'UPTIME',
        value: (online && d?.uptimeS != null) ? _uptime(d!.uptimeS!) : '--',
        icon: Icons.timer_outlined,
        mono: true,
      ),
      _Cell(
        label: 'FIRMWARE',
        value: (d != null && d.fw.isNotEmpty) ? 'v${d.fw}' : '--',
        icon: Icons.developer_board,
        mono: true,
      ),
      if (d != null && d.power.isNotEmpty)
        _Cell(label: 'POWER', value: d.power, icon: Icons.power_outlined),
    ];

    final rows = <Widget>[];
    for (var i = 0; i < cells.length; i += 2) {
      rows.add(
        Padding(
          padding: EdgeInsets.only(top: i == 0 ? 0 : 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: cells[i]),
              const SizedBox(width: 12),
              Expanded(
                child: i + 1 < cells.length ? cells[i + 1] : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      );
    }

    final p = ping;
    final pending = p?.kind == _PingKind.pending;

    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: dark ? Colors.white10 : AppColors.selected,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: const Icon(Icons.memory, size: 20, color: AppColors.teal),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${f.name} Node',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                    ),
                    Text(
                      f.location,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _MiniPill(pillLabel, pillColor),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: dark ? Colors.white.withAlpha(14) : const Color(0xFFF6F7F2),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(children: rows),
          ),
          if (d == null) ...[
            const SizedBox(height: 10),
            Text(
              "This node hasn't sent hardware details yet. They appear once its ESP32 starts reporting.",
              style: TextStyle(fontSize: 12, height: 1.35, color: Colors.grey.shade600),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  'MAC: ${(d != null && d.mac.isNotEmpty) ? d.mac : '--'}',
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.mono(
                    size: 11,
                    weight: FontWeight.w500,
                    color: Colors.grey.shade600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: pending ? null : onPing,
                icon: pending
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.teal,
                        ),
                      )
                    : const Icon(Icons.wifi_tethering, size: 18),
                label: const Text('Ping node'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.teal,
                  side: BorderSide(color: AppColors.teal.withAlpha(120)),
                  minimumSize: const Size(0, 42),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  textStyle: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: p == null
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(
                      _pingText(p),
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: _pingColor(p),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}