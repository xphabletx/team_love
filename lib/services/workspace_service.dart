// lib/services/workspace_service.dart
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class WorkspaceService {
  WorkspaceService._();
  static final WorkspaceService instance = WorkspaceService._();

  final _db = FirebaseFirestore.instance;
  User get _user => FirebaseAuth.instance.currentUser!;

  // -----------------------------
  // Collections & helpers
  // -----------------------------
  CollectionReference<Map<String, dynamic>> get _workspaces =>
      _db.collection('workspaces');
  DocumentReference<Map<String, dynamic>> _userDoc(String uid) =>
      _db.collection('users').doc(uid);

  String _newCode() {
    const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final r = Random.secure();
    return List.generate(6, (_) => alphabet[r.nextInt(alphabet.length)]).join();
  }

  // -----------------------------
  // CREATE + JOIN
  // -----------------------------

  Future<CreateWsResult> createWorkspace({String name = 'Team Love'}) async {
    final uid = _user.uid;
    final wsRef = _workspaces.doc();
    final joinCode = _newCode();

    final batch = _db.batch();

    // Workspace document — ARRAY is the source of truth for membership
    batch.set(wsRef, {
      'id': wsRef.id,
      'name': name,
      'ownerUid': uid,
      'joinCode': joinCode,
      'memberUids': [uid],
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // Best-effort: keep a member sub-doc (UI no longer depends on this)
    final memberRef = wsRef.collection('members').doc(uid);
    batch.set(memberRef, {
      'uid': uid,
      'role': 'owner',
      'joinedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // Ensure user profile + set current workspace
    final u = FirebaseAuth.instance.currentUser!;
    batch.set(_userDoc(uid), {
      'uid': uid,
      'email': u.email,
      'displayName': u.displayName,
      'currentWorkspaceId': wsRef.id,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await batch.commit();

    // Safety: patch sub-doc if missing (shouldn’t be needed, but harmless)
    final mSnap = await memberRef.get();
    if (!mSnap.exists) {
      await memberRef.set({
        'uid': uid,
        'role': 'owner',
        'joinedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }

    print("✅ Workspace created: ${wsRef.id} joinCode=$joinCode");
    return CreateWsResult(workspaceId: wsRef.id, joinCode: joinCode);
  }

  Future<bool> joinByCode(String rawCode) async {
    final code = rawCode.trim().toUpperCase();
    if (code.isEmpty) return false;

    final q = await _workspaces
        .where('joinCode', isEqualTo: code)
        .limit(1)
        .get();
    if (q.docs.isEmpty) return false;

    final wsRef = q.docs.first.reference;
    final uid = _user.uid;

    try {
      await _db.runTransaction((tx) async {
        // Add to membership array
        tx.update(wsRef, {
          'memberUids': FieldValue.arrayUnion([uid]),
          'updatedAt': FieldValue.serverTimestamp(),
        });

        // Best-effort: member sub-doc
        final mRef = wsRef.collection('members').doc(uid);
        final mSnap = await tx.get(mRef);
        if (!mSnap.exists) {
          tx.set(mRef, {
            'uid': uid,
            'role': 'editor',
            'joinedAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          });
        } else {
          tx.set(mRef, {
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        }

        // Always set user’s current workspace
        final userRef = _userDoc(uid);
        tx.set(userRef, {
          'uid': uid,
          'currentWorkspaceId': wsRef.id,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      });

      print("✅ Joined workspace ${wsRef.id}");
      return true;
    } catch (e, st) {
      print("❌ joinByCode failed: $e\n$st");
      return false;
    }
  }

  // -----------------------------
  // READ / WATCH
  // -----------------------------

  /// Card list in Workspace screen.
  /// 👉 Uses array-contains on `memberUids` (no subcollection dependency).
  Stream<List<WorkspaceSummary>> myMemberships() {
    final uid = _user.uid;

    return _workspaces.where('memberUids', arrayContains: uid).snapshots().map((
      snap,
    ) {
      final out = <WorkspaceSummary>[];
      for (final d in snap.docs) {
        final data = d.data();
        out.add(
          WorkspaceSummary(
            id: data['id'] as String? ?? d.id,
            name: (data['name'] as String?) ?? 'Workspace',
            role: (data['ownerUid'] == uid) ? 'owner' : 'editor',
          ),
        );
      }
      out.sort((a, b) => a.name.compareTo(b.name));
      return out;
    });
  }

  /// Minimal data for other screens that only need name/id/(optional) join code.
  Stream<WorkspaceLite?> watchWorkspace(String wsId) {
    return _workspaces.doc(wsId).snapshots().map((d) {
      final data = d.data();
      if (data == null) return null;
      return WorkspaceLite(
        id: data['id'] as String? ?? d.id,
        name: (data['name'] as String?) ?? 'Workspace',
        joinCode: data['joinCode'] as String?,
      );
    });
  }

  /// Members are derived from the `memberUids` array.
  /// Role is inferred: owner vs editor.
  Stream<List<Map<String, dynamic>>> watchMembers(String wsId) {
    final myUid = _user.uid;
    return _workspaces.doc(wsId).snapshots().map((snap) {
      final data = snap.data() ?? const {};
      final ownerUid = data['ownerUid'] as String?;
      final memberUids = List<String>.from(
        (data['memberUids'] as List?) ?? const [],
      );
      memberUids.sort((a, b) {
        // show owner first, then alphabetical
        if (a == ownerUid && b != ownerUid) return -1;
        if (b == ownerUid && a != ownerUid) return 1;
        return a.compareTo(b);
      });
      return memberUids
          .map(
            (uid) => {
              'uid': uid,
              'role': uid == ownerUid ? 'owner' : 'editor',
              'isMe': uid == myUid,
            },
          )
          .toList();
    });
  }

  // -----------------------------
  // PROFILE / CURRENT WORKSPACE
  // -----------------------------

  Future<String?> ensureProfileAndGetWorkspaceId(User u) async {
    final userRef = _userDoc(u.uid);
    await userRef.set({
      'uid': u.uid,
      'email': u.email,
      'displayName': u.displayName,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    final snap = await userRef.get();
    return (snap.data() ?? const {})['currentWorkspaceId'] as String?;
  }

  Future<void> setCurrentWorkspace(String wsId) async {
    await _userDoc(_user.uid).set({
      'currentWorkspaceId': wsId,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  // -----------------------------
  // ADMIN / MAINTENANCE
  // -----------------------------

  Future<String> regenerateJoinCode(String wsId) async {
    final code = _newCode();
    await _workspaces.doc(wsId).set({
      'joinCode': code,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    return code;
  }

  /// Keeps legacy behavior for the popup in your UI.
  /// If you make someone owner, we just switch `ownerUid`.
  Future<void> setMemberRole(String wsId, String memberUid, String role) async {
    final wsRef = _workspaces.doc(wsId);
    if (role == 'owner') {
      await wsRef.set({
        'ownerUid': memberUid,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } else {
      // no special field to change for 'editor' — keep sub-doc best-effort
      await wsRef.collection('members').doc(memberUid).set({
        'role': 'editor',
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
  }

  Future<void> removeMember(String wsId, String memberUid) async {
    final wsRef = _workspaces.doc(wsId);

    await _db.runTransaction((tx) async {
      final snap = await tx.get(wsRef);
      final data = snap.data() ?? const {};
      final ownerUid = data['ownerUid'] as String?;
      final members = List<String>.from(
        (data['memberUids'] as List?) ?? const [],
      );

      if (!members.contains(memberUid)) return;

      if (memberUid == ownerUid) {
        throw Exception('Owner cannot be removed. Transfer ownership first.');
      }

      tx.update(wsRef, {
        'memberUids': FieldValue.arrayRemove([memberUid]),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // Best-effort: delete legacy sub-doc
      tx.delete(wsRef.collection('members').doc(memberUid));
    });

    // If the removed member is me, clear my pointer
    if (memberUid == _user.uid) {
      await _userDoc(memberUid).set({
        'currentWorkspaceId': null,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
  }

  Future<void> leaveWorkspace(String wsId) async {
    final uid = _user.uid;
    final wsRef = _workspaces.doc(wsId);

    await _db.runTransaction((tx) async {
      final snap = await tx.get(wsRef);
      final data = snap.data() ?? const {};
      final ownerUid = data['ownerUid'] as String?;

      if (uid == ownerUid) {
        throw Exception('Owner cannot leave. Transfer ownership or delete.');
      }

      tx.update(wsRef, {
        'memberUids': FieldValue.arrayRemove([uid]),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      tx.delete(wsRef.collection('members').doc(uid));
    });

    // Clear pointer if this was my active workspace
    final userRef = _userDoc(uid);
    await _db.runTransaction((tx) async {
      final u = await tx.get(userRef);
      final curr = (u.data() ?? const {})['currentWorkspaceId'] as String?;
      if (curr == wsId) {
        tx.set(userRef, {
          'currentWorkspaceId': null,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    });
  }

  Future<void> deleteWorkspaceHard(String wsId) async {
    final uid = _user.uid;
    final wsRef = _workspaces.doc(wsId);

    final wsDoc = await wsRef.get();
    final ownerUid = (wsDoc.data() ?? const {})['ownerUid'] as String?;
    if (ownerUid != uid) {
      throw Exception('Only owner can delete this workspace.');
    }

    // Best-effort: delete subcollections that might exist
    final members = await wsRef.collection('members').get();
    for (final m in members.docs) {
      await m.reference.delete();
    }
    final consents = await wsRef.collection('consents').get();
    for (final c in consents.docs) {
      await c.reference.delete();
    }

    await wsRef.delete();

    await _userDoc(uid).set({
      'currentWorkspaceId': null,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  // -----------------------------
  // Consents
  // -----------------------------
  Future<Map<String, dynamic>?> watchConsentRawOnce(
    String wsId,
    String memberUid,
  ) async {
    final d = await _workspaces
        .doc(wsId)
        .collection('consents')
        .doc(memberUid)
        .get();
    return d.data();
  }

  Stream<Map<String, dynamic>?> watchConsent(String wsId, String memberUid) {
    return _workspaces
        .doc(wsId)
        .collection('consents')
        .doc(memberUid)
        .snapshots()
        .map((d) => d.data());
  }

  Future<void> updateConsent(
    String wsId,
    String memberUid,
    Map<String, String> featureToLevel,
  ) async {
    await _workspaces.doc(wsId).collection('consents').doc(memberUid).set({
      'feature': featureToLevel,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}

// -----------------------------
// Models
// -----------------------------
class WorkspaceSummary {
  final String id;
  final String name;
  final String role;
  WorkspaceSummary({required this.id, required this.name, required this.role});
}

class WorkspaceLite {
  final String id;
  final String name;
  final String? joinCode;
  WorkspaceLite({required this.id, required this.name, required this.joinCode});
}

class CreateWsResult {
  final String workspaceId;
  final String joinCode;
  CreateWsResult({required this.workspaceId, required this.joinCode});
}
