import 'package:flutter/material.dart';

class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final faqs = [
      _Faq(
        q: 'How do I add envelopes?',
        a: 'Tap the + button on the Budget screen, then choose “Create new envelope”.',
      ),
      _Faq(
        q: 'How do I jump to envelopes by letter?',
        a: 'Use the A–Z rail on the right. Tapping a bucket (e.g., MNO) scrolls to the first envelope in that range.',
      ),
      _Faq(
        q: 'What happens on long-press?',
        a: 'Long-press an envelope to Deposit, Withdraw, Transfer, Edit Target, Rename, or Delete.',
      ),
      _Faq(
        q: 'Can I see my partner’s envelopes?',
        a: 'Yes. Partner envelopes are visible but greyed out and cannot be edited. You can still Transfer to them.',
      ),
      _Faq(
        q: 'How do meals add items to shopping?',
        a: 'On a day, add ingredients. These will populate the Shopping list automatically (coming soon).',
      ),
      _Faq(
        q: 'How do I create or join a workspace?',
        a: 'Go to Workspace. Create a workspace to get a join code, or paste a code to join your partner’s.',
      ),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Help & FAQ')),
      body: ListView(
        children: [
          for (final f in faqs)
            ExpansionTile(
              title: Text(f.q),
              children: [
                Padding(padding: const EdgeInsets.all(16), child: Text(f.a)),
              ],
            ),
        ],
      ),
    );
  }
}

class _Faq {
  _Faq({required this.q, required this.a});
  final String q;
  final String a;
}
