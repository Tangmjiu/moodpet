import '../utils/country_name_mapping.dart';

/// 地区归类：PRC 仅含 CN / HK / MO，其余（包括 TW）均为 OTHER。
enum AppRegion { prc, other }

/// IP 地理位置信息。
class RegionInfo {
  const RegionInfo({
    required this.countryCode,
    required this.countryName,
    this.region,
    this.city,
    this.district,
  });

  final String countryCode;
  final String countryName;
  final String? region;
  final String? city;
  final String? district;

  String get flag => countryFlag(countryCode);

  AppRegion get regionClass =>
      const {'CN', 'HK', 'MO'}.contains(countryCode.toUpperCase())
          ? AppRegion.prc
          : AppRegion.other;

  /// 完整显示字符串：flag + 国家 + 省份/州 + 城市 + 区/县（逐级去重）。
  String get displayText {
    final parts = <String>[
      countryName,
      if (region != null && region!.trim().isNotEmpty)
        region!.trim(),
      if (city != null && city!.trim().isNotEmpty) city!.trim(),
      if (district != null && district!.trim().isNotEmpty)
        district!.trim(),
    ];
    final unique = <String>[];
    for (final part in parts) {
      if (part.trim().isEmpty) continue;
      if (unique.any((existing) => existing == part)) continue;
      unique.add(part);
    }
    return '$flag ${unique.join(' ')}';
  }

  factory RegionInfo.fromJson(Map<String, dynamic> json) {
    final code = ((json['countryCode'] as String?) ?? 'UN').toUpperCase();
    final rawCountry = (json['country'] as String?) ?? '';
    return RegionInfo(
      countryCode: code,
      countryName: countryNameOf(code, fallback: rawCountry),
      region: localizeAdminArea(code, (json['regionName'] as String?)),
      city: localizeAdminArea(code, (json['city'] as String?)),
      district: localizeAdminArea(code, (json['district'] as String?)),
    );
  }

  @override
  String toString() => displayText;
}
