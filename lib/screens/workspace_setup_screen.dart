// lib/screens/workspace_setup_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/workspace_service.dart';
import 'sign_in_screen.dart';

class WorkspaceSetupScreen extends StatefulWidget {
  const WorkspaceSetupScreen({super.key});
  @override
  State<WorkspaceSetupScreen> createState() => _WorkspaceSetupScreenState();
}

class _WorkspaceSetupScreenState extends State<WorkspaceSetupScreen> {
  final codeCtrl = TextEditingController();
  bool busy = false;
  String? expandedWs; // which workspace is expanded

  User? get _user => FirebaseAuth.instance.currentUser;

  @override
  void dispose() {
    codeCtrl.dispose();
    super.dispose();
  }

  // ---------------- helpers ----------------
  Future<void> _requireSignedIn(Future<void> Function() action) async {
    final u = _user;
    if (u == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please sign in to use workspaces.')),
      );
      return;
    }
    await action();
  }

  Future<String?> _askForName({String initial = ''}) async {
    final ctrl = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Create workspace'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Workspace name',
            hintText: 'e.g. Big Love Family',
          ),
          onSubmitted: (_) => Navigator.pop(ctx, ctrl.text.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  String _displayTitle({
    required WorkspaceSummary w,
    required Map<String, dynamic> aliases,
  }) {
    final alias = (aliases[w.id] as String?)?.trim();
    if (alias == null || alias.isEmpty) return w.name;
    return '$alias (${w.name})';
  }

  // ---------------- create (single prompt) ----------------
  Future<void> _create() async {
    await _requireSignedIn(() async {
      final name = await _askForName();
      if (name == null || name.isEmpty) return;

      setState(() => busy = true);
      try {
        final res = await WorkspaceService.instance.createWorkspace(name: name);
        if (!mounted) return;
        setState(() => busy = false);
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Workspace Created'),
            content: SelectableText(
              'Workspace “$name” created.\n\n'
              'ID: ${res.workspaceId}\n\n'
              'Use the card menu to invite people.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      } catch (e) {
        if (!mounted) return;
        setState(() => busy = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to create: $e')));
      }
    });
  }

  // ---------------- rename (for everyone) ----------------
  Future<void> _renameForEveryone(String wsId, String currentName) async {
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final ctrl = TextEditingController(text: currentName);
        return AlertDialog(
          title: const Text('Rename for everyone'),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'New name'),
            onSubmitted: (_) => Navigator.pop(ctx, ctrl.text.trim()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, null),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
    if (newName == null || newName.isEmpty) return;
    try {
      await WorkspaceService.instance.renameWorkspace(wsId, newName);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Workspace renamed to “$newName” for everyone')),
      );
      // TODO: enqueue notification to members about rename.
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Rename failed: $e')));
    }
  }

  // ---------------- rename (alias just for me) ----------------
  Future<void> _renameJustForMe(String wsId, String currentAliasOrEmpty) async {
    final alias = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final ctrl = TextEditingController(text: currentAliasOrEmpty);
        return AlertDialog(
          title: const Text('Rename (just for me)'),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'My private name (leave empty to reset)',
            ),
            onSubmitted: (_) => Navigator.pop(ctx, ctrl.text.trim()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, null),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
    if (alias == null) return;
    try {
      await WorkspaceService.instance.setMyWorkspaceAlias(
        wsId,
        alias.isEmpty ? null : alias,
      );
      if (!mounted) return;
      final msg = alias.isEmpty ? 'Removed my alias.' : 'Saved my alias.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to save alias: $e')));
    }
  }

  // ---------------- join (by invite code) ----------------
  Future<void> _join() async {
    final code = codeCtrl.text.trim();
    if (code.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Enter an invite code')));
      return;
    }
    await _requireSignedIn(() async {
      setState(() => busy = true);
      try {
        final ok = await WorkspaceService.instance.joinWithCode(code);
        if (!mounted) return;
        setState(() => busy = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              ok
                  ? 'Joined workspace.'
                  : 'Could not join. Check the invite is for your account and not revoked.',
            ),
          ),
        );
        if (ok) codeCtrl.clear();
      } catch (e) {
        if (!mounted) return;
        setState(() => busy = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Join failed: $e')));
      }
    });
  }

  // ---------------- leave / delete ----------------
  Future<void> _delete(String wsId, String name) async {
    await _requireSignedIn(() async {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setLocal) {
            bool localBusy = false;
            return AlertDialog(
              title: const Text('Delete workspace?'),
              content: Text('This permanently deletes “$name”.'),
              actions: [
                TextButton(
                  onPressed: localBusy ? null : () => Navigator.pop(ctx, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: Colors.red),
                  onPressed: localBusy
                      ? null
                      : () async {
                          setLocal(() => localBusy = true);
                          try {
                            await WorkspaceService.instance.deleteWorkspaceHard(
                              wsId,
                            );
                            if (context.mounted) Navigator.pop(ctx, true);
                          } catch (e) {
                            setLocal(() => localBusy = false);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Delete failed: $e')),
                              );
                            }
                          }
                        },
                  child: localBusy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Delete'),
                ),
              ],
            );
          },
        ),
      );
      if (ok == true && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Deleted “$name”')));
      }
    });
  }

  Future<void> _leave(String wsId, String name) async {
    await _requireSignedIn(() async {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Leave workspace?'),
          content: Text('You will leave “$name”. You can be re-invited later.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Leave'),
            ),
          ],
        ),
      );
      if (ok != true) return;

      try {
        await WorkspaceService.instance.leaveWorkspace(wsId);
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Left “$name”.')));
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Leave failed: $e')));
      }
    });
  }

  // ---------------- role / kick ----------------
  Future<void> _changeRole(String wsId, String memberUid, String role) async {
    await _requireSignedIn(() async {
      await WorkspaceService.instance.setMemberRole(wsId, memberUid, role);
    });
  }

  Future<void> _removeMember(String wsId, String memberUid) async {
    await _requireSignedIn(() async {
      await WorkspaceService.instance.removeMember(wsId, memberUid);
    });
  }

  // ---------------- UI (build) ----------------
  @override
  Widget build(BuildContext context) {
    // Signed-out gate
    if (_user == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Workspace')),
        body: Center(
          child: Card(
            margin: const EdgeInsets.all(24),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.lock_outline, size: 48),
                  const SizedBox(height: 12),
                  const Text(
                    'You’re signed out.\nSign in to create or join a workspace.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const SignInScreen()),
                      );
                    },
                    child: const Text('Go to Sign In'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final uid = _user!.uid;
    final userDocStream = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .snapshots();

    return Scaffold(
      appBar: AppBar(title: const Text('Workspace')),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: userDocStream,
        builder: (context, userSnap) {
          final userDoc = userSnap.data?.data() ?? const <String, dynamic>{};
          final aliases = Map<String, dynamic>.from(
            (userDoc['workspaceAliases'] as Map?) ?? const {},
          );

          return StreamBuilder<List<WorkspaceSummary>>(
            stream: WorkspaceService.instance.myMemberships(),
            builder: (context, snap) {
              final memberships = snap.data ?? const <WorkspaceSummary>[];

              final owned = memberships.where((w) => w.role == 'owner').toList()
                ..sort((a, b) => a.name.compareTo(b.name));
              final memberOf =
                  memberships.where((w) => w.role != 'owner').toList()
                    ..sort((a, b) => a.name.compareTo(b.name));

              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (snap.connectionState == ConnectionState.waiting)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (owned.isEmpty && memberOf.isEmpty)
                    const Text('You are not in any workspaces yet.')
                  else ...[
                    if (owned.isNotEmpty) ...[
                      Text(
                        'Workspaces you own',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      ...owned.map(
                        (w) => _workspaceCard(
                          w: w,
                          title: _displayTitle(w: w, aliases: aliases),
                          currentId: null,
                          isOwner: true,
                          myAlias: (aliases[w.id] as String?) ?? '',
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],
                    if (memberOf.isNotEmpty) ...[
                      Text(
                        'Workspaces you’re a member of',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      ...memberOf.map(
                        (w) => _workspaceCard(
                          w: w,
                          title: _displayTitle(w: w, aliases: aliases),
                          currentId: null,
                          isOwner: false,
                          myAlias: (aliases[w.id] as String?) ?? '',
                        ),
                      ),
                    ],
                  ],
                  const Divider(height: 32),
                  FilledButton.icon(
                    onPressed: busy ? null : _create,
                    icon: const Icon(Icons.add_circle_outline),
                    label: const Text('Create Workspace'),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: codeCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Invite code',
                      hintText: 'e.g. 7XK9QZ',
                    ),
                    textCapitalization: TextCapitalization.characters,
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: busy ? null : _join,
                    icon: const Icon(Icons.login),
                    label: const Text('Join via Invite'),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _workspaceCard({
    required WorkspaceSummary w,
    required String title,
    required String? currentId,
    required bool isOwner,
    required String myAlias,
  }) {
    final isExpanded = expandedWs == w.id;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          ListTile(
            title: Text(title),
            trailing: Wrap(
              spacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                IconButton(
                  tooltip: isExpanded ? 'Collapse' : 'Manage',
                  onPressed: () =>
                      setState(() => expandedWs = isExpanded ? null : w.id),
                  icon: Icon(
                    isExpanded ? Icons.expand_less : Icons.expand_more,
                  ),
                ),
                PopupMenuButton<String>(
                  onSelected: (value) async {
                    switch (value) {
                      case 'rename_all':
                        _renameForEveryone(w.id, w.name);
                        break;
                      case 'rename_me':
                        _renameJustForMe(w.id, myAlias);
                        break;
                      case 'leave':
                        _leave(w.id, w.name);
                        break;
                      case 'delete':
                        _delete(w.id, w.name);
                        break;
                    }
                  },
                  itemBuilder: (ctx) => [
                    const PopupMenuItem(
                      value: 'rename_me',
                      child: Text('Rename (just for me)'),
                    ),
                    if (isOwner)
                      const PopupMenuItem(
                        value: 'rename_all',
                        child: Text('Rename for everyone'),
                      ),
                    const PopupMenuDivider(),
                    const PopupMenuItem(
                      value: 'leave',
                      child: Text('Leave workspace'),
                    ),
                    if (isOwner)
                      const PopupMenuItem(
                        value: 'delete',
                        child: Text('Delete (owner)'),
                      ),
                  ],
                ),
              ],
            ),
            onTap: () => setState(() => expandedWs = isExpanded ? null : w.id),
          ),

          if (isExpanded)
            _WorkspaceAdminPanel(
              workspaceId: w.id,
              isOwner: isOwner,
              currentUserUid: _user!.uid,
              onChangeRole: _changeRole,
              onRemove: _removeMember,
              onConsentTap: (memberUid) {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ConsentEditorScreen(
                      workspaceId: w.id,
                      memberUid: memberUid,
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
} // <-- END of _WorkspaceSetupScreenState

/// --------------------------
/// Top-level widgets (not nested)
/// --------------------------

class _WorkspaceAdminPanel extends StatelessWidget {
  const _WorkspaceAdminPanel({
    super.key,
    required this.workspaceId,
    required this.isOwner,
    required this.currentUserUid,
    required this.onChangeRole,
    required this.onRemove,
    required this.onConsentTap,
  });

  final String workspaceId;
  final bool isOwner;
  final String currentUserUid;
  final Future<void> Function(String wsId, String memberUid, String role)
  onChangeRole;
  final Future<void> Function(String wsId, String memberUid) onRemove;
  final void Function(String memberUid) onConsentTap;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: WorkspaceService.instance.watchMembers(workspaceId),
      builder: (context, snap) {
        final members = snap.data ?? const <Map<String, dynamic>>[];
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            children: [
              const Divider(),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Members',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              const SizedBox(height: 8),
              if (members.isEmpty)
                const Text('No members yet.')
              else
                ...members.map((m) {
                  final uid = m['uid'] as String? ?? '';
                  final role = (m['role'] as String?) ?? 'editor';
                  return ListTile(
                    dense: true,
                    leading: const CircleAvatar(child: Icon(Icons.person)),
                    title: Text(uid == currentUserUid ? 'You' : uid),
                    subtitle: Text('Role: $role'),
                    trailing: Wrap(
                      spacing: 8,
                      children: [
                        OutlinedButton(
                          onPressed: () => onConsentTap(uid),
                          child: const Text('Consent'),
                        ),
                        if (isOwner)
                          PopupMenuButton<String>(
                            tooltip: 'Member actions',
                            onSelected: (value) {
                              switch (value) {
                                case 'owner':
                                  onChangeRole(workspaceId, uid, 'owner');
                                  break;
                                case 'editor':
                                  onChangeRole(workspaceId, uid, 'editor');
                                  break;
                                case 'remove':
                                  onRemove(workspaceId, uid);
                                  break;
                              }
                            },
                            itemBuilder: (ctx) => const [
                              PopupMenuItem(
                                value: 'owner',
                                child: Text('Make owner'),
                              ),
                              PopupMenuItem(
                                value: 'editor',
                                child: Text('Make editor'),
                              ),
                              PopupMenuDivider(),
                              PopupMenuItem(
                                value: 'remove',
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.delete_outline,
                                      color: Colors.red,
                                    ),
                                    SizedBox(width: 8),
                                    Text('Remove member'),
                                  ],
                                ),
                              ),
                            ],
                            child: const Icon(Icons.more_vert),
                          ),
                      ],
                    ),
                  );
                }),
            ],
          ),
        );
      },
    );
  }
}

// Very simple consent editor stub that writes to workspaces/{id}/consents/{uid}
class ConsentEditorScreen extends StatefulWidget {
  const ConsentEditorScreen({
    super.key,
    required this.workspaceId,
    required this.memberUid,
  });

  final String workspaceId;
  final String memberUid;

  @override
  State<ConsentEditorScreen> createState() => _ConsentEditorScreenState();
}

class _ConsentEditorScreenState extends State<ConsentEditorScreen> {
  final features = const [
    'budget',
    'ledger',
    'calendar',
    'meals',
    'shopping',
    'recipes',
  ];
  final levels = const ['none', 'view', 'contribute', 'edit'];

  Map<String, String> state = {};

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Manage Consent')),
      body: StreamBuilder<Map<String, dynamic>?>(
        stream: WorkspaceService.instance.watchConsent(
          widget.workspaceId,
          widget.memberUid,
        ),
        builder: (context, snap) {
          final data = snap.data ?? const {};
          final current = Map<String, String>.from(
            (data['feature'] as Map?) ?? {},
          );
          state = {...current, ...state}; // preserve edits

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: features.length,
            separatorBuilder: (_, i) => const Divider(), // lint fix
            itemBuilder: (_, i) {
              final f = features[i];
              final v = state[f] ?? current[f] ?? 'none';
              return ListTile(
                title: Text(f[0].toUpperCase() + f.substring(1)),
                trailing: DropdownButton<String>(
                  value: v,
                  items: levels
                      .map((l) => DropdownMenuItem(value: l, child: Text(l)))
                      .toList(),
                  onChanged: (val) {
                    if (val == null) return;
                    setState(() => state[f] = val);
                  },
                ),
              );
            },
          );
        },
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: FilledButton(
          onPressed: () async {
            await WorkspaceService.instance.updateConsent(
              widget.workspaceId,
              widget.memberUid,
              state,
            );
            if (mounted) Navigator.pop(context);
          },
          child: const Text('Save'),
        ),
      ),
    );
  }
}
