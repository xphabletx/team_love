// lib/firebase_emulator.dart
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Call this AFTER Firebase.initializeApp() and BEFORE any Firebase usage.
Future<void> connectToFirebaseEmulators() async {
  // Flip this to false if you want to hit prod later, or pass at build time:
  // flutter run --dart-define=USE_FIREBASE_EMULATOR=false
  const useEmu = bool.fromEnvironment(
    'USE_FIREBASE_EMULATOR',
    defaultValue: true,
  );
  if (!useEmu) return;

  final host = kIsWeb
      ? 'localhost'
      : (Platform.isAndroid ? '10.0.2.2' : 'localhost');

  // Auth emulator (default port 9099)
  await FirebaseAuth.instance.useAuthEmulator(host, 9099);

  // Firestore emulator (default port 8080)
  FirebaseFirestore.instance.useFirestoreEmulator(host, 8080);

  // If you add these later, uncomment:
  // await FirebaseStorage.instance.useStorageEmulator(host, 9199);
  // FirebaseFunctions.instanceFor(region: 'us-central1').useFunctionsEmulator(host, 5001);
}
