/// Market configuration: GitHub repository coordinates and URL builders.
///
/// The MoodPet plugin market is distributed entirely via a GitHub repository
/// (zero server cost). The container reads the directory listing through the
/// GitHub Contents API and fetches plugin packages / previews / metadata via
/// `raw.githubusercontent.com`. This module holds the repo coordinates and
/// builds the correct URLs so the repository layer stays pure networking.
///
/// An optional [token] raises the unauthenticated GitHub API rate limit
/// (60 req/hour/IP) to 5000 req/hour. Raw downloads are never rate-limited.
library;

/// One of the three plugin directories in the market repository.
///
/// Each [MarketDir] carries its on-disk path *and* the plugin-package suffix
/// used in that directory, so callers never mix the two.
enum MarketDir {
  /// Friend plugins — emotion partner identity packs.
  friend('friend', '.moodfriend'),

  /// Application plugins — capability packs.
  application('application', '.moodapp'),

  /// Packs — bundles of Friend + Application plugins.
  packs('packs', '.moodpack');

  /// Directory name inside the market repository.
  final String path;

  /// Plugin-package file suffix used in this directory.
  final String suffix;

  const MarketDir(this.path, this.suffix);
}

/// GitHub repository coordinates for the plugin market.
///
/// Construct with [defaultMarketConfig] for the official community market, or
/// a custom instance to point at a fork / private mirror. All URL builders are
/// derived from these four fields so the repository layer has no hard-coded
/// endpoints.
class MarketConfig {
  /// Repository owner (user or org login), e.g. `Tangmjiu`.
  final String owner;

  /// Repository name, e.g. `moodpet-plugin-market`.
  final String repo;

  /// Branch / ref to read from, e.g. `main`.
  final String branch;

  /// Optional GitHub token to raise the Contents API rate limit. `null` uses
  /// unauthenticated access (60 req/hour/IP). Never sent to raw URLs.
  final String? token;

  const MarketConfig({
    required this.owner,
    required this.repo,
    required this.branch,
    this.token,
  });

  /// The official community plugin market.
  static const MarketConfig defaultConfig = MarketConfig(
    owner: 'Tangmjiu',
    repo: 'moodpet-plugin-market',
    branch: 'main',
  );

  /// Contents API URL for a plugin directory: returns the file listing.
  ///
  /// `GET https://api.github.com/repos/{owner}/{repo}/contents/{dir}?ref={branch}`.
  /// The response is a JSON array of `{name, path, download_url, type, ...}`.
  String contentsApiUrl(MarketDir dir) =>
      'https://api.github.com/repos/$owner/$repo/contents/${dir.path}?ref=$branch';

  /// Raw URL for a file at [relPath] inside the repository on [branch].
  ///
  /// `https://raw.githubusercontent.com/{owner}/{repo}/{branch}/{relPath}`.
  /// Raw downloads are served via CDN and do not consume the API rate limit.
  String rawUrl(String relPath) =>
      'https://raw.githubusercontent.com/$owner/$repo/$branch/$relPath';

  /// Repository-relative path of a plugin's `.meta.json` in [dir].
  String metaPath(MarketDir dir, String id) => '${dir.path}/$id.meta.json';

  /// Repository-relative path of a plugin's package file in [dir].
  String packagePath(MarketDir dir, String id) =>
      '${dir.path}/$id${dir.suffix}';

  /// Repository-relative path of a plugin's preview image in [dir].
  String previewPath(MarketDir dir, String id) => '${dir.path}/$id.png';

  /// HTTP headers for GitHub API calls (accept + optional auth).
  Map<String, String> get apiHeaders => <String, String>{
        'Accept': 'application/vnd.github+json',
        'User-Agent': 'MoodPet-PluginMarket',
        if (token != null && token!.isNotEmpty)
          'Authorization': 'Bearer ${token!}',
      };

  /// HTTP headers for raw downloads (no auth needed; User-Agent still polite).
  Map<String, String> get rawHeaders => <String, String>{
        'User-Agent': 'MoodPet-PluginMarket',
      };
}

/// A recoverable market-layer error surfaced to the UI as a human message.
///
/// Mirrors the `LlmResult.fail` convention from `llm_client.dart` but as an
/// exception so the repository can throw and the UI's `.when(error:)` can
/// render it. Carries the HTTP status when relevant for diagnostics.
class MarketException implements Exception {
  final String message;
  final int statusCode;

  const MarketException(this.message, [this.statusCode = 0]);

  @override
  String toString() => statusCode == 0
      ? 'MarketException: $message'
      : 'MarketException ($statusCode): $message';
}
