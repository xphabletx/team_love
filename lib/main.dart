// lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'
    show kDebugMode, defaultTargetPlatform, TargetPlatform;

import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'firebase_options.dart';
import 'screens/auth_gate.dart';

Future<void> _configureFirebaseEmulatorsIfNeeded() async {
  // Only use emulators in debug mode.
  if (!kDebugMode) return;

  // Android emulators can't hit localhost directly.
  final isAndroidEmu = defaultTargetPlatform == TargetPlatform.android;
  final host = isAndroidEmu ? '10.0.2.2' : 'localhost';

  // IMPORTANT: configure emulators right after initializeApp and
  // before any Firestore/Auth reads.
  FirebaseFirestore.instance.useFirestoreEmulator(host, 8080);

  // DO NOT await here — useAuthEmulator returns void in recent FlutterFire
  FirebaseAuth.instance.useAuthEmulator(host, 9099);

  // Optional: if you add Storage later
  // FirebaseStorage.instance.useStorageEmulator(host, 9199);

  // Helpful log in debug
  // ignore: avoid_print
  print('[Firebase] Using local emulators at $host (fs:8080, auth:9099)');
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Correct function call (old snippet said connectToFirebaseEmulators)
  await _configureFirebaseEmulatorsIfNeeded();

  runApp(const TeamLoveApp());
}

class TeamLoveApp extends StatelessWidget {
  const TeamLoveApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Team Love',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF4A5CFF),
        useMaterial3: true,
      ),
      home: const AuthGate(),
    );
  }
}
