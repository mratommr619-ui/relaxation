import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'local_telethon_service.dart';
import 'telethon_resolver.dart';

class AndroidTelegramAuthState {
  const AndroidTelegramAuthState({
    required this.authorized,
    this.displayName = '',
    this.phone = '',
  });

  final bool authorized;
  final String displayName;
  final String phone;
}

class AndroidTelethonService {
  AndroidTelethonService._();

  static final AndroidTelethonService instance = AndroidTelethonService._();
  static const sessionKey = 'telegramSessionString';
  static const _channel = MethodChannel('relaxation/android_telethon');
  static const _apiIdFallback = 36969505;
  static const _apiHashFallback = 'f129bfcfe08725b285d2a1938fc18380';

  bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<AndroidTelegramAuthState> status() async {
    final data = await _invoke('status');
    final authorized = data['authorized'] == true;
    if (authorized) await _saveSession(data);
    return AndroidTelegramAuthState(
      authorized: authorized,
      displayName: _displayName(data),
      phone: (data['phone'] ?? '').toString(),
    );
  }

  Future<void> sendCode(String phone) async {
    await _invoke('sendCode', extra: {'phone': phone.trim()});
  }

  Future<bool> signInWithCode(String phone, String code) async {
    final data = await _invoke(
      'signIn',
      extra: {'phone': phone.trim(), 'code': code.trim()},
    );
    if (data['passwordNeeded'] == true) return false;
    await _saveSession(data);
    return true;
  }

  Future<void> signInWithPassword(String password) async {
    final data = await _invoke('password', extra: {'password': password});
    await _saveSession(data);
  }

  Future<ResolvedTelegramMedia> resolve(String telegramUrl) async {
    final data = await _invoke('resolve', extra: {'telegramUrl': telegramUrl});
    await _saveSession(data);
    final streamUrl = (data['streamUrl'] ?? '').toString();
    final downloadUrl = (data['downloadUrl'] ?? '').toString();
    if (streamUrl.isEmpty || downloadUrl.isEmpty) {
      throw const TelethonResolveException(
        'Telegram login is working on Android, but playback needs a direct/cached video URL.',
      );
    }
    return ResolvedTelegramMedia(
      streamUrl: streamUrl,
      downloadUrl: downloadUrl,
    );
  }

  Future<Map<String, dynamic>> _invoke(
    String method, {
    Map<String, Object?> extra = const {},
  }) async {
    if (!isSupported) {
      throw const AndroidTelethonException(
        'Android Telethon is only available on Android.',
      );
    }
    final config = await _loadConfig();
    final payload = <String, Object?>{
      'apiId': config.apiId,
      'apiHash': config.apiHash,
      'sessionString': config.sessionString,
      ...extra,
    };
    final raw = await _channel.invokeMethod<String>(method, payload);
    if (raw == null || raw.isEmpty) return {};
    return Map<String, dynamic>.from(jsonDecode(raw) as Map);
  }

  Future<LocalTelethonConfig> _loadConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final savedSession = prefs.getString(sessionKey) ?? '';
    Map<String, dynamic> data = {};
    try {
      final doc = await FirebaseFirestore.instance
          .collection('app_settings')
          .doc('telegram')
          .get();
      data = doc.data() ?? {};
    } catch (_) {
      data = {};
    }
    final apiId = data['apiId'] is int
        ? data['apiId'] as int
        : int.tryParse((data['apiId'] ?? '').toString()) ?? _apiIdFallback;
    final apiHash = (data['apiHash'] ?? _apiHashFallback).toString();
    final sessionString = savedSession.isNotEmpty
        ? savedSession
        : (data['sessionString'] ?? '').toString();
    return LocalTelethonConfig(
      apiId: apiId,
      apiHash: apiHash,
      sessionString: sessionString,
    );
  }

  Future<void> _saveSession(Map<String, dynamic> data) async {
    final sessionString = (data['sessionString'] ?? '').toString();
    if (sessionString.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(sessionKey, sessionString);
  }

  String _displayName(Map<String, dynamic> data) {
    final first = (data['firstName'] ?? '').toString();
    final last = (data['lastName'] ?? '').toString();
    final username = (data['username'] ?? '').toString();
    final name = '$first $last'.trim();
    if (name.isNotEmpty) return name;
    if (username.isNotEmpty) return '@$username';
    return (data['phone'] ?? '').toString();
  }
}

class AndroidTelethonException implements Exception {
  const AndroidTelethonException(this.message);

  final String message;

  @override
  String toString() => message;
}
