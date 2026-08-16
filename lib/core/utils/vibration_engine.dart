import 'package:flutter/foundation.dart';
import 'package:vibration/vibration.dart';

/// 震动反馈引擎：把情绪规则的毫秒数组转换为设备震动。
class VibrationEngine {
  const VibrationEngine();

  Future<void> vibratePattern(List<int> pattern) async {
    if (pattern.isEmpty) return;
    if (kIsWeb) return;
    try {
      final hasVibrator = await Vibration.hasVibrator();
      if (hasVibrator != true) return;
      await Vibration.vibrate(pattern: pattern, repeat: -1);
      // 不设置重复；数组播完自然结束（platform 侧 -1 表示不循环）。
      await Future<void>.delayed(
        Duration(milliseconds: pattern.fold(0, (sum, ms) => sum + ms) + 80),
      );
      await Vibration.cancel();
    } catch (_) {
      // 桌面端 / 模拟器不支持震动时静默降级。
    }
  }

  Future<void> cancel() async {
    try {
      await Vibration.cancel();
    } catch (_) {}
  }
}
