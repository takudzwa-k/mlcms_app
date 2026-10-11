class Fridge {
  final String id;
  final String name;
  final String location;
  final String model;
  final double minTemp;
  final double maxTemp;
  final double minHumidity;
  final double maxHumidity;
  final double temperature;
  final double humidity;
  final bool doorOpen;
  final int lastSeen;
  final String ackBy; // who acknowledged the current alert
  final int ackAt; // when (milliseconds since epoch), 0 = never
  final int mutedUntil; // 0 = not muted
  final int coolingLevel; // requested level: -3 (max cooling) to +3, 0 = neutral
  final double? targetTemp; // requested target, if any

  Fridge({
    required this.id,
    required this.name,
    required this.location,
    required this.model,
    required this.minTemp,
    required this.maxTemp,
    this.minHumidity = 30,
    this.maxHumidity = 70,
    required this.temperature,
    required this.humidity,
    required this.doorOpen,
    required this.lastSeen,
    this.ackBy = '',
    this.ackAt = 0,
    this.mutedUntil = 0,
    this.coolingLevel = 0,
    this.targetTemp,
  });

  // Converts raw Firebase data into a Fridge object
  factory Fridge.fromMap(String id, Map<dynamic, dynamic> map) {
    return Fridge(
      id: id,
      name: map['name'] ?? '',
      location: map['location'] ?? '',
      model: map['model'] ?? '',
      minTemp: (map['minTemp'] ?? 0).toDouble(),
      maxTemp: (map['maxTemp'] ?? 0).toDouble(),
      minHumidity: (map['minHumidity'] ?? 30).toDouble(),
      maxHumidity: (map['maxHumidity'] ?? 70).toDouble(),
      temperature: (map['temperature'] ?? 0).toDouble(),
      humidity: (map['humidity'] ?? 0).toDouble(),
      doorOpen: map['doorOpen'] ?? false,
      lastSeen: map['lastSeen'] ?? 0,
      ackBy: (map['ackBy'] ?? '').toString(),
      ackAt: ((map['ackAt'] ?? 0) as num).toInt(),
      mutedUntil: ((map['mutedUntil'] ?? 0) as num).toInt(),
      coolingLevel: ((map['coolingLevel'] ?? 0) as num).toInt(),
      targetTemp:
          map['targetTemp'] is num ? (map['targetTemp'] as num).toDouble() : null,
    );
  }

  // true if temperature is within the safe min/max range
  bool get inRange => temperature >= minTemp && temperature <= maxTemp;

  // false until the sensor has reported at least once
  bool get hasData => lastSeen > 0;

  // true only when there's a real reading and it's outside the safe range
  bool get isBreaching => hasData && !inRange;
}