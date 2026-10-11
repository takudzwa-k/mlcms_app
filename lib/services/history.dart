import '../models/fridge.dart';

/// One stored sensor reading: readings/{fridgeId}/{pushId}
class Reading {
  final int t; // milliseconds since epoch
  final double temp;
  final double hum;
  final bool door;

  const Reading({
    required this.t,
    required this.temp,
    required this.hum,
    required this.door,
  });
}

/// A stretch of time during which a unit was outside its safe range.
class Incident {
  final String fridgeId;
  final String fridgeName;
  final int startMs;
  final int endMs;
  final bool open; // still out of range at the latest reading
  final double peak; // the reading furthest outside the range
  final bool above; // true = too warm, false = too cold

  const Incident({
    required this.fridgeId,
    required this.fridgeName,
    required this.startMs,
    required this.endMs,
    required this.open,
    required this.peak,
    required this.above,
  });

  int get minutes => ((endMs - startMs) / 60000).round();
}

/// The last 24 hours, summarised for one unit.
class UnitStats {
  final Fridge fridge;
  final bool hasHistory;
  final double percentInRange; // 0 to 100
  final double avgTemp;
  final List<Incident> incidents;

  const UnitStats({
    required this.fridge,
    required this.hasHistory,
    required this.percentInRange,
    required this.avgTemp,
    required this.incidents,
  });
}

/// Turns the raw database value into a sorted list of readings.
List<Reading> parseReadings(Object? raw) {
  if (raw is! Map) return <Reading>[];

  final out = <Reading>[];
  for (final v in raw.values) {
    if (v is! Map) continue;
    final t = v['t'];
    final temp = v['temp'];
    if (t is! num || temp is! num) continue;
    final hum = v['hum'];
    out.add(
      Reading(
        t: t.toInt(),
        temp: temp.toDouble(),
        hum: hum is num ? hum.toDouble() : 0,
        door: v['door'] == true,
      ),
    );
  }
  out.sort((a, b) => a.t.compareTo(b.t));
  return out;
}

const _windowMs = 24 * 60 * 60 * 1000;

/// Works out time-in-range, average temperature and incidents for one unit,
/// using the unit's current safe range.
UnitStats computeStats(Fridge f, List<Reading> all, int nowMs) {
  final cutoff = nowMs - _windowMs;
  final r = all.where((x) => x.t >= cutoff).toList();

  if (r.isEmpty) {
    return UnitStats(
      fridge: f,
      hasHistory: false,
      percentInRange: 0,
      avgTemp: 0,
      incidents: const [],
    );
  }

  var inRangeCount = 0;
  var sum = 0.0;
  final incidents = <Incident>[];

  int? runStart;
  var worstDev = 0.0;
  var worstTemp = 0.0;
  var worstAbove = true;

  void close(int endMs, bool open) {
    incidents.add(
      Incident(
        fridgeId: f.id,
        fridgeName: f.name,
        startMs: runStart!,
        endMs: endMs,
        open: open,
        peak: worstTemp,
        above: worstAbove,
      ),
    );
    runStart = null;
  }

  for (final x in r) {
    sum += x.temp;
    final above = x.temp > f.maxTemp;
    final below = x.temp < f.minTemp;

    if (!above && !below) {
      inRangeCount++;
      if (runStart != null) close(x.t, false); // back in range: incident over
    } else {
      final dev = above ? x.temp - f.maxTemp : f.minTemp - x.temp;
      if (runStart == null) {
        runStart = x.t;
        worstDev = dev;
        worstTemp = x.temp;
        worstAbove = above;
      } else if (dev > worstDev) {
        worstDev = dev;
        worstTemp = x.temp;
        worstAbove = above;
      }
    }
  }

  // Still outside the range at the latest reading
  if (runStart != null) {
    final lastT = r.last.t;
    final end = (nowMs - lastT) < 15 * 60000 ? nowMs : lastT;
    close(end, true);
  }

  return UnitStats(
    fridge: f,
    hasHistory: true,
    percentInRange: inRangeCount / r.length * 100,
    avgTemp: sum / r.length,
    incidents: incidents,
  );

  
}

/// How far a breach has progressed, from the minutes the unit has been out
/// of range. These cut-offs are defaults: change them to match your lab's
/// protocol.
enum BreachStage { detect, respond, escalate, diagnose }

BreachStage stageForMinutes(int minutes) {
  if (minutes < 5) return BreachStage.detect;
  if (minutes < 15) return BreachStage.respond;
  if (minutes < 45) return BreachStage.escalate;
  return BreachStage.diagnose;
}

/// Temperature change in °C per minute over the last [windowMin] minutes
/// (a straight-line fit). Returns null when there isn't enough data.
double? rateOfChange(List<Reading> readings, int nowMs, {int windowMin = 20}) {
  final cutoff = nowMs - windowMin * 60000;
  final r = readings.where((x) => x.t >= cutoff).toList();
  if (r.length < 2) return null;

  final spanMin = (r.last.t - r.first.t) / 60000;
  if (spanMin < 3) return null;

  final n = r.length;
  final t0 = r.first.t;
  var sx = 0.0, sy = 0.0, sxx = 0.0, sxy = 0.0;
  for (final x in r) {
    final m = (x.t - t0) / 60000;
    sx += m;
    sy += x.temp;
    sxx += m * m;
    sxy += m * x.temp;
  }

  final denom = n * sxx - sx * sx;
  if (denom == 0) return null;
  return (n * sxy - sx * sy) / denom;
}

/// Minutes the door has been in its current state, or null if it hasn't
/// changed anywhere in the stored history.
int? doorStateMinutes(List<Reading> readings, bool doorOpen, int nowMs) {
  if (readings.isEmpty) return null;

  for (var i = readings.length - 1; i >= 0; i--) {
    if (readings[i].door != doorOpen) {
      final since = i + 1 < readings.length ? readings[i + 1].t : nowMs;
      return ((nowMs - since) / 60000).round();
    }
  }
  return null;
}
