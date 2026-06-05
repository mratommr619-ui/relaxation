import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'android_telethon_service.dart';
import 'local_telethon_service.dart';

class TelegramAuthState {
  const TelegramAuthState({
    required this.authorized,
    this.displayName = '',
    this.phone = '',
  });

  final bool authorized;
  final String displayName;
  final String phone;
}

class TelegramAuthService {
  TelegramAuthService({
    Dio? dio,
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
  }) : _dio = dio ?? Dio(),
       _auth = auth ?? FirebaseAuth.instance,
       _firestore = firestore ?? FirebaseFirestore.instance;

  static const _sessionKey = AndroidTelethonService.sessionKey;
  static const _apiIdFallback = 36969505;
  static const _apiHashFallback = 'f129bfcfe08725b285d2a1938fc18380';

  final Dio _dio;
  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  Future<TelegramAuthState> status() async {
    await _ensureFirebaseIdentity();
    if (AndroidTelethonService.instance.isSupported) {
      final state = await AndroidTelethonService.instance.status();
      return TelegramAuthState(
        authorized: state.authorized,
        displayName: state.displayName,
        phone: state.phone,
      );
    }
    final config = await _loadConfig();
    if (!config.hasApiCredentials) {
      return const TelegramAuthState(authorized: false);
    }
    try {
      final baseUrl = await LocalTelethonService.instance.ensureStartedForLogin(
        config,
      );
      final response = await _dio.get<Map<String, dynamic>>(
        '$baseUrl/auth/status',
      );
      final data = response.data ?? {};
      final authorized = data['authorized'] == true;
      if (authorized) await _saveSession(data);
      return TelegramAuthState(
        authorized: authorized,
        displayName: _displayName(data),
        phone: (data['phone'] ?? '').toString(),
      );
    } catch (_) {
      return const TelegramAuthState(authorized: false);
    }
  }

  Future<void> sendCode(String phone) async {
    if (AndroidTelethonService.instance.isSupported) {
      await _ensureFirebaseIdentity();
      await AndroidTelethonService.instance.sendCode(phone);
      return;
    }
    final baseUrl = await _startLoginHelper();
    await _dio.post<Map<String, dynamic>>(
      '$baseUrl/auth/send_code',
      data: {'phone': phone.trim()},
    );
  }

  Future<bool> signInWithCode(String phone, String code) async {
    if (AndroidTelethonService.instance.isSupported) {
      await _ensureFirebaseIdentity();
      return AndroidTelethonService.instance.signInWithCode(phone, code);
    }
    final baseUrl = await _startLoginHelper();
    final response = await _dio.post<Map<String, dynamic>>(
      '$baseUrl/auth/sign_in',
      data: {'phone': phone.trim(), 'code': code.trim()},
    );
    final data = response.data ?? {};
    if (data['passwordNeeded'] == true) return false;
    await _saveSession(data);
    return true;
  }

  Future<void> signInWithPassword(String password) async {
    if (AndroidTelethonService.instance.isSupported) {
      await _ensureFirebaseIdentity();
      await AndroidTelethonService.instance.signInWithPassword(password);
      return;
    }
    final baseUrl = await _startLoginHelper();
    final response = await _dio.post<Map<String, dynamic>>(
      '$baseUrl/auth/password',
      data: {'password': password},
    );
    await _saveSession(response.data ?? {});
  }

  Future<void> signOut() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_sessionKey);
    await LocalTelethonService.instance.stop();
  }

  Future<String> _startLoginHelper() async {
    await _ensureFirebaseIdentity();
    final config = await _loadConfig();
    if (!config.hasApiCredentials) {
      throw const TelegramAuthException('Telegram API settings are missing.');
    }
    return LocalTelethonService.instance.ensureStartedForLogin(config);
  }

  Future<void> _ensureFirebaseIdentity() async {
    if (_auth.currentUser != null) return;
    await _auth.signInAnonymously();
  }

  Future<LocalTelethonConfig> _loadConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final savedSession = prefs.getString(_sessionKey) ?? '';
    Map<String, dynamic> data = {};
    try {
      final doc = await _firestore
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
    await prefs.setString(_sessionKey, sessionString);
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

class TelegramAuthException implements Exception {
  const TelegramAuthException(this.message);

  final String message;

  @override
  String toString() => message;
}
