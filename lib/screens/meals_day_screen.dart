import 'package:flutter/material.dart';
import '../services/shopping_service.dart';

/// ---- Simple in-memory store of meals for the whole week ----
/// In a future pass, swap this to Firestore and keep the same API.
class MealsStore {
  MealsStore._();
  static final MealsStore instance = MealsStore._();

  /// Pretend workspace users (replace with your auth/workspace users later)
  final List<String> users = const ['you', 'partner'];

  /// dayName -> DayMeals
  final Map<String, DayMeals> _byDay = {
    for (final d in const [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ])
      d: DayMeals(),
  };

  DayMeals day(String dayName) => _byDay[dayName] ??= DayMeals();
}

class DayMeals {
  final List<MealEntry> lunch = [];
  final List<MealEntry> dinner = [];
}

/// One row user’s meal entry (or shared dinner entry)
class MealEntry {
  MealEntry({
    required this.userName,
    required this.items,
    this.sharedDinner = false,
  });

  String userName; // e.g., 'you' or 'partner' or 'shared'
  final List<String> items;
  bool sharedDinner;

  int ingredientsAdded = 0; // count pushed to shopping list
}

/// ------------------------------------------------------------

class MealsDayScreen extends StatefulWidget {
  const MealsDayScreen({super.key, required this.dayName});
  final String dayName;

  @override
  State<MealsDayScreen> createState() => _MealsDayScreenState();
}

class _MealsDayScreenState extends State<MealsDayScreen> {
  DayMeals get _day => MealsStore.instance.day(widget.dayName);

  // MASSIVE suggestions (trim/add more as you like)
  // Tip: keep it flat for now; we can categorize later.
  static const List<String> _suggestions = [
    // Meats
    'bacon',
    'beef steak',
    'ground beef',
    'beef jerky',
    'pork chops',
    'pork belly',
    'turkey steaks',
    'ham',
    'sausage',
    'rump steak',
    'sirloin steak',
    'fillet steak',
    'flat iron steak',
    'chorizo',
    'salami',
    'prosciutto',
    'lamb chops',
    'lamb shank',
    'duck breast',
    'turkey breast',
    'ground turkey',
    'chicken breast',
    'chicken thigh',
    'chicken drumstick',
    'roast chicken',
    'fried chicken',
    'grilled chicken',
    'roast pork',
    'barbecued ribs',
    'pulled pork', 'venison steak', 'rabbit stew', 'goose roast', 'quail roast',
    // Fish & Seafood
    'salmon fillet',
    'smoked salmon',
    'tuna steak',
    'canned tuna',
    'mackerel',
    'sardines',
    'anchovies',
    'cod fillet',
    'haddock',
    'halibut',
    'trout',
    'sea bass',
    'red snapper',
    'prawns',
    'shrimp',
    'lobster',
    'crab',
    'scallops',
    'mussels',
    'clams',
    'squid',
    'octopus',
    'oysters',
    // Eggs & Dairy
    'egg (fried)',
    'egg (boiled)',
    'egg (scrambled)',
    'omelette',
    'poached egg',
    'milk',
    'butter',
    'cream',
    'sour cream',
    'yogurt',
    'greek yogurt',
    'cheddar cheese',
    'mozzarella',
    'feta',
    'parmesan',
    'brie',
    'camembert',
    'goat cheese',
    'blue cheese',
    'cream cheese',
    // Vegetables
    'potato (baked)',
    'potato (mashed)',
    'potato (roast)',
    'sweet potato',
    'carrot',
    'onion',
    'red onion',
    'spring onion',
    'garlic',
    'ginger',
    'cabbage',
    'red cabbage',
    'lettuce',
    'romaine lettuce',
    'spinach',
    'kale',
    'broccoli',
    'cauliflower',
    'brussels sprouts',
    'peas',
    'green beans',
    'asparagus',
    'courgette',
    'aubergine',
    'cucumber',
    'tomato',
    'cherry tomato',
    'bell pepper (red)',
    'bell pepper (green)',
    'bell pepper (yellow)',
    'jalapeño',
    'chilli pepper',
    'mushrooms',
    'button mushrooms',
    'portobello mushrooms',
    'leek',
    'celery',
    'artichoke',
    'parsnip',
    'beetroot',
    'turnip',
    'radish',
    'pumpkin',
    'butternut squash',
    'corn on the cob',
    'grilled corn',
    // Fruits
    'apple',
    'pear',
    'banana',
    'orange',
    'clementine',
    'lemon',
    'lime',
    'grapefruit',
    'mango',
    'pineapple',
    'kiwi',
    'strawberries',
    'blueberries',
    'raspberries',
    'blackberries',
    'cherries',
    'grapes',
    'melon',
    'watermelon', 'figs', 'dates', 'plums', 'apricot', 'pomegranate', 'avocado',
    // Nuts & Seeds & Legumes & Grains (shortened a tad)
    'almonds',
    'peanuts',
    'cashews',
    'walnuts',
    'pecans',
    'hazelnuts',
    'macadamia nuts',
    'brazil nuts',
    'pine nuts',
    'pistachios',
    'chia seeds',
    'flax seeds',
    'pumpkin seeds',
    'sunflower seeds',
    'sesame seeds',
    'quinoa',
    'lentils',
    'red lentils',
    'green lentils',
    'chickpeas',
    'kidney beans',
    'black beans', 'pinto beans', 'butter beans', 'broad beans', 'edamame',
    'white bread',
    'wholemeal bread',
    'rye bread',
    'naan bread',
    'pita bread',
    'tortilla',
    'wrap',
    'spaghetti',
    'penne pasta',
    'fusilli pasta',
    'lasagna sheets',
    'couscous',
    'rice (white)',
    'rice (brown)',
    'basmati rice',
    'jasmine rice',
    'wild rice',
    'oats',
    'porridge oats',
    // Herbs & Spices
    'salt',
    'black pepper',
    'white pepper',
    'paprika',
    'smoked paprika',
    'cumin',
    'coriander',
    'turmeric',
    'cinnamon',
    'nutmeg',
    'allspice',
    'chilli flakes',
    'oregano',
    'thyme',
    'rosemary',
    'sage',
    'basil',
    'parsley',
    'dill',
    'mint',
    'bay leaves',
    'cloves',
    'cardamom',
    'star anise',
    'fennel seeds',
    'mustard seeds',
    // Cooking styles (for auto-complete “meal-ish” phrases)
    'grilled steak',
    'barbecued steak',
    'pan-fried salmon',
    'steamed vegetables',
    'stir-fried chicken',
    'roast beef',
    'braised lamb',
    'smoked brisket',
    'slow-cooked pork',
    'poached chicken',
    'deep-fried fish',
    'baked potato',
    'stuffed peppers',
    'roast vegetables',
    'pickled onions',
    'kimchi',
  ];

  // ------- Add / Edit bottom sheets -------

  Future<void> _addMeal({required bool isLunch}) async {
    String selectedUser = MealsStore.instance.users.first;
    bool sharedDinner = false;
    final items = <String>[];

    // ⬇️ create once (NOT inside the builder)
    final textCtrl = TextEditingController();
    final inputFocus = FocusNode();

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          void addItemFromField() {
            final t = textCtrl.text.trim();
            if (t.isEmpty) return;
            setModalState(() {
              items.add(t);
              textCtrl.clear();
              inputFocus.requestFocus();
            });
          }

          return Padding(
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
                  isLunch ? 'Add Lunch' : 'Add Dinner',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Text('User:'),
                    const SizedBox(width: 12),
                    DropdownButton<String>(
                      value: selectedUser,
                      onChanged: (v) => setModalState(() => selectedUser = v!),
                      items: MealsStore.instance.users
                          .map(
                            (u) => DropdownMenuItem(value: u, child: Text(u)),
                          )
                          .toList(),
                    ),
                    const Spacer(),
                    if (!isLunch)
                      Row(
                        children: [
                          const Text('Shared'),
                          Switch(
                            value: sharedDinner,
                            onChanged: (v) =>
                                setModalState(() => sharedDinner = v),
                          ),
                        ],
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: textCtrl,
                        focusNode: inputFocus,
                        decoration: const InputDecoration(
                          labelText: 'Add item (e.g., chicken salad)',
                        ),
                        onChanged: (_) =>
                            setModalState(() {}), // refresh suggestions
                        onSubmitted: (_) => addItemFromField(),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add),
                      onPressed: addItemFromField,
                    ),
                  ],
                ),
                if (items.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Wrap(
                      spacing: 6,
                      runSpacing: -8,
                      children: items
                          .map(
                            (s) => InputChip(
                              label: Text(s),
                              onDeleted: () =>
                                  setModalState(() => items.remove(s)),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                SizedBox(
                  height: 140,
                  child: _SuggestionList(
                    source: _suggestions,
                    query: textCtrl.text, // ⬅️ uses persistent controller
                    onPick: (s) {
                      setModalState(() {
                        items.add(s);
                        textCtrl.clear();
                        inputFocus.requestFocus();
                      });
                    },
                  ),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton(
                    onPressed: items.isEmpty
                        ? null
                        : () {
                            setState(() {
                              final entry = MealEntry(
                                userName: selectedUser,
                                items: List.from(items),
                                sharedDinner: !isLunch && sharedDinner,
                              );
                              (isLunch ? _day.lunch : _day.dinner).add(entry);
                            });
                            Navigator.pop(ctx);
                          },
                    child: const Text('Save'),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );

    // ⬇️ clean up AFTER the sheet closes
    textCtrl.dispose();
    inputFocus.dispose();
  }

  List<String> _filterSuggestions(List<String> current, String q) {
    final set = current.map((e) => e.toLowerCase()).toSet();
    q = q.toLowerCase();
    return _suggestions
        .where(
          (s) =>
              (q.isEmpty || s.toLowerCase().contains(q)) &&
              !set.contains(s.toLowerCase()),
        )
        .take(50)
        .toList();
  }

  Future<void> _addIngredientToShopping(MealEntry entry) async {
    final ctrl = TextEditingController(); // ⬅️ create once
    final focus = FocusNode();

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          void add(String name) {
            final n = name.trim();
            if (n.isEmpty) return;
            ShoppingService.instance.add(n);
            setState(() => entry.ingredientsAdded++);
            setModalState(() {
              ctrl.clear();
              focus.requestFocus();
            });
          }

          return Padding(
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
                  'Add ingredients to shopping list',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: ctrl,
                  focusNode: focus,
                  decoration: const InputDecoration(labelText: 'Ingredient'),
                  onChanged: (_) => setModalState(() {}), // refresh suggestions
                  onSubmitted: add,
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 140,
                  child: _SuggestionList(
                    source: _suggestions,
                    query: ctrl.text,
                    onPick: add,
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Done'),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );

    ctrl.dispose();
    focus.dispose();
  }

  // ------- UI -------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.dayName)),
      body: ListView(
        children: [
          _sectionHeader(
            icon: Icons.wb_sunny_outlined,
            title: 'Lunch',
            onAdd: () => _addMeal(isLunch: true),
          ),
          ..._day.lunch.map(_buildEntryTile).toList(),
          const Divider(),
          _sectionHeader(
            icon: Icons.nights_stay_outlined,
            title: 'Dinner',
            onAdd: () => _addMeal(isLunch: false),
          ),
          ..._day.dinner.map(_buildEntryTile).toList(),
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  Widget _sectionHeader({
    required IconData icon,
    required String title,
    required VoidCallback onAdd,
  }) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title, style: Theme.of(context).textTheme.titleMedium),
      trailing: IconButton(icon: const Icon(Icons.add), onPressed: onAdd),
    );
  }

  Widget _buildEntryTile(MealEntry e) {
    final subtitle = [
      if (e.sharedDinner) '[shared]',
      if (e.items.isNotEmpty) e.items.join(', '),
      if (e.ingredientsAdded > 0) '• ${e.ingredientsAdded} ingredients added',
    ].join('  ');

    return ListTile(
      leading: const Icon(Icons.restaurant_menu),
      title: Text('${e.userName}'),
      subtitle: Text(subtitle),
      trailing: Wrap(
        spacing: 4,
        children: [
          IconButton(
            tooltip: 'Add ingredients to shopping',
            icon: const Icon(Icons.add_shopping_cart),
            onPressed: () => _addIngredientToShopping(e),
          ),
          IconButton(
            tooltip: 'Delete entry',
            icon: const Icon(Icons.delete_outline),
            onPressed: () => setState(() {
              _day.lunch.remove(e);
              _day.dinner.remove(e);
            }),
          ),
        ],
      ),
    );
  }
}

/// Small suggestions list that updates on each keystroke (no scrolling trick needed)
class _SuggestionList extends StatelessWidget {
  const _SuggestionList({
    required this.source,
    required this.query,
    required this.onPick,
  });

  final List<String> source;
  final String query;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final q = query.trim().toLowerCase();
    final filtered = source
        .where((s) => q.isEmpty || s.toLowerCase().contains(q))
        .take(50)
        .toList();
    if (filtered.isEmpty) {
      return const Center(child: Text('No suggestions'));
    }
    return ListView.builder(
      itemCount: filtered.length,
      itemBuilder: (ctx, i) => ListTile(
        dense: true,
        title: Text(filtered[i]),
        onTap: () => onPick(filtered[i]),
      ),
    );
  }
}
