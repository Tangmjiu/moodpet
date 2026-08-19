/// Typed plugin manifests for the three MoodPet plugin kinds.
///
/// This file holds ONLY the three manifest subclasses ([FriendManifest],
/// [ApplicationManifest], [PackManifest]) plus their kind-specific sub-models
/// ([FriendInterfaces], [PackPluginEntry], [PackPlugins], [PackRecommended]).
/// Shared fields/sub-models ([PluginManifest] base, [PluginPlatforms],
/// [PluginDependencies], [ConfigSchemaField], [ApplicationOverrides],
/// [ApplicationProvides], [ApplicationRequirements], [ApplicationResources])
/// live in `manifest_parts.dart`.
///
/// Parsing is strict: missing required fields throw [FormatException] so a
/// malformed plugin fails loading loudly instead of degrading silently.
library;

import 'manifest_parts.dart';
import 'plugin_type.dart';

// Re-export the shared base + sub-models so callers can import this one file
// and get every manifest type.
export 'manifest_parts.dart' show
    PluginManifest,
    PluginPlatforms,
    PluginDependencies,
    ConfigSchemaField,
    ConfigSchema,
    parseConfigSchema,
    ApplicationOverrides,
    ApplicationProvides,
    ApplicationRequirements,
    ApplicationResources;

/// `interfaces` block of a Friend manifest (§6.2): relative paths to the
/// identity / personality / expression / voice / ui / rules files inside the
/// plugin directory.
class FriendInterfaces {
  /// Optional identity JSON (name/emoji/etc. metadata).
  final String? identity;

  /// Relative path to `system_prompt.txt` — required at load time.
  final String personality;

  /// Relative path to `emoji_mapping.json` — optional.
  final String? expression;

  /// Relative path to a voice config — [社区].
  final String? voice;

  /// Relative path to `ui_style.json` — [社区] optional.
  final String? ui;

  /// Relative path to a rules directory — [社区] optional.
  final String? rules;

  const FriendInterfaces({
    required this.identity,
    required this.personality,
    required this.expression,
    required this.voice,
    required this.ui,
    required this.rules,
  });

  factory FriendInterfaces.fromJson(Map<String, Object?> json) {
    final personality = json['personality'];
    if (personality is! String) {
      throw const FormatException(
          'Friend manifest requires interfaces.personality (system_prompt path)');
    }
    return FriendInterfaces(
      identity: json['identity'] as String?,
      personality: personality,
      expression: json['expression'] as String?,
      voice: json['voice'] as String?,
      ui: json['ui'] as String?,
      rules: json['rules'] as String?,
    );
  }
}

/// Parsed contents of a Friend plugin's `identity.json` (§6.2): the partner's
/// self-presenting metadata shown on the home screen and in management UI.
///
/// All fields are optional — a minimal Friend may ship only a name. The
/// container falls back to the manifest's `name` when [name] is absent.
class FriendIdentity {
  /// Display name override (falls back to the manifest name).
  final String? name;

  /// Canonical emoji used as the partner's avatar in idle state.
  final String? emoji;

  /// One-line tagline shown under the name on the home screen.
  final String? tagline;

  /// Author / creator credit.
  final String? creator;

  const FriendIdentity({
    this.name,
    this.emoji,
    this.tagline,
    this.creator,
  });

  factory FriendIdentity.fromJson(Map<String, Object?> json) {
    return FriendIdentity(
      name: json['name'] as String?,
      emoji: json['emoji'] as String?,
      tagline: json['tagline'] as String?,
      creator: json['creator'] as String?,
    );
  }

  static const FriendIdentity empty =
      FriendIdentity(name: null, emoji: null, tagline: null, creator: null);
}

/// Friend plugin manifest (§6.2): partner identity pack. Carries identity +
/// personality + emotion mapping; contains no executable code.
class FriendManifest extends PluginManifest {
  final FriendInterfaces interfaces;
  final PluginDependencies dependencies;
  final ConfigSchema configSchema;

  const FriendManifest({
    required super.id,
    required super.name,
    required super.description,
    required super.version,
    required super.author,
    required super.icon,
    required super.system,
    required super.uninstallable,
    required super.defaultEnabled,
    required super.platforms,
    required this.interfaces,
    required this.dependencies,
    required this.configSchema,
  }) : super(type: PluginType.friend);

  factory FriendManifest.fromJson(Map<String, Object?> json) {
    final base = PluginManifest.parseBase(json);
    if (base.type != PluginType.friend) {
      throw FormatException(
          'manifest ${base.id} declared type ${base.type.name}, expected friend');
    }
    final interfacesRaw = json['interfaces'];
    if (interfacesRaw is! Map<String, Object?>) {
      throw const FormatException(
          'Friend manifest requires an "interfaces" object');
    }
    final dependenciesRaw = json['dependencies'];
    return FriendManifest(
      id: base.id,
      name: base.name,
      description: base.description,
      version: base.version,
      author: base.author,
      icon: base.icon,
      system: base.system,
      uninstallable: base.uninstallable,
      defaultEnabled: base.defaultEnabled,
      platforms: base.platforms,
      interfaces: FriendInterfaces.fromJson(interfacesRaw),
      dependencies: dependenciesRaw is Map<String, Object?>
          ? PluginDependencies.fromJson(dependenciesRaw)
          : PluginDependencies.empty,
      configSchema: parseConfigSchema(json['configSchema']),
    );
  }
}

/// Application plugin manifest (§7.2): capability pack. May override container
/// services and UI.
class ApplicationManifest extends PluginManifest {
  /// Entry file, e.g. `lib/main.dart` or `python/main.py`.
  final String entry;

  /// Implementation language hint: `dart`, `python`, `binary`, ...
  final String language;

  final ApplicationOverrides overrides;
  final ApplicationProvides provides;
  final PluginDependencies dependencies;
  final ApplicationRequirements requirements;
  final ApplicationResources resources;
  final ConfigSchema configSchema;

  const ApplicationManifest({
    required super.id,
    required super.name,
    required super.description,
    required super.version,
    required super.author,
    required super.icon,
    required super.system,
    required super.uninstallable,
    required super.defaultEnabled,
    required super.platforms,
    required this.entry,
    required this.language,
    required this.overrides,
    required this.provides,
    required this.dependencies,
    required this.requirements,
    required this.resources,
    required this.configSchema,
  }) : super(type: PluginType.application);

  factory ApplicationManifest.fromJson(Map<String, Object?> json) {
    final base = PluginManifest.parseBase(json);
    if (base.type != PluginType.application) {
      throw FormatException(
          'manifest ${base.id} declared type ${base.type.name}, expected application');
    }
    final entry = json['entry'];
    final language = json['language'];
    if (entry is! String || language is! String) {
      throw const FormatException(
          'Application manifest requires string "entry" and "language"');
    }
    final overridesRaw = json['overrides'];
    final providesRaw = json['provides'];
    final dependenciesRaw = json['dependencies'];
    final requirementsRaw = json['requirements'];
    final resourcesRaw = json['resources'];
    return ApplicationManifest(
      id: base.id,
      name: base.name,
      description: base.description,
      version: base.version,
      author: base.author,
      icon: base.icon,
      system: base.system,
      uninstallable: base.uninstallable,
      defaultEnabled: base.defaultEnabled,
      platforms: base.platforms,
      entry: entry,
      language: language,
      overrides: overridesRaw is Map<String, Object?>
          ? ApplicationOverrides.fromJson(overridesRaw)
          : ApplicationOverrides.empty,
      provides: providesRaw is Map<String, Object?>
          ? ApplicationProvides.fromJson(providesRaw)
          : ApplicationProvides.empty,
      dependencies: dependenciesRaw is Map<String, Object?>
          ? PluginDependencies.fromJson(dependenciesRaw)
          : PluginDependencies.empty,
      requirements: requirementsRaw is Map<String, Object?>
          ? ApplicationRequirements.fromJson(requirementsRaw)
          : ApplicationRequirements.empty,
      resources: resourcesRaw is Map<String, Object?>
          ? ApplicationResources.fromJson(resourcesRaw)
          : ApplicationResources.empty,
      configSchema: parseConfigSchema(json['configSchema']),
    );
  }
}

/// One entry in a pack's `plugins.friend` / `plugins.application` lists (§8.2).
class PackPluginEntry {
  final String id;
  final String path;

  const PackPluginEntry({required this.id, required this.path});

  factory PackPluginEntry.fromJson(Map<String, Object?> json) {
    final id = json['id'];
    final path = json['path'];
    if (id is! String || path is! String) {
      throw const FormatException('Pack plugin entry requires "id" and "path"');
    }
    return PackPluginEntry(id: id, path: path);
  }
}

/// `plugins` block of a pack manifest.
class PackPlugins {
  final List<PackPluginEntry> friend;
  final List<PackPluginEntry> application;

  const PackPlugins({required this.friend, required this.application});

  factory PackPlugins.fromJson(Map<String, Object?> json) {
    List<PackPluginEntry> readEntries(String key) {
      final raw = json[key];
      if (raw is! List) return const <PackPluginEntry>[];
      return raw
          .whereType<Map<String, Object?>>()
          .map(PackPluginEntry.fromJson)
          .toList(growable: false);
    }

    return PackPlugins(
      friend: readEntries('friend'),
      application: readEntries('application'),
    );
  }
}

/// `recommended` block of a pack manifest.
class PackRecommended {
  final String? defaultFriend;
  final List<String> defaultApplication;

  const PackRecommended({
    required this.defaultFriend,
    required this.defaultApplication,
  });

  factory PackRecommended.fromJson(Map<String, Object?> json) {
    return PackRecommended(
      defaultFriend: json['defaultFriend'] as String?,
      defaultApplication: (json['defaultApplication'] as List?)
              ?.whereType<String>()
              .toList(growable: false) ??
          const <String>[],
    );
  }

  static const PackRecommended empty =
      PackRecommended(defaultFriend: null, defaultApplication: <String>[]);
}

/// Pack manifest (§8.2): bundle of Friend + Application plugins.
class PackManifest extends PluginManifest {
  final PackPlugins plugins;
  final PackRecommended recommended;

  const PackManifest({
    required super.id,
    required super.name,
    required super.description,
    required super.version,
    required super.author,
    required super.icon,
    required super.platforms,
    required this.plugins,
    required this.recommended,
  }) : super(
          type: PluginType.pack,
          system: false,
          uninstallable: true,
          defaultEnabled: false,
        );

  factory PackManifest.fromJson(Map<String, Object?> json) {
    final base = PluginManifest.parseBase(json);
    if (base.type != PluginType.pack) {
      throw FormatException(
          'manifest ${base.id} declared type ${base.type.name}, expected pack');
    }
    final pluginsRaw = json['plugins'];
    final recommendedRaw = json['recommended'];
    return PackManifest(
      id: base.id,
      name: base.name,
      description: base.description,
      version: base.version,
      author: base.author,
      icon: base.icon,
      platforms: base.platforms,
      plugins: pluginsRaw is Map<String, Object?>
          ? PackPlugins.fromJson(pluginsRaw)
          : const PackPlugins(
              friend: <PackPluginEntry>[], application: <PackPluginEntry>[]),
      recommended: recommendedRaw is Map<String, Object?>
          ? PackRecommended.fromJson(recommendedRaw)
          : PackRecommended.empty,
    );
  }
}
