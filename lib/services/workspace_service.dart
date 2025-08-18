import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class WorkspaceService {
  WorkspaceService._();
  static final instance = WorkspaceService._();

  final _db = FirebaseFirestore.instance;

  /// Ensures a user profile exists and returns the current workspace id (or null).
  Future<String?> ensureProfileAndGetWorkspaceId(User user) async {
    final userRef = _db.collection('users').doc(user.uid);
    final snap = await userRef.get();
    if (!snap.exists) {
      await userRef.set({
        'uid': user.uid,
        'email': user.email,
        'createdAt': DateTime.now().toIso8601String(),
        'currentWorkspaceId': null,
      });
      return null;
    }
    return (snap.data()?['currentWorkspaceId'] as String?);
  }

  /// Creates a workspace owned by the current user and returns (workspaceId, joinCode).
  Future<({String workspaceId, String joinCode})> createWorkspace() async {
    final user = FirebaseAuth.instance.currentUser!;
    final wsRef = _db.collection('workspaces').doc();
    final joinCode = _randomCode();

    await wsRef.set({
      'id': wsRef.id,
      'name': 'Team Love',
      'ownerUid': user.uid,
      'createdAt': DateTime.now().toIso8601String(),
      'joinCode': joinCode,
    });

    await wsRef.collection('members').doc(user.uid).set({
      'uid': user.uid,
      'role': 'owner',
      'joinedAt': DateTime.now().toIso8601String(),
    });

    await _db.collection('users').doc(user.uid).update({
      'currentWorkspaceId': wsRef.id,
    });

    return (workspaceId: wsRef.id, joinCode: joinCode);
  }

  /// Joins a workspace by invite code. Returns true if joined.
  Future<bool> joinByCode(String code) async {
    final user = FirebaseAuth.instance.currentUser!;
    final q = await _db
        .collection('workspaces')
        .where('joinCode', isEqualTo: code.trim().toUpperCase())
        .limit(1)
        .get();

    if (q.docs.isEmpty) return false;
    final ws = q.docs.first;

    // Upsert membership
    await ws.reference.collection('members').doc(user.uid).set({
      'uid': user.uid,
      'role': 'editor',
      'joinedAt': DateTime.now().toIso8601String(),
    });

    await _db.collection('users').doc(user.uid).update({
      'currentWorkspaceId': ws.id,
    });

    return true;
  }

  String _randomCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // no confusing 0/O/I/1
    final rnd = Random();
    return List.generate(6, (_) => chars[rnd.nextInt(chars.length)]).join();
  }
}
