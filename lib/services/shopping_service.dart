import 'package:flutter/foundation.dart';

class ShoppingItem {
  ShoppingItem({required this.name, this.done = false});
  final String name;
  bool done;
}

class ShoppingService extends ChangeNotifier {
  static final instance = ShoppingService._();
  ShoppingService._();

  final List<ShoppingItem> _items = [];
  List<ShoppingItem> get items => List.unmodifiable(_items);

  void add(String name) {
    _items.add(ShoppingItem(name: name));
    notifyListeners();
  }

  // ✅ Accepts either a ShoppingItem or a String (item name)
  void remove(dynamic itemOrName) {
    if (itemOrName is ShoppingItem) {
      _items.remove(itemOrName);
    } else if (itemOrName is String) {
      _items.removeWhere((it) => it.name == itemOrName);
    }
    notifyListeners();
  }

  // ✅ Accepts a mixture of ShoppingItem and/or String names
  void removeAll(Iterable<dynamic> itemsOrNames) {
    final names = <String>{};
    final objs = <ShoppingItem>{};
    for (final x in itemsOrNames) {
      if (x is ShoppingItem) objs.add(x);
      if (x is String) names.add(x);
    }
    _items.removeWhere((it) => objs.contains(it) || names.contains(it.name));
    notifyListeners();
  }
}
