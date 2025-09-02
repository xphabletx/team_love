import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Tracks the signed-in user's current workspace id (from Firestore).
/// Simple singleton + stream. The `of/maybeOf` helpers exist purely so
/// widgets can call `WorkspaceSession.maybeOf(context)` even though
/// this isn't an InheritedWidget.
class WorkspaceSession {
  WorkspaceSession._();
  static final WorkspaceSession instance = WorkspaceSession._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _sub;

  // Broadcast stream for anyone who wants to listen to workspace changes.
  final _controller = StreamController<String?>.broadcast();
  Stream<String?> get currentWorkspaceId$ => _controller.stream;

  // Latest values kept in memory for easy access.
  String? _currentWorkspaceId;
  String? _uid;

  /// The current workspace id (or null if none).
  String? get workspaceId => _currentWorkspaceId;

  /// The current user's uid (or null if signed out).
  String? get uid => _uid;

  /// These helpers just return the singleton. We accept a BuildContext so
  /// call sites like `WorkspaceSession.maybeOf(context)` compile cleanly.
  static WorkspaceSession? maybeOf(BuildContext context) => instance;
  static WorkspaceSession of(BuildContext context) => instance;

  /// Call after FirebaseAuth is ready & user is signed in.
  void start() {
    _sub?.cancel();

    final user = FirebaseAuth.instance.currentUser;
    _uid = user?.uid;

    if (user == null) {
      _currentWorkspaceId = null;
      _controller.add(null);
      return;
    }

    _sub = _db
        .collection('users')
        .doc(user.uid)
        .snapshots()
        .listen(
          (snap) {
            final wsId = snap.data()?['currentWorkspaceId'] as String?;
            _currentWorkspaceId = wsId;
            _controller.add(wsId);
          },
          onError: (_) {
            _currentWorkspaceId = null;
            _controller.add(null);
          },
        );
  }

  /// Stop listening (e.g., on sign-out).
  void stop() {
    _sub?.cancel();
    _sub = null;
    _currentWorkspaceId = null;
    _uid = null;
    _controller.add(null);
  }
}
