// lib/main.dart
import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';

import 'screens/splash_screen.dart';
import 'services/workspace_session.dart';

// Messaging is optional; we guard every call.
import 'package:firebase_messaging/firebase_messaging.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase core first.
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // ⚠️ Never let FCM initialization delay app launch.
  unawaited(_initFcmSafely());

  // Start any app session logic (non-blocking).
  WorkspaceSession.instance.start();

  runApp(const TeamLoveApp());
}

class TeamLoveApp extends StatelessWidget {
  const TeamLoveApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Team Love',
      themeMode: ThemeMode.system,
      theme: ThemeData(useMaterial3: true, brightness: Brightness.light),
      darkTheme: ThemeData(useMaterial3: true, brightness: Brightness.dark),
      home: const SplashScreen(),
    );
  }
}

/// Initializes Firebase Messaging in a way that *cannot* block UI.
/// This is extra tolerant of emulators / flaky Play Services.
Future<void> _initFcmSafely() async {
  try {
    final messaging = FirebaseMessaging.instance;

    // On emulators / CI, auto-init can trigger token/network errors.
    // Turning it off stops background fetches from throwing noise.
    try {
      await messaging.setAutoInitEnabled(false);
    } catch (_) {}

    // On Android we don't need notification permission; on iOS/macOS we do.
    if (!kIsWeb && (Platform.isIOS || Platform.isMacOS)) {
      try {
        final settings = await messaging
            .requestPermission(alert: true, badge: true, sound: true)
            .timeout(const Duration(seconds: 2));
        debugPrint('🔔 FCM auth status: ${settings.authorizationStatus}');
      } on TimeoutException {
        debugPrint('🔔 FCM permission request timed out (ignored).');
      } catch (e) {
        debugPrint('🔔 FCM permission request failed (ignored): $e');
      }
    } else {
      debugPrint(
        '🔔 FCM: permission request skipped on ${Platform.operatingSystem}.',
      );
    }

    // Foreground presentation (no-op on Android; harmless elsewhere).
    try {
      await messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );
    } catch (_) {}

    // Try for a token, but bail quickly if Installations/Play Services are unhappy.
    try {
      final token = await messaging.getToken().timeout(
        const Duration(seconds: 2),
      );
      if (token != null) {
        debugPrint('🔑 FCM token: $token');
      } else {
        debugPrint('🔑 FCM token: null (ignored)');
      }
    } on TimeoutException {
      debugPrint('⚠️ FCM getToken timed out (ignored).');
    } catch (e) {
      debugPrint('⚠️ FCM getToken failed (ignored): $e');
    }

    // Non-fatal listeners
    FirebaseMessaging.onMessage.listen((m) {
      debugPrint('📩 FG message: ${m.messageId} "${m.notification?.title}"');
    });
    FirebaseMessaging.onMessageOpenedApp.listen((m) {
      debugPrint('🚪 Notification opened app: ${m.messageId}');
    });
  } catch (e) {
    // Absolutely never let this bubble to the UI thread.
    debugPrint('⚠️ FCM init failed (ignored): $e');
  }
}
