import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class WorkspaceScope extends InheritedWidget {
  const WorkspaceScope({
    super.key,
    required this.currentWorkspaceId,
    required this.uid,
    required super.child,
  });

  final String? currentWorkspaceId; // null => Local
  final String? uid;

  static WorkspaceScope? of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<WorkspaceScope>();
  }

  bool get usingWorkspace =>
      currentWorkspaceId != null && currentWorkspaceId!.isNotEmpty;

  @override
  bool updateShouldNotify(covariant WorkspaceScope oldWidget) {
    return oldWidget.currentWorkspaceId != currentWorkspaceId ||
        oldWidget.uid != uid;
  }
}

/// Wrap any feature screen with this to get reactive workspace/uid.
class WorkspaceScopeBuilder extends StatelessWidget {
  const WorkspaceScopeBuilder({super.key, required this.builder});

  final Widget Function(BuildContext context, String? workspaceId, String? uid)
  builder;

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    Stream<DocumentSnapshot<Map<String, dynamic>>>? userStream;
    if (uid != null) {
      userStream = FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .snapshots();
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: userStream,
      builder: (context, userSnap) {
        String? wsId;
        if (uid != null && userSnap.hasData) {
          final data = userSnap.data?.data() ?? const <String, dynamic>{};
          final id = (data['currentWorkspaceId'] as String?) ?? '';
          wsId = id.isEmpty ? null : id;
        }

        return WorkspaceScope(
          currentWorkspaceId: wsId,
          uid: uid,
          child: Builder(builder: (ctx) => builder(ctx, wsId, uid)),
        );
      },
    );
  }
}
