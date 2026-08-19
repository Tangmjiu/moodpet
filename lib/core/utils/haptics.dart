/// Haptic feedback helper — translates the `vibration` array from an
/// [EmotionResponse] into platform haptic patterns.
library;

import 'package:flutter/services.dart';

/// Play a haptic pattern from an [EmotionResponse] `vibration` array.
///
/// The array is interpreted as millisecond durations: odd indices are
/// vibration-on durations, even indices are pauses. On platforms without
/// vibration (desktop), this is a no-op. On Android, uses [HapticFeedback]
/// for short patterns and [Vibration] via platform channel for longer ones
/// (simplified: uses medium/heavy impact taps for each on-segment).
Future<void> playVibrationPattern(List<int> pattern) async {
  if (pattern.isEmpty) return;
  for (var i = 0; i < pattern.length; i++) {
    if (i.isEven) {
      // On-segment: trigger a haptic tap.
      final duration = pattern[i];
      if (duration > 300) {
        await HapticFeedback.heavyImpact();
      } else if (duration > 100) {
        await HapticFeedback.mediumImpact();
      } else {
        await HapticFeedback.lightImpact();
      }
    }
    // Pause for the specified duration (best-effort; HapticFeedback has no
    // built-in delay so we use a simple Future.delayed).
    await Future<void>.delayed(Duration(milliseconds: pattern[i].clamp(20, 800)));
  }
}
