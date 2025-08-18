import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/username_service.dart';

class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  final newUsernameCtrl = TextEditingController();
  bool busy = false;
  String? message;

  @override
  void dispose() {
    newUsernameCtrl.dispose();
    super.dispose();
  }

  Future<void> _changeUsername() async {
    final newU = newUsernameCtrl.text.trim();
    if (newU.isEmpty) {
      setState(() => message = 'Enter a username.');
      return;
    }
    setState(() {
      busy = true;
      message = null;
    });
    try {
      final email = FirebaseAuth.instance.currentUser?.email;
      if (email == null) {
        setState(() => message = 'Not signed in.');
        return;
      }
      await UsernameService.instance.claimUsername(
        username: newU,
        email: email,
      );
      setState(() => message = 'Username updated!');
      // TODO: (optional) delete old username mapping if you want a strict single handle
    } on FormatException catch (e) {
      setState(() => message = e.message);
    } on StateError catch (e) {
      setState(() => message = e.message);
    } catch (e) {
      setState(() => message = e.toString());
    } finally {
      setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // TODO: replace with Firestore query for workspace-wide ledger
    final ledger = <_LedgerEntry>[
      // _LedgerEntry(type: 'Deposit', envelope: 'Groceries', amount: 50, when: DateTime.now()),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Account')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Ledger', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (ledger.isEmpty)
            const Text('No transactions yet.')
          else
            ...ledger.map(
              (e) => ListTile(
                leading: Icon(_iconFor(e.type)),
                title: Text('${e.type} • £${e.amount.toStringAsFixed(2)}'),
                subtitle: Text('${e.envelope} — ${e.when}'),
              ),
            ),
          const Divider(height: 32),
          Text(
            'Change username',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: newUsernameCtrl,
            decoration: const InputDecoration(
              labelText: 'New username',
              helperText: 'a–z, 0–9, . _ - (3–20 chars)',
            ),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: busy ? null : _changeUsername,
            child: const Text('Update'),
          ),
          if (message != null) ...[
            const SizedBox(height: 8),
            Text(
              message!,
              style: TextStyle(color: Theme.of(context).colorScheme.primary),
            ),
          ],
        ],
      ),
    );
  }

  IconData _iconFor(String type) {
    switch (type) {
      case 'Deposit':
        return Icons.add_circle_outline;
      case 'Withdraw':
        return Icons.remove_circle_outline;
      case 'Transfer':
        return Icons.swap_horiz;
    }
    return Icons.receipt_long;
  }
}

class _LedgerEntry {
  _LedgerEntry({
    required this.type,
    required this.envelope,
    required this.amount,
    required this.when,
  });
  final String type; // Deposit | Withdraw | Transfer
  final String envelope;
  final double amount;
  final DateTime when;
}
