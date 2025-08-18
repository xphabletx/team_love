import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Handles username <-> account mapping:
/// - claimUsername(): atomically reserve a unique username and write it to users/{uid}
/// - resolveEmailFromIdentifier(): accept username OR email and return an email
class UsernameService {
  UsernameService._();
  static final instance = UsernameService._();

  final _db = FirebaseFirestore.instance;

  /// Username rules: lowercase letters, numbers, underscore, dot, hyphen; 3–20 chars.
  final RegExp _usernameRx = RegExp(r'^[a-z0-9._-]{3,20}$');

  String normalize(String username) => username.trim().toLowerCase();

  void validateFormat(String username) {
    final s = username.trim().toLowerCase();
    if (!_usernameRx.hasMatch(s)) {
      throw const FormatException(
        'Username must be 3–20 chars: a–z, 0–9, . _ - only.',
      );
    }
  }

  /// Atomically claims a username for the current user.
  /// Fails if the username doc already exists.
  ///
  /// Writes:
  /// - usernames/{usernameLower} -> { uid, email, createdAt }
  /// - users/{uid} (merge) -> { username }
  Future<void> claimUsername({
    required String username,
    required String email,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw StateError('No signed-in user.');
    }

    final uname = normalize(username);
    validateFormat(uname);

    final unameRef = _db.collection('usernames').doc(uname);
    final userRef = _db.collection('users').doc(user.uid);

    await _db.runTransaction((txn) async {
      final existing = await txn.get(unameRef);
      if (existing.exists) {
        throw StateError('That username is already taken.');
      }
      txn.set(unameRef, {
        'uid': user.uid,
        'email': email,
        'createdAt': FieldValue.serverTimestamp(),
      });
      txn.set(userRef, {
        'uid': user.uid,
        'email': email,
        'username': uname,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    });
  }

  /// Convert an identifier (email OR username) into an email for Firebase Auth.
  Future<String> resolveEmailFromIdentifier(String identifier) async {
    final input = identifier.trim();
    if (input.contains('@')) {
      return input; // looks like an email
    }
    final uname = normalize(input);
    final snap = await _db.collection('usernames').doc(uname).get();
    final data = snap.data();
    if (data == null || (data['email'] as String?) == null) {
      throw StateError('No account found for "$identifier".');
    }
    return data['email'] as String;
  }
}
