import 'package:flutter/foundation.dart';

class ShoppingItem {
  ShoppingItem({required this.name, this.done = false});
  final String name;
  bool done;
}

class ShoppingService extends ChangeNotifier {
  ShoppingService._();
  static final ShoppingService instance = ShoppingService._();

  final List<ShoppingItem> _items = [];
  List<ShoppingItem> get items => List.unmodifiable(_items);

  void add(String name) {
    if (name.trim().isEmpty) return;
    _items.add(ShoppingItem(name: name.trim()));
    notifyListeners();
  }

  void toggle(int index, bool value) {
    if (index < 0 || index >= _items.length) return;
    _items[index].done = value;
    notifyListeners();
  }
}
