import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _prefsKeyRecipes = 'teamlove_recipes_v1';

class RecipesService extends ChangeNotifier {
  RecipesService._();
  static final RecipesService instance = RecipesService._();

  final List<Recipe> _recipes = [];
  bool _loaded = false;

  List<Recipe> get recipes => List.unmodifiable(_recipes);

  Future<void> ensureLoaded() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKeyRecipes);
    if (raw != null && raw.isNotEmpty) {
      try {
        final list = (jsonDecode(raw) as List<dynamic>)
            .map((e) => Recipe.fromJson(e as Map<String, dynamic>))
            .toList();
        _recipes
          ..clear()
          ..addAll(list);
      } catch (_) {}
    }
    _loaded = true;
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefsKeyRecipes,
      jsonEncode(_recipes.map((e) => e.toJson()).toList()),
    );
  }

  void add(Recipe r) {
    _recipes.add(r);
    _save();
    notifyListeners();
  }

  void update(Recipe r) {
    final i = _recipes.indexWhere((x) => x.id == r.id);
    if (i != -1) _recipes[i] = r;
    _save();
    notifyListeners();
  }

  void remove(String id) {
    _recipes.removeWhere((x) => x.id == id);
    _save();
    notifyListeners();
  }
}

class Recipe {
  Recipe({
    required this.id,
    required this.title,
    required this.ingredients,
    this.method = '',
    this.notes = '',
    this.sourceUrl,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  final String id;
  String title;
  List<RecipeLine> ingredients;
  String method;
  String notes;
  String? sourceUrl;
  DateTime createdAt;

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'ingredients': ingredients.map((e) => e.toJson()).toList(),
    'method': method,
    'notes': notes,
    'sourceUrl': sourceUrl,
    'createdAt': createdAt.toIso8601String(),
  };

  factory Recipe.fromJson(Map<String, dynamic> m) => Recipe(
    id: m['id'] as String,
    title: m['title'] as String? ?? '',
    ingredients: (m['ingredients'] as List<dynamic>? ?? [])
        .map((e) => RecipeLine.fromJson(e as Map<String, dynamic>))
        .toList(),
    method: m['method'] as String? ?? '',
    notes: m['notes'] as String? ?? '',
    sourceUrl: m['sourceUrl'] as String?,
    createdAt:
        DateTime.tryParse(m['createdAt'] as String? ?? '') ?? DateTime.now(),
  );
}

class RecipeLine {
  RecipeLine({
    required this.n,
    this.unit = '',
    this.prep = '',
    this.item = '',
    this.cook = '',
  });

  String n; // required (but we don't enforce > 0)
  String unit; // measurement (can be blank)
  String prep; // e.g., diced (can be blank)
  String item; // ingredient name (can be blank per your request)
  String cook; // e.g., roasted (can be blank)

  Map<String, dynamic> toJson() => {
    'n': n,
    'unit': unit,
    'prep': prep,
    'item': item,
    'cook': cook,
  };

  factory RecipeLine.fromJson(Map<String, dynamic> m) => RecipeLine(
    n: m['n'] as String? ?? '',
    unit: m['unit'] as String? ?? '',
    prep: m['prep'] as String? ?? '',
    item: m['item'] as String? ?? '',
    cook: m['cook'] as String? ?? '',
  );

  /// Renders: [n] [unit] of [prep] [item] [cook]
  /// If unit is blank => remove "of".
  String render() {
    final p = prep.trim();
    final it = item.trim();
    final ck = cook.trim();
    final u = unit.trim();
    final buf = StringBuffer();
    buf.write(n.trim());
    if (u.isNotEmpty) buf.write(' $u of');
    if (p.isNotEmpty) buf.write(' $p');
    if (it.isNotEmpty) buf.write(' $it');
    if (ck.isNotEmpty) buf.write(' $ck');
    return buf.toString().trim();
  }
}
