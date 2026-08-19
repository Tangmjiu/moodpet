/// Pack detail page: same shape as the plugin detail page, reached via
/// `/market/pack`. The pack's constituent list lives inside the `.moodpack`
/// zip (not in `.meta.json`), so instead of fetching the zip just for display
/// this page shows the standard meta plus an honest explanatory note — the
/// installer expands the constituents on install.
library;

import 'package:flutter/material.dart';

import '../../core/market/market_repository.dart';
import 'plugin_detail_page.dart';

class PackDetailPage extends StatelessWidget {
  const PackDetailPage({super.key});

  @override
  Widget build(BuildContext context) {
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is! MarketPlugin) {
      return Scaffold(
        appBar: AppBar(title: const Text('整合包详情')),
        body: const Center(child: Text('参数错误')),
      );
    }
    return PluginDetailBody(plugin: args, isPack: true);
  }
}
