import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:team_love_app/services/recipes_service.dart';
import 'package:team_love_app/services/shopping_service.dart';
import 'package:team_love_app/screens/meals_day_screen.dart' as meals;
import 'package:team_love_app/services/input_service.dart';
import '../widgets/side_nav_drawer.dart';

/// Lunch/Dinner selection should be top-level (not inside a class)
enum MealType { lunch, dinner }

class RecipeEditorScreen extends StatefulWidget {
  const RecipeEditorScreen({super.key, this.existing});
  final Recipe? existing;

  @override
  State<RecipeEditorScreen> createState() => _RecipeEditorScreenState();
}

class _RecipeEditorScreenState extends State<RecipeEditorScreen> {
  final titleCtrl = TextEditingController();
  final methodCtrl = TextEditingController();
  final notesCtrl = TextEditingController();

  late List<RecipeLine> lines;

  static const _units = <String>[
    '', // none
    'g', 'kg', 'mg',
    'ml', 'l',
    'tsp', 'tbsp',
    'cup', 'cups',
    'oz', 'fl oz', 'lb',
    'pinch', 'dash',
    'slice', 'slices',
    'piece', 'pieces',
  ];

  @override
  void initState() {
    super.initState();
    final r = widget.existing;
    titleCtrl.text = r?.title ?? '';
    methodCtrl.text = r?.method ?? '';
    notesCtrl.text = r?.notes ?? '';

    // If r is null, seed with empty list. (No null-aware on element fields.)
    final src = (r?.ingredients ?? <RecipeLine>[]);
    lines = src
        .map(
          (e) => RecipeLine(
            n: e.n,
            unit: e.unit,
            prep: e.prep,
            item: e.item,
            cook: e.cook,
          ),
        )
        .toList();

    if (lines.isEmpty) {
      lines = [RecipeLine(n: '1')];
    }
  }

  @override
  void dispose() {
    titleCtrl.dispose();
    methodCtrl.dispose();
    notesCtrl.dispose();
    super.dispose();
  }

  void _addLine() => setState(() => lines.add(RecipeLine(n: '1')));
  void _removeLine(int i) => setState(() => lines.removeAt(i));

  Future<void> _save() async {
    final id =
        widget.existing?.id ?? DateTime.now().microsecondsSinceEpoch.toString();
    final r = Recipe(
      id: id,
      title: titleCtrl.text.trim(),
      ingredients: lines,
      method: methodCtrl.text,
      notes: notesCtrl.text,
      sourceUrl: widget.existing?.sourceUrl,
      createdAt: widget.existing?.createdAt,
    );
    if (widget.existing == null) {
      RecipesService.instance.add(r);
    } else {
      RecipesService.instance.update(r);
    }
    if (!mounted) return;
    Navigator.pop(context);
  }

  void _addAllToShopping() {
    // Only: "<n> <item>" (e.g., "2 carrots")
    for (final line in lines) {
      final qty = line.n.trim();
      final item = line.item.trim();
      if (item.isEmpty) continue;
      final name = qty.isEmpty ? item : '$qty $item';
      ShoppingService.instance.add(name);
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Ingredients added to shopping')),
    );
  }

  Future<void> _addToMealPlan() async {
    // 1) Pick date
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 1)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked == null) return;

    // 2) Pick lunch/dinner (visually obvious via SegmentedButton)
    MealType selected = MealType.lunch;

    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSB) => Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Add to meal plan',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                SegmentedButton<MealType>(
                  segments: const [
                    ButtonSegment(
                      value: MealType.lunch,
                      label: Text('Lunch'),
                      icon: Icon(Icons.wb_sunny_outlined),
                    ),
                    ButtonSegment(
                      value: MealType.dinner,
                      label: Text('Dinner'),
                      icon: Icon(Icons.nightlight_round),
                    ),
                  ],
                  selected: {selected},
                  onSelectionChanged: (s) => setSB(() => selected = s.first),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () async {
                    final store = meals.MealsStore.instance;
                    await store.ensureLoaded();

                    final day = store.dayForDate(picked);
                    final entry = meals.MealEntry(
                      userName: 'you',
                      items: [
                        titleCtrl.text.trim().isEmpty
                            ? 'Recipe'
                            : titleCtrl.text.trim(),
                      ],
                    );
                    if (selected == MealType.lunch) {
                      day.lunch.add(entry);
                    } else {
                      day.dinner.add(entry);
                    }
                    await store.saveState();

                    // Use the local bottom-sheet context and guard after awaits.
                    if (!ctx.mounted) return;
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Added "${entry.items.first}" to '
                          '${selected == MealType.lunch ? 'Lunch' : 'Dinner'}',
                        ),
                      ),
                    );
                  },
                  child: const Text('Add'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existing == null ? 'New recipe' : 'Edit recipe'),
        actions: [
          IconButton(
            tooltip: 'Save',
            icon: const Icon(Icons.check),
            onPressed: _save,
          ),
        ],
      ),
      drawer: const Drawer(child: SideNavDrawer()),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
        children: [
          AppInputs.textField(
            controller: titleCtrl,
            decoration: const InputDecoration(labelText: 'Recipe title'),
          ),
          const SizedBox(height: 12),
          Text('Ingredients', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          ...List.generate(lines.length, (i) {
            final l = lines[i];
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: _IngredientRow(
                  line: l,
                  units: _units,
                  onRemove: () => _removeLine(i),
                  onChanged: () => setState(() {}),
                ),
              ),
            );
          }),
          TextButton.icon(
            onPressed: _addLine,
            icon: const Icon(Icons.add),
            label: const Text('Add ingredient'),
          ),
          const SizedBox(height: 12),
          AppInputs.textField(
            controller: methodCtrl,
            maxLines: 6,
            decoration: const InputDecoration(labelText: 'Method (optional)'),
          ),
          const SizedBox(height: 12),
          AppInputs.textField(
            controller: notesCtrl,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'Notes (optional)'),
          ),
          const SizedBox(height: 24),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: _addAllToShopping,
                icon: const Icon(Icons.add_shopping_cart),
                label: const Text('Add all to Shopping'),
              ),
              OutlinedButton.icon(
                onPressed: _addToMealPlan,
                icon: const Icon(Icons.event),
                label: const Text('Add to Meal Plan'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _IngredientRow extends StatelessWidget {
  const _IngredientRow({
    required this.line,
    required this.units,
    required this.onRemove,
    required this.onChanged,
  });

  final RecipeLine line;
  final List<String> units;
  final VoidCallback onRemove;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final showOf = line.unit.trim().isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            // [n] (number only)
            SizedBox(
              width: 72,
              child: TextFormField(
                initialValue: line.n,
                onChanged: (v) => line.n = v,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9\.\,]')),
                ],
                decoration: const InputDecoration(labelText: 'n'),
              ),
            ),
            const SizedBox(width: 8),
            // [measurement]
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: line.unit, // <- replace deprecated value:
                items: units
                    .map(
                      (u) => DropdownMenuItem<String>(
                        value: u,
                        child: Text(u.isEmpty ? '(none)' : u),
                      ),
                    )
                    .toList(),
                onChanged: (v) {
                  line.unit = v ?? '';
                  onChanged();
                },
                decoration: const InputDecoration(labelText: 'measurement'),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'Remove line',
              icon: const Icon(Icons.delete_outline),
              onPressed: onRemove,
            ),
          ],
        ),
        const SizedBox(height: 6),
        if (showOf) const Text('of'),
        const SizedBox(height: 6),

        // [prep] [item]
        Row(
          children: [
            Expanded(
              child: TextFormField(
                initialValue: line.prep,
                onChanged: (v) => line.prep = v,
                decoration: const InputDecoration(
                  labelText: 'prep (e.g., diced)',
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextFormField(
                initialValue: line.item,
                onChanged: (v) => line.item = v,
                decoration: const InputDecoration(
                  labelText: 'item (e.g., carrots)',
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        // [cook]
        TextFormField(
          initialValue: line.cook,
          onChanged: (v) => line.cook = v,
          decoration: const InputDecoration(
            labelText: 'cooking condition (e.g., roasted)',
          ),
        ),
      ],
    );
  }
}
