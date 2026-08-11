import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'services/theme_controller.dart';
import 'widgets/app_notice_gate.dart';
import 'widgets/app_update_gate.dart';

class FriendlyhoodSplitApp extends StatelessWidget {
  const FriendlyhoodSplitApp({super.key, required this.themeController});

  final AppThemeController themeController;

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF6C5CE7);
    final lightTheme = ThemeData(
      brightness: Brightness.light,
      colorScheme: ColorScheme.fromSeed(
        seedColor: seed,
        brightness: Brightness.light,
        surface: const Color(0xFFF9F9FD),
      ),
      scaffoldBackgroundColor: const Color(0xFFF3F5FB),
      useMaterial3: true,
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFFF3F5FB),
        foregroundColor: Color(0xFF171824),
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: const CardThemeData(
        color: Color(0xFFFCFBFF),
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(24)),
          side: BorderSide(color: Color(0xFFDDE0EC)),
        ),
      ),
      popupMenuTheme: const PopupMenuThemeData(
        color: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 14,
        shadowColor: Color(0x33000000),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
          side: BorderSide(color: Color(0xFFE0E2EC)),
        ),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
          borderSide: BorderSide(color: Color(0xFFE0E2EC)),
        ),
      ),
      dividerColor: const Color(0xFFE0E2EC),
    );
    final darkTheme = ThemeData(
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: seed,
        brightness: Brightness.dark,
        surface: const Color(0xFF12131A),
      ),
      scaffoldBackgroundColor: const Color(0xFF0B0C12),
      useMaterial3: true,
      cardTheme: const CardThemeData(
        color: Color(0xFF151721),
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(24)),
          side: BorderSide(color: Color(0xFF252836)),
        ),
      ),
      popupMenuTheme: const PopupMenuThemeData(
        color: Color(0xFF2A2840),
        surfaceTintColor: Color(0xFF2A2840),
        elevation: 18,
        shadowColor: Colors.black,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
          side: BorderSide(color: Color(0xFF5B5678)),
        ),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        filled: true,
        fillColor: Color(0xFF171925),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
          borderSide: BorderSide.none,
        ),
      ),
    );
    return AnimatedBuilder(
      animation: themeController,
      builder: (context, _) => MaterialApp(
        title: 'BroSplit',
        debugShowCheckedModeBanner: false,
        themeMode: themeController.themeMode,
        theme: lightTheme,
        darkTheme: darkTheme,
        home: AppNoticeGate(
          child: AppUpdateGate(
            child: StreamBuilder<User?>(
              stream: FirebaseAuth.instance.authStateChanges(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Scaffold(
                      body: Center(child: CircularProgressIndicator()));
                }
                return snapshot.data == null
                    ? const LoginScreen()
                    : HomeScreen(
                        user: snapshot.data!,
                        themeController: themeController,
                      );
              },
            ),
          ),
        ),
      ),
    );
  }
}
