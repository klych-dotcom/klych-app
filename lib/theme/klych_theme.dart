import 'package:flutter/material.dart';

/// KLYCH unified design system — operational, minimal, readable.
abstract final class KlychTheme {
  // ── Colors ──────────────────────────────────────────────────────────────

  static const background = Color(0xFF0C0C0E);
  static const surface = Color(0xFF161618);
  static const surfaceElevated = Color(0xFF1E1E22);
  static const border = Color(0xFF2A2A30);
  static const borderSubtle = Color(0xFF222228);

  static const textPrimary = Color(0xFFF2F2F4);
  static const textSecondary = Color(0xFF9A9AA3);
  static const textMuted = Color(0xFF6B6B75);

  static const accent = Color(0xFFE85D4C);
  static const accentMuted = Color(0xFFB8483A);

  static const alertRed = Color(0xFFD64545);
  static const alertRedSoft = Color(0xFF3D2222);
  static const alertGreen = Color(0xFF4CAF7A);
  static const alertGreenSoft = Color(0xFF1E2E24);

  static const statusAvailable = Color(0xFF5CB87A);
  static const statusOnDuty = Color(0xFF5B9BD5);
  static const statusDeployed = Color(0xFFD4A054);
  static const statusVacation = Color(0xFF8E8E96);
  static const statusUnavailable = Color(0xFFBF6B6B);

  static const roleAdmin = Color(0xFFE85D4C);
  static const roleLeader = Color(0xFFD4A054);
  static const roleMember = Color(0xFF9A9AA3);

  static const online = Color(0xFF5CB87A);
  static const offline = Color(0xFFBF6B6B);

  // ── Spacing ─────────────────────────────────────────────────────────────

  static const spaceXs = 4.0;
  static const spaceSm = 8.0;
  static const spaceMd = 12.0;
  static const spaceLg = 16.0;
  static const spaceXl = 20.0;
  static const space2xl = 24.0;
  static const space3xl = 32.0;

  // ── Radius ──────────────────────────────────────────────────────────────

  static const radiusSm = 10.0;
  static const radiusMd = 14.0;
  static const radiusLg = 18.0;
  static const radiusXl = 22.0;

  // ── Typography ──────────────────────────────────────────────────────────

  static const displayLarge = TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.w700,
    color: textPrimary,
    letterSpacing: -0.5,
  );

  static const titleLarge = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w700,
    color: textPrimary,
    letterSpacing: -0.3,
  );

  static const titleMedium = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: textPrimary,
  );

  static const bodyLarge = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w400,
    color: textPrimary,
    height: 1.4,
  );

  static const bodyMedium = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w400,
    color: textSecondary,
    height: 1.35,
  );

  static const labelSmall = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w600,
    color: textMuted,
    letterSpacing: 0.8,
  );

  static const labelCaps = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w600,
    color: textSecondary,
    letterSpacing: 1.2,
  );

  // ── Status colors ───────────────────────────────────────────────────────

  static Color statusColor(String status) {
    switch (status) {
      case 'on_duty':
        return statusOnDuty;
      case 'deployed':
        return statusDeployed;
      case 'vacation':
        return statusVacation;
      case 'unavailable':
        return statusUnavailable;
      default:
        return statusAvailable;
    }
  }

  static Color roleColor(String role) {
    switch (role) {
      case 'admin':
        return roleAdmin;
      case 'leader':
        return roleLeader;
      default:
        return roleMember;
    }
  }

  // ── ThemeData ───────────────────────────────────────────────────────────

  static ThemeData build() {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: background,
      colorScheme: const ColorScheme.dark(
        surface: surface,
        primary: accent,
        secondary: statusOnDuty,
        error: alertRed,
        onSurface: textPrimary,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: background,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: IconThemeData(color: textSecondary),
        titleTextStyle: titleMedium,
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          side: const BorderSide(color: borderSubtle),
        ),
        margin: EdgeInsets.zero,
      ),
      dividerColor: borderSubtle,
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        hintStyle: bodyMedium.copyWith(color: textMuted),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: spaceLg,
          vertical: spaceMd,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: const BorderSide(color: borderSubtle),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: const BorderSide(color: accent, width: 1.5),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(
            horizontal: spaceXl,
            vertical: spaceMd,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusMd),
          ),
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.3,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(
            horizontal: spaceXl,
            vertical: spaceMd,
          ),
          side: const BorderSide(color: border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusMd),
          ),
          foregroundColor: textSecondary,
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: surfaceElevated,
        contentTextStyle: bodyMedium.copyWith(color: textPrimary),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusSm),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surfaceElevated,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusLg),
        ),
        titleTextStyle: titleMedium,
        contentTextStyle: bodyMedium.copyWith(color: textSecondary),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: accent,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surface,
        selectedColor: accent.withValues(alpha: 0.2),
        disabledColor: surface,
        labelStyle: bodyMedium,
        side: const BorderSide(color: borderSubtle),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusSm),
        ),
        padding: const EdgeInsets.symmetric(horizontal: spaceSm),
      ),
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(
          horizontal: spaceLg,
          vertical: spaceXs,
        ),
        dense: true,
        visualDensity: VisualDensity.compact,
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
        },
      ),
    );
  }
}
