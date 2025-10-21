// lib/services/auth_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

class AuthService {
  AuthService._();
  static final instance = AuthService._();

  final _auth = FirebaseAuth.instance;
  final _db = FirebaseFirestore.instance;

  Stream<User?> authChanges() => _auth.authStateChanges();
  User? get currentUser => _auth.currentUser;

  Future<void> _ensureUserProfile(User u) async {
    final ref = _db.collection('users').doc(u.uid);
    final snap = await ref.get();
    if (!snap.exists) {
      await ref.set({
        'uid': u.uid,
        'email': u.email,
        'displayName': u.displayName,
        'photoURL': u.photoURL,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } else {
      await ref.update({'updatedAt': FieldValue.serverTimestamp()});
    }
  }

  // -------- Email/Password --------
  Future<void> signUpWithEmail({
    required String email,
    required String password,
    String? displayName,
  }) async {
    final cred = await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    if (displayName != null && displayName.trim().isNotEmpty) {
      await cred.user!.updateDisplayName(displayName.trim());
    }
    await _ensureUserProfile(cred.user!);
  }

  Future<void> signInWithEmail({
    required String email,
    required String password,
  }) async {
    final cred = await _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    await _ensureUserProfile(cred.user!);
  }

  // --- Password reset ---
  Future<void> sendPasswordReset(String email) async {
    final e = email.trim();
    if (e.isEmpty)
      throw FirebaseAuthException(
        code: 'invalid-email',
        message: 'Enter your email',
      );
    await _auth.sendPasswordResetEmail(email: e);
  }

  // -------- Google (Android) --------
  Future<void> signInWithGoogle() async {
    final g = GoogleSignIn(scopes: ['email']);
    final acc = await g.signIn();
    if (acc == null) throw Exception('Sign-in aborted');
    final auth = await acc.authentication;
    final credential = GoogleAuthProvider.credential(
      accessToken: auth.accessToken,
      idToken: auth.idToken,
    );
    final cred = await _auth.signInWithCredential(credential);
    await _ensureUserProfile(cred.user!);
  }

  Future<void> signOut() async {
    await _auth.signOut();
    try {
      final g = GoogleSignIn();
      if (await g.isSignedIn()) await g.signOut();
    } catch (_) {}
  }
}
