/// Resolves the [PlatformId] the container is currently running on.
///
/// Kept separate from the pure model module so `dart:io` is imported in only
/// one place; the model layer never touches platform side-effects.
library;

import 'dart:io' show Platform;

import 'models/plugin_type.dart';

/// The platform this container build is running on right now.
///
/// Wear OS is built on Android and cannot be distinguished from a phone at the
/// dart:io level, so it reports as [PlatformId.android]; Wear-specific layout
/// adaptation is driven by screen size, not by this value.
PlatformId get currentPlatformId {
  if (Platform.isAndroid) return PlatformId.android;
  if (Platform.isLinux) return PlatformId.linux;
  if (Platform.isWindows) return PlatformId.windows;
  if (Platform.isMacOS) return PlatformId.macos;
  // ios/web fall back to android-shaped layout; MoodPet targets are listed in
  // the platform-compatibility matrix (§9).
  return PlatformId.android;
}
