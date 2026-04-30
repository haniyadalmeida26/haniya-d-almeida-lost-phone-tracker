import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

import 'device_service.dart';
import 'firebase_options.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/lost_mode_screen.dart';
import 'ui_common.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  await DeviceService().handleRemoteCommandMessage(message.data);
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  runApp(const LostPhoneTrackerApp());
}

class LostPhoneTrackerApp extends StatelessWidget {
  const LostPhoneTrackerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Lost Phone Tracker',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppPalette.primary,
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: AppPalette.background,
        cardColor: AppPalette.surface,
        dividerColor: AppPalette.border,
        textTheme: ThemeData.light().textTheme.apply(
              bodyColor: AppPalette.text,
              displayColor: AppPalette.text,
            ),
        appBarTheme: const AppBarTheme(
          elevation: 0,
          backgroundColor: Colors.transparent,
          foregroundColor: AppPalette.text,
          surfaceTintColor: Colors.transparent,
        ),
        useMaterial3: true,
      ),
      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const LoadingScaffold();
          }

          if (snapshot.hasData) {
            return const AppShell();
          }

          return const LoginScreen();
        },
      ),
    );
  }
}

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  final DeviceService _deviceService = DeviceService();
  late final Future<String?> _deviceFuture;

  @override
  void initState() {
    super.initState();
    _deviceFuture = _prepareDevice();
  }

  Future<String?> _prepareDevice() async {
    await _deviceService.initializeCurrentDevice();
    return _deviceService.getCurrentTrackedDeviceIdOrNull();
  }

  @override
  Widget build(BuildContext context) {
    if (!_deviceService.isTrackablePhone) {
      return const HomeScreen();
    }

    return FutureBuilder<String?>(
      future: _deviceFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const LoadingScaffold();
        }

        final deviceId = snapshot.data;
        if (deviceId == null) {
          return const HomeScreen();
        }

        final deviceStream = FirebaseFirestore.instance
            .collection('devices')
            .doc(deviceId)
            .snapshots();

        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: deviceStream,
          builder: (context, deviceSnapshot) {
            if (!deviceSnapshot.hasData) {
              return const LoadingScaffold();
            }

            final data = deviceSnapshot.data?.data() ?? <String, dynamic>{};
            final status = Map<String, dynamic>.from(data['status'] ?? {});
            final isLost = status['isLost'] == true;

            if (isLost) {
              return LostModeScreen(
                deviceId: deviceId,
                deviceStream: deviceStream,
              );
            }

            return const HomeScreen();
          },
        );
      },
    );
  }
}
