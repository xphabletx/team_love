import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'local_shopping_store.dart';
import 'shopping_repo.dart';

/// Handles moving shopping list data between local storage and Firestore workspaces.
class ShoppingMigrationService {
  ShoppingMigrationService._();
  static final instance = ShoppingMigrationService._();

  final _repo = ShoppingRepo(FirebaseFirestore.instance);

  /// When a user joins or switches to a workspace:
  /// - Push all current local items into that workspace (keeping ownership)
  /// - Keep local items (don’t delete) for offline backup
  Future<void> migrateLocalToWorkspace(String workspaceId) async {
    final items = LocalShoppingStore.instance.snapshot();
    if (items.isEmpty) return;

    // Upsert all local items into the workspace, retaining createdByUid ownership.
    await _repo.upsertMany(workspaceId, items);
  }

  /// When a user leaves a workspace:
  /// - Fetch only *their* items from Firestore
  /// - Store them back in local storage (replacing existing)
  Future<void> extractMineFromWorkspace(String workspaceId) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) return;

    final myItems = await _repo.fetchMine(workspaceId, uid);
    if (myItems.isEmpty) return;

    // Replace local list with user's items.
    await LocalShoppingStore.instance.clearAll();
    final store = LocalShoppingStore.instance;
    for (final it in myItems) {
      await store.add(it.name, source: {'migratedFrom': workspaceId});
    }
  }
}
