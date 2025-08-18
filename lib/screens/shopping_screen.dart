import 'package:flutter/material.dart';
import '../services/shopping_service.dart';

class ShoppingScreen extends StatefulWidget {
  const ShoppingScreen({super.key});
  @override
  State<ShoppingScreen> createState() => _ShoppingScreenState();
}

class _ShoppingScreenState extends State<ShoppingScreen> {
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

  void _addItemManually() {
    final ctrl = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add item'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(labelText: 'Name'),
          onSubmitted: (_) => _finish(ctrl, ctx),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => _finish(ctrl, ctx),
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  void _finish(TextEditingController ctrl, BuildContext ctx) {
    final name = ctrl.text.trim();
    if (name.isNotEmpty) {
      ShoppingService.instance.add(name);
    }
    Navigator.pop(ctx);
  }

  @override
  Widget build(BuildContext context) {
    final items = ShoppingService.instance.items;
    return Scaffold(
      appBar: AppBar(title: const Text('Shopping')),
      body: ListView.separated(
        itemCount: items.length,
        separatorBuilder: (_, __) => const Divider(height: 0),
        itemBuilder: (ctx, i) {
          final it = items[i];
          return CheckboxListTile(
            value: it.done,
            onChanged: (v) => setState(() => it.done = v ?? false),
            title: Text(
              it.name,
              style: it.done
                  ? Theme.of(context).textTheme.bodyLarge?.copyWith(
                      decoration: TextDecoration.lineThrough,
                    )
                  : null,
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addItemManually,
        child: const Icon(Icons.add),
      ),
    );
  }
}
