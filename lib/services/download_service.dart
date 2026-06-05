import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DownloadResult {
  const DownloadResult({required this.path});

  final String path;
}

class DownloadService {
  DownloadService({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;
  static const _historyKey = 'relaxationDownloadHistory';

  Future<DownloadResult> downloadToRelaxationFolder(
    String url, {
    required String title,
    void Function(int received, int total)? onProgress,
  }) async {
    if (kIsWeb) {
      throw const DownloadException('Downloads are not supported on web.');
    }
    if (Platform.isAndroid) {
      await _ensurePermission();
    }
    final dir = await _downloadDirectory();
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final fileName = _fileNameFromUrl(url, title);
    final path = '${dir.path}/$fileName';
    await _dio.download(
      url,
      path,
      onReceiveProgress: onProgress,
      options: Options(followRedirects: true, receiveTimeout: Duration.zero),
    );
    return DownloadResult(path: path);
  }

  Future<List<DownloadHistoryItem>> loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final values = prefs.getStringList(_historyKey) ?? const [];
    final items = <DownloadHistoryItem>[];
    for (final value in values) {
      final item = DownloadHistoryItem.tryParse(value);
      if (item != null) items.add(item);
    }
    return items;
  }

  Future<void> addHistory(DownloadHistoryItem item) async {
    final prefs = await SharedPreferences.getInstance();
    final current = await loadHistory();
    final next = [
      item,
      ...current.where((entry) => entry.path != item.path),
    ].take(50).map((entry) => entry.encode()).toList();
    await prefs.setStringList(_historyKey, next);
  }

  Future<void> clearHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_historyKey);
  }

  Future<Directory> _downloadDirectory() async {
    if (Platform.isAndroid) {
      return Directory('/storage/emulated/0/Download/Relaxation');
    }
    final home =
        Platform.environment['USERPROFILE'] ??
        Platform.environment['HOME'] ??
        Directory.current.path;
    return Directory(
      '$home${Platform.pathSeparator}Downloads${Platform.pathSeparator}Relaxation',
    );
  }

  Future<void> _ensurePermission() async {
    final notification = await Permission.notification.status;
    if (notification.isDenied) {
      await Permission.notification.request();
    }

    var storage = await Permission.storage.status;
    if (storage.isDenied) {
      storage = await Permission.storage.request();
    }
    if (storage.isGranted) return;

    var manage = await Permission.manageExternalStorage.status;
    if (manage.isDenied) {
      manage = await Permission.manageExternalStorage.request();
    }
    if (!manage.isGranted) {
      throw const DownloadException(
        'Storage permission denied. Allow file access to save downloads.',
      );
    }
  }

  String _fileNameFromUrl(String url, String title) {
    final uri = Uri.tryParse(url);
    final raw = uri?.pathSegments.isNotEmpty == true
        ? uri!.pathSegments.last
        : title;
    final clean = raw
        .split('?')
        .first
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        .trim();
    final fallback = title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
    final name = clean.isEmpty ? fallback : clean;
    return name.contains('.') ? name : '$name.mp4';
  }
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

  static DownloadHistoryItem? tryParse(String value) {
    final parts = value.split('\n');
    if (parts.length < 3) return null;
    final savedAt = DateTime.tryParse(parts.first);
    if (savedAt == null) return null;
    return DownloadHistoryItem(
      savedAt: savedAt,
      title: parts[1],
      path: parts.sublist(2).join('\n'),
    );
  }
}

class DownloadException implements Exception {
  const DownloadException(this.message);

  final String message;

  @override
  String toString() => message;
}
