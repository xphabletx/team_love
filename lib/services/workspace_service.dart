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
  // CREATE
  // -----------------------------
  Future<CreateWsResult> createWorkspace({required String name}) async {
    final uid = _user.uid;
    final wsRef = _workspaces.doc();

    final batch = _db.batch();

    batch.set(wsRef, {
      'id': wsRef.id,
      'name': name,
      'ownerUid': uid,
      // ▶ we keep joinCode null (deprecated) and use per-invite codes instead
      'joinCode': null,
      'memberUids': [uid],
      'blockedUids': <String>[], // ▶ NEW
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    final memberRef = wsRef.collection('members').doc(uid);
    batch.set(memberRef, {
      'uid': uid,
      'role': 'owner',
      'joinedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

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

    return CreateWsResult(
      workspaceId: wsRef.id,
      joinCode: '',
    ); // code per-invite
  }

  // -----------------------------
  // INVITES
  // -----------------------------
  // Each invite lives at: workspaces/{wsId}/invites/{inviteId}
  // Fields:
  //  - code (6 chars)
  //  - invitedEmail (optional)
  //  - invitedUid (optional)
  //  - status: pending|accepted|revoked|expired
  //  - createdAt, acceptedAt
  //  - createdByUid

  Future<InviteInfo> createInvite({
    required String wsId,
    String? invitedEmail,
    String? invitedUid,
  }) async {
    if (invitedEmail == null && invitedUid == null) {
      throw Exception('Provide invitedEmail or invitedUid');
    }
    final code = _newCode();
    final ref = _workspaces.doc(wsId).collection('invites').doc();
    await ref.set({
      'id': ref.id,
      'code': code,
      'invitedEmail': invitedEmail,
      'invitedUid': invitedUid,
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
      'createdByUid': _user.uid,
    });
    return InviteInfo(inviteId: ref.id, code: code);
  }

  Future<void> revokeInvite({required String wsId, required String inviteId}) {
    return _workspaces.doc(wsId).collection('invites').doc(inviteId).set({
      'status': 'revoked',
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  // -----------------------------
  // JOIN (invite + code required)
  // -----------------------------
  Future<bool> joinWithCode(String rawCode) async {
    final code = rawCode.trim().toUpperCase();
    if (code.isEmpty) return false;

    // Find an invite with this code that is still pending
    final qs = await _db
        .collectionGroup('invites')
        .where('code', isEqualTo: code)
        .where('status', isEqualTo: 'pending')
        .limit(1)
        .get();

    if (qs.docs.isEmpty) return false;

    final inviteDoc = qs.docs.first;
    final invite = inviteDoc.data();
    final wsRef = inviteDoc.reference.parent.parent!;
    final wsSnap = await wsRef.get();
    if (!wsSnap.exists) return false;

    final myUid = _user.uid;
    final myEmail = _user.email?.toLowerCase();

    final invitedUid = (invite['invitedUid'] as String?)?.trim();
    final invitedEmail = (invite['invitedEmail'] as String?)
        ?.toLowerCase()
        .trim();

    // ▶ Enforce “invited + code” rule
    final isThisInviteForMe =
        (invitedUid != null && invitedUid == myUid) ||
        (invitedEmail != null && invitedEmail == myEmail);

    if (!isThisInviteForMe) return false;

    // ▶ Blocked user check
    final blocked = List<String>.from(
      (wsSnap.data()!['blockedUids'] as List?) ?? [],
    );
    if (blocked.contains(myUid)) {
      // Optionally mark invite revoked to prevent retries
      await inviteDoc.reference.set({
        'status': 'revoked',
      }, SetOptions(merge: true));
      return false;
    }

    // Continue with membership
    try {
      await _db.runTransaction((tx) async {
        final ws = await tx.get(wsRef);
        final members = List<String>.from(
          (ws.data()?['memberUids'] as List?) ?? [],
        );
        if (!members.contains(myUid)) {
          members.add(myUid);
        }
        tx.update(wsRef, {
          'memberUids': members,
          'updatedAt': FieldValue.serverTimestamp(),
        });

        // best-effort sub-doc
        final mRef = wsRef.collection('members').doc(myUid);
        tx.set(mRef, {
          'uid': myUid,
          'role': 'editor',
          'joinedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        // set current workspace pointer
        final userRef = _userDoc(myUid);
        tx.set(userRef, {
          'uid': myUid,
          'currentWorkspaceId': wsRef.id,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        // mark invite accepted
        tx.update(inviteDoc.reference, {
          'status': 'accepted',
          'acceptedAt': FieldValue.serverTimestamp(),
          'acceptedByUid': myUid,
        });
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  // -----------------------------
  // Legacy join-code (optional – kept for old UI actions)
  // -----------------------------
  Future<String> regenerateJoinCode(String wsId) async {
    final code = _newCode();
    await _workspaces.doc(wsId).set({
      'joinCode': code,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    return code;
  }

  // -----------------------------
  // READ / WATCH (unchanged except notes)
  // -----------------------------
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

  // Rename the workspace for everyone (owner-only in UI)
  Future<void> renameWorkspace(String wsId, String newName) async {
    await _workspaces.doc(wsId).set({
      'name': newName,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  // Set/remove *my* personal alias for a workspace.
  // alias == null or empty => remove alias.
  Future<void> setMyWorkspaceAlias(String wsId, String? alias) async {
    final userRef = _userDoc(_user.uid);
    final field = 'workspaceAliases.$wsId';
    if (alias == null || alias.trim().isEmpty) {
      await userRef.update({field: FieldValue.delete()});
    } else {
      await userRef.set({
        'workspaceAliases': {wsId: alias.trim()},
      }, SetOptions(merge: true));
    }
  }

  Stream<WorkspaceLite?> watchWorkspace(String wsId) {
    return _workspaces.doc(wsId).snapshots().map((d) {
      final data = d.data();
      if (data == null) return null;
      return WorkspaceLite(
        id: data['id'] as String? ?? d.id,
        name: (data['name'] as String?) ?? 'Workspace',
        joinCode: data['joinCode'] as String?, // deprecated, but kept
      );
    });
  }

  Stream<List<Map<String, dynamic>>> watchMembers(String wsId) {
    final myUid = _user.uid;
    return _workspaces.doc(wsId).snapshots().map((snap) {
      final data = snap.data() ?? const {};
      final ownerUid = data['ownerUid'] as String?;
      final memberUids = List<String>.from(
        (data['memberUids'] as List?) ?? const [],
      );
      memberUids.sort((a, b) {
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
  // ROLES
  // -----------------------------
  Future<void> setMemberRole(String wsId, String memberUid, String role) async {
    final wsRef = _workspaces.doc(wsId);

    if (role == 'owner') {
      // Transfer ownership: simply switch ownerUid
      await wsRef.set({
        'ownerUid': memberUid,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } else {
      // Keep “editor” as best-effort info in the legacy sub-doc
      await wsRef.collection('members').doc(memberUid).set({
        'role': 'editor',
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
  }

  // -----------------------------
  // BLOCK / UNBLOCK / LEAVE / DELETE
  // -----------------------------
  Future<void> blockMember(String wsId, String memberUid) async {
    await _workspaces.doc(wsId).set({
      'blockedUids': FieldValue.arrayUnion([memberUid]),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> unblockMember(String wsId, String memberUid) async {
    await _workspaces.doc(wsId).set({
      'blockedUids': FieldValue.arrayRemove([memberUid]),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
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
      tx.delete(wsRef.collection('members').doc(memberUid));
    });

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
    await _userDoc(uid).set({
      'currentWorkspaceId': null,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> deleteWorkspaceHard(String wsId) async {
    final uid = _user.uid;
    final wsRef = _workspaces.doc(wsId);
    final wsDoc = await wsRef.get();
    final ownerUid = (wsDoc.data() ?? const {})['ownerUid'] as String?;
    if (ownerUid != uid) {
      throw Exception('Only owner can delete this workspace.');
    }
    for (final c in ['members', 'consents', 'invites']) {
      final qs = await wsRef.collection(c).get();
      for (final d in qs.docs) {
        await d.reference.delete();
      }
    }
    await wsRef.delete();
    await _userDoc(uid).set({
      'currentWorkspaceId': null,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  // Consents (unchanged)
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

// Models
class WorkspaceSummary {
  final String id;
  final String name;
  final String role;
  WorkspaceSummary({required this.id, required this.name, required this.role});
}

class WorkspaceLite {
  final String id;
  final String name;
  final String? joinCode; // deprecated
  WorkspaceLite({required this.id, required this.name, required this.joinCode});
}

class CreateWsResult {
  final String workspaceId;
  final String joinCode; // unused; kept for API stability
  CreateWsResult({required this.workspaceId, required this.joinCode});
}

// ▶ NEW
class InviteInfo {
  final String inviteId;
  final String code;
  InviteInfo({required this.inviteId, required this.code});
}
