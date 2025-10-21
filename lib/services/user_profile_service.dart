// lib/services/user_profile_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';

class UserProfileService {
  UserProfileService._();
  static final instance = UserProfileService._();

  final _db = FirebaseFirestore.instance;

  Future<Map<String, dynamic>?> getProfile(String uid) async {
    final snap = await _db.collection('users').doc(uid).get();
    return snap.data();
  }

  Future<void> updateProfile(String uid, Map<String, dynamic> data) async {
    await _db.collection('users').doc(uid).set({
      ...data,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}
