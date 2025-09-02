import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../services/workspace_service.dart';

class WorkspaceSetupScreen extends StatefulWidget {
  const WorkspaceSetupScreen({super.key});
  @override
  State<WorkspaceSetupScreen> createState() => _WorkspaceSetupScreenState();
}

class _WorkspaceSetupScreenState extends State<WorkspaceSetupScreen> {
  final codeCtrl = TextEditingController();
  bool busy = false;
  String? expandedWs; // which workspace is expanded

  User get _user => FirebaseAuth.instance.currentUser!;

  @override
  void dispose() {
    codeCtrl.dispose();
    super.dispose();
  }

  // ---- CREATE ----
  Future<void> _create() async {
    setState(() => busy = true);
    try {
      final res = await WorkspaceService.instance.createWorkspace();
      if (!mounted) return;
      setState(() => busy = false);
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Workspace Created'),
          content: SelectableText(
            'Share this join code with your partner:\n\n${res.joinCode}',
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
  }

  // ---- JOIN ----
  Future<void> _join() async {
    final code = codeCtrl.text.trim();
    if (code.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Enter a join code')));
      return;
    }
    setState(() => busy = true);
    try {
      final ok = await WorkspaceService.instance.joinByCode(code);
      if (!mounted) return;
      setState(() => busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ok ? 'Joined workspace' : 'Invalid code')),
      );
      if (ok) codeCtrl.clear();
    } catch (e) {
      if (!mounted) return;
      setState(() => busy = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Join failed: $e')));
    }
  }

  // ---- LEAVE ----
  Future<void> _leave(String wsId, String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Leave workspace?'),
        content: Text('You will leave "$name". Others keep their data.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
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
      ).showSnackBar(SnackBar(content: Text('Left "$name"')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to leave: $e')));
    }
  }

  // ---- DELETE ----
  Future<void> _delete(String wsId, String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete workspace?'),
        content: Text('This permanently deletes "$name".'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await WorkspaceService.instance.deleteWorkspaceHard(wsId);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Deleted "$name"')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Delete failed: $e')));
    }
  }

  // ---- COPY / SHARE / REGENERATE CODE ----
  Future<void> _copyCode(String wsId) async {
    final doc = await FirebaseFirestore.instance
        .collection('workspaces')
        .doc(wsId)
        .get();
    final code = (doc.data()?['joinCode'] as String?) ?? '';
    await Clipboard.setData(ClipboardData(text: code));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Join code copied')));
  }

  Future<void> _shareCode(String wsId, String name) async {
    final doc = await FirebaseFirestore.instance
        .collection('workspaces')
        .doc(wsId)
        .get();
    final code = (doc.data()?['joinCode'] as String?) ?? '';
    await Share.share('Join my "$name" workspace: $code');
  }

  Future<void> _regenCode(String wsId) async {
    final newCode = await WorkspaceService.instance.regenerateJoinCode(wsId);
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('New join code: $newCode')));
  }

  // ---- SET ACTIVE ----
  Future<void> _setActive(String wsId) async {
    await WorkspaceService.instance.setCurrentWorkspace(wsId);
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Workspace selected')));
  }

  // ---- ROLE / KICK ----
  Future<void> _changeRole(String wsId, String memberUid, String role) async {
    await WorkspaceService.instance.setMemberRole(wsId, memberUid, role);
  }

  Future<void> _removeMember(String wsId, String memberUid) async {
    await WorkspaceService.instance.removeMember(wsId, memberUid);
  }

  @override
  Widget build(BuildContext context) {
    final userDocStream = FirebaseFirestore.instance
        .collection('users')
        .doc(_user.uid)
        .snapshots();

    return Scaffold(
      appBar: AppBar(title: const Text('Workspace')),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: userDocStream,
        builder: (context, userSnap) {
          final currentId =
              userSnap.data?.data()?['currentWorkspaceId'] as String?;

          return StreamBuilder<List<WorkspaceSummary>>(
            stream: WorkspaceService.instance.myMemberships(),
            builder: (context, snap) {
              final memberships = snap.data ?? const <WorkspaceSummary>[];

              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    'Your workspaces',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),

                  if (snap.connectionState == ConnectionState.waiting)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (memberships.isEmpty)
                    const Text('You are not in any workspaces yet.')
                  else
                    ...memberships.map((w) {
                      final isExpanded = expandedWs == w.id;
                      return Card(
                        clipBehavior: Clip.antiAlias,
                        child: Column(
                          children: [
                            ListTile(
                              title: Text(w.name),
                              subtitle: Text('Role: ${w.role} · ID: ${w.id}'),
                              trailing: Wrap(
                                spacing: 8,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  if (currentId == w.id)
                                    const Chip(
                                      label: Text('Active'),
                                      visualDensity: VisualDensity.compact,
                                    )
                                  else
                                    TextButton(
                                      onPressed: () => _setActive(w.id),
                                      child: const Text('Set active'),
                                    ),
                                  IconButton(
                                    tooltip: isExpanded ? 'Collapse' : 'Manage',
                                    onPressed: () => setState(() {
                                      expandedWs = isExpanded ? null : w.id;
                                    }),
                                    icon: Icon(
                                      isExpanded
                                          ? Icons.expand_less
                                          : Icons.expand_more,
                                    ),
                                  ),
                                  PopupMenuButton<String>(
                                    onSelected: (value) {
                                      switch (value) {
                                        case 'copy':
                                          _copyCode(w.id);
                                          break;
                                        case 'share':
                                          _shareCode(w.id, w.name);
                                          break;
                                        case 'regen':
                                          _regenCode(w.id);
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
                                        value: 'copy',
                                        child: Text('Copy join code'),
                                      ),
                                      const PopupMenuItem(
                                        value: 'share',
                                        child: Text('Share join code'),
                                      ),
                                      const PopupMenuItem(
                                        value: 'regen',
                                        child: Text('Regenerate code'),
                                      ),
                                      const PopupMenuDivider(),
                                      const PopupMenuItem(
                                        value: 'leave',
                                        child: Text('Leave workspace'),
                                      ),
                                      if (w.role == 'owner')
                                        const PopupMenuItem(
                                          value: 'delete',
                                          child: Text('Delete (owner)'),
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                              onTap: () => setState(() {
                                expandedWs = isExpanded ? null : w.id;
                              }),
                            ),

                            // Expanded admin panel
                            if (isExpanded)
                              _WorkspaceAdminPanel(
                                workspaceId: w.id,
                                isOwner: w.role == 'owner',
                                currentUserUid: _user.uid,
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
                    }),

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
                      labelText: 'Join code',
                      hintText: 'e.g. 7XK9QZ',
                    ),
                    textCapitalization: TextCapitalization.characters,
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: busy ? null : _join,
                    icon: const Icon(Icons.login),
                    label: const Text('Join Workspace'),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _WorkspaceAdminPanel extends StatelessWidget {
  const _WorkspaceAdminPanel({
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
                            itemBuilder: (ctx) => [
                              const PopupMenuItem(
                                value: 'owner',
                                child: Text('Make owner'),
                              ),
                              const PopupMenuItem(
                                value: 'editor',
                                child: Text('Make editor'),
                              ),
                              const PopupMenuDivider(),
                              PopupMenuItem(
                                value: 'remove',
                                child: Row(
                                  children: const [
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
            data['feature'] as Map? ?? {},
          );
          state = {...current, ...state}; // preserve edits

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: features.length,
            separatorBuilder: (_, __) => const Divider(),
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
