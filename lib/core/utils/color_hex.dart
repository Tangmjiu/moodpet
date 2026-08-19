/// Color hex parsing helper — converts `#RRGGBB` strings (as emitted by the
/// agent and emoji mapping) into `dart:ui` [Color]s for the UI layer.
library;

import 'dart:ui';

/// Parse a `#RRGGBB` or `#AARRGGBB` hex string into a [Color].
///
/// Returns [Colors.grey] when the string is malformed.
Color parseHexColor(String hex) {
  var h = hex.trim();
  if (h.startsWith('#')) h = h.substring(1);
  if (h.length == 6) {
    h = 'FF$h';
  } else if (h.length != 8) {
    return const Color(0xFF9E9E9E);
  }
  final value = int.tryParse(h, radix: 16);
  if (value == null) return const Color(0xFF9E9E9E);
  return Color(value);
}
