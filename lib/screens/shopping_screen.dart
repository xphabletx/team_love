import 'package:flutter/material.dart';
import '../services/shopping_service.dart';
import '../services/input_service.dart';
import '../services/calendar_events_service.dart';

class ShoppingScreen extends StatefulWidget {
  const ShoppingScreen({super.key});
  @override
  State<ShoppingScreen> createState() => _ShoppingScreenState();
}

class _ShoppingScreenState extends State<ShoppingScreen> {
  bool _removeMode = false;
  final Set<String> _selectedNames = <String>{};

  @override
  void initState() {
    super.initState();
    // Rebuild when Meals adds/removes items
    ShoppingService.instance.addListener(_onChanged);
  }

  @override
  void dispose() {
    ShoppingService.instance.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() => setState(() {});

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
      ShoppingService.instance.add(name);
    }
    Navigator.pop(ctx);
  }

  // ── Remove mode & actions ──────────────────────────────────────────────────
  void _enterRemoveMode() {
    setState(() {
      _removeMode = true;
      _selectedNames.clear();
    });
  }

  void _exitRemoveMode() {
    setState(() {
      _removeMode = false;
      _selectedNames.clear();
    });
  }

  Future<void> _confirmDeleteSelected() async {
    if (_selectedNames.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete selected items?'),
        content: Text(
          'This will remove ${_selectedNames.length} item(s) from your list.',
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

    // Remove one-by-one via the service (keeps persistence consistent).
    for (final n in _selectedNames) {
      ShoppingService.instance.remove(n); // <-- adjust if your API differs
    }
    _exitRemoveMode();
  }

  Future<void> _confirmDeleteAll() async {
    final items = ShoppingService.instance.items;
    if (items.isEmpty) return;
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

    // Clear by removing each (works with simple service APIs).
    for (final it in List.of(items)) {
      ShoppingService.instance.remove(it.name); // adjust if needed
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
        date: d, // date-only (no time codes)
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
    // A tiny, friendly fallback “namer”
    final last4 = cleaned.length >= 4
        ? cleaned.substring(cleaned.length - 4)
        : cleaned;
    return 'Item $last4';
  }

  Future<void> _scanBarcode() async {
    // Placeholder UI: you can replace this with a camera scanner later.
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
                      ShoppingService.instance.add(name);
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
    final items = ShoppingService.instance.items;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Shopping'),
        actions: _removeMode
            ? [
                TextButton(
                  onPressed: _selectedNames.isEmpty
                      ? null
                      : _confirmDeleteSelected,
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
      body: items.isEmpty
          ? const Center(child: Text('No items yet'))
          : ListView.separated(
              itemCount: items.length,
              separatorBuilder: (_, _) => const Divider(height: 0),
              itemBuilder: (ctx, i) {
                final it = items[i];

                // Leading selection checkbox only in remove mode
                final leading = _removeMode
                    ? Checkbox(
                        value: _selectedNames.contains(it.name),
                        onChanged: (v) {
                          setState(() {
                            if (v == true) {
                              _selectedNames.add(it.name);
                            } else {
                              _selectedNames.remove(it.name);
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
                              setState(() => it.done = v ?? false),
                        )
                      : null,
                  onTap: _removeMode
                      ? () {
                          setState(() {
                            if (_selectedNames.contains(it.name)) {
                              _selectedNames.remove(it.name);
                            } else {
                              _selectedNames.add(it.name);
                            }
                          });
                        }
                      : null,
                );
              },
            ),
      floatingActionButton: _fab(context),
      bottomNavigationBar: _removeMode
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Row(
                  children: [
                    Text('${_selectedNames.length} selected'),
                    const Spacer(),
                    TextButton(
                      onPressed: () {
                        // Select all currently visible
                        final names = ShoppingService.instance.items.map(
                          (e) => e.name,
                        );
                        setState(() => _selectedNames.addAll(names));
                      },
                      child: const Text('Select all'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.red,
                      ),
                      onPressed: _selectedNames.isEmpty
                          ? null
                          : _confirmDeleteSelected,
                      child: const Text('Delete selected'),
                    ),
                  ],
                ),
              ),
            )
          : null,
    );
  }

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
