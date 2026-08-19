/// Region detection (§5.2 Step 3 — "自动检测地区推荐提供商").
///
/// Best-effort detection from `dart:io` locale + timezone. No network call.
/// For China (CN), detection is precise to province/municipality level using
/// the IANA timezone name. HK/MO/TW are treated as special regions.
library;

import 'dart:io' show Platform;

import '../models/region_info.dart';

/// Detect the user's region from locale and timezone.
RegionInfo detectRegion() {
  final localeCountry = _countryFromLocale(Platform.localeName);
  final tzName = DateTime.now().timeZoneName;

  // HK/MO/TW from locale → use directly.
  if (localeCountry != null) {
    final upper = localeCountry.toUpperCase();
    if (upper == 'HK' || upper == 'MO' || upper == 'TW') {
      return RegionInfo(
        countryCode: upper,
        countryName: kCountryNames[upper],
        emoji: flagEmojiFromCode(upper),
        confident: true,
      );
    }
  }

  // CN → detect province from timezone.
  if (localeCountry != null && localeCountry.toUpperCase() == 'CN') {
    final province = kChinaTimezoneProvinces[tzName] ?? '北京市';
    return RegionInfo(
      countryCode: 'CN',
      countryName: '中国大陆',
      provinceName: province,
      emoji: kProvinceEmojis[province] ?? '🇨🇳',
      confident: true,
    );
  }

  // General case — cross-check locale vs timezone.
  final tzCountry = _countryFromTimezone(tzName);
  if (localeCountry != null && tzCountry != null) {
    final agree = localeCountry.toLowerCase() == tzCountry.toLowerCase();
    return RegionInfo(
      countryCode: localeCountry,
      countryName: countryNameFromCode(localeCountry),
      emoji: flagEmojiFromCode(localeCountry),
      confident: agree,
    );
  }
  if (localeCountry != null) {
    return RegionInfo(
      countryCode: localeCountry,
      countryName: countryNameFromCode(localeCountry),
      emoji: flagEmojiFromCode(localeCountry),
      confident: true,
    );
  }
  if (tzCountry != null) {
    return RegionInfo(
      countryCode: tzCountry,
      countryName: countryNameFromCode(tzCountry),
      emoji: flagEmojiFromCode(tzCountry),
      confident: false,
    );
  }
  return RegionInfo.unknown;
}

String? _countryFromLocale(String locale) {
  final parts = locale.split('_');
  if (parts.length < 2) return null;
  final code = parts[1];
  if (code.length != 2) return null;
  return code.toUpperCase();
}

String? _countryFromTimezone(String tzName) {
  final lower = tzName.toLowerCase();
  if (lower.contains('shanghai') || lower.contains('chongqing') ||
      lower.contains('harbin') || lower.contains('urumqi') ||
      lower.contains('kashgar') || lower.contains('chungking') ||
      lower == 'prc' || lower == 'ctt') {
    return 'CN';
  }
  if (lower.contains('hong_kong') || lower.contains('hong kong')) {
    return 'HK';
  }
  if (lower.contains('macau') || lower.contains('macao')) {
    return 'MO';
  }
  if (lower.contains('taipei') || lower.contains('taiwan')) {
    return 'TW';
  }
  if (lower.contains('tokyo')) {
    return 'JP';
  }
  if (lower.contains('seoul')) {
    return 'KR';
  }
  if (lower.contains('singapore')) {
    return 'SG';
  }
  if (lower.contains('new_york') || lower.contains('chicago') ||
      lower.contains('denver') || lower.contains('los_angeles') ||
      lower.contains('detroit') || lower.contains('anchorage') ||
      lower.contains('honolulu') || lower.contains('phoenix')) {
    return 'US';
  }
  if (lower.contains('london')) {
    return 'GB';
  }
  if (lower.contains('paris')) {
    return 'FR';
  }
  if (lower.contains('berlin')) {
    return 'DE';
  }
  if (lower.contains('madrid')) {
    return 'ES';
  }
  if (lower.contains('rome')) {
    return 'IT';
  }
  if (lower.contains('amsterdam')) {
    return 'NL';
  }
  if (lower.contains('stockholm')) {
    return 'SE';
  }
  if (lower.contains('oslo')) {
    return 'NO';
  }
  if (lower.contains('copenhagen')) {
    return 'DK';
  }
  if (lower.contains('helsinki')) {
    return 'FI';
  }
  if (lower.contains('zurich') || lower.contains('geneva')) {
    return 'CH';
  }
  if (lower.contains('vienna')) {
    return 'AT';
  }
  if (lower.contains('brussels')) {
    return 'BE';
  }
  if (lower.contains('dublin')) {
    return 'IE';
  }
  if (lower.contains('lisbon')) {
    return 'PT';
  }
  if (lower.contains('prague')) {
    return 'CZ';
  }
  if (lower.contains('warsaw')) {
    return 'PL';
  }
  if (lower.contains('moscow')) {
    return 'RU';
  }
  if (lower.contains('istanbul')) {
    return 'TR';
  }
  if (lower.contains('mumbai') || lower.contains('delhi') ||
      lower.contains('kolkata') || lower.contains('bangalore')) {
    return 'IN';
  }
  if (lower.contains('bangkok')) {
    return 'TH';
  }
  if (lower.contains('jakarta')) {
    return 'ID';
  }
  if (lower.contains('manila')) {
    return 'PH';
  }
  if (lower.contains('kuala_lumpur')) {
    return 'MY';
  }
  if (lower.contains('hanoi') || lower.contains('saigon')) {
    return 'VN';
  }
  if (lower.contains('sydney') || lower.contains('melbourne') ||
      lower.contains('brisbane') || lower.contains('perth')) {
    return 'AU';
  }
  if (lower.contains('auckland') || lower.contains('wellington')) {
    return 'NZ';
  }
  if (lower.contains('toronto') || lower.contains('vancouver') ||
      lower.contains('montreal') || lower.contains('edmonton')) {
    return 'CA';
  }
  if (lower.contains('mexico_city')) {
    return 'MX';
  }
  if (lower.contains('sao_paulo') || lower.contains('rio')) {
    return 'BR';
  }
  if (lower.contains('buenos_aires')) {
    return 'AR';
  }
  if (lower.contains('santiago')) {
    return 'CL';
  }
  if (lower.contains('lima')) {
    return 'PE';
  }
  if (lower.contains('bogota')) {
    return 'CO';
  }
  if (lower.contains('cairo')) {
    return 'EG';
  }
  if (lower.contains('lagos')) {
    return 'NG';
  }
  if (lower.contains('nairobi')) {
    return 'KE';
  }
  if (lower.contains('johannesburg')) {
    return 'ZA';
  }
  if (lower.contains('dubai')) {
    return 'AE';
  }
  if (lower.contains('riyadh')) {
    return 'SA';
  }
  if (lower.contains('tel_aviv') || lower.contains('jerusalem')) {
    return 'IL';
  }
  return null;
}

bool isChinaRegion(String? code) =>
    code != null && code.toUpperCase() == 'CN';
