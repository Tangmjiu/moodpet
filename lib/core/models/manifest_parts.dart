/// Shared manifest sub-models used by every plugin kind.
///
/// The base [PluginManifest] (common id/name/version/author/icon/system/
/// uninstallable/defaultEnabled/platforms fields) plus the shared
/// [PluginPlatforms], [PluginDependencies], [ConfigSchema] / [ConfigSchemaField]
/// and the Application-only [ApplicationOverrides] / [ApplicationProvides] /
/// [ApplicationRequirements] / [ApplicationResources] blocks live here.
///
/// The three kind-specific subclasses ([FriendManifest], [ApplicationManifest],
/// [PackManifest]) live in `plugin_manifest.dart` and import this file.
library;

import 'plugin_type.dart';

/// Common fields present in every plugin manifest (§6.2 / §7.2 / §8.2).
///
/// The kind-specific subclasses ([FriendManifest], [ApplicationManifest],
/// [PackManifest] in `plugin_manifest.dart`) extend this base. Parsing entry
/// point is [parseBase], which the subclass `fromJson` factories call before
/// reading their own fields off the same JSON map.
class PluginManifest {
  /// Reverse-DNS-style plugin id, e.g. `moodpet.friend.default_smiley`.
  final String id;

  /// Plugin kind — drives which subclass and which loader is used.
  final PluginType type;

  /// Human-readable plugin name (the Friend's display name).
  final String name;

  /// Short description shown in plugin management UI.
  final String description;

  /// Semver version string.
  final String version;

  /// Author or org name.
  final String author;

  /// Relative path to the plugin icon asset (optional).
  final String? icon;

  /// System plugins ship with the container and cannot be uninstalled.
  /// The default smiley Friend is a system plugin.
  final bool system;

  /// Whether the user is allowed to uninstall this plugin. System plugins are
  /// always non-uninstallable regardless of this flag.
  final bool uninstallable;

  /// Whether the plugin starts enabled after installation.
  final bool defaultEnabled;

  /// Platform compatibility matrix.
  final PluginPlatforms platforms;

  const PluginManifest({
    required this.id,
    required this.type,
    required this.name,
    required this.description,
    required this.version,
    required this.author,
    required this.icon,
    required this.system,
    required this.uninstallable,
    required this.defaultEnabled,
    required this.platforms,
  });

  /// Parse the common fields shared by every plugin kind from a raw manifest
  /// object. Subclasses call this then read their own fields off the same map.
  ///
  /// Does NOT dispatch on `type` — the subclass factory is responsible for
  /// asserting the type matches.
  static PluginManifest parseBase(Map<String, Object?> json) {
    final id = json['id'];
    final typeRaw = json['type'];
    final name = json['name'];
    final description = json['description'];
    final version = json['version'];
    final author = json['author'];
    if (id is! String ||
        typeRaw is! String ||
        name is! String ||
        description is! String ||
        version is! String ||
        author is! String) {
      throw const FormatException(
          'manifest requires string id/type/name/description/version/author');
    }
    final platformsRaw = json['platforms'];
    return PluginManifest(
      id: id,
      type: PluginType.fromString(typeRaw),
      name: name,
      description: description,
      version: version,
      author: author,
      icon: json['icon'] as String?,
      system: (json['system'] as bool?) ?? false,
      uninstallable: (json['uninstallable'] as bool?) ?? true,
      defaultEnabled: (json['defaultEnabled'] as bool?) ?? false,
      platforms: platformsRaw is Map<String, Object?>
          ? PluginPlatforms.fromJson(platformsRaw)
          : const PluginPlatforms(
              supported: <PlatformId>[],
              optimized: <PlatformId>[],
              fallback: <PlatformId, String>{}),
    );
  }
}

/// `platforms` block (§6.2 / §7.2 / §8.2): which platforms the plugin runs on.
class PluginPlatforms {
  /// Platforms the plugin can run on. The container refuses to enable a plugin
  /// whose `supported` list does not contain the current platform.
  final List<PlatformId> supported;

  /// Platforms the plugin is tuned for (best experience). Informational only.
  final List<PlatformId> optimized;

  /// Human-readable fallback notes per platform, e.g. `{"windows": "无震动反馈"}`.
  final Map<PlatformId, String> fallback;

  const PluginPlatforms({
    required this.supported,
    this.optimized = const <PlatformId>[],
    this.fallback = const <PlatformId, String>{},
  });

  factory PluginPlatforms.fromJson(Map<String, Object?> json) {
    final sup = json['supported'];
    final opt = json['optimized'];
    final fb = json['fallback'];
    if (sup is! List) {
      throw const FormatException('platforms.supported must be an array');
    }
    final supported = sup
        .whereType<String>()
        .map(PlatformId.fromString)
        .toList(growable: false);
    final optimized = (opt is List)
        ? opt
            .whereType<String>()
            .map(PlatformId.fromString)
            .toList(growable: false)
        : const <PlatformId>[];
    final fallback = <PlatformId, String>{};
    if (fb is Map) {
      fb.forEach((key, value) {
        if (key is String && value is String) {
          fallback[PlatformId.fromString(key)] = value;
        }
      });
    }
    return PluginPlatforms(
      supported: supported,
      optimized: optimized,
      fallback: fallback,
    );
  }

  /// Whether [platform] is in [supported].
  bool supports(PlatformId platform) => supported.contains(platform);
}

/// `dependencies` block (§6.2 / §7.2): minimum container version, plugin deps,
/// consumed container services.
class PluginDependencies {
  /// Minimum container version (semver-ish string) the plugin requires.
  final String? minContainerVersion;

  /// Other plugin ids this plugin depends on.
  final List<String> plugins;

  /// Container service names this plugin consumes, e.g. `["tts","renderer"]`.
  final List<String> services;

  const PluginDependencies({
    this.minContainerVersion,
    this.plugins = const <String>[],
    this.services = const <String>[],
  });

  factory PluginDependencies.fromJson(Map<String, Object?> json) {
    final min = json['minContainerVersion'];
    final plugins = json['plugins'];
    final services = json['services'];
    return PluginDependencies(
      minContainerVersion: min is String ? min : null,
      plugins: (plugins is List)
          ? plugins.whereType<String>().toList(growable: false)
          : const <String>[],
      services: (services is List)
          ? services.whereType<String>().toList(growable: false)
          : const <String>[],
    );
  }

  /// Empty dependencies (used by the default system Friend and packs).
  static const PluginDependencies empty = PluginDependencies(
    minContainerVersion: '1.0.0',
    plugins: <String>[],
    services: <String>[],
  );
}

/// A single field in a plugin's `configSchema` (§6.2 / §7.2).
class ConfigSchemaField {
  /// Field type: `"string"`, `"boolean"`, `"number"`, or `"select"`.
  final String type;

  /// Default value applied when the user has not set this field.
  final Object? defaultValue;

  /// Human-readable label shown in the plugin settings UI.
  final String label;

  /// Whether this field holds a secret (e.g. an API key) — rendered masked and
  /// persisted to secure storage.
  final bool secret;

  /// Allowed values when [type] is `"select"`.
  final List<String>? options;

  const ConfigSchemaField({
    required this.type,
    required this.defaultValue,
    required this.label,
    this.secret = false,
    this.options,
  });

  factory ConfigSchemaField.fromJson(Map<String, Object?> json) {
    final type = json['type'];
    if (type is! String) {
      throw const FormatException('configSchema field requires "type" string');
    }
    return ConfigSchemaField(
      type: type,
      defaultValue: json['default'],
      label: (json['label'] as String?) ?? '',
      secret: (json['secret'] as bool?) ?? false,
      options: (json['options'] as List?)?.whereType<String>().toList(),
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'type': type,
        if (defaultValue != null) 'default': defaultValue,
        'label': label,
        if (secret) 'secret': secret,
        if (options != null) 'options': options,
      };
}

/// `configSchema` block: user-editable per-plugin settings.
typedef ConfigSchema = Map<String, ConfigSchemaField>;

/// Parse a `configSchema` JSON object into a typed [ConfigSchema].
ConfigSchema parseConfigSchema(Object? raw) {
  if (raw is! Map<String, Object?>) return const <String, ConfigSchemaField>{};
  return raw.map(
    (key, value) => MapEntry(
        key, ConfigSchemaField.fromJson(value as Map<String, Object?>)),
  );
}

/// `overrides` block of an Application manifest (§7.2): which container
/// services / UI pages this plugin takes over.
class ApplicationOverrides {
  /// Service names this plugin overrides, mapped to whether it overrides them.
  /// Keys: `tts`, `memory`, `agent`, `renderer`, ...
  final Map<String, bool> services;

  /// UI page names this plugin overrides, mapped to whether it overrides them.
  /// Keys: `home_page`, `settings_page`, ...
  final Map<String, bool> ui;

  const ApplicationOverrides({
    this.services = const <String, bool>{},
    this.ui = const <String, bool>{},
  });

  factory ApplicationOverrides.fromJson(Map<String, Object?> json) {
    final services = <String, bool>{};
    final ui = <String, bool>{};
    final sRaw = json['services'];
    final uRaw = json['ui'];
    if (sRaw is Map) {
      sRaw.forEach((k, v) {
        if (k is String && v is bool) services[k] = v;
      });
    }
    if (uRaw is Map) {
      uRaw.forEach((k, v) {
        if (k is String && v is bool) ui[k] = v;
      });
    }
    return ApplicationOverrides(services: services, ui: ui);
  }

  static const ApplicationOverrides empty =
      ApplicationOverrides(services: <String, bool>{}, ui: <String, bool>{});

  bool overridesService(String name) => services[name] == true;
  bool overridesUi(String name) => ui[name] == true;
}

/// `provides` block (§7.2): triggers, actions, interfaces the plugin exposes.
class ApplicationProvides {
  final List<String> triggers;
  final List<String> actions;
  final List<String> interfaces;

  const ApplicationProvides({
    this.triggers = const <String>[],
    this.actions = const <String>[],
    this.interfaces = const <String>[],
  });

  factory ApplicationProvides.fromJson(Map<String, Object?> json) {
    List<String> readList(String key) => (json[key] is List)
        ? (json[key] as List).whereType<String>().toList(growable: false)
        : const <String>[];

    return ApplicationProvides(
      triggers: readList('triggers'),
      actions: readList('actions'),
      interfaces: readList('interfaces'),
    );
  }

  static const ApplicationProvides empty = ApplicationProvides(
    triggers: <String>[],
    actions: <String>[],
    interfaces: <String>[],
  );
}

/// `requirements` block (§7.2): webview, permissions, min platform versions,
/// runtime deps.
class ApplicationRequirements {
  final String? webview;
  final List<String> permissions;
  final Map<String, String> minPlatformVersion;
  final Map<String, Object?> runtime;

  const ApplicationRequirements({
    this.webview,
    this.permissions = const <String>[],
    this.minPlatformVersion = const <String, String>{},
    this.runtime = const <String, Object?>{},
  });

  factory ApplicationRequirements.fromJson(Map<String, Object?> json) {
    final minPv = <String, String>{};
    final mpv = json['minPlatformVersion'];
    if (mpv is Map) {
      mpv.forEach((k, v) {
        if (k is String && v is String) minPv[k] = v;
      });
    }
    final runtime = <String, Object?>{};
    final rt = json['runtime'];
    if (rt is Map) {
      rt.forEach((k, v) {
        if (k is String) runtime[k] = v;
      });
    }
    return ApplicationRequirements(
      webview: json['webview'] as String?,
      permissions: (json['permissions'] is List)
          ? (json['permissions'] as List)
              .whereType<String>()
              .toList(growable: false)
          : const <String>[],
      minPlatformVersion: minPv,
      runtime: runtime,
    );
  }

  static const ApplicationRequirements empty = ApplicationRequirements(
    webview: null,
    permissions: <String>[],
    minPlatformVersion: <String, String>{},
    runtime: <String, Object?>{},
  );
}

/// `resources` block (§7.2): minimum resource budget the plugin needs.
class ApplicationResources {
  final int? minRam;
  final int? minDisk;
  final int? maxCpuCores;

  const ApplicationResources({this.minRam, this.minDisk, this.maxCpuCores});

  factory ApplicationResources.fromJson(Map<String, Object?> json) =>
      ApplicationResources(
        minRam: (json['minRam'] is num) ? (json['minRam'] as num).toInt() : null,
        minDisk:
            (json['minDisk'] is num) ? (json['minDisk'] as num).toInt() : null,
        maxCpuCores: (json['maxCpuCores'] is num)
            ? (json['maxCpuCores'] as num).toInt()
            : null,
      );

  static const ApplicationResources empty =
      ApplicationResources(minRam: null, minDisk: null, maxCpuCores: null);
}
