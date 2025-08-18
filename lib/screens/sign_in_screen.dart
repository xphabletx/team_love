import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/username_service.dart';
import 'sign_up_screen.dart';

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final identifier = TextEditingController(); // username OR email
  final password = TextEditingController();
  bool busy = false;
  String? error;

  @override
  void dispose() {
    identifier.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> _handleSignIn() async {
    if (!mounted) return;

    setState(() {
      busy = true;
      error = null;
    });

    try {
      final email = await UsernameService.instance.resolveEmailFromIdentifier(
        identifier.text.trim(),
      );

      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password.text,
      );

      if (!mounted) return;
      // Navigation after sign-in (example)
      // Navigator.pushReplacementNamed(context, '/team_love');
    } on StateError catch (e) {
      if (mounted) {
        setState(() => error = e.message);
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        setState(() => error = e.message ?? e.code);
      }
    } catch (e) {
      if (mounted) {
        setState(() => error = e.toString());
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  Future<void> _forgotPassword() async {
    final id = identifier.text.trim();
    if (id.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter your username or email first.')),
      );
      return;
    }

    try {
      final email = await UsernameService.instance.resolveEmailFromIdentifier(
        id,
      );

      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Password reset email sent to $email')),
      );
    } on StateError catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message ?? e.code)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sign In')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: identifier,
              decoration: const InputDecoration(
                labelText: 'Username or Email',
                helperText: 'You can sign in with either one',
              ),
              textInputAction: TextInputAction.next,
            ),
            TextField(
              controller: password,
              decoration: const InputDecoration(labelText: 'Password'),
              obscureText: true,
              onSubmitted: (_) => _handleSignIn(),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: busy ? null : _forgotPassword,
                child: const Text('Forgot password?'),
              ),
            ),
            if (error != null)
              Text(error!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: busy ? null : _handleSignIn,
              child: const Text('Sign In'),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: busy
                  ? null
                  : () {
                      if (!mounted) return;
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const SignUpScreen()),
                      );
                    },
              child: const Text('Create an account'),
            ),
          ],
        ),
      ),
    );
  }
}
