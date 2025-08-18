import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

// Go directly to the concrete screens, not HomeTabs
import '../screens/budget_screen.dart';
import '../screens/calendar_screen.dart';
import '../screens/meals_screen.dart';
import '../screens/shopping_screen.dart';
import '../screens/workspace_setup_screen.dart';
import '../screens/account_screen.dart';
import '../screens/help_screen.dart';

class SideNavDrawer extends StatelessWidget {
  const SideNavDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return Drawer(
      child: SafeArea(
        child: uid == null
            ? const _HeaderAndList(username: 'there')
            : StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance
                    .collection('users')
                    .doc(uid)
                    .snapshots(),
                builder: (context, snap) {
                  final data = snap.data?.data();
                  final uname =
                      (data?['username'] as String?) ??
                      (FirebaseAuth.instance.currentUser?.email ?? 'there');
                  return _HeaderAndList(username: uname);
                },
              ),
      ),
    );
  }
}

class _HeaderAndList extends StatelessWidget {
  final String username;
  const _HeaderAndList({required this.username});

  void _go(BuildContext context, Widget screen) {
    // Close the drawer, then replace the current page with the target screen.
    Navigator.pop(context);
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => screen),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        DrawerHeader(
          child: Align(
            alignment: Alignment.bottomLeft,
            child: Text(
              'Hi $username',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.account_balance_wallet_outlined),
          title: const Text('Budget'),
          onTap: () => _go(context, const BudgetScreen()),
        ),
        ListTile(
          leading: const Icon(Icons.calendar_month_outlined),
          title: const Text('Calendar'),
          onTap: () => _go(context, const CalendarScreen()),
        ),
        ListTile(
          leading: const Icon(Icons.restaurant_menu_outlined),
          title: const Text('Meals'),
          onTap: () => _go(context, const MealsScreen()),
        ),
        ListTile(
          leading: const Icon(Icons.shopping_cart_outlined),
          title: const Text('Shopping'),
          onTap: () => _go(context, const ShoppingScreen()),
        ),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.group_work_outlined),
          title: const Text('Workspace'),
          onTap: () => _go(context, const WorkspaceSetupScreen()),
        ),
        ListTile(
          leading: const Icon(Icons.person_outline),
          title: const Text('Account'),
          onTap: () => _go(context, const AccountScreen()),
        ),
        ListTile(
          leading: const Icon(Icons.help_outline),
          title: const Text('Help'),
          onTap: () => _go(context, const HelpScreen()),
        ),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.logout),
          title: const Text('Logout'),
          onTap: () async {
            await FirebaseAuth.instance.signOut();
            if (context.mounted) {
              Navigator.pop(context); // close drawer
              // You likely have an AuthGate at app root; after signOut it will redirect.
            }
          },
        ),
      ],
    );
  }
}
