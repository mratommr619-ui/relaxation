import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AccessState {
  const AccessState({
    required this.deviceHash,
    required this.trialExpiresAt,
    required this.licenseExpiresAt,
    required this.licenseKey,
    required this.disabled,
    required this.telegramDisplayName,
    required this.telegramPhone,
  });

  final String deviceHash;
  final DateTime? trialExpiresAt;
  final DateTime? licenseExpiresAt;
  final String licenseKey;
  final bool disabled;
  final String telegramDisplayName;
  final String telegramPhone;

  bool get hasTelegramLogin =>
      telegramDisplayName.trim().isNotEmpty || telegramPhone.trim().isNotEmpty;

  bool get hasAccess {
    if (disabled) return false;
    final now = DateTime.now();
    return (licenseExpiresAt != null && licenseExpiresAt!.isAfter(now)) ||
        (trialExpiresAt != null && trialExpiresAt!.isAfter(now));
  }

  bool get isPremium =>
      !disabled &&
      licenseExpiresAt != null &&
      licenseExpiresAt!.isAfter(DateTime.now());

  int get daysLeft {
    final expiry = isPremium ? licenseExpiresAt : trialExpiresAt;
    if (expiry == null) return 0;
    final diff = expiry.difference(DateTime.now());
    if (diff.isNegative) return 0;
    return (diff.inHours / 24).ceil();
  }

  DateTime? get expiryDate {
    final dates = [licenseExpiresAt, trialExpiresAt]
        .whereType<DateTime>()
        .where((date) => date.isAfter(DateTime.now()))
        .toList();
    if (dates.isEmpty) return null;
    dates.sort((a, b) => b.compareTo(a));
    return dates.first;
  }
}

class AccessException implements Exception {
  const AccessException(this.message);

  final String message;

  @override
  String toString() => message;
}

class AccessService {
  AccessService({FirebaseFirestore? firestore, FirebaseAuth? auth})
    : _firestore = firestore,
      _auth = auth;

  final FirebaseFirestore? _firestore;
  final FirebaseAuth? _auth;

  FirebaseFirestore get firestore => _firestore ?? FirebaseFirestore.instance;
  FirebaseAuth get auth => _auth ?? FirebaseAuth.instance;

  Stream<User?> authStateChanges() => auth.authStateChanges();

  Future<void> signInWithEmail(String email, String password) {
    return auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
  }

  Future<void> createAccount(String email, String password) {
    return auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
  }

  Future<void> signInAnonymously() {
    return auth.signInAnonymously();
  }

  Future<void> signOut() => auth.signOut();

  Stream<AccessState> watchAccess() async* {
    final user = auth.currentUser;
    if (user == null) return;
    final deviceHash = await currentDeviceHash();
    await ensureDeviceAccess(user, deviceHash);
    yield* firestore
        .collection('access_devices')
        .doc(deviceHash)
        .snapshots()
        .map((doc) => _stateFromDoc(deviceHash, doc.data() ?? {}));
  }

  Future<AccessState> ensureCurrentAccess() async {
    final user = auth.currentUser;
    if (user == null) {
      throw const AccessException('Please sign in first.');
    }
    final deviceHash = await currentDeviceHash();
    await ensureDeviceAccess(user, deviceHash);
    final doc = await firestore
        .collection('access_devices')
        .doc(deviceHash)
        .get();
    return _stateFromDoc(deviceHash, doc.data() ?? {});
  }

  Future<void> ensureDeviceAccess(User user, String deviceHash) async {
    final ref = firestore.collection('access_devices').doc(deviceHash);
    await firestore.runTransaction((transaction) async {
      final snap = await transaction.get(ref);
      final now = Timestamp.now();
      if (!snap.exists) {
        transaction.set(ref, {
          'deviceHash': deviceHash,
          'createdAt': now,
          'lastSeenAt': now,
          'trialStartedAt': null,
          'trialExpiresAt': null,
          'trialStartedByTelegram': false,
          'linkedUids': [user.uid],
          'lastUid': user.uid,
          'lastEmail': user.email ?? '',
          'disabled': false,
          'licenseKey': '',
          'licenseExpiresAt': null,
        });
      } else {
        final data = snap.data() ?? {};
        final linked = List<String>.from(data['linkedUids'] ?? const []);
        if (!linked.contains(user.uid)) linked.add(user.uid);
        transaction.update(ref, {
          'lastSeenAt': now,
          'linkedUids': linked,
          'lastUid': user.uid,
          'lastEmail': user.email ?? '',
        });
      }
    });
  }

  Future<void> startTrialAfterTelegramLogin() async {
    final user = auth.currentUser;
    if (user == null) {
      throw const AccessException('Please sign in first.');
    }
    final deviceHash = await currentDeviceHash();
    await ensureDeviceAccess(user, deviceHash);
    final ref = firestore.collection('access_devices').doc(deviceHash);
    await firestore.runTransaction((transaction) async {
      final snap = await transaction.get(ref);
      final data = snap.data() ?? {};
      if (_timestampToDate(data['licenseExpiresAt']) != null ||
          data['trialStartedByTelegram'] == true) {
        transaction.update(ref, {'lastSeenAt': Timestamp.now()});
        return;
      }
      final now = DateTime.now();
      transaction.update(ref, {
        'trialStartedAt': Timestamp.fromDate(now),
        'trialExpiresAt': Timestamp.fromDate(trialExpiryFromTelegramLogin(now)),
        'trialStartedByTelegram': true,
        'lastSeenAt': Timestamp.fromDate(now),
      });
    });
  }

  Future<void> registerTelegramAccount({
    required String accountId,
    required String phone,
    required String displayName,
  }) async {
    final user = auth.currentUser;
    if (user == null) {
      throw const AccessException('Please sign in first.');
    }
    final accountKey = accountId.trim().isNotEmpty
        ? accountId.trim()
        : phone.trim().replaceAll(RegExp(r'\D+'), '');
    if (accountKey.isEmpty) return;
    final deviceHash = await currentDeviceHash();
    await ensureDeviceAccess(user, deviceHash);
    final now = Timestamp.now();
    final accountRef = firestore
        .collection('telegram_accounts')
        .doc(accountKey);
    final sessionRef = accountRef.collection('devices').doc(deviceHash);
    final deviceRef = firestore.collection('access_devices').doc(deviceHash);

    await firestore.runTransaction((transaction) async {
      transaction.set(accountRef, {
        'accountId': accountId,
        'phone': phone,
        'displayName': displayName,
        'updatedAt': now,
      }, SetOptions(merge: true));
      transaction.set(sessionRef, {
        'deviceHash': deviceHash,
        'uid': user.uid,
        'phone': phone,
        'displayName': displayName,
        'lastSeenAt': now,
        'createdAt': now,
      }, SetOptions(merge: true));
      transaction.set(deviceRef, {
        'deviceHash': deviceHash,
        'telegramAccountKey': accountKey,
        'telegramPhone': phone,
        'telegramDisplayName': displayName,
        'lastUid': user.uid,
        'lastEmail': user.email ?? '',
        'disabled': false,
        'lastSeenAt': now,
      }, SetOptions(merge: true));
    });
    await _enforceTwoDeviceLimit(accountKey, deviceHash);
  }

  Future<void> _enforceTwoDeviceLimit(
    String accountKey,
    String currentDeviceHash,
  ) async {
    final sessions = await firestore
        .collection('telegram_accounts')
        .doc(accountKey)
        .collection('devices')
        .orderBy('lastSeenAt', descending: true)
        .limit(10)
        .get();
    final docs = sessions.docs;
    if (docs.length <= 2) return;
    final batch = firestore.batch();
    for (final doc in docs.skip(2)) {
      if (doc.id == currentDeviceHash) continue;
      batch.update(doc.reference, {'kickedAt': Timestamp.now()});
      batch.set(
        firestore.collection('access_devices').doc(doc.id),
        {
          'deviceHash': doc.id,
          'disabled': true,
          'disabledReason': 'This account is already active on 2 devices.',
          'disabledAt': Timestamp.now(),
        },
        SetOptions(merge: true),
      );
    }
    await batch.commit();
  }

  Future<AccessState> activateLicense(String rawKey) async {
    final user = auth.currentUser;
    if (user == null) {
      throw const AccessException('Please sign in first.');
    }
    final key = rawKey.trim().toUpperCase();
    if (key.isEmpty) {
      throw const AccessException('Invalid license key.');
    }
    final deviceHash = await currentDeviceHash();
    final deviceRef = firestore.collection('access_devices').doc(deviceHash);
    final keyRef = firestore.collection('license_keys').doc(key);

    await firestore.runTransaction((transaction) async {
      final deviceSnap = await transaction.get(deviceRef);
      final keySnap = await transaction.get(keyRef);
      if (!keySnap.exists) {
        throw const AccessException('Invalid license key.');
      }
      final keyData = keySnap.data() ?? {};
      final usedBy = (keyData['usedByDeviceHash'] ?? '').toString();
      if (usedBy.isNotEmpty && usedBy != deviceHash) {
        throw const AccessException('This license key has already been used.');
      }
      final days = keyData['days'] is int ? keyData['days'] as int : 0;
      if (days <= 0) {
        throw const AccessException('Invalid license duration.');
      }

      final nowDate = DateTime.now();
      final expiresAt = licenseExpiryFromActivation(nowDate, days);

      final devicePayload = {
        'licenseKey': key,
        'licenseExpiresAt': Timestamp.fromDate(expiresAt),
        'licenseOwner': (keyData['name'] ?? '').toString(),
        'lastSeenAt': Timestamp.now(),
      };
      if (deviceSnap.exists) {
        transaction.update(deviceRef, devicePayload);
      } else {
        transaction.set(deviceRef, {
          'deviceHash': deviceHash,
          'createdAt': Timestamp.now(),
          'trialStartedAt': Timestamp.now(),
          'trialExpiresAt': null,
          'linkedUids': [user.uid],
          'lastUid': user.uid,
          'lastEmail': user.email ?? '',
          'disabled': false,
          ...devicePayload,
        });
      }
      transaction.update(keyRef, {
        'usedByDeviceHash': deviceHash,
        'usedByUid': user.uid,
        'usedByEmail': user.email ?? '',
        'usedAt': Timestamp.now(),
        'expiresAt': Timestamp.fromDate(expiresAt),
      });
      transaction.set(firestore.collection('user_access').doc(user.uid), {
        'uid': user.uid,
        'email': user.email ?? '',
        'deviceHash': deviceHash,
        'licenseKey': key,
        'expiresAt': Timestamp.fromDate(expiresAt),
        'updatedAt': Timestamp.now(),
      }, SetOptions(merge: true));
    });

    return ensureCurrentAccess();
  }

  Future<String> currentDeviceHash() async {
    final prefs = await SharedPreferences.getInstance();
    final fallback = await _fallbackInstallId(prefs);
    final info = await DeviceInfoPlugin().deviceInfo;
    final raw = jsonEncode({
      'platform': defaultTargetPlatform.name,
      'web': kIsWeb,
      'device': info.data,
      'fallback': fallback,
    });
    return sha256.convert(utf8.encode(raw)).toString();
  }

  Future<String> _fallbackInstallId(SharedPreferences prefs) async {
    const key = 'relaxationInstallId';
    final existing = prefs.getString(key);
    if (existing != null && existing.isNotEmpty) return existing;
    final id = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    await prefs.setString(key, id);
    return id;
  }

  AccessState _stateFromDoc(String deviceHash, Map<String, dynamic> data) {
    return AccessState(
      deviceHash: deviceHash,
      trialExpiresAt: _timestampToDate(data['trialExpiresAt']),
      licenseExpiresAt: _timestampToDate(data['licenseExpiresAt']),
      licenseKey: (data['licenseKey'] ?? '').toString(),
      disabled: data['disabled'] == true,
      telegramDisplayName: (data['telegramDisplayName'] ?? '').toString(),
      telegramPhone: (data['telegramPhone'] ?? '').toString(),
    );
  }
}

DateTime? _timestampToDate(dynamic value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  return null;
}

DateTime licenseExpiryFromActivation(DateTime activatedAt, int days) {
  return activatedAt.add(Duration(days: days));
}

DateTime trialExpiryFromTelegramLogin(DateTime loggedInAt) {
  return loggedInAt.add(const Duration(days: 3));
}
