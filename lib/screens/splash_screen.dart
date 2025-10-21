import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'auth_gate.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  static const _bg = Color(0xFFF5F0E6); // match native splash color
  late final AnimationController _fade;

  @override
  void initState() {
    super.initState();

    // Make status/nav bars blend into the splash
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: _bg,
        statusBarIconBrightness: Brightness.dark,
        systemNavigationBarColor: _bg,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
    );

    _fade = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
      value: 1.0, // start fully visible
    );

    // Preload the image to avoid a 1-frame pop-in
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await precacheImage(
        const AssetImage('assets/splash/team_love_splash.png'),
        context,
      );
      // Short hold so the artwork is seen, then fade out and navigate
      Timer(const Duration(milliseconds: 900), _go);
    });
  }

  void _go() {
    if (!mounted) return;
    _fade.reverse().whenComplete(() {
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
  void dispose() {
    _fade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: FadeTransition(
        opacity: _fade,
        child: Stack(
          fit: StackFit.expand,
          children: const [
            // Full-bleed artwork
            _SplashImage(),
          ],
        ),
      ),
    );
  }
}

class _SplashImage extends StatelessWidget {
  const _SplashImage();

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/splash/team_love_splash.png',
      fit: BoxFit.cover, // <-- full-screen cover
      alignment: Alignment.center,
    );
  }
}
