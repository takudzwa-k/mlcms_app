import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'alert_state.dart';
import 'notification_service.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final DatabaseReference _usersRef = FirebaseDatabase.instance.ref('users');

  // Tells the rest of the app: "is someone logged in right now?"
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  // Creates a new account and saves their role (and name, if given)
  Future<UserCredential> signUp(
    String email,
    String password,
    String role, {
    String name = '',
  }) async {
    final cred = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
    await _usersRef.child(cred.user!.uid).set({
      'email': email,
      'role': role,
      if (name.isNotEmpty) 'name': name,
    });
    return cred;
  }

  // Logs an existing user in
  Future<UserCredential> signIn(String email, String password) {
    return _auth.signInWithEmailAndPassword(email: email, password: password);
  }

  // Sends Firebase's password-reset email
  Future<void> sendPasswordReset(String email) {
    return _auth.sendPasswordResetEmail(email: email);
  }

  // Looks up whether a user is a technician or supervisor
  Future<String?> getUserRole(String uid) async {
    final snapshot = await _usersRef.child(uid).child('role').get();
    return snapshot.exists ? snapshot.value as String : null;
  }

  Future<Map<String, dynamic>?> getUserData(String uid) async {
    final snapshot = await _usersRef.child(uid).get();
    if (!snapshot.exists) return null;
    return Map<String, dynamic>.from(snapshot.value as Map);
  }

  Future<void> updateDisplayName(String uid, String name) async {
    await _usersRef.child(uid).update({'name': name});
  }

  Future<void> signOut() async {
    AlertState.unread.value = 0; // clear the Alerts badge
    await NotificationService.stop(); // stop alerts on this phone
    await _auth.signOut();
  }
}