/// About page (关于): brand hero, version, GitHub contributors, support link
/// and open-source info.
///
/// Android "About device" aesthetic translated into MoodPet's claymorphism
/// language — calm, informative single-column layout with a staggered M3
/// Expressive entrance (fade + slide up, skipped to fade-only under
/// reduced-motion). All colours come from the theme's colour scheme.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../../app.dart'
    show
        ClayContainer,
        IconBadge,
        clayShadows,
        kCurveEnter,
        kMotionMedium,
        kRadiusLg,
        kRadiusSm,
        kSpace4,
        kSpace8,
        kSpace12,
        kSpace16,
        kSpace20,
        kSpace24,
        kSpace32,
        reducedMotionEnabled;

/// App version — kept in sync with pubspec.yaml.
const String appVersion = '1.0.0';

const String _kRepoUrl = 'https://github.com/Tangmjiu/moodpet';
const String _kMarketUrl = 'https://github.com/Tangmjiu/moodpet-plugin-market';
const String _kAfdianUrl = 'https://www.ifdian.net/a/mjiutang';
const String _kContributorsApi =
    'https://api.github.com/repos/Tangmjiu/moodpet/contributors?per_page=30';

Future<void> _launchUrl(String url) async {
  final uri = Uri.parse(url);
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

class AboutPage extends StatefulWidget {
  const AboutPage({super.key});

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  late Future<List<_Contributor>> _contributorsFuture = _fetchContributors();

  static Future<List<_Contributor>> _fetchContributors() async {
    final response = await http.get(
      Uri.parse(_kContributorsApi),
      headers: const {
        'Accept': 'application/vnd.github+json',
        'User-Agent': 'MoodPet',
      },
    );
    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! List) {
      throw const FormatException('Unexpected contributors payload');
    }
    return [
      for (final item in decoded)
        if (item is Map<String, dynamic>) _Contributor.fromJson(item),
    ];
  }

  void _retryContributors() {
    setState(() => _contributorsFuture = _fetchContributors());
  }

  Future<void> _copyVersion() async {
    await Clipboard.setData(
      const ClipboardData(text: 'MoodPet $appVersion'),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已复制')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('关于')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: kSpace16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: kSpace24),
              // 1. Brand hero.
              _FadeSlideIn(
                child: _BrandHero(theme: theme, cs: cs),
              ),
              const SizedBox(height: kSpace32),
              // 2. Version card.
              _FadeSlideIn(
                order: 1,
                child: ClayContainer(
                  radius: kRadiusLg,
                  child: Row(
                    children: [
                      IconBadge(
                        icon: Icons.info_outline,
                        backgroundColor: cs.primaryContainer,
                        foregroundColor: cs.onPrimaryContainer,
                      ),
                      const SizedBox(width: kSpace16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '版本',
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              appVersion,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.copy_rounded),
                        tooltip: '复制版本号',
                        onPressed: _copyVersion,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: kSpace16),
              // 3. Contributors card (GitHub).
              _FadeSlideIn(
                order: 2,
                child: ClayContainer(
                  radius: kRadiusLg,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          IconBadge(
                            icon: Icons.people_outline_rounded,
                            backgroundColor: cs.secondaryContainer,
                            foregroundColor: cs.onSecondaryContainer,
                          ),
                          const SizedBox(width: kSpace16),
                          Expanded(
                            child: Text(
                              '贡献者',
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          Icon(
                            Icons.code_rounded,
                            size: 20,
                            color: cs.onSurfaceVariant,
                          ),
                        ],
                      ),
                      const SizedBox(height: kSpace16),
                      FutureBuilder<List<_Contributor>>(
                        future: _contributorsFuture,
                        builder: (context, snapshot) {
                          if (snapshot.connectionState !=
                              ConnectionState.done) {
                            return const SizedBox(
                              height: 60,
                              child: Center(
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            );
                          }
                          if (snapshot.hasError) {
                            return Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    '贡献者获取失败',
                                    style: theme.textTheme.bodySmall,
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.refresh_rounded),
                                  tooltip: '重试',
                                  onPressed: _retryContributors,
                                ),
                              ],
                            );
                          }
                          final contributors =
                              snapshot.data ?? const <_Contributor>[];
                          if (contributors.isEmpty) {
                            return Text(
                              '暂无贡献者数据',
                              style: theme.textTheme.bodySmall,
                            );
                          }
                          return Wrap(
                            spacing: kSpace8,
                            runSpacing: kSpace8,
                            children: [
                              for (final c in contributors)
                                _ContributorChip(contributor: c),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: kSpace16),
              // 4. 爱发电 support card — warm gradient, whole card tappable.
              _FadeSlideIn(
                order: 3,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        cs.primary.withValues(alpha: 0.08),
                        cs.tertiary.withValues(alpha: 0.08),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(kRadiusLg),
                    boxShadow: clayShadows(context),
                  ),
                  child: Material(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(kRadiusLg),
                    child: InkWell(
                      onTap: () => _launchUrl(_kAfdianUrl),
                      borderRadius: BorderRadius.circular(kRadiusLg),
                      child: Padding(
                        padding: const EdgeInsets.all(kSpace20),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            IconBadge(
                              icon: Icons.favorite_rounded,
                              backgroundColor: cs.primaryContainer,
                              foregroundColor: cs.onPrimaryContainer,
                              size: 48,
                              iconSize: 24,
                            ),
                            const SizedBox(width: kSpace16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '爱发电',
                                    style:
                                        theme.textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '支持这个项目，让它持续成长',
                                    style: theme.textTheme.bodySmall,
                                  ),
                                  const SizedBox(height: kSpace12),
                                  FilledButton.tonalIcon(
                                    icon: const Icon(
                                      Icons.open_in_new_rounded,
                                      size: 18,
                                    ),
                                    label: const Text('前往爱发电'),
                                    onPressed: () => _launchUrl(_kAfdianUrl),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: kSpace16),
              // 5. Open source info card.
              _FadeSlideIn(
                order: 4,
                child: ClayContainer(
                  radius: kRadiusLg,
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      _InfoRow(
                        icon: Icons.balance_rounded,
                        title: '开源协议',
                        trailing: Text(
                          'AGPL-3.0',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: cs.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const _RowDivider(),
                      _InfoRow(
                        icon: Icons.code_rounded,
                        title: '源代码',
                        trailing: _LinkText(
                          label: 'GitHub',
                          url: _kRepoUrl,
                        ),
                      ),
                      const _RowDivider(),
                      _InfoRow(
                        icon: Icons.store_outlined,
                        title: '插件市场',
                        trailing: _LinkText(
                          label: 'GitHub',
                          url: _kMarketUrl,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: kSpace32),
              // 6. Footer.
              Text(
                '用 ♥ 制作',
                textAlign: TextAlign.center,
                style: theme.textTheme.labelMedium,
              ),
              const SizedBox(height: kSpace32),
            ],
          ),
        ),
      ),
    );
  }
}

/// A GitHub contributor, parsed from the REST API payload.
class _Contributor {
  final String login;
  final String avatarUrl;
  final String profileUrl;
  final int contributions;

  const _Contributor({
    required this.login,
    required this.avatarUrl,
    required this.profileUrl,
    required this.contributions,
  });

  factory _Contributor.fromJson(Map<String, dynamic> json) {
    return _Contributor(
      login: json['login'] as String? ?? '',
      avatarUrl: json['avatar_url'] as String? ?? '',
      profileUrl: json['html_url'] as String? ?? '',
      contributions: json['contributions'] as int? ?? 0,
    );
  }
}

/// A pill chip for one contributor: avatar, login and contribution count.
/// Tapping opens their GitHub profile. 48dp-tall touch target.
class _ContributorChip extends StatelessWidget {
  final _Contributor contributor;

  const _ContributorChip({required this.contributor});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Material(
      color: cs.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(kRadiusLg),
      child: InkWell(
        onTap: contributor.profileUrl.isEmpty
            ? null
            : () => _launchUrl(contributor.profileUrl),
        borderRadius: BorderRadius.circular(kRadiusLg),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
              kSpace8, kSpace8, kSpace12, kSpace8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: cs.surfaceContainerHighest,
                backgroundImage: contributor.avatarUrl.isEmpty
                    ? null
                    : NetworkImage(contributor.avatarUrl),
                child: contributor.avatarUrl.isEmpty
                    ? Icon(Icons.person_rounded,
                        size: 18, color: cs.onSurfaceVariant)
                    : null,
              ),
              const SizedBox(width: kSpace8),
              Text(
                contributor.login,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: cs.onSurface,
                ),
              ),
              const SizedBox(width: kSpace4),
              Text(
                '×${contributor.contributions}',
                style: theme.textTheme.labelSmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One row in the open-source info card: icon badge + title + trailing.
class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final Widget trailing;

  const _InfoRow({
    required this.icon,
    required this.title,
    required this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: kSpace16, vertical: kSpace12),
      child: Row(
        children: [
          IconBadge(
            icon: icon,
            backgroundColor: cs.surfaceContainerHighest,
            foregroundColor: cs.onSurface,
            size: 40,
            iconSize: 20,
          ),
          const SizedBox(width: kSpace16),
          Expanded(
            child: Text(
              title,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          trailing,
        ],
      ),
    );
  }
}

/// A tappable link label used as an [_InfoRow] trailing. Padded to keep a
/// 48dp touch target.
class _LinkText extends StatelessWidget {
  final String label;
  final String url;

  const _LinkText({required this.label, required this.url});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return InkWell(
      onTap: () => _launchUrl(url),
      borderRadius: BorderRadius.circular(kRadiusSm),
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: kSpace12, vertical: kSpace12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: cs.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: kSpace4),
            Icon(Icons.open_in_new_rounded, size: 14, color: cs.primary),
          ],
        ),
      ),
    );
  }
}

/// Indented divider between [_InfoRow]s, aligned past the icon badge.
class _RowDivider extends StatelessWidget {
  const _RowDivider();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(left: kSpace16 + 40 + kSpace16),
      child: Divider(
        height: 1,
        color: cs.outlineVariant.withValues(alpha: 0.4),
      ),
    );
  }
}

/// Brand hero: app orb + name + tagline.
class _BrandHero extends StatelessWidget {
  final ThemeData theme;
  final ColorScheme cs;

  const _BrandHero({required this.theme, required this.cs});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 120,
          height: 120,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                cs.primaryContainer,
                cs.primaryContainer.withValues(alpha: 0.35),
              ],
            ),
            boxShadow: clayShadows(context, intensity: 1.2),
          ),
          child: const Center(
            child: Text('🥳', style: TextStyle(fontSize: 56)),
          ),
        ),
        const SizedBox(height: kSpace20),
        Text(
          'MoodPet',
          style: theme.textTheme.displayMedium?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: kSpace8),
        Text(
          '一切皆插件的开源共生情感体平台',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: cs.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// Staggered M3 Expressive entrance: fade + slide up (emphasized decelerate).
/// Under reduced-motion the slide is dropped, keeping the fade only.
class _FadeSlideIn extends StatelessWidget {
  final Widget child;
  final int order;

  const _FadeSlideIn({required this.child, this.order = 0});

  @override
  Widget build(BuildContext context) {
    final reduce = reducedMotionEnabled(context);
    final begin = (order * 0.12).clamp(0.0, 0.6);

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: kMotionMedium,
      curve: Interval(begin, 1, curve: kCurveEnter),
      child: child,
      builder: (context, t, child) {
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: reduce ? Offset.zero : Offset(0, 24 * (1 - t)),
            child: child,
          ),
        );
      },
    );
  }
}
