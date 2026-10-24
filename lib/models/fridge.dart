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
  final int coolingLevel; // old step-based setting, no longer used
  final double? targetTemp; // hold the unit at this temperature, if set
  final double? coolOffset; // manual adjustment in degrees (negative = cooler), if set
  final double? sensorTemp; // what the DHT22 itself measures
  final double coolEffect; // cooling the node is adding right now, in degrees
  final double? coolGoal; // the cooling the node is heading towards
  final int cmdId; // id of the latest request sent from the app
  final int cmdAck; // the latest request id the node has carried out

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
    this.coolOffset,
    this.sensorTemp,
    this.coolEffect = 0,
    this.coolGoal,
    this.cmdId = 0,
    this.cmdAck = 0,
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
      targetTemp: _asDouble(map['targetTemp']),
      coolOffset: _asDouble(map['coolOffset']),
      sensorTemp: _asDouble(map['sensorTemp']),
      coolEffect: _asDouble(map['coolEffect']) ?? 0,
      coolGoal: _asDouble(map['coolGoal']),
      cmdId: ((map['cmdId'] ?? 0) as num).toInt(),
      cmdAck: ((map['cmdAck'] ?? 0) as num).toInt(),
    );
  }

  static double? _asDouble(Object? v) => v is num ? v.toDouble() : null;

  // true if temperature is within the safe min/max range
  bool get inRange => temperature >= minTemp && temperature <= maxTemp;

  // false until the sensor has reported at least once
  bool get hasData => lastSeen > 0;

  // true only when there's a real reading and it's outside the safe range
  bool get isBreaching => hasData && !inRange;

  // a request has been sent from the app but the node hasn't picked it up yet
  bool get commandPending => cmdId != 0 && cmdId != cmdAck;
}