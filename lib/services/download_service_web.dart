class DownloadResult {
  const DownloadResult({required this.path});

  final String path;
}

class DownloadService {
  Future<DownloadResult> downloadToRelaxationFolder(
    String url, {
    required String title,
    void Function(int received, int total)? onProgress,
  }) {
    throw const DownloadException('Downloads are handled by the browser.');
  }

  Future<List<DownloadHistoryItem>> loadHistory() async => const [];

  Future<void> addHistory(DownloadHistoryItem item) async {}

  Future<void> clearHistory() async {}
}

class DownloadHistoryItem {
  const DownloadHistoryItem({
    required this.title,
    required this.path,
    required this.savedAt,
  });

  final String title;
  final String path;
  final DateTime savedAt;

  String encode() => '${savedAt.toIso8601String()}\n$title\n$path';

  static DownloadHistoryItem? tryParse(String value) => null;
}

class DownloadException implements Exception {
  const DownloadException(this.message);

  final String message;

  @override
  String toString() => message;
}
