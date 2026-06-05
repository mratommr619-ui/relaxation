import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:url_launcher/url_launcher.dart';

import '../main.dart' show appNavigatorKey, openDetails;
import '../models/media_content.dart';
import 'access_service.dart';

class NotificationService {
  NotificationService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    FirebaseMessaging? messaging,
    FlutterLocalNotificationsPlugin? localNotifications,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _auth = auth ?? FirebaseAuth.instance,
       _messaging = messaging ?? FirebaseMessaging.instance,
       _local = localNotifications ?? FlutterLocalNotificationsPlugin();

  static final instance = NotificationService();

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final FirebaseMessaging _messaging;
  final FlutterLocalNotificationsPlugin _local;
  final _seenMedia = <String>{};
  final _seenAdminNotifications = <String>{};
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _mediaSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _adminSub;
  bool _mediaPrimed = false;
  bool _adminPrimed = false;
  bool _started = false;

  Future<void> start() async {
    if (_started) {
      await registerCurrentUserToken();
      return;
    }
    _started = true;
    await _initLocalNotifications();
    await _requestNotificationPermission();
    await registerCurrentUserToken();
    _listenForNewMedia();
    _listenForAdminNotifications();
    FirebaseMessaging.onMessage.listen(_showRemoteMessage);
    FirebaseMessaging.onMessageOpenedApp.listen(_openRemoteMessage);
    final initial = await _messaging.getInitialMessage();
    if (initial != null) _openRemoteMessage(initial);
  }

  Future<void> dispose() async {
    await _mediaSub?.cancel();
    await _adminSub?.cancel();
  }

  Future<void> _initLocalNotifications() async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: android);
    await _local.initialize(
      settings,
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        if (payload == null || payload.isEmpty) return;
        _openPayload(jsonDecode(payload) as Map<String, dynamic>);
      },
    );
    const channel = AndroidNotificationChannel(
      'relaxation_updates',
      'Relaxation Updates',
      description: 'Movie, series, and admin announcements',
      importance: Importance.high,
    );
    await _local
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(channel);
  }

  Future<void> _requestNotificationPermission() async {
    await _messaging.requestPermission(alert: true, badge: true, sound: true);
    await _local
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();
  }

  Future<void> registerCurrentUserToken() async {
    final user = _auth.currentUser;
    if (user == null) return;
    final token = await _messaging.getToken();
    if (token == null || token.isEmpty) return;
    await _firestore.collection('users').doc(user.uid).set({
      'uid': user.uid,
      'email': user.email ?? '',
      'fcmTokens': FieldValue.arrayUnion([token]),
      'lastTokenAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  void _listenForNewMedia() {
    _mediaSub = _firestore
        .collection('media')
        .orderBy('createdAt', descending: true)
        .limit(25)
        .snapshots()
        .listen((snapshot) {
          if (!_mediaPrimed) {
            _seenMedia.addAll(snapshot.docs.map((doc) => doc.id));
            _mediaPrimed = true;
            return;
          }
          for (final change in snapshot.docChanges) {
            if (change.type != DocumentChangeType.added) continue;
            if (!_seenMedia.add(change.doc.id)) continue;
            final item = MediaContent.fromDoc(change.doc);
            final typeLabel = item.type == MediaType.series
                ? 'Series'
                : 'Movie';
            _showLocal(
              title: 'New $typeLabel: ${item.title}',
              body: item.description.isEmpty
                  ? '${item.genreLabel} • ${item.quality}'
                  : item.description,
              imageUrl: item.posterUrl,
              payload: {'type': 'media', 'mediaId': item.id},
            );
          }
        });
  }

  void _listenForAdminNotifications() {
    _adminSub = _firestore
        .collection('notifications')
        .orderBy('createdAt', descending: true)
        .limit(25)
        .snapshots()
        .listen((snapshot) {
          if (!_adminPrimed) {
            _seenAdminNotifications.addAll(snapshot.docs.map((doc) => doc.id));
            _adminPrimed = true;
            return;
          }
          for (final change in snapshot.docChanges) {
            if (change.type != DocumentChangeType.added) continue;
            if (!_seenAdminNotifications.add(change.doc.id)) continue;
            final data = change.doc.data() ?? {};
            _showLocal(
              title: (data['title'] ?? 'Relaxation').toString(),
              body: (data['body'] ?? '').toString(),
              imageUrl: (data['photoUrl'] ?? '').toString(),
              payload: {
                'type': 'admin',
                'mediaId': (data['mediaId'] ?? '').toString(),
                'link': (data['link'] ?? '').toString(),
                'photoUrl': (data['photoUrl'] ?? '').toString(),
              },
            );
          }
        });
  }

  Future<void> _showRemoteMessage(RemoteMessage message) {
    return _showLocal(
      title:
          message.notification?.title ?? message.data['title'] ?? 'Relaxation',
      body: message.notification?.body ?? message.data['body'] ?? '',
      imageUrl: message.data['photoUrl'] ?? message.data['image'],
      payload: message.data,
    );
  }

  void _openRemoteMessage(RemoteMessage message) {
    _openPayload(message.data);
  }

  Future<void> _showLocal({
    required String title,
    required String body,
    required Map<String, dynamic> payload,
    String imageUrl = '',
  }) async {
    final style = await _pictureStyle(imageUrl);
    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        'relaxation_updates',
        'Relaxation Updates',
        channelDescription: 'Movie, series, and admin announcements',
        importance: Importance.high,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
        styleInformation: style,
      ),
    );
    await _local.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      details,
      payload: jsonEncode(payload),
    );
  }

  Future<BigPictureStyleInformation?> _pictureStyle(String imageUrl) async {
    if (imageUrl.trim().isEmpty) return null;
    try {
      final response = await Dio().get<List<int>>(
        imageUrl,
        options: Options(responseType: ResponseType.bytes),
      );
      final bytes = response.data;
      if (bytes == null || bytes.isEmpty) return null;
      final bitmap = ByteArrayAndroidBitmap(Uint8List.fromList(bytes));
      return BigPictureStyleInformation(bitmap, largeIcon: bitmap);
    } catch (_) {
      return null;
    }
  }

  Future<void> _openPayload(Map<String, dynamic> payload) async {
    final mediaId = (payload['mediaId'] ?? '').toString();
    if (mediaId.isNotEmpty) {
      final doc = await _firestore.collection('media').doc(mediaId).get();
      if (doc.exists) {
        final context = appNavigatorKey.currentContext;
        if (context == null) return;
        if (!context.mounted) return;
        openDetails(context, MediaContent.fromDoc(doc), null, AccessService());
        return;
      }
    }
    final link = (payload['link'] ?? '').toString();
    if (link.isNotEmpty) {
      final uri = Uri.tryParse(link);
      if (uri != null) {
        try {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        } catch (_) {
          // External links may fail on emulator images or restricted networks.
        }
      }
    }
  }
}
