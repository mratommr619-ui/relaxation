import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

class LocalTelethonConfig {
  const LocalTelethonConfig({
    required this.apiId,
    required this.apiHash,
    required this.sessionString,
  });

  final int apiId;
  final String apiHash;
  final String sessionString;

  bool get isUsable =>
      apiId > 0 && apiHash.trim().isNotEmpty && sessionString.trim().isNotEmpty;

  bool get hasApiCredentials => apiId > 0 && apiHash.trim().isNotEmpty;
}

class LocalTelethonService {
  LocalTelethonService._();

  static final LocalTelethonService instance = LocalTelethonService._();

  Process? _process;
  String? _baseUrl;

  bool get isSupported {
    if (kIsWeb) return false;
    return Platform.isWindows || Platform.isLinux || Platform.isMacOS;
  }

  Future<String> ensureStarted(LocalTelethonConfig config) async {
    return _ensureStarted(config, requireSession: true);
  }

  Future<String> ensureStartedForLogin(LocalTelethonConfig config) async {
    return _ensureStarted(config, requireSession: false);
  }

  Future<String> _ensureStarted(
    LocalTelethonConfig config, {
    required bool requireSession,
  }) async {
    if (!isSupported) {
      throw const LocalTelethonException(
        'Local Telethon helper is not available on this platform yet.',
      );
    }
    if (!config.hasApiCredentials || (requireSession && !config.isUsable)) {
      throw const LocalTelethonException(
        'Telegram API ID, API hash, or session string is missing.',
      );
    }
    final current = _baseUrl;
    if (current != null && await _isHealthy(current)) {
      return current;
    }

    await stop();
    final port = await _freePort();
    final helperDir = _helperDirectory();
    final executable = _helperExecutable(helperDir);
    final python = executable == null ? _pythonExecutable(helperDir) : null;
    final baseUrl = 'http://127.0.0.1:$port';

    _process = await Process.start(
      executable ?? python!,
      executable == null
          ? [
              '-m',
              'uvicorn',
              'main:app',
              '--host',
              '127.0.0.1',
              '--port',
              '$port',
            ]
          : const [],
      workingDirectory: helperDir.path,
      environment: {
        'TELEGRAM_API_ID': '${config.apiId}',
        'TELEGRAM_API_HASH': config.apiHash.trim(),
        if (config.sessionString.trim().isNotEmpty)
          'TELEGRAM_SESSION_STRING': config.sessionString.trim(),
        'PUBLIC_BASE_URL': baseUrl,
        'PORT': '$port',
      },
      mode: ProcessStartMode.detachedWithStdio,
    );
    _process!.stdout.drain<void>();
    _process!.stderr.drain<void>();

    final deadline = DateTime.now().add(const Duration(seconds: 25));
    while (DateTime.now().isBefore(deadline)) {
      if (await _isHealthy(baseUrl)) {
        _baseUrl = baseUrl;
        return baseUrl;
      }
      await Future<void>.delayed(const Duration(milliseconds: 350));
    }
    await stop();
    throw const LocalTelethonException('Local Telethon helper did not start.');
  }

  Future<void> stop() async {
    _baseUrl = null;
    final process = _process;
    _process = null;
    process?.kill();
  }

  Future<bool> _isHealthy(String baseUrl) async {
    try {
      final response = await Dio().get<dynamic>(
        '$baseUrl/health',
        options: Options(
          sendTimeout: const Duration(seconds: 2),
          receiveTimeout: const Duration(seconds: 2),
        ),
      );
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<int> _freePort() async {
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = socket.port;
    await socket.close();
    return port;
  }

  Directory _helperDirectory() {
    final devDir = Directory(
      '${Directory.current.path}${Platform.pathSeparator}telegram_ingest',
    );
    if (File('${devDir.path}${Platform.pathSeparator}main.py').existsSync()) {
      return devDir;
    }

    final executableDir = File(Platform.resolvedExecutable).parent;
    final packaged = Directory(
      '${executableDir.path}${Platform.pathSeparator}data'
      '${Platform.pathSeparator}flutter_assets'
      '${Platform.pathSeparator}telegram_ingest',
    );
    if (File('${packaged.path}${Platform.pathSeparator}main.py').existsSync()) {
      return packaged;
    }

    throw const LocalTelethonException('Telethon helper files were not found.');
  }

  String _pythonExecutable(Directory helperDir) {
    final override = Platform.environment['TELETHON_PYTHON']?.trim();
    if (override != null && override.isNotEmpty) return override;

    final runtimeName = Platform.isWindows ? 'python.exe' : 'python';
    final bundled = File(
      '${helperDir.parent.path}${Platform.pathSeparator}python'
      '${Platform.pathSeparator}$runtimeName',
    );
    if (bundled.existsSync()) return bundled.path;

    return Platform.isWindows ? 'python' : 'python3';
  }

  String? _helperExecutable(Directory helperDir) {
    final name = Platform.isWindows ? 'telethon_helper.exe' : 'telethon_helper';
    final executableDir = File(Platform.resolvedExecutable).parent;
    final candidates = [
      File('${helperDir.path}${Platform.pathSeparator}$name'),
      File('${executableDir.path}${Platform.pathSeparator}$name'),
      File(
        '${executableDir.path}${Platform.pathSeparator}data'
        '${Platform.pathSeparator}$name',
      ),
      File(
        '${executableDir.path}${Platform.pathSeparator}data'
        '${Platform.pathSeparator}telethon_helper'
        '${Platform.pathSeparator}$name',
      ),
    ];
    for (final candidate in candidates) {
      if (candidate.existsSync()) return candidate.path;
    }
    return null;
  }
}

class LocalTelethonException implements Exception {
  const LocalTelethonException(this.message);

  final String message;

  @override
  String toString() => message;
}
