/// Market repository: fetch plugin market data from GitHub.
///
/// The market lives in a public GitHub repository (see `market_config.dart`).
/// This repository layer talks to two GitHub surfaces:
///
///  * **Contents API** — discovers which plugins exist in a directory. The
///    directory listing *is* the index (no `index.json` to maintain).
///  * **Raw files** — downloads `.meta.json`, `.mood*` packages and `.png`
///    previews. Raw downloads are CDN-served and do not count against the API
///    rate limit.
///
/// All network access goes through a `package:http` client, mirroring the
/// style of `llm_client.dart`: a per-instance client (injectable for tests),
/// `timeout()`, a 200-status guard, and `jsonDecode`. Failures throw
/// [MarketException] so the UI's `AsyncValue.error` can render them.
///
/// Caching is delegated to [MarketCache]; this layer only checks the cache and
/// stores results, never owns TTL logic.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/plugin_type.dart';
import 'market_cache.dart';
import 'market_config.dart';

/// Parsed `.meta.json` — the market-display overlay for a plugin.
///
/// Field names align with the on-disk `manifest.json` base fields
/// (`id`/`type`/`name`/`description`/`version`/`author`/`platforms`) so the
/// market card and the installed plugin never drift, plus display-only fields
/// (`fileSize`/`downloads`/`rating`) that have no runtime meaning.
class MarketPlugin {
  /// Plugin id (reverse-DNS), matches the package's `manifest.json` `id`.
  final String id;

  /// Plugin kind.
  final PluginType type;

  /// Display name.
  final String name;

  /// One-line description.
  final String description;

  /// Semantic version string.
  final String version;

  /// Author or org.
  final String author;

  /// Supported platforms (typed).
  final List<PlatformId> platforms;

  /// Optional relative path to the in-package icon asset.
  final String? icon;

  /// Display-only file size label, e.g. `"12KB"`. `null` when omitted.
  final String? fileSize;

  /// Display-only download count. `0` when omitted.
  final int downloads;

  /// Display-only rating (0–5). `0` when omitted.
  final double rating;

  /// Which market directory this entry came from.
  final MarketDir dir;

  const MarketPlugin({
    required this.id,
    required this.type,
    required this.name,
    required this.description,
    required this.version,
    required this.author,
    required this.platforms,
    required this.dir,
    this.icon,
    this.fileSize,
    this.downloads = 0,
    this.rating = 0,
  });

  /// Parse a `.meta.json` object. Throws [FormatException] on missing/invalid
  /// required fields — a malformed market entry should fail loudly.
  factory MarketPlugin.fromJson(Map<String, Object?> json,
      {required MarketDir dir}) {
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
          'meta.json requires string id/type/name/description/version/author');
    }
    final platformsRaw = json['platforms'];
    if (platformsRaw is! List) {
      throw const FormatException('meta.json platforms must be an array');
    }
    final platforms = platformsRaw
        .whereType<String>()
        .map(PlatformId.fromString)
        .toList(growable: false);

    final downloadsRaw = json['downloads'];
    final ratingRaw = json['rating'];

    return MarketPlugin(
      id: id,
      type: PluginType.fromString(typeRaw),
      name: name,
      description: description,
      version: version,
      author: author,
      platforms: platforms,
      dir: dir,
      icon: json['icon'] as String?,
      fileSize: json['fileSize'] as String?,
      downloads: downloadsRaw is int ? downloadsRaw : 0,
      rating: ratingRaw is num ? ratingRaw.toDouble() : 0,
    );
  }
}

/// The market repository: GitHub networking + cache lookup.
class MarketRepository {
  final MarketConfig config;
  final MarketCache cache;

  final http.Client _client;
  final bool _ownsClient;

  /// Construct with an optional [client] (mainly for tests). When `null`, a
  /// short-lived client is created and closed by [dispose].
  MarketRepository(this.config, this.cache, {http.Client? client})
      : _client = client ?? http.Client(),
        _ownsClient = client == null;

  /// Release the owned HTTP client (no-op when a client was injected).
  void dispose() {
    if (_ownsClient) _client.close();
  }

  // ── directory listing ─────────────────────────────────────────────────────

  /// List all plugins in [dir] with their full metadata.
  ///
  /// Uses the cached directory listing (5 min TTL) to know *which* ids exist,
  /// then fetches each plugin's metadata (1 h TTL) — so a warm listing is
  /// served entirely from memory with no network. Plugins whose meta fetch
  /// fails are silently skipped (a broken market entry does not abort the
  /// whole listing), mirroring `plugin_loader`'s per-plugin tolerance.
  Future<List<MarketPlugin>> listDirectory(MarketDir dir) async {
    var refs = cache.getDirectory(dir);
    if (refs == null) {
      refs = await _fetchContents(dir);
      cache.putDirectory(dir, refs);
    }
    final plugins = <MarketPlugin>[];
    for (final ref in refs) {
      try {
        plugins.add(await fetchMeta(dir, ref.id));
      } on MarketException {
        // Skip a plugin whose meta cannot be fetched; the validator should
        // have caught it before merge, but be defensive at runtime too.
        continue;
      }
    }
    return plugins;
  }

  /// Force-refresh a directory: drop the cached listing + all its metas, then
  /// re-list. Used by pull-to-refresh.
  Future<List<MarketPlugin>> refreshDirectory(MarketDir dir) async {
    cache.invalidateDirectory(dir);
    return listDirectory(dir);
  }

  // ── single-plugin fetches ─────────────────────────────────────────────────

  /// Fetch one plugin's metadata (cache → network). Throws [MarketException]
  /// on network/HTTP failures.
  Future<MarketPlugin> fetchMeta(MarketDir dir, String id) async {
    final cached = cache.getMeta(dir, id);
    if (cached != null) {
      return MarketPlugin.fromJson(cached, dir: dir);
    }
    final json = await _getJson(config.rawUrl(config.metaPath(dir, id)),
        headers: config.rawHeaders);
    if (json is! Map<String, Object?>) {
      throw const MarketException('meta.json is not a JSON object');
    }
    cache.putMeta(dir, id, json);
    return MarketPlugin.fromJson(json, dir: dir);
  }

  /// Download a plugin package to the on-disk cache and return the [File].
  /// Packages are cached permanently. [onProgress] (optional) receives 0.0–1.0
  /// as bytes stream in, so the UI can show a determinate progress bar. Throws
  /// [MarketException] on failure.
  Future<File> downloadPackage(
    MarketDir dir,
    String id, {
    void Function(double progress)? onProgress,
  }) async {
    final cached = cache.getPackage(dir, id);
    if (cached != null) return cached;
    final bytes = await _getStreamingBytes(
        config.rawUrl(config.packagePath(dir, id)),
        headers: config.rawHeaders,
        onProgress: onProgress);
    return cache.putPackage(dir, id, bytes);
  }

  /// Fetch a plugin's preview image to the on-disk cache and return the [File].
  /// Images are cached for 7 days. Throws [MarketException] on failure.
  Future<File> fetchPreview(MarketDir dir, String id) async {
    final cached = cache.getImage(dir, id);
    if (cached != null) return cached;
    final bytes = await _getBytes(
        config.rawUrl(config.previewPath(dir, id)),
        headers: config.rawHeaders);
    return cache.putImage(dir, id, bytes);
  }

  // ── HTTP helpers ──────────────────────────────────────────────────────────

  /// Fetch the GitHub Contents API listing for [dir] and extract the plugin
  /// ids (the `.meta.json` filename stems).
  Future<List<MarketPluginRef>> _fetchContents(MarketDir dir) async {
    final json = await _getJson(config.contentsApiUrl(dir),
        headers: config.apiHeaders);
    if (json is! List) {
      throw MarketException('contents API did not return a JSON array');
    }
    final refs = <MarketPluginRef>[];
    for (final entry in json) {
      if (entry is! Map<String, Object?>) continue;
      final name = entry['name'];
      if (name is! String) continue;
      if (!name.endsWith('.meta.json')) continue;
      final id = name.substring(0, name.length - '.meta.json'.length);
      refs.add(MarketPluginRef(id: id, dir: dir));
    }
    return refs;
  }

  Future<Object?> _getJson(
    String url, {
    required Map<String, String> headers,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final response = await _client.get(Uri.parse(url), headers: headers).timeout(timeout);
    if (response.statusCode != 200) {
      throw MarketException(
        'HTTP ${response.statusCode}: ${_truncate(response.body, 200)}',
        response.statusCode,
      );
    }
    try {
      return jsonDecode(response.body);
    } on FormatException {
      throw MarketException('response is not valid JSON', response.statusCode);
    }
  }

  /// Stream a binary response, reporting download progress via [onProgress].
  ///
  /// Uses `http.Client.send` to obtain a `StreamedResponse` and accumulates
  /// chunks into one byte list. Progress is `collected / total` when the server
  /// sends a `Content-Length`; when it is unknown the caller falls back to an
  /// indeterminate indicator (the callback is simply not invoked).
  Future<List<int>> _getStreamingBytes(
    String url, {
    required Map<String, String> headers,
    void Function(double progress)? onProgress,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final request = http.Request('GET', Uri.parse(url));
    request.headers.addAll(headers);
    final response = await _client.send(request).timeout(timeout);
    if (response.statusCode != 200) {
      final body = await response.stream.bytesToString();
      throw MarketException(
        'HTTP ${response.statusCode}: ${_truncate(body, 200)}',
        response.statusCode,
      );
    }
    final total = response.contentLength;
    final collected = <int>[];
    await response.stream.forEach((chunk) {
      collected.addAll(chunk);
      if (onProgress != null && total != null && total > 0) {
        onProgress(collected.length / total);
      }
    });
    return collected;
  }

  Future<List<int>> _getBytes(
    String url, {
    required Map<String, String> headers,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final response =
        await _client.get(Uri.parse(url), headers: headers).timeout(timeout);
    if (response.statusCode != 200) {
      throw MarketException(
        'HTTP ${response.statusCode}: ${_truncate(response.body, 200)}',
        response.statusCode,
      );
    }
    return response.bodyBytes;
  }
}

String _truncate(String s, int max) => s.length <= max ? s : '${s.substring(0, max)}…';
