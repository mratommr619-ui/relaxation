import 'package:dio/dio.dart';

class ResolvedTelegramMedia {
  const ResolvedTelegramMedia({
    required this.streamUrl,
    required this.downloadUrl,
  });

  final String streamUrl;
  final String downloadUrl;
}

class TelethonResolver {
  TelethonResolver({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;

  Future<ResolvedTelegramMedia> resolve({
    required String ingestBaseUrl,
    required String telegramUrl,
  }) async {
    final base = ingestBaseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    if (base.isEmpty) {
      throw const TelethonResolveException('Playback server URL is missing.');
    }
    if (telegramUrl.trim().isEmpty) {
      throw const TelethonResolveException('Video source link is missing.');
    }
    final response = await _dio.post<Map<String, dynamic>>(
      '$base/resolve',
      data: {'telegram_url': telegramUrl.trim()},
    );
    final data = response.data ?? {};
    final streamUrl = (data['streamUrl'] ?? '').toString();
    final downloadUrl = (data['downloadUrl'] ?? '').toString();
    if (streamUrl.isEmpty || downloadUrl.isEmpty) {
      throw const TelethonResolveException(
        'Playback server did not return stream links.',
      );
    }
    return ResolvedTelegramMedia(
      streamUrl: streamUrl,
      downloadUrl: downloadUrl,
    );
  }
}

class TelethonResolveException implements Exception {
  const TelethonResolveException(this.message);

  final String message;

  @override
  String toString() => message;
}
