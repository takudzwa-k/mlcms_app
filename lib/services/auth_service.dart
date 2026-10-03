import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final DatabaseReference _usersRef = FirebaseDatabase.instance.ref('users');

  // Tells the rest of the app: "is someone logged in right now?"
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  // Creates a new account, and saves their role (technician/supervisor)
  Future<UserCredential> signUp(String email, String password, String role) async {
    final cred = await _auth.createUserWithEmailAndPassword(email: email, password: password);
    await _usersRef.child(cred.user!.uid).set({'email': email, 'role': role});
    return cred;
  }

  // Logs an existing user in
  Future<UserCredential> signIn(String email, String password) {
    return _auth.signInWithEmailAndPassword(email: email, password: password);
  }

  // Looks up whether a user is a technician or supervisor
  Future<String?> getUserRole(String uid) async {
    final snapshot = await _usersRef.child(uid).child('role').get();
    return snapshot.exists ? snapshot.value as String : null;
  }

  Future<void> signOut() => _auth.signOut();
}