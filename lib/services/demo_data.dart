import 'dart:math' as math;
import 'package:firebase_database/firebase_database.dart';
import '../models/fridge.dart';

/// An earlier, already-resolved excursion above a unit's max limit.
class _Excursion {
  final int startedMinutesAgo;
  final int lengthMinutes;
  final double peakOver; // degrees above the max limit at the worst point

  const _Excursion(this.startedMinutesAgo, this.lengthMinutes, this.peakOver);
}

/// Simulated history for demos. The real ESP32 will write the same shape:
///   readings/{fridgeId}/{pushId} = { t, temp, hum, door }
class DemoData {
  static const _intervalMinutes = 5;
  static const _hours = 24;

  // Past excursions, handed out to units in order
  static const List<List<_Excursion>> _past = [
    [],
    [_Excursion(430, 25, 3.5)],
    [_Excursion(850, 40, 4.8), _Excursion(190, 18, 2.2)],
  ];

  /// Replaces each unit's history with 24 hours of readings and marks the
  /// units as live. Units that have never reported are skipped.
  /// Returns how many readings were written.
  static Future<int> generate(List<Fridge> fridges) async {
    final db = FirebaseDatabase.instance.ref();
    final now = DateTime.now().millisecondsSinceEpoch;
    const points = _hours * 60 ~/ _intervalMinutes;

    final updates = <String, Object?>{};
    var written = 0;
    var unitIndex = 0;

    for (final f in fridges) {
      if (!f.hasData) continue;

      final rnd = math.Random(f.id.hashCode);
      final mid = (f.minTemp + f.maxTemp) / 2;
      final half = (f.maxTemp - f.minTemp) / 2;
      final past = _past[unitIndex % _past.length];
      unitIndex++;

      // If the unit is out of range right now, show it drifting out of range
      // in a straight line from the middle of its safe range.
      double ramp = 0;
      if (f.isBreaching) {
        final edge = f.temperature > f.maxTemp ? f.maxTemp : f.minTemp;
        final desiredMinutes = 18 + rnd.nextInt(30);
        final ratio = (f.temperature - mid) / (f.temperature - edge);
        ramp = math.min(desiredMinutes * ratio, 240.0);
      }

      final readings = <String, Object?>{};

      for (var i = 0; i < points; i++) {
        final minutesAgo = (points - 1 - i) * _intervalMinutes;
        final t = now - minutesAgo * 60000;

        // normal behaviour: a gentle wave plus a little noise
        var temp = mid +
            math.sin(i / 14.0) * half * 0.18 +
            (rnd.nextDouble() - 0.5) * half * 0.12;
        var hum = f.humidity +
            math.sin(i / 20.0) * 2.5 +
            (rnd.nextDouble() - 0.5) * 2;
        var door = false;

        // earlier excursions: the door was left open and the unit warmed up
        for (final ex in past) {
          final progress =
              (ex.startedMinutesAgo - minutesAgo) / ex.lengthMinutes;
          if (progress >= 0 && progress <= 1) {
            temp = f.maxTemp +
                ex.peakOver * (0.4 + 0.6 * math.sin(math.pi * progress));
            hum += 6;
            door = true;
          }
        }

        // the current drift out of range
        if (ramp > 0 && minutesAgo <= ramp) {
          temp = f.temperature +
              (mid - f.temperature) * (minutesAgo / ramp) +
              (rnd.nextDouble() - 0.5) * 0.06;
        }

        // the newest reading always matches what the unit shows right now
        if (i == points - 1) {
          temp = f.temperature;
          hum = f.humidity;
          door = false;
        }

        hum = hum.clamp(0.0, 100.0).toDouble();

        final key = db.child('readings/${f.id}').push().key!;
        readings[key] = {
          't': t,
          'temp': double.parse(temp.toStringAsFixed(1)),
          'hum': double.parse(hum.toStringAsFixed(1)),
          'door': door,
        };
      }

      updates['readings/${f.id}'] = readings;
      updates['fridges/${f.id}/lastSeen'] = now; // shows the unit as live
      written += points;
    }

    if (updates.isEmpty) return 0;
    await db.update(updates);
    return written;
  }

  /// Removes every stored reading.
  static Future<void> clear() {
    return FirebaseDatabase.instance.ref('readings').remove();
  }
}