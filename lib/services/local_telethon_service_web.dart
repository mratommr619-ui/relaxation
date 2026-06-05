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

  bool get isSupported => false;

  Future<String> ensureStarted(LocalTelethonConfig config) {
    throw const LocalTelethonException(
      'Local Telethon helper is not available on web.',
    );
  }

  Future<String> ensureStartedForLogin(LocalTelethonConfig config) {
    throw const LocalTelethonException(
      'Local Telethon helper is not available on web.',
    );
  }

  Future<void> stop() async {}
}

class LocalTelethonException implements Exception {
  const LocalTelethonException(this.message);

  final String message;

  @override
  String toString() => message;
}
