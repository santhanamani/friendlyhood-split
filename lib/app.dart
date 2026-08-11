import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'widgets/app_update_gate.dart';

class FriendlyhoodSplitApp extends StatelessWidget {
  const FriendlyhoodSplitApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF6C5CE7);
    return MaterialApp(
      title: 'friendlyhood-split',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData(
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
        inputDecorationTheme: const InputDecorationTheme(
          filled: true,
          fillColor: Color(0xFF171925),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(16)),
            borderSide: BorderSide.none,
          ),
        ),
      ),
      home: AppUpdateGate(
        child: StreamBuilder<User?>(
          stream: FirebaseAuth.instance.authStateChanges(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(body: Center(child: CircularProgressIndicator()));
            }
            return snapshot.data == null
                ? const LoginScreen()
                : HomeScreen(user: snapshot.data!);
          },
        ),
      ),
    );
  }
}
