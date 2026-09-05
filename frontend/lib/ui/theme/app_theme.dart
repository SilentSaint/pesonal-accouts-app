import 'package:flutter/material.dart';

/// Centralized Design System Tokens & Theme
class AppColors {
  // Canvas & Surfaces
  static const Color background = Color(0xFF07131D);
  static const Color surface = Color(0xFF0D1E2A);
  static const Color surfaceElevated = Color(0xFF132A38);
  static const Color surfaceSubtle = Color(0xFF193545);
  static const Color border = Color(0xFF254453);
  static const Color borderSubtle = Color(0x1AFFFFFF);

  // Semantic Accents
  static const Color primary = Color(0xFF0EA5C9); // Ledger cyan
  static const Color primaryLight = Color(0xFF62D6F4);
  static const Color primaryDark = Color(0xFF087D9B);

  static const Color success = Color(0xFF19A974); // Reconciled mint
  static const Color successLight = Color(0xFF5BE0A8);

  static const Color danger = Color(0xFFF43F5E); // Coral Rose
  static const Color dangerLight = Color(0xFFFB7185);

  static const Color warning = Color(0xFFF59E0B); // Solar Amber
  static const Color warningLight = Color(0xFFFBBF24);

  static const Color info = Color(0xFF0EA5E9); // Sky Blue
  static const Color infoLight = Color(0xFF38BDF8);

  static const Color purple = Color(0xFF8B5CF6);
  static const Color purpleLight = Color(0xFFA78BFA);

  // Text Hierarchy
  static const Color textPrimary = Color(0xFFF2F8FA);
  static const Color textSecondary = Color(0xFFACC2CC);
  static const Color textTertiary = Color(0xFF74939F);
  static const Color textMuted = Color(0xFF53717D);

  // Category Color Map
  static Color getCategoryColor(String category) {
    final lower = category.toLowerCase();
    if (lower.contains('food') ||
        lower.contains('dining') ||
        lower.contains('restaurant')) {
      return const Color(0xFFF59E0B); // Amber
    } else if (lower.contains('shop') ||
        lower.contains('cloth') ||
        lower.contains('electronics')) {
      return const Color(0xFF8B5CF6); // Violet
    } else if (lower.contains('transport') ||
        lower.contains('fuel') ||
        lower.contains('travel') ||
        lower.contains('cab')) {
      return const Color(0xFF0EA5E9); // Sky
    } else if (lower.contains('bill') ||
        lower.contains('utilit') ||
        lower.contains('recharge') ||
        lower.contains('electric')) {
      return const Color(0xFFF43F5E); // Rose
    } else if (lower.contains('grocer') ||
        lower.contains('market') ||
        lower.contains('health') ||
        lower.contains('med')) {
      return const Color(0xFF10B981); // Emerald
    } else if (lower.contains('invest') ||
        lower.contains('salary') ||
        lower.contains('interest')) {
      return const Color(0xFF34D399); // Mint
    } else if (lower.contains('peer') ||
        lower.contains('debt') ||
        lower.contains('loan')) {
      return const Color(0xFFA855F7); // Purple
    } else if (lower.contains('transfer') || lower.contains('self')) {
      return const Color(0xFF06B6D4); // Cyan
    }
    return const Color(0xFF6366F1); // Default Primary
  }

  // Category Icon Map
  static IconData getCategoryIcon(String category) {
    final lower = category.toLowerCase();
    if (lower.contains('food') ||
        lower.contains('dining') ||
        lower.contains('restaurant')) {
      return Icons.restaurant;
    } else if (lower.contains('shop') ||
        lower.contains('cloth') ||
        lower.contains('electronics')) {
      return Icons.shopping_bag_outlined;
    } else if (lower.contains('transport') ||
        lower.contains('fuel') ||
        lower.contains('travel')) {
      return Icons.local_gas_station_outlined;
    } else if (lower.contains('bill') ||
        lower.contains('utilit') ||
        lower.contains('recharge')) {
      return Icons.receipt_long_outlined;
    } else if (lower.contains('grocer') || lower.contains('market')) {
      return Icons.local_grocery_store_outlined;
    } else if (lower.contains('invest') || lower.contains('salary')) {
      return Icons.trending_up;
    } else if (lower.contains('peer') ||
        lower.contains('debt') ||
        lower.contains('loan')) {
      return Icons.handshake_outlined;
    } else if (lower.contains('transfer') || lower.contains('self')) {
      return Icons.swap_horiz_rounded;
    }
    return Icons.credit_card_outlined;
  }
}

class AppTheme {
  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      primaryColor: AppColors.primary,
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.primary,
        onPrimary: Color(0xFF03161D),
        secondary: AppColors.success,
        onSecondary: Color(0xFF031B13),
        surface: AppColors.surface,
        onSurface: AppColors.textPrimary,
        error: AppColors.danger,
      ),
      useMaterial3: true,
      splashFactory: InkSparkle.splashFactory,
      focusColor: AppColors.primaryLight.withValues(alpha: 0.20),
      textTheme: const TextTheme(
        headlineSmall: TextStyle(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.4,
        ),
        titleLarge: TextStyle(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.3,
        ),
        bodyLarge: TextStyle(
          color: AppColors.textPrimary,
          height: 1.5,
        ),
        bodyMedium: TextStyle(
          color: AppColors.textSecondary,
          height: 1.5,
        ),
        labelLarge: TextStyle(
          fontWeight: FontWeight.w700,
          letterSpacing: 0.1,
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.border, width: 1),
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AppColors.border, width: 1),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textPrimary,
          side: const BorderSide(color: AppColors.border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceElevated,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
        labelStyle:
            const TextStyle(color: AppColors.textSecondary, fontSize: 13),
        hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 13),
      ),
    );
  }
}
