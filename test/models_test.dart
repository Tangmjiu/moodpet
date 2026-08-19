import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:moodpet/core/models/emotion.dart';
import 'package:moodpet/core/models/plugin_manifest.dart';
import 'package:moodpet/core/models/plugin_type.dart';
import 'package:moodpet/core/models/provider_config.dart';
import 'package:moodpet/core/models/region_info.dart';

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

  group('PlatformId', () {
    test('fromString parses valid platforms', () {
      expect(PlatformId.fromString('android'), PlatformId.android);
      expect(PlatformId.fromString('wearos'), PlatformId.wearos);
      expect(PlatformId.fromString('windows'), PlatformId.windows);
      expect(PlatformId.fromString('linux'), PlatformId.linux);
      expect(PlatformId.fromString('macos'), PlatformId.macos);
    });

    test('fromString throws on unknown platform', () {
      expect(() => PlatformId.fromString('ios'), throwsArgumentError);
    });
  });

  group('EmotionResponse', () {
    test('fromJson parses a complete response', () {
      final json = jsonDecode('''{
        "emoji": "😢",
        "color": "#6C9BCF",
        "vibration": [500],
        "suggestion": "我在呢"
      }''') as Map<String, Object?>;
      final resp = EmotionResponse.fromJson(json);
      expect(resp.emoji, '😢');
      expect(resp.color, '#6C9BCF');
      expect(resp.vibration, [500]);
      expect(resp.suggestion, '我在呢');
    });

    test('fromJson handles missing vibration gracefully', () {
      final resp = EmotionResponse.fromJson({
        'emoji': '😊',
        'color': '#FFD93D',
        'suggestion': '好',
      });
      expect(resp.vibration, isEmpty);
    });

    test('idle is the default response', () {
      expect(EmotionResponse.idle.emoji, '😊');
    });
  });

  group('EmojiMapping', () {
    test('resolve matches keyword rules', () {
      final mapping = parseEmojiMapping('''{
        "rules": [
          {
            "keywords": ["开心", "高兴"],
            "response": {"emoji": "😊", "color": "#FFD93D", "vibration": [100], "suggestion": "好"}
          }
        ],
        "default": {"emoji": "😐", "color": "#999", "vibration": [], "suggestion": "嗯"}
      }''');
      expect(mapping.resolve('我今天很开心').emoji, '😊');
      expect(mapping.resolve('随机文字').emoji, '😐');
    });
  });

  group('FriendManifest', () {
    test('fromJson parses a valid friend manifest', () {
      final json = jsonDecode('''{
        "id": "moodpet.friend.test",
        "type": "friend",
        "name": "测试伙伴",
        "description": "测试用",
        "version": "1.0.0",
        "author": "tester",
        "system": false,
        "uninstallable": true,
        "defaultEnabled": true,
        "platforms": {"supported": ["android", "linux"]},
        "interfaces": {"personality": "system_prompt.txt"},
        "configSchema": {}
      }''') as Map<String, Object?>;
      final manifest = FriendManifest.fromJson(json);
      expect(manifest.id, 'moodpet.friend.test');
      expect(manifest.type, PluginType.friend);
      expect(manifest.name, '测试伙伴');
      expect(manifest.interfaces.personality, 'system_prompt.txt');
      expect(manifest.platforms.supported, contains(PlatformId.android));
    });

    test('fromJson throws on missing interfaces', () {
      expect(
        () => FriendManifest.fromJson({
          'id': 'x',
          'type': 'friend',
          'name': 'x',
          'description': 'x',
          'version': '1.0.0',
          'author': 'x',
        }),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('ApplicationManifest', () {
    test('fromJson parses a valid application manifest', () {
      final json = jsonDecode('''{
        "id": "moodpet.app.test",
        "type": "application",
        "name": "测试应用",
        "description": "测试",
        "version": "1.0.0",
        "author": "tester",
        "entry": "lib/main.dart",
        "language": "dart",
        "overrides": {"services": {"tts": true, "agent": false}},
        "provides": {"triggers": ["on_mood_shift"]}
      }''') as Map<String, Object?>;
      final manifest = ApplicationManifest.fromJson(json);
      expect(manifest.id, 'moodpet.app.test');
      expect(manifest.entry, 'lib/main.dart');
      expect(manifest.language, 'dart');
      expect(manifest.overrides.overridesService('tts'), isTrue);
      expect(manifest.overrides.overridesService('agent'), isFalse);
    });
  });

  group('PackManifest', () {
    test('fromJson parses a valid pack manifest', () {
      final json = jsonDecode('''{
        "id": "moodpet.pack.test",
        "type": "pack",
        "name": "测试包",
        "description": "测试",
        "version": "1.0.0",
        "author": "tester",
        "plugins": {
          "friend": [{"id": "f1", "path": "friend/f1.moodfriend"}],
          "application": [{"id": "a1", "path": "application/a1.moodapp"}]
        },
        "recommended": {"defaultFriend": "f1"}
      }''') as Map<String, Object?>;
      final manifest = PackManifest.fromJson(json);
      expect(manifest.id, 'moodpet.pack.test');
      expect(manifest.plugins.friend.length, 1);
      expect(manifest.plugins.friend.first.id, 'f1');
      expect(manifest.recommended.defaultFriend, 'f1');
    });
  });

  group('ProviderConfig', () {
    test('kBuiltinProviders is non-empty', () {
      expect(kBuiltinProviders, isNotEmpty);
    });

    test('builtinProviderById finds known providers', () {
      expect(builtinProviderById('openai'), isNotNull);
      expect(builtinProviderById('deepseek'), isNotNull);
      expect(builtinProviderById('nonexistent'), isNull);
    });

    test('copyWith updates apiKey and modelOverride', () {
      final base = kBuiltinProviders.first;
      final updated = base.copyWith(apiKey: 'sk-test', modelOverride: 'gpt-4');
      expect(updated.apiKey, 'sk-test');
      expect(updated.modelOverride, 'gpt-4');
      expect(updated.effectiveModel, 'gpt-4');
    });
  });

  group('RegionInfo', () {
    test('countryNameFromCode returns Chinese names', () {
      expect(countryNameFromCode('CN'), '中国大陆');
      expect(countryNameFromCode('US'), '美国');
    });

    test('countryNameFromCode falls back to upper-cased code', () {
      expect(countryNameFromCode('XX'), 'XX');
    });

    test('countryNameFromCode handles null', () {
      expect(countryNameFromCode(null), '未知地区');
    });
  });

  group('PluginManifest.parseBase', () {
    test('parseBase reads common fields', () {
      final json = <String, Object?>{
        'id': 'test.friend',
        'type': 'friend',
        'name': 'F',
        'description': 'd',
        'version': '1.0.0',
        'author': 'a',
      };
      final base = PluginManifest.parseBase(json);
      expect(base.id, 'test.friend');
      expect(base.type, PluginType.friend);
      expect(base.name, 'F');
    });
  });
}
