import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../services/input_service.dart';
import '../services/calendar_events_service.dart';
import '../services/shopping_repo.dart'; // Firestore repo (defines ShoppingDoc)
import '../services/local_shopping_store.dart'; // Pure offline store
import '../services/shopping_migration_service.dart';

class ShoppingScreen extends StatefulWidget {
  const ShoppingScreen({super.key});
  @override
  State<ShoppingScreen> createState() => _ShoppingScreenState();
}

class _ShoppingScreenState extends State<ShoppingScreen> {
  bool _removeMode = false;
  final Set<String> _selectedIds = <String>{}; // used in BOTH modes
  final _repo = ShoppingRepo(FirebaseFirestore.instance);

  String? _workspaceId; // null => offline/local mode
  String? _lastWorkspaceId;
  bool get _usingWorkspace => _workspaceId != null && _workspaceId!.isNotEmpty;

  // ── Add item manually ──────────────────────────────────────────────────────
  void _addItemManually() {
    final ctrl = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add item'),
        content: AppInputs.textField(
          controller: ctrl,
          label: 'Name',
          onSubmitted: (_) => _finishAdd(ctrl, ctx),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => _finishAdd(ctrl, ctx),
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  void _finishAdd(TextEditingController ctrl, BuildContext ctx) {
    final name = ctrl.text.trim();
    if (name.isNotEmpty) {
      if (_usingWorkspace) {
        _repo.add(_workspaceId!, name);
      } else {
        LocalShoppingStore.instance.add(name);
      }
    }
    Navigator.pop(ctx);
  }

  // ── Remove mode & actions ──────────────────────────────────────────────────
  void _enterRemoveMode() {
    setState(() {
      _removeMode = true;
      _selectedIds.clear();
    });
  }

  void _exitRemoveMode() {
    setState(() {
      _removeMode = false;
      _selectedIds.clear();
    });
  }

  Future<void> _confirmDeleteSelected() async {
    if (_selectedIds.isEmpty) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete selected items?'),
        content: Text(
          'This will remove ${_selectedIds.length} item(s) from your list.',
        ),
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

    if (_usingWorkspace) {
      for (final id in _selectedIds) {
        await _repo.remove(_workspaceId!, id);
      }
    } else {
      await LocalShoppingStore.instance.removeMany(_selectedIds);
    }
    _exitRemoveMode();
  }

  Future<void> _confirmDeleteAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete ALL items?'),
        content: const Text('This will remove every item from your list.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete all'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    if (_usingWorkspace) {
      final col = FirebaseFirestore.instance
          .collection('workspaces')
          .doc(_workspaceId!)
          .collection('shoppingItems');
      final snap = await col.get();
      for (final d in snap.docs) {
        await d.reference.delete();
      }
    } else {
      await LocalShoppingStore.instance.clearAll();
    }
    _exitRemoveMode();
  }

  // ── Calendar: set shopping date (date-only event) ──────────────────────────
  Future<void> _setShoppingDate() async {
    final today = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: today,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;

    final d = DateTime(picked.year, picked.month, picked.day);
    final id =
        'shopping:${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

    CalendarEvents.instance.upsert(
      CalEvent(
        id: id,
        title: 'Shopping trip',
        date: d,
        repeat: 'None',
        every: 1,
        reminder: 'None',
        meta: {'type': 'shopping'},
      ),
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Shopping date set: ${d.toLocal().toString().split(' ').first}',
        ),
      ),
    );
  }

  // ── Barcode (stub) ────────────────────────────────────────────────────────
  String _nameFromBarcode(String code) {
    final cleaned = code.replaceAll(RegExp(r'\D'), '');
    if (cleaned.isEmpty) return 'Unknown item';
    final last4 = cleaned.length >= 4
        ? cleaned.substring(cleaned.length - 4)
        : cleaned;
    return 'Item $last4';
  }

  Future<void> _scanBarcode() async {
    final ctrl = TextEditingController();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Scan / enter barcode',
              style: Theme.of(ctx).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            AppInputs.textField(
              controller: ctrl,
              label: 'Barcode',
              onSubmitted: (_) {},
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                const Spacer(),
                FilledButton.icon(
                  onPressed: () {
                    final code = ctrl.text.trim();
                    final name = _nameFromBarcode(code);
                    if (name.isNotEmpty) {
                      if (_usingWorkspace) {
                        _repo.add(_workspaceId!, name);
                      } else {
                        LocalShoppingStore.instance.add(name);
                      }
                    }
                    Navigator.pop(ctx);
                  },
                  icon: const Icon(Icons.check),
                  label: const Text('Add item'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── UI ─────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    Stream<DocumentSnapshot<Map<String, dynamic>>>? userDocStream;
    if (uid != null) {
      userDocStream = FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .snapshots();
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: userDocStream,
      builder: (context, userSnap) {
        if (userSnap.hasData) {
          final userData = userSnap.data?.data() ?? const <String, dynamic>{};
          final wsId = (userData['currentWorkspaceId'] as String?) ?? '';
          final newWorkspace = wsId.isEmpty ? null : wsId;

          // Detect workspace change
          if (newWorkspace != _lastWorkspaceId) {
            if (_lastWorkspaceId == null && newWorkspace != null) {
              // Joining a workspace
              ShoppingMigrationService.instance.migrateLocalToWorkspace(
                newWorkspace,
              );
            } else if (_lastWorkspaceId != null && newWorkspace == null) {
              // Leaving workspace
              ShoppingMigrationService.instance.extractMineFromWorkspace(
                _lastWorkspaceId!,
              );
            }
            _lastWorkspaceId = newWorkspace;
          }

          _workspaceId = newWorkspace;
        } else {
          if (_lastWorkspaceId != null) {
            // Handle sign-out scenario (also counts as leaving workspace)
            ShoppingMigrationService.instance.extractMineFromWorkspace(
              _lastWorkspaceId!,
            );
            _lastWorkspaceId = null;
          }
          _workspaceId = null;
        }

        return Scaffold(
          appBar: AppBar(
            title: const Text('Shopping'),
            actions: _removeMode
                ? [
                    TextButton(
                      onPressed: _confirmDeleteSelected,
                      child: const Text('Delete selected'),
                    ),
                    IconButton(
                      tooltip: 'Delete all',
                      onPressed: _confirmDeleteAll,
                      icon: const Icon(Icons.delete_forever),
                    ),
                    IconButton(
                      tooltip: 'Cancel',
                      onPressed: _exitRemoveMode,
                      icon: const Icon(Icons.close),
                    ),
                  ]
                : null,
          ),
          body: _usingWorkspace ? _buildFirestoreBody() : _buildLocalBody(),
          floatingActionButton: _fab(context),
          bottomNavigationBar: _removeMode
              ? SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                    child: Row(
                      children: [
                        Text('${_selectedIds.length} selected'),
                        const Spacer(),
                        TextButton(
                          onPressed: () {
                            // “Select all” implemented in each builder
                            // by capturing the current list there.
                          },
                          child: const Text('Select all'),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.red,
                          ),
                          onPressed: _confirmDeleteSelected,
                          child: const Text('Delete selected'),
                        ),
                      ],
                    ),
                  ),
                )
              : null,
        );
      },
    );
  }

  // ── Firestore mode body ────────────────────────────────────────────────────
  Widget _buildFirestoreBody() {
    return StreamBuilder<List<ShoppingDoc>>(
      stream: _repo.watch(_workspaceId!),
      builder: (context, snap) {
        final items = snap.data ?? const <ShoppingDoc>[];

        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (items.isEmpty) {
          return const Center(child: Text('No items yet'));
        }

        return ListView.separated(
          itemCount: items.length,
          separatorBuilder: (_, __) => const Divider(height: 0),
          itemBuilder: (ctx, i) {
            final it = items[i];

            final leading = _removeMode
                ? Checkbox(
                    value: _selectedIds.contains(it.id),
                    onChanged: (v) {
                      setState(() {
                        if (v == true) {
                          _selectedIds.add(it.id);
                        } else {
                          _selectedIds.remove(it.id);
                        }
                      });
                    },
                  )
                : null;

            return ListTile(
              leading: leading,
              title: Text(
                it.name,
                style: it.done
                    ? Theme.of(context).textTheme.bodyLarge?.copyWith(
                        decoration: TextDecoration.lineThrough,
                      )
                    : null,
              ),
              trailing: !_removeMode
                  ? Checkbox(
                      value: it.done,
                      onChanged: (v) =>
                          _repo.toggleDone(_workspaceId!, it.id, v ?? false),
                    )
                  : null,
              onTap: _removeMode
                  ? () {
                      setState(() {
                        if (_selectedIds.contains(it.id)) {
                          _selectedIds.remove(it.id);
                        } else {
                          _selectedIds.add(it.id);
                        }
                      });
                    }
                  : null,
            );
          },
        );
      },
    );
  }

  // ── Local mode body (offline, no workspace) ────────────────────────────────
  Widget _buildLocalBody() {
    return FutureBuilder(
      future: LocalShoppingStore.instance.ensureInitialized(),
      builder: (context, _) {
        return StreamBuilder<List<ShoppingDoc>>(
          stream: LocalShoppingStore.instance.watch(),
          builder: (context, snap) {
            final items = snap.data ?? const <ShoppingDoc>[];

            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (items.isEmpty) {
              return const Center(child: Text('No items yet'));
            }

            return ListView.separated(
              itemCount: items.length,
              separatorBuilder: (_, __) => const Divider(height: 0),
              itemBuilder: (ctx, i) {
                final it = items[i];

                final leading = _removeMode
                    ? Checkbox(
                        value: _selectedIds.contains(it.id),
                        onChanged: (v) {
                          setState(() {
                            if (v == true) {
                              _selectedIds.add(it.id);
                            } else {
                              _selectedIds.remove(it.id);
                            }
                          });
                        },
                      )
                    : null;

                return ListTile(
                  leading: leading,
                  title: Text(
                    it.name,
                    style: it.done
                        ? Theme.of(context).textTheme.bodyLarge?.copyWith(
                            decoration: TextDecoration.lineThrough,
                          )
                        : null,
                  ),
                  trailing: !_removeMode
                      ? Checkbox(
                          value: it.done,
                          onChanged: (v) => LocalShoppingStore.instance
                              .toggleDone(it.id, v ?? false),
                        )
                      : null,
                  onTap: _removeMode
                      ? () {
                          setState(() {
                            if (_selectedIds.contains(it.id)) {
                              _selectedIds.remove(it.id);
                            } else {
                              _selectedIds.add(it.id);
                            }
                          });
                        }
                      : null,
                );
              },
            );
          },
        );
      },
    );
  }

  // ── FAB ────────────────────────────────────────────────────────────────────
  Widget _fab(BuildContext context) {
    return PopupMenuButton<_FabAction>(
      tooltip: 'Actions',
      position: PopupMenuPosition.over,
      onSelected: (a) {
        switch (a) {
          case _FabAction.add:
            _addItemManually();
            break;
          case _FabAction.remove:
            _enterRemoveMode();
            break;
          case _FabAction.setDate:
            _setShoppingDate();
            break;
          case _FabAction.scan:
            _scanBarcode();
            break;
        }
      },
      itemBuilder: (ctx) => const [
        PopupMenuItem(
          value: _FabAction.add,
          child: ListTile(
            leading: Icon(Icons.add),
            title: Text('Add item'),
            dense: true,
            contentPadding: EdgeInsets.zero,
          ),
        ),
        PopupMenuItem(
          value: _FabAction.remove,
          child: ListTile(
            leading: Icon(Icons.remove_circle_outline),
            title: Text('Remove item(s)'),
            dense: true,
            contentPadding: EdgeInsets.zero,
          ),
        ),
        PopupMenuItem(
          value: _FabAction.setDate,
          child: ListTile(
            leading: Icon(Icons.event),
            title: Text('Set shopping date'),
            dense: true,
            contentPadding: EdgeInsets.zero,
          ),
        ),
        PopupMenuItem(
          value: _FabAction.scan,
          child: ListTile(
            leading: Icon(Icons.qr_code_scanner),
            title: Text('Scan barcode'),
            dense: true,
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ],
      child: const FloatingActionButton(
        onPressed: null, // handled by PopupMenuButton
        child: Icon(Icons.add),
      ),
    );
  }
}

enum _FabAction { add, remove, setDate, scan }
