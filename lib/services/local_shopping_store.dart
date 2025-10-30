import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import 'shopping_repo.dart'; // for the ShoppingDoc class

/// Offline-first store for shopping items when no workspace is selected.
/// Persists to SharedPreferences and exposes a reactive stream identical
/// enough to the Firestore repo to keep the UI simple.
class LocalShoppingStore {
  LocalShoppingStore._();
  static final LocalShoppingStore instance = LocalShoppingStore._();

  static const _prefsKey = 'local_shopping_v1';

  final _controller = StreamController<List<ShoppingDoc>>.broadcast();
  List<ShoppingDoc> _items = const [];

  bool _initialized = false;
  Future<void>? _initFuture;

  Future<void> ensureInitialized() {
    if (_initialized) return Future.value();
    return _initFuture ??= _load();
  }

  Stream<List<ShoppingDoc>> watch() {
    // Emit immediately on listen.
    // (ensureInitialized should be awaited before watch in UI)
    scheduleMicrotask(() => _controller.add(List.unmodifiable(_items)));
    return _controller.stream;
  }

  Future<void> add(String name, {Map<String, dynamic>? source}) async {
    await ensureInitialized();
    final id = _makeLocalId();
    final now = DateTime.now();
    final doc = ShoppingDoc(
      id: id,
      name: name,
      done: false,
      createdByUid: 'local',
      createdAt: now,
      updatedAt: now,
      source: source,
    );
    _items = [..._items, doc];
    await _save();
  }

  Future<void> toggleDone(String id, bool done) async {
    await ensureInitialized();
    _items = _items
        .map(
          (e) => e.id == id
              ? ShoppingDoc(
                  id: e.id,
                  name: e.name,
                  done: done,
                  createdByUid: e.createdByUid,
                  createdAt: e.createdAt,
                  updatedAt: DateTime.now(),
                  source: e.source,
                )
              : e,
        )
        .toList();
    await _save();
  }

  Future<void> remove(String id) async {
    await ensureInitialized();
    _items = _items.where((e) => e.id != id).toList();
    await _save();
  }

  Future<void> removeMany(Iterable<String> ids) async {
    await ensureInitialized();
    final set = ids.toSet();
    _items = _items.where((e) => !set.contains(e.id)).toList();
    await _save();
  }

  Future<void> clearAll() async {
    await ensureInitialized();
    _items = const [];
    await _save();
  }

  /// For future migration (join workspace): dump current local list.
  List<ShoppingDoc> snapshot() => List.unmodifiable(_items);

  // ── internals ──────────────────────────────────────────────────────────────
  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) {
      _items = const [];
    } else {
      try {
        final list = (jsonDecode(raw) as List)
            .cast<Map>()
            .map((m) => _fromJson(m.cast<String, dynamic>()))
            .toList();
        // Order by createdAt ascending to mimic Firestore ordering
        list.sort((a, b) {
          final at = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          final bt = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          return at.compareTo(bt);
        });
        _items = list;
      } catch (_) {
        _items = const [];
      }
    }
    _initialized = true;
    _controller.add(List.unmodifiable(_items));
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    final data = _items.map(_toJson).toList();
    await prefs.setString(_prefsKey, jsonEncode(data));
    _controller.add(List.unmodifiable(_items));
  }

  Map<String, dynamic> _toJson(ShoppingDoc d) => {
    'id': d.id,
    'name': d.name,
    'done': d.done,
    'createdByUid': d.createdByUid,
    'createdAt': d.createdAt?.toIso8601String(),
    'updatedAt': d.updatedAt?.toIso8601String(),
    if (d.source != null) 'source': d.source,
  };

  ShoppingDoc _fromJson(Map<String, dynamic> m) {
    DateTime? _parse(String? s) =>
        (s == null || s.isEmpty) ? null : DateTime.tryParse(s);
    return ShoppingDoc(
      id: (m['id'] as String?) ?? _makeLocalId(),
      name: (m['name'] as String?) ?? '',
      done: (m['done'] as bool?) ?? false,
      createdByUid: (m['createdByUid'] as String?) ?? 'local',
      createdAt: _parse(m['createdAt'] as String?),
      updatedAt: _parse(m['updatedAt'] as String?),
      source: (m['source'] as Map?)?.cast<String, dynamic>(),
    );
  }

  String _makeLocalId() {
    // Stable, user-scoped style: "local:<random>"
    // (Keeps the same prefix format as workspace IDs "uid:<random>")
    final r = Random();
    final bytes = List<int>.generate(12, (_) => r.nextInt(256));
    final b64 = base64UrlEncode(bytes).replaceAll('=', '');
    return 'local:$b64';
  }
}
