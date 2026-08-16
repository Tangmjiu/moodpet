import 'package:dio/dio.dart';

import '../models/region_info.dart';

class RegionDetectionException implements Exception {
  const RegionDetectionException(this.message);

  final String message;

  @override
  String toString() => 'RegionDetectionException: $message';
}

/// 通过 ip-api.com 检测 IP 地理位置（免费 HTTP 端点）。
class RegionDetector {
  RegionDetector({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 6),
              receiveTimeout: const Duration(seconds: 6),
              responseType: ResponseType.json,
            ));

  final Dio _dio;

  static const String _endpoint = 'http://ip-api.com/json/';

  Future<RegionInfo> detect() async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        _endpoint,
        queryParameters: {
          'fields':
              'status,message,countryCode,country,regionName,city,district,query',
        },
      );
      final data = response.data;
      if (data == null) {
        throw const RegionDetectionException('地区接口返回为空');
      }
      if (data['status'] != 'success') {
        throw RegionDetectionException(
          '地区检测失败：${data['message'] ?? data['status']}',
        );
      }
      final info = RegionInfo.fromJson(data);
      if (info.countryCode == 'UN') {
        throw const RegionDetectionException('无法解析国家代码');
      }
      return info;
    } on RegionDetectionException {
      rethrow;
    } on DioException catch (e) {
      throw RegionDetectionException(
        switch (e.type) {
          DioExceptionType.connectionTimeout ||
          DioExceptionType.receiveTimeout ||
          DioExceptionType.sendTimeout =>
            '地区检测超时，已使用默认分组',
          DioExceptionType.connectionError => '网络不可达，已使用默认分组',
          _ => '地区检测异常：${e.message}',
        },
      );
    } catch (e) {
      throw RegionDetectionException('地区检测异常：$e');
    }
  }
}
