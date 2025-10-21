// lib/screens/auth_gate.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../services/workspace_session.dart';
import 'team_love_screen.dart';
import 'sign_in_screen.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const _BootSplash();
        }

        final user = snap.data;
        if (user == null) {
          // Not signed in → normal Sign In screen
          return const SignInScreen();
        }

        // Signed in → start workspace session for other screens that want context
        WorkspaceSession.instance.start();

        // Route to the main shell (Team Love)
        return const TeamLoveScreen();
      },
    );
  }
}

class _BootSplash extends StatelessWidget {
  const _BootSplash();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}
