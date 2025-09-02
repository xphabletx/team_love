import 'dart:async';
import 'package:flutter/material.dart';
import 'auth_gate.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    Timer(const Duration(milliseconds: 1200), () {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => const AuthGate(),
          transitionDuration: const Duration(milliseconds: 250),
          transitionsBuilder: (_, a, __, child) =>
              FadeTransition(opacity: a, child: child),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    // Same paper color you used in the image
    const bg = Color(0xFFF5F0E6);
    return Scaffold(
      backgroundColor: bg,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(16), // small safe margin
          child: AspectRatio(
            aspectRatio: 1, // your PNG is square
            child: Image.asset(
              'assets/splash/team_love_splash.png',
              fit: BoxFit.contain, // show entire poster; no cropping
            ),
          ),
        ),
      ),
    );
  }
}
