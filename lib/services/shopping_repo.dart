import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Simple data class used by the UI.
class ShoppingDoc {
  ShoppingDoc({
    required this.id,
    required this.name,
    required this.done,
    required this.createdByUid,
    required this.createdAt,
    required this.updatedAt,
    this.source,
  });

  final String id; // stable: "<uid or local>:<randomId>"
  final String name;
  final bool done;
  final String createdByUid; // attribution
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final Map<String, dynamic>? source;

  factory ShoppingDoc.fromSnap(DocumentSnapshot<Map<String, dynamic>> d) {
    final data = d.data() ?? const <String, dynamic>{};
    return ShoppingDoc(
      id: d.id,
      name: (data['name'] as String?) ?? '',
      done: (data['done'] as bool?) ?? false,
      createdByUid: (data['createdByUid'] as String?) ?? 'local',
      createdAt: (data['createdAt'] is Timestamp)
          ? (data['createdAt'] as Timestamp).toDate()
          : null,
      updatedAt: (data['updatedAt'] is Timestamp)
          ? (data['updatedAt'] as Timestamp).toDate()
          : null,
      source: (data['source'] as Map?)?.cast<String, dynamic>(),
    );
    // NOTE: if createdAt is null right after creation (server timestamp),
    // the stream will emit again with a non-null value.
  }

  Map<String, dynamic> toMap() => {
    'name': name,
    'done': done,
    'createdByUid': createdByUid,
    'createdAt': createdAt,
    'updatedAt': updatedAt,
    if (source != null) 'source': source,
  };
}

class ShoppingRepo {
  ShoppingRepo(this._db);
  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> _col(String wsId) => _db
      .collection('workspaces')
      .doc(wsId)
      .collection('shoppingItems')
      .withConverter<Map<String, dynamic>>(
        fromFirestore: (snap, _) => snap.data() ?? <String, dynamic>{},
        toFirestore: (data, _) => data,
      );

  /// Watch items in a workspace, ordered by createdAt (nulls last).
  Stream<List<ShoppingDoc>> watch(String wsId) {
    // We order by createdAt; for brand-new docs the timestamp may be null
    // until the server resolves it. For those, Firestore puts nulls first.
    // If you'd rather push nulls to the end, you can add a second orderBy.
    return _col(wsId)
        .orderBy('createdAt', descending: false)
        .snapshots()
        .map((qs) => qs.docs.map((d) => ShoppingDoc.fromSnap(d)).toList());
  }

  /// Add item with a stable, user-scoped ID and attribution.
  Future<void> add(
    String wsId,
    String name, {
    Map<String, dynamic>? source,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? 'local';

    // Generate a stable ID that will be the same if we migrate
    // between local <-> workspace for this user’s items.
    final randomId = _db.collection('_').doc().id; // cheap random id
    final id = '$uid:$randomId';

    final nowServer = FieldValue.serverTimestamp();
    final docRef = _col(wsId).doc(id);

    await docRef.set({
      'name': name,
      'done': false,
      'createdByUid': uid,
      'createdAt': nowServer,
      'updatedAt': nowServer,
      if (source != null) 'source': source,
    }, SetOptions(merge: true)); // merge just in case we re-upsert same id
  }

  /// Toggle 'done' + bump updatedAt.
  Future<void> toggleDone(String wsId, String id, bool done) {
    return _col(
      wsId,
    ).doc(id).update({'done': done, 'updatedAt': FieldValue.serverTimestamp()});
  }

  /// Remove an item by id.
  Future<void> remove(String wsId, String id) {
    return _col(wsId).doc(id).delete();
  }

  /// (Optional) bulk upsert – handy for future local→workspace migration.
  Future<void> upsertMany(String wsId, Iterable<ShoppingDoc> items) async {
    final batch = _db.batch();
    for (final it in items) {
      final ref = _col(wsId).doc(it.id);
      batch.set(ref, {
        'name': it.name,
        'done': it.done,
        'createdByUid': it.createdByUid,
        'createdAt': it.createdAt == null
            ? FieldValue.serverTimestamp()
            : Timestamp.fromDate(it.createdAt!),
        'updatedAt': FieldValue.serverTimestamp(),
        if (it.source != null) 'source': it.source,
      }, SetOptions(merge: true));
    }
    await batch.commit();
  }

  /// (Optional) fetch only the current user's items – useful when leaving a workspace.
  Future<List<ShoppingDoc>> fetchMine(String wsId, String uid) async {
    final qs = await _col(wsId).where('createdByUid', isEqualTo: uid).get();
    return qs.docs.map((d) => ShoppingDoc.fromSnap(d)).toList();
  }
}
