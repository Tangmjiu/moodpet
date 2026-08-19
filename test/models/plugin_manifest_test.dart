import 'package:flutter_test/flutter_test.dart';
import 'package:moodpet/core/models/plugin_manifest.dart';
import 'package:moodpet/core/models/plugin_type.dart';

void main() {
  group('PluginType', () {
    test('fromString parses valid types', () {
      expect(PluginType.fromString('friend'), PluginType.friend);
      expect(PluginType.fromString('application'), PluginType.application);
      expect(PluginType.fromString('pack'), PluginType.pack);
    });

    test('fromString throws on unknown type', () {
      expect(() => PluginType.fromString('unknown'), throwsArgumentError);
    });
  });

  group('FriendManifest', () {
    final validFriendJson = <String, Object?>{
      'id': 'moodpet.friend.test',
      'type': 'friend',
      'name': '测试伙伴',
      'description': '测试用伙伴插件',
      'version': '1.0.0',
      'author': 'Test',
      'system': false,
      'uninstallable': true,
      'defaultEnabled': true,
      'platforms': {
        'supported': ['android', 'linux'],
        'optimized': ['android'],
      },
      'interfaces': {
        'personality': 'system_prompt.txt',
        'expression': 'emoji_mapping.json',
      },
      'dependencies': {
        'minContainerVersion': '1.0.0',
        'services': ['renderer'],
      },
    };

    test('fromJson parses all fields', () {
      final manifest = FriendManifest.fromJson(validFriendJson);
      expect(manifest.id, 'moodpet.friend.test');
      expect(manifest.type, PluginType.friend);
      expect(manifest.name, '测试伙伴');
      expect(manifest.system, false);
      expect(manifest.uninstallable, true);
      expect(manifest.defaultEnabled, true);
      expect(manifest.platforms.supported,
          containsAll([PlatformId.android, PlatformId.linux]));
      expect(manifest.platforms.optimized, [PlatformId.android]);
      expect(manifest.interfaces.personality, 'system_prompt.txt');
      expect(manifest.interfaces.expression, 'emoji_mapping.json');
      expect(manifest.dependencies.services, ['renderer']);
    });

    test('fromJson throws on missing required field', () {
      final broken = Map<String, Object?>.from(validFriendJson)
        ..remove('name');
      expect(() => FriendManifest.fromJson(broken), throwsFormatException);
    });

    test('fromJson throws on wrong type', () {
      final wrong = Map<String, Object?>.from(validFriendJson)
        ..['type'] = 'application';
      expect(() => FriendManifest.fromJson(wrong), throwsFormatException);
    });
  });

  group('ApplicationManifest', () {
    final validAppJson = <String, Object?>{
      'id': 'moodpet.application.test',
      'type': 'application',
      'name': '测试应用',
      'description': '测试用应用插件',
      'version': '1.0.0',
      'author': 'Test',
      'entry': 'lib/main.dart',
      'language': 'dart',
      'platforms': {
        'supported': ['android', 'windows'],
      },
      'overrides': {
        'services': {'tts': true, 'agent': false},
        'ui': {'home_page': false},
      },
      'provides': {
        'triggers': ['on_mood_shift'],
        'interfaces': ['TTSProvider'],
      },
    };

    test('fromJson parses overrides correctly', () {
      final manifest = ApplicationManifest.fromJson(validAppJson);
      expect(manifest.entry, 'lib/main.dart');
      expect(manifest.language, 'dart');
      expect(manifest.overrides.overridesService('tts'), true);
      expect(manifest.overrides.overridesService('agent'), false);
      expect(manifest.overrides.overridesUi('home_page'), false);
      expect(manifest.provides.triggers, ['on_mood_shift']);
      expect(manifest.provides.interfaces, ['TTSProvider']);
    });
  });

  group('PackManifest', () {
    final validPackJson = <String, Object?>{
      'id': 'moodpet.pack.test',
      'type': 'pack',
      'name': '测试整合包',
      'description': '包含 2 个 Friend + 1 个 Application',
      'version': '1.0.0',
      'author': 'Test',
      'platforms': {
        'supported': ['android', 'linux'],
      },
      'plugins': {
        'friend': [
          {'id': 'friend_a', 'path': 'friend/friend_a.moodfriend'},
        ],
        'application': [
          {'id': 'app_a', 'path': 'application/app_a.moodapp'},
        ],
      },
      'recommended': {
        'defaultFriend': 'friend_a',
        'defaultApplication': ['app_a'],
      },
    };

    test('fromJson parses plugin references', () {
      final manifest = PackManifest.fromJson(validPackJson);
      expect(manifest.plugins.friend.length, 1);
      expect(manifest.plugins.friend.first.id, 'friend_a');
      expect(manifest.plugins.application.length, 1);
      expect(manifest.recommended.defaultFriend, 'friend_a');
    });
  });
}
