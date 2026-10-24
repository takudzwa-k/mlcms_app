import 'package:firebase_database/firebase_database.dart';
import '../models/fridge.dart';
import 'dart:math' as math;

class FridgeService {
  final DatabaseReference _fridgesRef = FirebaseDatabase.instance.ref('fridges');

  // A live stream of all fridges — updates automatically whenever the data changes in Firebase
  Stream<List<Fridge>> get fridgesStream {
    return _fridgesRef.onValue.map((event) {
      final data = event.snapshot.value;
      if (data == null) return <Fridge>[];

      final map = Map<dynamic, dynamic>.from(data as Map);
      return map.entries
          .map((entry) => Fridge.fromMap(entry.key, Map<dynamic, dynamic>.from(entry.value)))
          .toList();
    });
  }
  
    Future<void> addFridge({
    required String name,
    required String location,
    required double minTemp,
    required double maxTemp,
  }) async {
    final newFridgeRef = _fridgesRef.push(); // generates a unique ID automatically
    await newFridgeRef.set({
      'name': name,
      'location': location,
      'model': 'ESP32-DHT22',
      'minTemp': minTemp,
      'maxTemp': maxTemp,
      'temperature': 0,
      'humidity': 0,
      'doorOpen': false,
      'lastSeen': 0,
    });
  }
    Future<void> deleteFridge(String id) async {
    await _fridgesRef.child(id).remove();
  }
    Future<void> updateFridge({
    required String id,
    required String name,
    required String location,
    required double minTemp,
    required double maxTemp,
  }) async {
    await _fridgesRef.child(id).update({
      'name': name,
      'location': location,
      'minTemp': minTemp,
      'maxTemp': maxTemp,
    });
  }
    Future<void> updateThresholds({
    required String id,
    required double minTemp,
    required double maxTemp,
    required double minHumidity,
    required double maxHumidity,
  }) async {
    await _fridgesRef.child(id).update({
      'minTemp': minTemp,
      'maxTemp': maxTemp,
      'minHumidity': minHumidity,
      'maxHumidity': maxHumidity,
    });
  }  
    Stream<Fridge?> fridgeStream(String id) {
    return _fridgesRef.child(id).onValue.map((event) {
      final data = event.snapshot.value;
      if (data == null) return null;
      return Fridge.fromMap(id, Map<dynamic, dynamic>.from(data as Map));
    });
  }
   Future<void> acknowledge(String id, String by) async {
    await _fridgesRef.child(id).update({
      'ackBy': by,
      'ackAt': DateTime.now().millisecondsSinceEpoch,
    });
  }

  // untilMs = 0 clears the mute
  Future<void> setMute(String id, int untilMs) async {
    await _fridgesRef.child(id).update({'mutedUntil': untilMs});
  }

  // Saves a cooling request to the command log and tells the node what to do.
  //   target: hold the unit at this temperature
  //   offset: add this many degrees to the sensor reading (negative = cooler)
  //   reset:  go back to automatic
  Future<void> logCommand({
    required String id,
    required String type,
    required String by,
    String? note,
    double? target,
    double? offset,
    double? delta,
    bool reset = false,
  }) async {
    final db = FirebaseDatabase.instance.ref();
    final key = db.child('commands/$id').push().key!;

    final updates = <String, Object?>{
      'commands/$id/$key': {
        't': DateTime.now().millisecondsSinceEpoch,
        'type': type,
        'by': by,
        if (note != null && note.isNotEmpty) 'note': note,
        if (target != null) 'target': target,
        if (offset != null) 'offset': offset,
        if (delta != null) 'delta': delta,
      },
      // The node compares this number with the last one it carried out,
      // which is how the app can tell when a request has been picked up.
      'fridges/$id/cmdId': math.Random().nextInt(2000000000) + 1,
      'fridges/$id/coolingLevel': null, // the old step setting is no longer used
    };

    if (reset) {
      updates['fridges/$id/coolOffset'] = null;
      updates['fridges/$id/targetTemp'] = null;
    } else if (target != null) {
      updates['fridges/$id/targetTemp'] = target;
      updates['fridges/$id/coolOffset'] = null;
    } else if (offset != null) {
      updates['fridges/$id/coolOffset'] = offset;
      updates['fridges/$id/targetTemp'] = null;
    }

    await db.update(updates);
  }
}