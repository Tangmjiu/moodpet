/// MoodPet app shell + Material Design 3 Expressive theme.
///
/// Design language: **Claymorphism** — soft 3D, chunky, playful, rounded
/// corners (24–32px), layered soft shadows, spring-based motion. The palette
/// is a warm sand/peach seed (#E8A87C) that feels emotional and non-techy,
/// paired with a sage-teal secondary for calm trust. The active Friend's mood
/// colour is layered dynamically on the home screen for ambient personalisation.
library;

import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

import 'features/market/market_page.dart';
import 'features/market/pack_detail_page.dart';
import 'features/market/plugin_detail_page.dart';
import 'features/plugins/plugin_management_page.dart';
import 'features/settings/settings_page.dart';
import 'features/splash_page.dart';

const String kAppName = 'MoodPet';

/// Pet palette seed: warm sand / peach — avoids tech-feel purple-blue.
const Color kMoodPetSeed = Color(0xFFE8A87C);

/// Secondary accent: sage-teal for trust/calm surfaces.
const Color kMoodPetSecondary = Color(0xFF7FB069);

// ─── Claymorphism design tokens ─────────────────────────────────────────────

/// Corner radii (px) — generous, friendly, toy-like.
const double kRadiusSm = 16;
const double kRadiusMd = 24;
const double kRadiusLg = 28;
const double kRadiusXl = 32;

/// Spacing rhythm (4dp base) — consistent vertical cadence.
const double kSpace4 = 4;
const double kSpace8 = 8;
const double kSpace12 = 12;
const double kSpace16 = 16;
const double kSpace20 = 20;
const double kSpace24 = 24;
const double kSpace32 = 32;
const double kSpace48 = 48;

/// Touch-target minimum (Android 48dp).
const double kTouchTarget = 48;

// ─── M3 Expressive motion tokens ───────────────────────────────────────────
//
// Re-exports of the official Material Design 3 `Durations` and `Easing` tokens
// from `package:flutter/material.dart`, mapped to semantic names the rest of
// the codebase uses. This ensures all motion is M3-spec-compliant rather than
// ad-hoc values.

/// Small component changes (press feedback, toggle, chip tap).
/// M3 token: `Durations.short4` (200ms).
const Duration kMotionFast = Durations.short4;

/// Standard transitions (page slides, card expansions, list reorders).
/// M3 token: `Durations.medium2` (300ms).
const Duration kMotionMedium = Durations.medium2;

/// Entrance / hero animations (onboarding welcome, orb appear).
/// M3 token: `Durations.long2` (500ms).
const Duration kMotionSlow = Durations.long2;

/// M3 Easing: incoming elements (decelerate to rest). Use for enter animations.
const Curve kCurveEnter = Easing.emphasizedDecelerate;

/// M3 Easing: outgoing elements (accelerate from rest). Use for exit animations.
const Curve kCurveExit = Easing.emphasizedAccelerate;

/// M3 Easing: elements that begin and end at rest (standard).
const Curve kCurveStandard = Easing.standard;

/// M3 Easing: standard accelerate for exiting/leaving transitions.
const Curve kCurveStandardAccel = Easing.standardAccelerate;

// ── Legacy curve aliases (kept for backward compat with existing imports) ──
/// Spring curve for playful emotion-feedback bounces.
const Curve kCurveSpring = Curves.elasticOut;

/// Emphasised curve for page-view transitions (M3 emphasized pair).
const Curve kCurveEmphasised = Easing.emphasizedDecelerate;

/// Soft deceleration for press feedback (M3 standard).
const Curve kCurveSoft = Easing.standard;

/// Press feedback curve (M3 standard).
const Curve kCurvePress = Easing.standard;

// ─── M3 Expressive spring physics presets ──────────────────────────────────
//
// M3 Expressive calls for true spring-based motion (not just elastic curves).
// These [SpringDescription] presets drive [SpringSimulation]s for organic,
// physics-based animations — the companion orb's emotion bounce, the mic FAB's
// press-release, etc.

/// Default spring — snappy but gentle. Good for most UI element responses.
final SpringDescription kSpringDefault = SpringDescription.withDampingRatio(
  mass: 1.0,
  stiffness: 200,
  ratio: 0.8,
);

/// Bouncy spring — playful overshoot for emotion-change feedback.
final SpringDescription kSpringBouncy = SpringDescription.withDampingRatio(
  mass: 1.0,
  stiffness: 120,
  ratio: 0.6,
);

/// Gentle spring — slow, soothing motion for ambient life-signs.
final SpringDescription kSpringGentle = SpringDescription.withDampingRatio(
  mass: 1.0,
  stiffness: 80,
  ratio: 0.9,
);

/// Whether the user has requested reduced motion. M3 Expressive requires
/// respecting this: replace spring/bounce animations with fade, and disable
/// continuous ambient animations.
bool reducedMotionEnabled(BuildContext context) {
  return MediaQuery.disableAnimationsOf(context);
}

/// Soft layered shadow — the claymorphism signature (double shadow, no hard
/// lines). Use [clayShadows] on any elevated surface.
List<BoxShadow> clayShadows(BuildContext context, {double intensity = 1}) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  if (isDark) {
    return [
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.3 * intensity),
        blurRadius: 12 * intensity,
        offset: Offset(0, 3 * intensity),
      ),
    ];
  }
  return [
    BoxShadow(
      color: kMoodPetSeed.withValues(alpha: 0.10 * intensity),
      blurRadius: 16 * intensity,
      offset: Offset(0, 6 * intensity),
    ),
    BoxShadow(
      color: kMoodPetSeed.withValues(alpha: 0.05 * intensity),
      blurRadius: 4 * intensity,
      offset: Offset(0, 2 * intensity),
    ),
  ];
}

/// A claymorphism container — rounded, soft-shadowed, subtle surface tint.
/// Use this as the base for cards, tiles, and elevated surfaces across the app.
class ClayContainer extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final double radius;
  final Color? color;
  final Color? borderColor;
  final double shadowIntensity;
  final VoidCallback? onTap;
  final BorderRadius? borderRadius;

  const ClayContainer({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(kSpace16),
    this.margin = EdgeInsets.zero,
    this.radius = kRadiusLg,
    this.color,
    this.borderColor,
    this.shadowIntensity = 1,
    this.onTap,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final br = borderRadius ?? BorderRadius.circular(radius);
    final surface = color ?? theme.colorScheme.surface;
    final decoration = BoxDecoration(
      color: surface,
      borderRadius: br,
      border: borderColor != null
          ? Border.all(color: borderColor!, width: 1)
          : null,
      boxShadow: clayShadows(context, intensity: shadowIntensity),
    );
    if (onTap != null) {
      return Container(
        margin: margin,
        decoration: decoration,
        child: Material(
          color: Colors.transparent,
          borderRadius: br,
          child: InkWell(
            onTap: onTap,
            borderRadius: br,
            child: Padding(padding: padding, child: child),
          ),
        ),
      );
    }
    return Container(
      margin: margin,
      decoration: decoration,
      child: Padding(padding: padding, child: child),
    );
  }
}

/// A small circular icon badge — coloured circle behind an icon, used in
/// settings / list tiles to add visual warmth without emoji-as-icon.
class IconBadge extends StatelessWidget {
  final IconData icon;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final double size;
  final double iconSize;

  const IconBadge({
    super.key,
    required this.icon,
    this.backgroundColor,
    this.foregroundColor,
    this.size = 44,
    this.iconSize = 22,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bg = backgroundColor ?? theme.colorScheme.primaryContainer;
    final fg = foregroundColor ?? theme.colorScheme.onPrimaryContainer;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(size * 0.3),
      ),
      child: Icon(icon, size: iconSize, color: fg),
    );
  }
}

/// Material Design 3 Expressive theme — claymorphism-flavoured.
ThemeData buildMoodPetTheme({Brightness brightness = Brightness.light}) {
  final colorScheme = ColorScheme.fromSeed(
    seedColor: kMoodPetSeed,
    brightness: brightness,
  );

  final isLight = brightness == Brightness.light;

  return ThemeData(
    useMaterial3: true,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: isLight
        ? colorScheme.surface
        : colorScheme.surface,
    appBarTheme: AppBarTheme(
      centerTitle: true,
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: Colors.transparent,
      foregroundColor: colorScheme.onSurface,
      titleTextStyle: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: colorScheme.onSurface,
        letterSpacing: -0.2,
      ),
    ),
    // MD3 Expressive: large rounded corners, soft elevation, generous padding.
    cardTheme: CardThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kRadiusLg),
      ),
      elevation: 0,
      margin: EdgeInsets.zero,
      color: isLight
          ? colorScheme.surface
          : colorScheme.surfaceContainerLow,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(kRadiusLg),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
        textStyle: const TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 16,
          letterSpacing: 0.1,
        ),
        minimumSize: const Size(kTouchTarget, kTouchTarget),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(kRadiusLg),
        ),
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
        minimumSize: const Size(kTouchTarget, kTouchTarget),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(kRadiusLg),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
        minimumSize: const Size(kTouchTarget, kTouchTarget),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(kRadiusMd),
        ),
        minimumSize: const Size(kTouchTarget, kTouchTarget),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: isLight
          ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.5)
          : colorScheme.surfaceContainerHigh,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(kRadiusMd),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(kRadiusMd),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(kRadiusMd),
        borderSide: BorderSide(color: colorScheme.primary, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(kRadiusMd),
        borderSide: BorderSide(color: colorScheme.error, width: 1.5),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(kRadiusMd),
        borderSide: BorderSide(color: colorScheme.error, width: 2),
      ),
      isDense: true,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      labelStyle: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: colorScheme.onSurfaceVariant,
      ),
      hintStyle: TextStyle(
        color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
      ),
    ),
    listTileTheme: ListTileThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kRadiusMd),
      ),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: kSpace20, vertical: kSpace8),
      titleTextStyle: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: colorScheme.onSurface,
      ),
      subtitleTextStyle: TextStyle(
        fontSize: 13,
        color: colorScheme.onSurfaceVariant,
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return colorScheme.onPrimary;
        }
        return colorScheme.outline;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return colorScheme.primary;
        }
        return colorScheme.surfaceContainerHighest;
      }),
      trackOutlineWidth: const WidgetStatePropertyAll(0),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kRadiusMd),
      ),
      elevation: 0,
    ),
    dividerTheme: DividerThemeData(
      color: colorScheme.outlineVariant.withValues(alpha: 0.5),
      thickness: 1,
      space: 1,
    ),
    textTheme: TextTheme(
      // Display
      displayLarge: TextStyle(
        fontWeight: FontWeight.w800,
        letterSpacing: -0.5,
        color: colorScheme.onSurface,
      ),
      displayMedium: TextStyle(
        fontWeight: FontWeight.w800,
        letterSpacing: -0.5,
        color: colorScheme.onSurface,
      ),
      // Headlines
      headlineLarge: TextStyle(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
        color: colorScheme.onSurface,
      ),
      headlineMedium: TextStyle(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
        color: colorScheme.onSurface,
      ),
      headlineSmall: TextStyle(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
        color: colorScheme.onSurface,
      ),
      // Titles
      titleLarge: TextStyle(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.1,
        color: colorScheme.onSurface,
      ),
      titleMedium: TextStyle(
        fontWeight: FontWeight.w600,
        color: colorScheme.onSurface,
      ),
      titleSmall: TextStyle(
        fontWeight: FontWeight.w600,
        fontSize: 14,
        color: colorScheme.onSurface,
      ),
      // Body
      bodyLarge: TextStyle(
        fontSize: 16,
        height: 1.5,
        color: colorScheme.onSurface,
      ),
      bodyMedium: TextStyle(
        fontSize: 14,
        height: 1.5,
        color: colorScheme.onSurface,
      ),
      bodySmall: TextStyle(
        fontSize: 12,
        height: 1.45,
        color: colorScheme.onSurfaceVariant,
      ),
      // Labels
      labelLarge: TextStyle(
        fontWeight: FontWeight.w700,
        fontSize: 14,
        letterSpacing: 0.2,
        color: colorScheme.onSurface,
      ),
      labelMedium: TextStyle(
        fontWeight: FontWeight.w600,
        fontSize: 12,
        letterSpacing: 0.2,
        color: colorScheme.onSurfaceVariant,
      ),
      labelSmall: TextStyle(
        fontWeight: FontWeight.w500,
        fontSize: 11,
        letterSpacing: 0.3,
        color: colorScheme.onSurfaceVariant,
      ),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.macOS: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
      },
    ),
  );
}

class MoodPetApp extends StatelessWidget {
  const MoodPetApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: kAppName,
      debugShowCheckedModeBanner: false,
      theme: buildMoodPetTheme(),
      darkTheme: buildMoodPetTheme(brightness: Brightness.dark),
      home: const SplashPage(),
      routes: {
        '/plugins': (context) => const PluginManagementPage(),
        '/settings': (context) => const SettingsPage(),
        '/market': (context) => const MarketPage(),
        '/market/plugin': (context) => const PluginDetailPage(),
        '/market/pack': (context) => const PackDetailPage(),
      },
    );
  }
}
