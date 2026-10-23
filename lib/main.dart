import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'auth_service.dart';
import 'firestore_service.dart';
import 'login_screen.dart';
import 'splash_screen.dart';
import './services/notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

  // Keep a full offline copy of the data on the phone.
  FirestoreService.configure();

  // Initialize notification plugin (permission is requested after the first frame)
  await NotificationService.init();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Tea Picker App',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
      ),
      home: AuthWrapper(),
    );
  }
}

class AuthWrapper extends StatelessWidget {
  final AuthService _authService = AuthService();

  AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: _authService.authStateChanges,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasData) {
          return const SplashScreen(); // Navigates to MainScreen
        } else {
          return LoginScreen();
        }
      },
    );
  }
}
