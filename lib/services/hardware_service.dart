import 'dart:math' as math;
import 'dart:async';
import 'package:firebase_database/firebase_database.dart';

int? _asInt(Object? v) => v is num ? v.toInt() : null;

/// Health details a node reports about itself: devices/{fridgeId}
class DeviceInfo {
  final String id;
  final String mac;
  final String fw;
  final int? rssi; // Wi-Fi signal in dBm
  final bool? sensorOk; // null = the node hasn't reported it
  final int? uptimeS;
  final String power; // optional, for example "Mains" or "Battery 87%"

  const DeviceInfo({
    required this.id,
    required this.mac,
    required this.fw,
    required this.rssi,
    required this.sensorOk,
    required this.uptimeS,
    required this.power,
  });

  factory DeviceInfo.fromMap(String id, Map<dynamic, dynamic> m) {
    return DeviceInfo(
      id: id,
      mac: (m['mac'] ?? '').toString(),
      fw: (m['fw'] ?? '').toString(),
      rssi: _asInt(m['rssi']),
      sensorOk: m['sensorOk'] is bool ? m['sensorOk'] as bool : null,
      uptimeS: _asInt(m['uptimeS']),
      power: (m['power'] ?? '').toString(),
    );
  }
}

/// A recurring check-up. The tasks live in code; completions live in the
/// database under maintenance/{taskId}.
class MaintenanceTask {
  final String id;
  final String title;
  final String detail;
  final String cadence;
  final int everyDays;

  const MaintenanceTask({
    required this.id,
    required this.title,
    required this.detail,
    required this.cadence,
    required this.everyDays,
  });
}

const maintenanceTasks = [
  MaintenanceTask(
    id: 'weekly_inspection',
    title: 'Weekly node inspection',
    detail: 'Check door seals, wiring and sensor placement',
    cadence: 'Weekly',
    everyDays: 7,
  ),
  MaintenanceTask(
    id: 'monthly_calibration',
    title: 'Monthly sensor calibration check',
    detail: 'Compare each DHT22 against a reference thermometer',
    cadence: 'Monthly',
    everyDays: 30,
  ),
];

class TaskState {
  final int startAt; // when the schedule began (first time the screen opened)
  final int lastDoneAt; // 0 = never
  final String lastDoneBy;

  const TaskState({this.startAt = 0, this.lastDoneAt = 0, this.lastDoneBy = ''});

  /// When the task is next due, in milliseconds since epoch (0 = not known yet).
  int dueMs(MaintenanceTask t) {
    final base = lastDoneAt > 0 ? lastDoneAt : startAt;
    return base == 0 ? 0 : base + t.everyDays * 86400000;
  }
}

class HardwareService {
  final DatabaseReference _db = FirebaseDatabase.instance.ref();

  Stream<Map<String, DeviceInfo>> get devicesStream {
    return _db.child('devices').onValue.map((event) {
      final raw = event.snapshot.value;
      final out = <String, DeviceInfo>{};
      if (raw is Map) {
        raw.forEach((key, value) {
          if (value is Map) {
            out[key.toString()] = DeviceInfo.fromMap(key.toString(), value);
          }
        });
      }
      return out;
    });
  }

  Stream<Map<String, TaskState>> get tasksStream {
    return _db.child('maintenance').onValue.map((event) {
      final raw = event.snapshot.value;
      final out = <String, TaskState>{};
      if (raw is Map) {
        raw.forEach((key, value) {
          if (value is Map) {
            out[key.toString()] = TaskState(
              startAt: _asInt(value['startAt']) ?? 0,
              lastDoneAt: _asInt(value['lastDoneAt']) ?? 0,
              lastDoneBy: (value['lastDoneBy'] ?? '').toString(),
            );
          }
        });
      }
      return out;
    });
  }

  /// True while demo history is loaded (the Demo tools mark it).
  Stream<bool> get demoStream {
    return _db.child('readings/_demo').onValue.map((e) => e.snapshot.value is num);
  }

  /// Starts the schedule for any check-up that has never been set up.
  Future<void> ensureBaselines() async {
    try {
      final snap = await _db.child('maintenance').get();
      final raw = snap.value;
      final existing = raw is Map
          ? raw.keys.map((k) => k.toString()).toSet()
          : <String>{};
      final now = DateTime.now().millisecondsSinceEpoch;

      final updates = <String, Object?>{};
      for (final t in maintenanceTasks) {
        if (!existing.contains(t.id)) {
          updates['maintenance/${t.id}/startAt'] = now;
        }
      }
      if (updates.isNotEmpty) await _db.update(updates);
    } catch (_) {
      // the screen still works; the due dates just appear a little later
    }
  }

  /// Records a completed check-up, with who did it and when.
  Future<void> markDone(String taskId, String by) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final key = _db.child('maintenance/$taskId/log').push().key!;
    await _db.update({
      'maintenance/$taskId/lastDoneAt': now,
      'maintenance/$taskId/lastDoneBy': by,
      'maintenance/$taskId/log/$key': {'t': now, 'by': by},
    });
  }

  /// Asks a node to answer. The ESP32 copies the request value into
  /// devices/{id}/pingAck, so the clocks on the phone and the node don't matter.
  /// Returns how long the reply took, or null if there was none in time.
  Future<Duration?> ping(
    String id, {
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final ref = _db.child('devices/$id');
    final sent = math.Random().nextInt(2000000000) + 1;
    final started = DateTime.now();

    await ref.update({'pingAt': sent});

    final replied = await ref
        .child('pingAck')
        .onValue
        .map((e) => e.snapshot.value)
        .timeout(timeout, onTimeout: (sink) => sink.close())
        .any((v) => v is num && v.toInt() == sent);

    return replied ? DateTime.now().difference(started) : null;
  }
}