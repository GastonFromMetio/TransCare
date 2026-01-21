import 'package:flutter/material.dart';

import 'screens/auth_landing_page.dart';
import 'screens/login_page.dart';
import 'screens/prescription_home_page.dart';
import 'screens/profile_page.dart';
import 'screens/signup_page.dart';

class PrescriptionNormalizerApp extends StatelessWidget {
  const PrescriptionNormalizerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TransCare',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
        textTheme: Theme.of(context).textTheme.apply(fontSizeFactor: 1.02),
      ),
      initialRoute: '/auth',
      routes: {
        '/auth': (_) => const AuthLandingPage(),
        '/login': (_) => const LoginPage(),
        '/signup': (_) => const SignupPage(),
        '/home': (_) => const PrescriptionHomePage(),
        '/profile': (_) => const ProfilePage(),
      },
    );
  }
}
