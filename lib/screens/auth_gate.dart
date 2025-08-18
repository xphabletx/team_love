import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/workspace_service.dart';
import 'sign_in_screen.dart';
import 'team_love_screen.dart'; // landing page

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  static const int reauthDays = 90;

  Future<bool> _isRecentLogin(User user) async {
    await user.reload();
    final refreshed = FirebaseAuth.instance.currentUser!;
    final last = refreshed.metadata.lastSignInTime;
    if (last == null) return false;
    final diff = DateTime.now().difference(last).inDays;
    return diff < reauthDays;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, authSnap) {
        final user = authSnap.data;
        if (user == null) return const SignInScreen();

        // Enforce 90-day reauth
        return FutureBuilder<bool>(
          future: _isRecentLogin(user),
          builder: (context, recentSnap) {
            if (recentSnap.connectionState != ConnectionState.done) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }
            final recent = recentSnap.data ?? false;
            if (!recent) {
              FirebaseAuth.instance.signOut();
              return const SignInScreen();
            }

            // Ensure profile exists (but don't block on workspace)
            return FutureBuilder<String?>(
              future: WorkspaceService.instance.ensureProfileAndGetWorkspaceId(
                user,
              ),
              builder: (context, _) {
                // Regardless of workspace, land on the app home screen
                return const TeamLoveScreen();
              },
            );
          },
        );
      },
    );
  }
}
