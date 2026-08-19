/// Shared market preview image: fetches a plugin's `.png` preview through the
/// [MarketRepository] (7-day on-disk cache) and shows it cover-fit. While
/// loading, a spinner is visible; on failure, a tinted [IconBadge] placeholder
/// keeps the surface honest (content-first: the image is the focus, the
/// container fades back when no preview exists).
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app.dart' show IconBadge;
import '../../core/market/market_config.dart';
import '../../core/market/market_providers.dart';

/// A market plugin's preview image, resolved asynchronously from the market
/// cache / network. Used by the market grid cards and both detail pages.
class PreviewImage extends ConsumerStatefulWidget {
  final MarketDir dir;
  final String id;

  const PreviewImage({super.key, required this.dir, required this.id});

  @override
  ConsumerState<PreviewImage> createState() => _PreviewImageState();
}

class _PreviewImageState extends ConsumerState<PreviewImage> {
  File? _file;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    ref
        .read(marketRepositoryProvider.future)
        .then((repo) => repo.fetchPreview(widget.dir, widget.id))
        .then((file) {
          if (mounted) setState(() => _file = file);
        })
        .catchError((_) {
          if (mounted) setState(() => _error = true);
        });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final file = _file;
    if (file != null) {
      return Image.file(file, fit: BoxFit.cover, gaplessPlayback: true);
    }
    if (_error) {
      return Container(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        child: const Center(
          child: IconBadge(
            icon: Icons.image_outlined,
            size: 40,
            iconSize: 20,
          ),
        ),
      );
    }
    return Container(
      color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
      child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
    );
  }
}
