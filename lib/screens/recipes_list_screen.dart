import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:team_love_app/services/recipes_service.dart';
import 'package:team_love_app/screens/recipe_editor_screen.dart';
import 'package:team_love_app/screens/meals_day_screen.dart' as meals;
import '../widgets/side_nav_drawer.dart';

enum RecipeFilter { all, created, imported }

class RecipesListScreen extends StatefulWidget {
  const RecipesListScreen({super.key});
  @override
  State<RecipesListScreen> createState() => _RecipesListScreenState();
}

class _RecipesListScreenState extends State<RecipesListScreen> {
  List<Recipe> _filtered(List<Recipe> all) {
    switch (filter) {
      case RecipeFilter.created:
        return all
            .where((r) => (r.sourceUrl == null) || r.sourceUrl!.isEmpty)
            .toList();
      case RecipeFilter.imported:
        return all.where((r) => (r.sourceUrl ?? '').isNotEmpty).toList();
      case RecipeFilter.all:
        return all;
    }
  }

  RecipeFilter filter = RecipeFilter.all;
  bool selectionMode = false;
  final Set<String> _selectedIds = {};

  @override
  void initState() {
    super.initState();
    RecipesService.instance
      ..addListener(_rebuild)
      ..ensureLoaded().then((_) {
        if (mounted) setState(() {});
      });
  }

  @override
  void dispose() {
    RecipesService.instance.removeListener(_rebuild);
    super.dispose();
  }

  void _rebuild() => setState(() {});

  void _openEditor({Recipe? existing}) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => RecipeEditorScreen(existing: existing)),
    );
  }

  Future<void> _importFromUrl() async {
    final ctrl = TextEditingController();

    final url = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Import recipe from URL'),
        content: Row(
          children: [
            Expanded(
              child: TextField(
                controller: ctrl,
                decoration: const InputDecoration(
                  labelText: 'Paste link',
                  hintText: 'https://example.com/recipe',
                ),
                keyboardType: TextInputType.url,
                autofocus: true,
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'Paste',
              icon: const Icon(Icons.content_paste_go),
              onPressed: () async {
                final data = await Clipboard.getData(Clipboard.kTextPlain);
                if (data?.text != null && data!.text!.trim().isNotEmpty) {
                  ctrl.text = data.text!.trim();
                }
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Import'),
          ),
        ],
      ),
    );

    if (url == null || url.isEmpty) return;

    try {
      // --- Fetch HTML (spoof UA so some sites return full markup) ---
      final uri = Uri.parse(url);
      final client = HttpClient()
        ..userAgent =
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
            '(KHTML, like Gecko) Chrome/124.0 Safari/537.36';
      final req = await client.getUrl(uri);
      final res = await req.close();
      final html = await res.transform(utf8.decoder).join();
      client.close(force: true);

      // --- Parse JSON-LD recipe first; fall back to <title> ---
      final parsed = _parseRecipeFromHtml(html, url);

      RecipesService.instance.add(parsed);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            parsed.ingredients.isEmpty
                ? 'Imported link (no structured ingredients found).'
                : 'Imported recipe: ${parsed.title.isEmpty ? '(Untitled)' : parsed.title}',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Could not fetch page.')));
    }
  }

  /// Build a Recipe from HTML by reading JSON-LD (Schema.org Recipe).
  Recipe _parseRecipeFromHtml(String html, String url) {
    final jsonLdBlocks = _extractJsonLdBlocks(html);

    Map<String, dynamic>? recipeObj;

    for (final raw in jsonLdBlocks) {
      try {
        final decoded = json.decode(raw);

        if (decoded is Map<String, dynamic>) {
          if (decoded['@type'] == 'Recipe') {
            recipeObj = decoded;
            break;
          } else if (decoded['@graph'] is List) {
            final hit = (decoded['@graph'] as List)
                .cast<Map<String, dynamic>?>()
                .firstWhere(
                  (m) => (m?['@type'] == 'Recipe'),
                  orElse: () => null,
                );
            if (hit != null) {
              recipeObj = hit;
              break;
            }
          }
        } else if (decoded is List) {
          final hit = decoded.cast<Map<String, dynamic>?>().firstWhere((m) {
            final t = m?['@type'];
            if (t is String) return t == 'Recipe';
            if (t is List) return t.contains('Recipe');
            return false;
          }, orElse: () => null);
          if (hit != null) {
            recipeObj = hit;
            break;
          }
        }
      } catch (_) {
        // ignore parse errors
      }
    }

    String title = '';
    List<String> ingredients = [];
    String method = '';

    if (recipeObj != null) {
      // Title
      final t = recipeObj['name'];
      if (t is String) title = t.trim();

      // Ingredients
      final ing = recipeObj['recipeIngredient'];
      if (ing is List) {
        ingredients = ing.whereType<String>().map((s) => s.trim()).toList();
      }

      // Instructions
      final instr = recipeObj['recipeInstructions'];
      if (instr is String) {
        method = instr.trim();
      } else if (instr is List) {
        final parts = <String>[];
        for (final step in instr) {
          if (step is String) {
            parts.add(step.trim());
          } else if (step is Map) {
            final text = (step['text'] ?? step['name'])?.toString().trim();
            if (text != null && text.isNotEmpty) parts.add(text);
          }
        }
        method = parts.join('\n');
      }
    }

    // Fallback title from <title>
    if (title.isEmpty) {
      final m = RegExp(
        r'<title>([^<]{1,160})</title>',
        caseSensitive: false,
      ).firstMatch(html);
      title = (m?.group(1) ?? 'Imported recipe').trim();
    }

    // Build Recipe model
    final lines = ingredients.map((s) => RecipeLine(n: '', item: s)).toList();
    final notes = ingredients.isEmpty && method.isEmpty ? 'Source: $url' : '';

    return Recipe(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      title: title,
      ingredients: lines,
      method: method,
      notes: notes,
      sourceUrl: url,
    );
  }

  /// Extract all <script type="application/ld+json"> blocks from HTML.
  List<String> _extractJsonLdBlocks(String html) {
    final rx = RegExp(
      "<script[^>]+type=[\"']application/ld\\+json[\"'][^>]*>([\\s\\S]*?)</script>",
      caseSensitive: false,
    );
    return rx
        .allMatches(html)
        .map((m) => m.group(1))
        .whereType<String>()
        .map((s) => s.trim())
        .toList();
  }

  Future<void> _quickAddToMealPlan(Recipe r) async {
    // 1) Pick date
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked == null) return;

    // 2) Pick lunch/dinner
    var selected = MealType.lunch;
    if (!mounted) return;

    await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
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
                    items: [r.title.isEmpty ? 'Recipe' : r.title],
                  );
                  if (selected == MealType.lunch) {
                    day.lunch.add(entry);
                  } else {
                    day.dinner.add(entry);
                  }
                  await store.saveState();

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
      ),
    );
  }

  void _toggleSelectionMode([bool? on]) {
    setState(() {
      selectionMode = on ?? !selectionMode;
      if (!selectionMode) _selectedIds.clear();
    });
  }

  void _toggleSelected(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  void _deleteSelected() {
    if (_selectedIds.isEmpty) return;
    for (final id in _selectedIds) {
      RecipesService.instance.remove(id);
    }
    _toggleSelectionMode(false);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Deleted selected recipes')));
  }

  void _copyAsText(Recipe r) {
    final buf = StringBuffer()
      ..writeln(r.title.isEmpty ? '(Untitled recipe)' : r.title)
      ..writeln()
      ..writeln('Ingredients:')
      ..writeln(
        r.ingredients.isEmpty
            ? '- (none)'
            : r.ingredients
                  .map((e) {
                    // These fields are non-nullable in the model; no null-aware ops.
                    final qty = e.n.trim();
                    final item = e.item.trim();
                    final unit = e.unit.trim();
                    final prep = e.prep.trim();
                    final cook = e.cook.trim();

                    final of = unit.isEmpty ? '' : ' of ';
                    final prepTxt = prep.isEmpty ? '' : '$prep ';
                    final cookTxt = cook.isEmpty ? '' : ' ($cook)';
                    final qtyTxt = qty.isEmpty ? '' : '$qty ';
                    final unitTxt = unit.isEmpty ? '' : unit;
                    return '- $qtyTxt$unitTxt$of$prepTxt$item$cookTxt';
                  })
                  .join('\n'),
      )
      ..writeln()
      ..writeln('Method:')
      ..writeln(r.method.trim().isEmpty ? '(none)' : r.method.trim());
    Clipboard.setData(ClipboardData(text: buf.toString()));
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Recipe copied to clipboard')));
  }

  @override
  Widget build(BuildContext context) {
    final all = RecipesService.instance.recipes;
    final items = _filtered(all);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Recipes'),
        actions: [
          if (!selectionMode)
            IconButton(
              tooltip: 'Select',
              icon: const Icon(Icons.checklist),
              onPressed: _toggleSelectionMode,
            )
          else ...[
            TextButton(
              onPressed: _deleteSelected,
              child: Text('Delete (${_selectedIds.length})'),
            ),
            IconButton(
              tooltip: 'Cancel selection',
              icon: const Icon(Icons.close),
              onPressed: () => _toggleSelectionMode(false),
            ),
          ],
        ],
      ),
      drawer: const Drawer(child: SideNavDrawer()),
      body: Column(
        children: [
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: SegmentedButton<RecipeFilter>(
              segments: const [
                ButtonSegment(value: RecipeFilter.all, label: Text('All')),
                ButtonSegment(
                  value: RecipeFilter.created,
                  label: Text('Created'),
                ),
                ButtonSegment(
                  value: RecipeFilter.imported,
                  label: Text('Imported'),
                ),
              ],
              selected: {filter},
              onSelectionChanged: (s) => setState(() => filter = s.first),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: items.isEmpty
                ? const Center(child: Text('No recipes yet'))
                : ListView.separated(
                    itemCount: items.length,
                    separatorBuilder: (context, _) =>
                        const Divider(height: 0), // no multi-underscore param
                    itemBuilder: (ctx, i) {
                      final r = items[i];
                      final imported = (r.sourceUrl ?? '').isNotEmpty;
                      final selected = _selectedIds.contains(r.id);

                      return ListTile(
                        leading: selectionMode
                            ? Checkbox(
                                value: selected,
                                onChanged: (_) => _toggleSelected(r.id),
                              )
                            : Icon(imported ? Icons.link : Icons.book_outlined),
                        title: Text(r.title.isEmpty ? '(Untitled)' : r.title),
                        subtitle: Text(
                          r.ingredients.isEmpty
                              ? (imported ? 'Imported' : 'No ingredients')
                              : '${r.ingredients.length} ingredient(s)'
                                    '${imported ? ' · Imported' : ''}',
                        ),
                        onTap: selectionMode
                            ? () => _toggleSelected(r.id)
                            : () => _openEditor(existing: r),
                        trailing: selectionMode
                            ? null
                            : Wrap(
                                spacing: 0,
                                children: [
                                  IconButton(
                                    tooltip: 'Add to meal plan',
                                    icon: const Icon(Icons.event),
                                    onPressed: () => _quickAddToMealPlan(r),
                                  ),
                                  PopupMenuButton<String>(
                                    onSelected: (value) {
                                      switch (value) {
                                        case 'copy':
                                          _copyAsText(r);
                                          break;
                                        case 'delete':
                                          RecipesService.instance.remove(r.id);
                                          break;
                                      }
                                    },
                                    itemBuilder: (ctx) => const [
                                      PopupMenuItem(
                                        value: 'copy',
                                        child: Text('Copy as text'),
                                      ),
                                      PopupMenuItem(
                                        value: 'delete',
                                        child: Text('Delete'),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showFab,
        child: const Icon(Icons.add),
      ),
    );
  }

  void _showFab() {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            if (!selectionMode)
              ListTile(
                leading: const Icon(Icons.add),
                title: const Text('Create recipe'),
                onTap: () {
                  Navigator.pop(ctx);
                  _openEditor();
                },
              ),
            if (!selectionMode)
              ListTile(
                leading: const Icon(Icons.link),
                title: const Text('Import from URL'),
                onTap: () {
                  Navigator.pop(ctx);
                  _importFromUrl();
                },
              ),
            if (selectionMode)
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: Text('Delete selected (${_selectedIds.length})'),
                onTap: () {
                  Navigator.pop(ctx);
                  _deleteSelected();
                },
              ),
            if (!selectionMode)
              ListTile(
                leading: const Icon(Icons.checklist),
                title: const Text('Multi-select'),
                onTap: () {
                  Navigator.pop(ctx);
                  _toggleSelectionMode(true);
                },
              ),
            ListTile(
              leading: const Icon(Icons.close),
              title: const Text('Close'),
              onTap: () => Navigator.pop(ctx),
            ),
          ],
        ),
      ),
    );
  }
}
