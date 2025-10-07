// import 'package:flutter/material.dart';
// import 'auth_service.dart';
// import 'home_screen.dart';
// import 'package:firebase_auth/firebase_auth.dart';
//
// class LoginScreen extends StatelessWidget {
//   final AuthService _authService = AuthService();
//
//   LoginScreen({super.key});
//
//   Future<void> _signIn(BuildContext context) async {
//     User? user = await _authService.signInWithGoogle();
//     if (user != null) {
//       Navigator.pushReplacement(
//         context,
//         MaterialPageRoute(builder: (context) => HomeScreen()),
//       );
//     } else {
//       ScaffoldMessenger.of(context).showSnackBar(
//         const SnackBar(content: Text('Sign-in failed. Try again.')),
//       );
//     }
//   }
//
//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(title: const Text('Login')),
//       body: Center(
//         child: ElevatedButton(
//           onPressed: () => _signIn(context),
//           child: const Text('Sign in with Google'),
//         ),
//       ),
//     );
//   }
// }


import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'auth_service.dart';
import 'main_screen.dart'; // Update to MainScreen

class LoginScreen extends StatelessWidget {
  final AuthService _authService = AuthService();

  LoginScreen({super.key});

  Future<void> _signIn(BuildContext context) async {
    User? user = await _authService.signInWithGoogle();
    if (user != null) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) =>  MainScreen()), // Navigate to MainScreen
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sign-in failed. Try again.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Login')),
      body: Center(
        child: ElevatedButton(
          onPressed: () => _signIn(context),
          child: const Text('Sign in with Google'),
        ),
      ),
    );
  }
}