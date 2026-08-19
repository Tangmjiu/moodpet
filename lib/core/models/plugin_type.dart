/// Plugin type taxonomy and supported platform identifiers.
///
/// Every MoodPet plugin declares exactly one [PluginType] in its
/// `manifest.json`. The container uses the type to pick the correct loader,
/// registry and lifecycle.
///
/// The *current* platform the container is running on is resolved by
/// `platform_info.dart` (which may use dart:io); this model module stays free
/// of platform side-effects.
library;

/// The three plugin kinds defined by the MoodPet plugin specification.
enum PluginType {
  /// Partner identity pack: name, emoji, system prompt, emotion mapping.
  /// Contains no executable code.
  friend,

  /// Capability pack: unrestricted, may be written in any language and may
  /// override container services (TTS / memory / agent / renderer / UI).
  application,

  /// Bundle of Friend + Application plugins; installable as one unit and
  /// expandable into its constituents.
  pack;

  /// Parse the manifest `"type"` string. Throws [ArgumentError] on unknown
  /// values so a malformed manifest fails loading loudly rather than silently.
  static PluginType fromString(String value) {
    switch (value) {
      case 'friend':
        return PluginType.friend;
      case 'application':
        return PluginType.application;
      case 'pack':
        return PluginType.pack;
      default:
        throw ArgumentError.value(
            value, 'type', 'manifest "type" must be friend|application|pack');
    }
  }
}

/// Platforms recognised by the platform-compatibility matrix (§9).
///
/// Plugins declare which platforms they [PluginPlatforms.support] and which
/// they are [PluginPlatforms.optimized] for; the container refuses to enable
/// a plugin on an unsupported platform.
enum PlatformId {
  android,
  wearos,
  windows,
  linux,
  macos;

  /// Parse a platform string from a manifest. Throws on unknown ids.
  static PlatformId fromString(String value) {
    switch (value) {
      case 'android':
        return PlatformId.android;
      case 'wearos':
        return PlatformId.wearos;
      case 'windows':
        return PlatformId.windows;
      case 'linux':
        return PlatformId.linux;
      case 'macos':
        return PlatformId.macos;
      default:
        throw ArgumentError.value(value, 'platform', 'unknown platform id');
    }
  }
}
