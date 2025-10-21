import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'budget_screen.dart';
import 'calendar_screen.dart';
import 'meals_screen.dart';
import 'shopping_screen.dart';
import 'workspace_setup_screen.dart';
import 'account_screen.dart';
import 'help_screen.dart';

// 🔽 Add this import for the Recipes list screen
import 'recipes_list_screen.dart'; // contains `RecipesListScreen`

class TeamLoveScreen extends StatelessWidget {
  const TeamLoveScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return Scaffold(
      appBar: AppBar(title: const Text('Team Love')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: uid == null
              ? _buildGrid(context, username: 'there')
              : StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                  stream: FirebaseFirestore.instance
                      .collection('users')
                      .doc(uid)
                      .snapshots(),
                  builder: (context, snap) {
                    final data = snap.data?.data();
                    final uname =
                        (data?['username'] as String?) ??
                        FirebaseAuth.instance.currentUser?.email ??
                        'there';
                    return _buildGrid(context, username: uname);
                  },
                ),
        ),
      ),
    );
  }

  Widget _buildGrid(BuildContext context, {required String username}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Hi $username 👋',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 12),
        Expanded(
          child: GridView.count(
            crossAxisCount: 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            children: [
              _NavCard(
                icon: Icons.account_balance_wallet_outlined,
                label: 'Money',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const BudgetScreen()),
                ),
              ),
              _NavCard(
                icon: Icons.calendar_month_outlined,
                label: 'Calendar',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const CalendarScreen()),
                ),
              ),
              _NavCard(
                icon: Icons.restaurant_menu_outlined,
                label: 'Meals',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const MealsScreen()),
                ),
              ),
              _NavCard(
                icon: Icons.shopping_cart_outlined,
                label: 'Shopping',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ShoppingScreen()),
                ),
              ),

              // ✅ New Recipes tile
              _NavCard(
                icon: Icons.menu_book_outlined,
                label: 'Recipes',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const RecipesListScreen()),
                ),
              ),

              _NavCard(
                icon: Icons.group_work_outlined,
                label: 'Workspace',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const WorkspaceSetupScreen(),
                  ),
                ),
              ),
              _NavCard(
                icon: Icons.person_outline,
                label: 'Account',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AccountScreen()),
                ),
              ),
              _NavCard(
                icon: Icons.help_outline,
                label: 'Help',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const HelpScreen()),
                ),
              ),
              _NavCard(
                icon: Icons.logout,
                label: 'Logout',
                onTap: () async {
                  await FirebaseAuth.instance.signOut();
                  if (context.mounted) Navigator.pop(context);
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _NavCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _NavCard({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 40),
              const SizedBox(height: 8),
              Text(label),
            ],
          ),
        ),
      ),
    );
  }
}
