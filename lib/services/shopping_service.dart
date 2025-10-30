// lib/services/shopping_service.dart
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ShoppingItem {
  ShoppingItem({required this.name, this.done = false});
  final String name;
  bool done;

  Map<String, dynamic> toJson() => {'name': name, 'done': done};

  factory ShoppingItem.fromJson(Map<String, dynamic> m) => ShoppingItem(
    name: (m['name'] as String? ?? '').trim(),
    done: m['done'] as bool? ?? false,
  );
}

class ShoppingService extends ChangeNotifier {
  ShoppingService._() {
    // fire-and-forget initial load
    // ignore: discarded_futures
    ensureLoaded();
  }
  static final instance = ShoppingService._();

  // persistence
  static const _kItems = 'teamlove_shopping_items_v1';

  // state
  final List<ShoppingItem> _items = [];
  bool _loaded = false;

  List<ShoppingItem> get items => List.unmodifiable(_items);
  bool get isLoaded => _loaded;

  // ── load/save ──────────────────────────────────────────────────────────────
  Future<void> ensureLoaded() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kItems);

    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw) as List<dynamic>;
        _items
          ..clear()
          ..addAll(
            decoded
                .whereType<Map<String, dynamic>>()
                .map(ShoppingItem.fromJson)
                .where((it) => it.name.isNotEmpty),
          );
      } catch (_) {
        // ignore corrupt json
      }
    }

    _loaded = true;
    notifyListeners();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    final data = jsonEncode(_items.map((e) => e.toJson()).toList());
    await prefs.setString(_kItems, data);
  }

  // ── mutators ───────────────────────────────────────────────────────────────

  /// Add a single item (no-ops on empty or duplicate name).
  void add(String name) {
    final t = name.trim();
    if (t.isEmpty) return;

    final exists = _items.any((it) => it.name.toLowerCase() == t.toLowerCase());
    if (exists) return;

    _items.add(ShoppingItem(name: t));
    notifyListeners();
    // ignore: discarded_futures
    _save();
  }

  /// Bulk add with de-dupe.
  void addMany(Iterable<String> names) {
    final seen = _items.map((it) => it.name.toLowerCase()).toSet();
    var changed = false;

    for (final n in names) {
      final t = n.trim();
      if (t.isEmpty) continue;
      final key = t.toLowerCase();
      if (seen.add(key)) {
        _items.add(ShoppingItem(name: t));
        changed = true;
      }
    }

    if (changed) {
      notifyListeners();
      // ignore: discarded_futures
      _save();
    }
  }

  /// Accepts either a ShoppingItem or a String (item name)
  void remove(dynamic itemOrName) {
    var changed = false;
    if (itemOrName is ShoppingItem) {
      changed = _items.remove(itemOrName);
    } else if (itemOrName is String) {
      final key = itemOrName.toLowerCase().trim();
      final before = _items.length;
      _items.removeWhere((it) => it.name.toLowerCase() == key);
      changed = _items.length != before;
    }
    if (changed) {
      notifyListeners();
      // ignore: discarded_futures
      _save();
    }
  }

  /// Accepts a mixture of ShoppingItem and/or String names
  void removeAll(Iterable<dynamic> itemsOrNames) {
    final names = <String>{};
    final objs = <ShoppingItem>{};
    for (final x in itemsOrNames) {
      if (x is ShoppingItem) objs.add(x);
      if (x is String) names.add(x.toLowerCase().trim());
    }
    final before = _items.length;
    _items.removeWhere(
      (it) => objs.contains(it) || names.contains(it.name.toLowerCase()),
    );
    final changed = _items.length != before;
    if (changed) {
      notifyListeners();
      // ignore: discarded_futures
      _save();
    }
  }

  /// Toggle completion state.
  void toggleDone(ShoppingItem item, {bool? to}) {
    final i = _items.indexOf(item);
    if (i < 0) return;
    _items[i].done = to ?? !_items[i].done;
    notifyListeners();
    // ignore: discarded_futures
    _save();
  }

  /// Clear all items.
  void clearAll() {
    if (_items.isEmpty) return;
    _items.clear();
    notifyListeners();
    // ignore: discarded_futures
    _save();
  }

  /// Clear only completed items.
  void clearCompleted() {
    final before = _items.length;
    _items.removeWhere((it) => it.done);
    if (_items.length != before) {
      notifyListeners();
      // ignore: discarded_futures
      _save();
    }
  }
}
