/// Region detection result (§5.2 Step 3 — "自动检测地区推荐提供商").
///
/// Detection is offline and best-effort: locale country code + timezone name.
/// When the two agree the result is [confident]; when they disagree or either
/// is unavailable, the locale country wins but `confident` is `false`.
///
/// For China (CN), detection is precise to the province/municipality level
/// using the timezone name (e.g. `Asia/Shanghai` → 上海市, `Asia/Urumqi` →
/// 新疆维吾尔自治区). HK/MO/TW are treated as special regions with their
/// own display names (香港特别行政区 / 澳门特别行政区 / 中国台湾).
library;

/// A detected region.
class RegionInfo {
  /// ISO 3166-1 alpha-2 country code, e.g. `CN`, `US`, `JP`, `HK`, `TW`.
  /// `null` when detection failed entirely.
  final String? countryCode;

  /// Human-readable country name in Chinese, e.g. `中国`, `美国`.
  final String? countryName;

  /// For China (CN), the detected province/municipality/autonomous region
  /// name in Chinese, e.g. `上海市`, `广东省`, `新疆维吾尔自治区`.
  /// `null` for non-CN regions or when sub-region detection failed.
  final String? provinceName;

  /// An emoji flag or symbol representing the detected region.
  /// For countries: the ISO 3166-1 flag emoji (🇨🇳, 🇺🇸, 🇯🇵…).
  /// For CN sub-regions: the province's emoji (见 [kProvinceEmojis]).
  final String? emoji;

  /// Whether detection was confident (locale country agreed with timezone).
  final bool confident;

  const RegionInfo({
    required this.countryCode,
    required this.countryName,
    this.provinceName,
    this.emoji,
    required this.confident,
  });

  /// Unknown region — used when every detection heuristic failed.
  static const RegionInfo unknown = RegionInfo(
    countryCode: null,
    countryName: null,
    provinceName: null,
    emoji: null,
    confident: false,
  );

  /// A human-readable display string combining country + province.
  String get displayText {
    if (countryName == null) return '未知地区';
    if (provinceName != null) return '$countryName · $provinceName';
    return countryName!;
  }

  @override
  bool operator ==(Object other) =>
      other is RegionInfo &&
      other.countryCode == countryCode &&
      other.countryName == countryName &&
      other.provinceName == provinceName;

  @override
  int get hashCode => Object.hash(countryCode, countryName, provinceName);
}

// ---- Country names --------------------------------------------------------

/// ISO-3166-1 alpha-2 → Chinese country-name table.
/// CN/HK/MO/TW have special names per user requirement.
const Map<String, String> kCountryNames = <String, String>{
  'CN': '中国大陆', 'US': '美国', 'JP': '日本', 'KR': '韩国', 'GB': '英国',
  'DE': '德国', 'FR': '法国', 'CA': '加拿大', 'AU': '澳大利亚', 'SG': '新加坡',
  'TW': '中国台湾', 'HK': '香港特别行政区', 'MO': '澳门特别行政区',
  'IN': '印度', 'BR': '巴西', 'RU': '俄罗斯', 'IT': '意大利', 'ES': '西班牙',
  'NL': '荷兰', 'SE': '瑞典', 'CH': '瑞士', 'AT': '奥地利', 'BE': '比利时',
  'FI': '芬兰', 'DK': '丹麦', 'NO': '挪威', 'PL': '波兰', 'TR': '土耳其',
  'MX': '墨西哥', 'ID': '印度尼西亚', 'TH': '泰国', 'VN': '越南',
  'MY': '马来西亚', 'PH': '菲律宾', 'NZ': '新西兰', 'IE': '爱尔兰',
  'PT': '葡萄牙', 'CZ': '捷克', 'HU': '匈牙利', 'RO': '罗马尼亚',
  'IL': '以色列', 'AE': '阿联酋', 'SA': '沙特阿拉伯', 'ZA': '南非',
  'AR': '阿根廷', 'CL': '智利', 'CO': '哥伦比亚', 'EG': '埃及',
  'NG': '尼日利亚', 'KE': '肯尼亚', 'PE': '秘鲁',
};

/// ISO-3166-1 alpha-2 → flag emoji table.
const Map<String, String> kCountryFlagEmojis = <String, String>{
  'CN': '🇨🇳', 'US': '🇺🇸', 'JP': '🇯🇵', 'KR': '🇰🇷', 'GB': '🇬🇧',
  'DE': '🇩🇪', 'FR': '🇫🇷', 'CA': '🇨🇦', 'AU': '🇦🇺', 'SG': '🇸🇬',
  'TW': '🇨🇳', 'HK': '🇨🇳', 'MO': '🇨🇳', 'IN': '🇮🇳', 'BR': '🇧🇷',
  'RU': '🇷🇺', 'IT': '🇮🇹', 'ES': '🇪🇸', 'NL': '🇳🇱', 'SE': '🇸🇪',
  'CH': '🇨🇭', 'AT': '🇦🇹', 'BE': '🇧🇪', 'FI': '🇫🇮', 'DK': '🇩🇰',
  'NO': '🇳🇴', 'PL': '🇵🇱', 'TR': '🇹🇷', 'MX': '🇲🇽', 'ID': '🇮🇩',
  'TH': '🇹🇭', 'VN': '🇻🇳', 'MY': '🇲🇾', 'PH': '🇵🇭', 'NZ': '🇳🇿',
  'IE': '🇮🇪', 'PT': '🇵🇹', 'CZ': '🇨🇿', 'HU': '🇭🇺', 'RO': '🇷🇴',
  'IL': '🇮🇱', 'AE': '🇦🇪', 'SA': '🇸🇦', 'ZA': '🇿🇦', 'AR': '🇦🇷',
  'CL': '🇨🇱', 'CO': '🇨🇴', 'EG': '🇪🇬', 'NG': '🇳🇬', 'KE': '🇪',
  'PE': '🇵🇪',
};

// ---- China province/municipality/autonomous region table ------------------

/// IANA timezone → Chinese province/municipality/autonomous region name.
/// Used when the country code is CN to detect the sub-region from the
/// timezone. China spans 5 IANA zones; most map to their province.
const Map<String, String> kChinaTimezoneProvinces = <String, String>{
  'Asia/Shanghai': '上海市',
  'Asia/Chongqing': '重庆市',
  'Asia/Harbin': '黑龙江省',
  'Asia/Urumqi': '新疆维吾尔自治区',
  'Asia/Kashgar': '新疆维吾尔自治区',
  // Non-IANA aliases that some platforms report:
  'Asia/Chungking': '重庆市',
  'PRC': '北京市',
  'CTT': '上海市',
};

/// Province/municipality/autonomous region → emoji.
/// China provinces don't have official flag emojis; we use 🏙️ for
/// municipalities (直辖市) and 🗺️ for provinces/autonomous regions.
/// Special administrative regions use their own emojis.
const Map<String, String> kProvinceEmojis = <String, String>{
  '北京市': '🏙️', '上海市': '🏙️', '天津市': '🏙️', '重庆市': '🏙️',
  '广东省': '🗺️', '江苏省': '🗺️', '浙江省': '🗺️', '山东省': '🗺️',
  '河南省': '🗺️', '四川省': '🗺️', '湖北省': '🗺️', '湖南省': '🗺️',
  '河北省': '🗺️', '福建省': '🗺️', '安徽省': '🗺️', '辽宁省': '🗺️',
  '陕西省': '🗺️', '江西省': '🗺️', '广西壮族自治区': '🗺️',
  '云南省': '🗺️', '贵州省': '🗺️', '山西省': '🗺️', '吉林省': '🗺️',
  '黑龙江省': '🗺️', '甘肃省': '🗺️', '海南省': '🗺️', '青海省': '🗺️',
  '内蒙古自治区': '🗺️', '宁夏回族自治区': '🗺️',
  '新疆维吾尔自治区': '🗺️', '西藏自治区': '🗺️',
  '香港特别行政区': '🏙️', '澳门特别行政区': '🏙️',
  '中国台湾': '🗺️',
};

/// Look up a Chinese country name by alpha-2 code; falls back to the code
/// itself (upper-cased) when the country is not in [kCountryNames].
String countryNameFromCode(String? code) {
  if (code == null) return '未知地区';
  final upper = code.toUpperCase();
  return kCountryNames[upper] ?? upper;
}

/// Look up a flag emoji by alpha-2 code. Returns 🌍 when unknown.
String flagEmojiFromCode(String? code) {
  if (code == null) return '🌍';
  final upper = code.toUpperCase();
  return kCountryFlagEmojis[upper] ?? '🌍';
}
