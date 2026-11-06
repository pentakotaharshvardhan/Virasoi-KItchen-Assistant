import 'package:flutter/material.dart';

/// Dark, warm, "kitchen at night" palette — charcoal surfaces with a
/// saffron/amber accent (evokes spice & flame) and a teal secondary accent
/// for freshness (herbs). Chosen for high contrast + AA-friendly text.
class AppColors {
  AppColors._();

  static const Color background = Color(0xFF0F1115);
  static const Color surface = Color(0xFF181B21);
  static const Color surfaceElevated = Color(0xFF20242C);
  static const Color surfaceCard = Color(0xFF1D212A);

  static const Color primary = Color(0xFFFF9F45);   // saffron amber
  static const Color primaryDark = Color(0xFFE07B2A);
  static const Color secondary = Color(0xFF3FD6B0);  // fresh teal
  static const Color tertiary = Color(0xFFFF6B6B);   // chili red (errors / spicy tags)

  static const Color textPrimary = Color(0xFFF3F1EC);
  static const Color textSecondary = Color(0xFFA6ACB8);
  static const Color textMuted = Color(0xFF6C7280);

  static const Color divider = Color(0xFF2A2E37);
  static const Color success = Color(0xFF4CD988);
  static const Color warning = Color(0xFFFFC24B);
  static const Color error = Color(0xFFFF5D5D);

  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFFF9F45), Color(0xFFFF6B6B)],
  );

  static const LinearGradient heroGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF20242C), Color(0xFF0F1115)],
  );

  static const RadialGradient voiceListeningGlow = RadialGradient(
    colors: [Color(0x553FD6B0), Color(0x00000000)],
  );

  static const RadialGradient voiceSpeakingGlow = RadialGradient(
    colors: [Color(0x55FF9F45), Color(0x00000000)],
  );
}
