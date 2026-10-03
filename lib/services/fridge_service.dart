import 'package:firebase_database/firebase_database.dart';
import '../models/fridge.dart';

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
    Stream<Fridge?> fridgeStream(String id) {
    return _fridgesRef.child(id).onValue.map((event) {
      final data = event.snapshot.value;
      if (data == null) return null;
      return Fridge.fromMap(id, Map<dynamic, dynamic>.from(data as Map));
    });
  }
}