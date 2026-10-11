import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';

/// Shared state for the Alerts feed: how many alerts the signed-in user
/// hasn't seen yet, and when they last pressed "Mark all read".
class AlertState {
  /// Number of unread alerts. The Alerts screen keeps this up to date and
  /// the tab bar shows it as a badge.
  static final ValueNotifier<int> unread = ValueNotifier<int>(0);

  static DatabaseReference? _readAtRef() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    return FirebaseDatabase.instance.ref('users/${user.uid}/alertsReadAt');
  }

  /// The time (milliseconds since epoch) the user last marked everything read.
  static Stream<int> readAtStream() {
    final ref = _readAtRef();
    if (ref == null) return Stream<int>.value(0);
    return ref.onValue.map((event) {
      final v = event.snapshot.value;
      return v is num ? v.toInt() : 0;
    });
  }

  static Future<void> markAllRead() async {
    final ref = _readAtRef();
    if (ref == null) return;
    await ref.set(DateTime.now().millisecondsSinceEpoch);
  }
}