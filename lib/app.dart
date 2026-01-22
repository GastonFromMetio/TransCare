import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'screens/auth_landing_page.dart';
import 'screens/login_page.dart';
import 'screens/transcare_shell_page.dart';
import 'screens/profile_page.dart';
import 'screens/signup_page.dart';

class TranscareApp extends StatelessWidget {
  const TranscareApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seedColor = Color(0xFF5B6EA5);
    const surfaceColor = Color(0xFFF7F7FB);
    final colorScheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: Brightness.light,
      surface: surfaceColor,
      background: surfaceColor,
    ).copyWith(
      primary: const Color(0xFF5B6EA5),
      secondary: const Color(0xFF6FB9BE),
      onPrimary: Colors.white,
      onSecondary: Colors.white,
      surfaceContainerHighest: const Color(0xFFF0F1F7),
    );
    final baseTextTheme = ThemeData.light().textTheme;
    final textTheme = GoogleFonts.manropeTextTheme(baseTextTheme).apply(
      bodyColor: colorScheme.onSurface,
      displayColor: colorScheme.onSurface,
    );

    return MaterialApp(
      title: 'TransCare',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: colorScheme,
        useMaterial3: true,
        scaffoldBackgroundColor: surfaceColor,
        textTheme: textTheme,
        appBarTheme: AppBarTheme(
          centerTitle: true,
          elevation: 0,
          backgroundColor: Colors.transparent,
          foregroundColor: colorScheme.onSurface,
          titleTextStyle: textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
            textStyle: textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
            textStyle: textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(
              color: colorScheme.primary.withOpacity(0.4),
              width: 1.2,
            ),
          ),
        ),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
      ),
      initialRoute: '/auth',
      routes: {
        '/auth': (_) => const AuthLandingPage(),
        '/login': (_) => const LoginPage(),
        '/signup': (_) => const SignupPage(),
        '/home': (_) => const TranscareShellPage(),
        '/profile': (_) => const ProfilePage(),
      },
    );
  }
}
