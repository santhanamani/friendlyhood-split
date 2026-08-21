import 'package:flutter/material.dart';

/// BroSplit's shared light-mode design tokens.
///
/// Dark-mode colors remain owned by the existing dark theme and dark widget
/// branches. Screens should use these values only when the active brightness
/// is light.
abstract final class AppColors {
  static const background = Color(0xFFF7F8FC);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceSoft = Color(0xFFF9F8FF);
  static const inputBackground = Color(0xFFF3F4F8);

  static const border = Color(0xFFE4E6EF);
  static const divider = Color(0xFFE6E7ED);

  static const textPrimary = Color(0xFF181A24);
  static const textSecondary = Color(0xFF4F5363);
  static const textMuted = Color(0xFF858A9A);
  static const textDisabled = Color(0xFFB6BAC6);

  static const primary = Color(0xFF5B4BE8);
  static const primaryDark = Color(0xFF4638C8);
  static const primaryLight = Color(0xFFEFEDFF);
  static const primaryTint = Color(0xFFF6F4FF);
  static const primaryBorder = Color(0xFFDDD8FF);

  static const success = Color(0xFF21A875);
  static const successBackground = Color(0xFFE9F8F2);
  static const successMint = Color(0xFF36B996);

  static const expense = Color(0xFFF0645A);
  static const expenseBackground = Color(0xFFFFF0EE);

  static const warning = Color(0xFFF59A3D);
  static const warningBackground = Color(0xFFFFF4E8);
}
