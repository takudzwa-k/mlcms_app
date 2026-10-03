class Fridge {
  final String id;
  final String name;
  final String location;
  final String model;
  final double minTemp;
  final double maxTemp;
  final double temperature;
  final double humidity;
  final bool doorOpen;
  final int lastSeen;

  Fridge({
    required this.id,
    required this.name,
    required this.location,
    required this.model,
    required this.minTemp,
    required this.maxTemp,
    required this.temperature,
    required this.humidity,
    required this.doorOpen,
    required this.lastSeen,
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
      temperature: (map['temperature'] ?? 0).toDouble(),
      humidity: (map['humidity'] ?? 0).toDouble(),
      doorOpen: map['doorOpen'] ?? false,
      lastSeen: map['lastSeen'] ?? 0,
    );
  }

  // true if temperature is within the safe min/max range
  bool get inRange => temperature >= minTemp && temperature <= maxTemp;
}