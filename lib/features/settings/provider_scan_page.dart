/// Full-screen QR scanner for importing a shared provider configuration.
///
/// Pushed from the provider selection page's import chooser. The camera
/// permission prompt is handled by the scanner plugin itself. When a
/// `moodpet-provider:v1:` payload is scanned it is decoded once and the page
/// pops with the decoded [ProviderConfig]; anything else keeps the scanner
/// running.
library;

import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/models/provider_config.dart';
import '../../core/utils/provider_share_codec.dart';

/// Scans a provider-share QR code and pops with the decoded config, or with
/// `null` when the user backs out without a successful scan.
class ProviderScanPage extends StatefulWidget {
  const ProviderScanPage({super.key});

  @override
  State<ProviderScanPage> createState() => _ProviderScanPageState();
}

class _ProviderScanPageState extends State<ProviderScanPage> {
  final MobileScannerController _controller = MobileScannerController();

  /// One-shot guard: `onDetect` fires per camera frame, so the first payload
  /// match latches until it has been decoded or rejected.
  bool _handled = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    // The callback can fire after the page was popped; using the context
    // below (ScaffoldMessenger/Navigator) would then throw.
    if (!mounted) return;
    final raw = capture.barcodes.firstOrNull?.rawValue;
    if (raw == null || !raw.trim().startsWith(kProviderSharePrefix)) return;
    _handled = true;
    final decoded = decodeProviderShare(raw);
    if (decoded == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('二维码无效')),
      );
      // Re-arm after the snackbar has shown so scanning can continue.
      Timer(const Duration(seconds: 2), () {
        if (mounted) _handled = false;
      });
      return;
    }
    Navigator.of(context).pop(decoded);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('扫描提供商二维码'),
        actions: [
          IconButton(
            tooltip: '闪光灯',
            icon: const Icon(Icons.flash_on_rounded),
            onPressed: () => unawaited(_controller.toggleTorch()),
          ),
        ],
      ),
      body: MobileScanner(
        controller: _controller,
        onDetect: _onDetect,
      ),
    );
  }
}
