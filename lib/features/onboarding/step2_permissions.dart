import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import 'onboarding_page.dart';

enum _PermissionCardStatus { unknown, granted, denied }

class _PermissionCardData {
  const _PermissionCardData({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.permission,
    required this.alwaysGranted,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Permission? permission;
  final bool alwaysGranted;
}

/// Step 2 权限授予页（卡片式）。
class Step2PermissionsPage extends StatefulWidget {
  const Step2PermissionsPage({required this.onNext, super.key});

  final VoidCallback onNext;

  @override
  State<Step2PermissionsPage> createState() => _Step2PermissionsPageState();
}

class _Step2PermissionsPageState extends State<Step2PermissionsPage> {
  final Map<int, _PermissionCardStatus> _statuses = {
    0: _PermissionCardStatus.unknown,
    1: _PermissionCardStatus.unknown,
    2: _PermissionCardStatus.unknown,
  };

  late final List<_PermissionCardData> _cards = [
    const _PermissionCardData(
      icon: Icons.mic,
      title: '麦克风',
      subtitle: '用于听你说话，把语音转成文字',
      permission: Permission.microphone,
      alwaysGranted: false,
    ),
    const _PermissionCardData(
      icon: Icons.vibration,
      title: '震动',
      subtitle: '情绪变化时给你触觉反馈（系统正常权限）',
      permission: null,
      alwaysGranted: true,
    ),
    const _PermissionCardData(
      icon: Icons.notifications,
      title: '通知',
      subtitle: '用于主动推送陪伴提醒',
      permission: Permission.notification,
      alwaysGranted: false,
    ),
  ];

  bool get _allGranted =>
      _statuses.values.every((s) => s == _PermissionCardStatus.granted);

  @override
  void initState() {
    super.initState();
    _loadInitialStatuses();
  }

  Future<void> _loadInitialStatuses() async {
    for (var i = 0; i < _cards.length; i++) {
      final card = _cards[i];
      if (card.alwaysGranted || card.permission == null) {
        _statuses[i] = _PermissionCardStatus.granted;
        continue;
      }
      final status = await card.permission!.status;
      _statuses[i] = status.isGranted || status.isLimited
          ? _PermissionCardStatus.granted
          : _PermissionCardStatus.unknown;
    }
    if (mounted) setState(() {});
  }

  Future<void> _request(int index) async {
    final card = _cards[index];
    if (card.alwaysGranted || card.permission == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('震动是系统正常权限，已自动授予')),
      );
      return;
    }

    final status = await card.permission!.request();
    if (!mounted) return;
    setState(() {
      if (status.isGranted || status.isLimited) {
        _statuses[index] = _PermissionCardStatus.granted;
      } else {
        _statuses[index] = _PermissionCardStatus.denied;
      }
    });

    if (status.isPermanentlyDenied) {
      _showOpenSettingsDialog(card.title);
    }
  }

  void _showOpenSettingsDialog(String title) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('$title 权限已被拒绝'),
        content: const Text('请在系统设置中手动开启该权限。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(context).pop();
              openAppSettings();
            },
            child: const Text('打开设置'),
          ),
        ],
      ),
    );
  }

  Icon _statusIcon(_PermissionCardStatus status) {
    return switch (status) {
      _PermissionCardStatus.granted =>
        const Icon(Icons.check_circle, color: Colors.green),
      _PermissionCardStatus.denied =>
        const Icon(Icons.block, color: Colors.red),
      _PermissionCardStatus.unknown =>
        const Icon(Icons.error_outline, color: Colors.orange),
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          Text(
            '授予必要权限',
            style: theme.textTheme.headlineMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            'MoodPet 只会为以下能力申请权限',
            style: theme.textTheme.bodyLarge
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 24),
          for (var i = 0; i < _cards.length; i++) ...[
            Card(
              clipBehavior: Clip.antiAlias,
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 8,
                ),
                leading: CircleAvatar(
                  backgroundColor: theme.colorScheme.secondaryContainer,
                  child: Icon(
                    _cards[i].icon,
                    color: theme.colorScheme.onSecondaryContainer,
                  ),
                ),
                title: Text(
                  _cards[i].title,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(_cards[i].subtitle),
                trailing: _statusIcon(_statuses[i]!),
                onTap: _statuses[i] == _PermissionCardStatus.granted
                    ? null
                    : () => _request(i),
              ),
            ),
            const SizedBox(height: 12),
          ],
          const Spacer(),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '已授权 ${_statuses.values.where((s) => s == _PermissionCardStatus.granted).length}/${_cards.length}',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              if (_statuses.values
                  .any((s) => s == _PermissionCardStatus.denied)) ...[
                const SizedBox(width: 12),
                TextButton(
                  onPressed: () {
                    for (var i = 0; i < _cards.length; i++) {
                      if (_statuses[i] == _PermissionCardStatus.denied) {
                        _request(i);
                      }
                    }
                  },
                  child: const Text('重新申请'),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _allGranted ? widget.onNext : null,
              child: const Text('下一步'),
            ),
          ),
          const SizedBox(height: 20),
          const OnboardingDots(total: 3, current: 1),
        ],
      ),
    );
  }
}
