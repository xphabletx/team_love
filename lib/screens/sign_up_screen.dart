import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final username = TextEditingController();
  final email = TextEditingController();
  final password = TextEditingController();

  String? error;
  bool busy = false;

  Future<void> _handleSignUp() async {
    setState(() {
      busy = true;
      error = null;
    });

    try {
      // Create user in FirebaseAuth
      final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email.text.trim(),
        password: password.text.trim(),
      );

      // Save username into Firestore
      await FirebaseFirestore.instance
          .collection('users')
          .doc(cred.user!.uid)
          .set({
            'username': username.text.trim(),
            'email': email.text.trim(),
            'createdAt': FieldValue.serverTimestamp(),
          });

      if (!mounted) return;
      Navigator.pop(context);
    } on FirebaseAuthException catch (e) {
      setState(() {
        error = e.message;
      });
    } catch (e) {
      setState(() {
        error = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create Account')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            TextField(
              controller: username,
              decoration: const InputDecoration(
                labelText: 'Username',
                helperText: 'a–z, 0–9, . _ - (3–20 chars)',
              ),
              textInputAction: TextInputAction.next,
            ),
            TextField(
              controller: email,
              decoration: const InputDecoration(labelText: 'Email'),
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
            ),
            TextField(
              controller: password,
              decoration: const InputDecoration(
                labelText: 'Password (6+ chars)',
              ),
              obscureText: true,
              onSubmitted: (_) => _handleSignUp(),
            ),
            const SizedBox(height: 12),

            // ✅ FIX: use spread list operator here
            if (error != null) ...[
              Text(error!, style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 12),
            ],

            FilledButton(
              onPressed: busy ? null : _handleSignUp,
              child: busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Sign Up'),
            ),
          ],
        ),
      ),
    );
  }
}
