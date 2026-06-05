import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/media_content.dart';

class MediaRepository {
  MediaRepository({FirebaseFirestore? firestore}) : _firestore = firestore;

  final FirebaseFirestore? _firestore;

  Stream<List<MediaContent>> watchMedia() {
    return (_firestore ?? FirebaseFirestore.instance)
        .collection('media')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs.map(MediaContent.fromDoc).toList());
  }

  Stream<List<AdminAd>> watchAds() {
    return (_firestore ?? FirebaseFirestore.instance)
        .collection('ads')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs.map(AdminAd.fromDoc).toList());
  }

  Stream<List<GenreSection>> watchGenreSections() {
    return (_firestore ?? FirebaseFirestore.instance)
        .collection('genre_sections')
        .orderBy('order')
        .snapshots()
        .map((snapshot) => snapshot.docs.map(GenreSection.fromDoc).toList());
  }

  Future<void> addMedia(MediaContent item) {
    return (_firestore ?? FirebaseFirestore.instance)
        .collection('media')
        .add(item.toFirestore());
  }

  static List<MediaContent> demoItems = [
    const MediaContent(
      id: 'demo-1',
      title: 'Silent Horizon',
      type: MediaType.movie,
      genre: 'Drama',
      quality: '4K',
      description: 'A calm featured movie card used before Firebase is set up.',
      posterUrl: '',
      posterBase64: '',
      streamUrl: '',
      downloadUrl: '',
      watchLinks: [
        MediaServerLink(
          label: 'Server 1',
          url: 'https://t.me/MagicChineseSeriesPage/18499',
        ),
      ],
      downloadLinks: [
        MediaServerLink(
          label: 'Server 1',
          url: 'https://t.me/MagicChineseSeriesPage/18499',
        ),
        MediaServerLink(
          label: 'Server 2',
          url: 'https://t.me/MagicChineseSeriesPage/18499',
        ),
      ],
      telegramUrl: 'https://t.me/MagicChineseSeriesPage/18499',
      telegramChat: '@your_channel',
      telegramMessageId: 101,
      ingestBaseUrl: '',
      episodes: [],
      createdAt: null,
    ),
    const MediaContent(
      id: 'demo-2',
      title: 'Neon Harbor',
      type: MediaType.series,
      genre: 'Sci-Fi',
      quality: '1080p',
      description: 'A series placeholder showing the Firestore schema.',
      posterUrl: '',
      posterBase64: '',
      streamUrl: '',
      downloadUrl: '',
      watchLinks: [],
      downloadLinks: [],
      telegramUrl: '',
      telegramChat: '@your_channel',
      telegramMessageId: 102,
      ingestBaseUrl: '',
      episodes: [],
      createdAt: null,
    ),
    const MediaContent(
      id: 'demo-3',
      title: 'Crimson Alley',
      type: MediaType.movie,
      genre: 'Action',
      quality: '1080p',
      description: 'A sharp action demo card for dynamic genre sections.',
      posterUrl: '',
      posterBase64: '',
      streamUrl: '',
      downloadUrl: '',
      watchLinks: [],
      downloadLinks: [],
      telegramUrl: '',
      telegramChat: '@your_channel',
      telegramMessageId: 103,
      ingestBaseUrl: '',
      episodes: [],
      createdAt: null,
    ),
  ];

  static List<AdminAd> demoAds = [
    const AdminAd(
      id: 'ad-1',
      title: 'Tonight Picks',
      subtitle: 'Admin ads appear here with image or color fallback.',
      imageUrl: '',
      imageBase64: '',
      actionUrl: '',
    ),
  ];

  static List<GenreSection> demoGenreSections = [
    const GenreSection(id: 'Action', title: 'Action', order: 0, visible: true),
    const GenreSection(id: 'Drama', title: 'Drama', order: 1, visible: true),
    const GenreSection(id: 'Sci-Fi', title: 'Sci-Fi', order: 2, visible: true),
  ];
}
