import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ScopeSwitcher {
  static Future<void> show(BuildContext context) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    final membershipsStream = uid == null
        ? const Stream<List<Map<String, dynamic>>>.empty()
        : FirebaseFirestore.instance
              .collection('workspaces')
              .where('memberUids', arrayContains: uid)
              .snapshots()
              .map(
                (q) => q.docs.map((d) => {'id': d.id, ...d.data()}).toList(),
              );

    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => StreamBuilder<List<Map<String, dynamic>>>(
        stream: membershipsStream,
        builder: (context, snap) {
          final list = snap.data ?? const <Map<String, dynamic>>[];
          return SafeArea(
            child: ListView(
              shrinkWrap: true,
              children: [
                const ListTile(title: Text('Choose scope')),
                ListTile(
                  leading: const Icon(Icons.phone_iphone),
                  title: const Text('Local (Device)'),
                  onTap: () async {
                    if (uid != null) {
                      await FirebaseFirestore.instance
                          .collection('users')
                          .doc(uid)
                          .update({'currentWorkspaceId': ''});
                    }
                    if (context.mounted) Navigator.pop(context);
                  },
                ),
                const Divider(),
                if (uid == null)
                  const ListTile(
                    title: Text('Sign in to use workspaces'),
                    subtitle: Text(
                      'Local mode is available without an account.',
                    ),
                  )
                else if (list.isEmpty)
                  const ListTile(
                    title: Text('No workspaces yet'),
                    subtitle: Text(
                      'Create or join one from Workspace settings.',
                    ),
                  )
                else
                  ...list.map(
                    (w) => ListTile(
                      leading: const Icon(Icons.groups),
                      title: Text((w['name'] as String?) ?? 'Workspace'),
                      onTap: () async {
                        await FirebaseFirestore.instance
                            .collection('users')
                            .doc(uid)
                            .update({'currentWorkspaceId': w['id']});
                        if (context.mounted) Navigator.pop(context);
                      },
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
