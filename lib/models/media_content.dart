import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

enum MediaType { movie, series }

class MediaServerLink {
  const MediaServerLink({required this.label, required this.url});

  final String label;
  final String url;

  factory MediaServerLink.fromMap(Map<String, dynamic> data, int index) {
    return MediaServerLink(
      label: (data['label'] ?? 'Server ${index + 1}').toString(),
      url: (data['url'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toMap() => {'label': label, 'url': url};
}

class MediaEpisode {
  const MediaEpisode({
    required this.label,
    required this.telegramUrl,
    required this.watchLinks,
    required this.downloadLinks,
  });

  final String label;
  final String telegramUrl;
  final List<MediaServerLink> watchLinks;
  final List<MediaServerLink> downloadLinks;

  factory MediaEpisode.fromMap(Map<String, dynamic> data, int index) {
    return MediaEpisode(
      label: (data['label'] ?? 'Episode ${index + 1}').toString(),
      telegramUrl: (data['telegramUrl'] ?? '').toString(),
      watchLinks: _linksFromData(data['watchLinks'], data['streamUrl']),
      downloadLinks: _linksFromData(data['downloadLinks'], data['downloadUrl']),
    );
  }

  Map<String, dynamic> toMap() => {
    'label': label,
    'telegramUrl': telegramUrl,
    'watchLinks': watchLinks.map((link) => link.toMap()).toList(),
    'downloadLinks': downloadLinks.map((link) => link.toMap()).toList(),
  };
}

class AdminAd {
  const AdminAd({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.imageUrl,
    required this.imageBase64,
    required this.actionUrl,
  });

  final String id;
  final String title;
  final String subtitle;
  final String imageUrl;
  final String imageBase64;
  final String actionUrl;

  factory AdminAd.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return AdminAd(
      id: doc.id,
      title: (data['title'] ?? 'Relaxation').toString(),
      subtitle: (data['subtitle'] ?? '').toString(),
      imageUrl: (data['imageUrl'] ?? '').toString(),
      imageBase64: (data['imageBase64'] ?? '').toString(),
      actionUrl: (data['actionUrl'] ?? '').toString(),
    );
  }
}

class GenreSection {
  const GenreSection({
    required this.id,
    required this.title,
    required this.order,
    required this.visible,
  });

  final String id;
  final String title;
  final int order;
  final bool visible;

  factory GenreSection.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return GenreSection(
      id: doc.id,
      title: (data['title'] ?? doc.id).toString(),
      order: data['order'] is int ? data['order'] as int : 999,
      visible: data['visible'] != false,
    );
  }
}

class MediaContent {
  const MediaContent({
    required this.id,
    required this.title,
    required this.type,
    required this.genre,
    required this.genres,
    required this.quality,
    required this.description,
    required this.posterUrl,
    required this.posterBase64,
    required this.streamUrl,
    required this.downloadUrl,
    required this.watchLinks,
    required this.downloadLinks,
    required this.telegramUrl,
    required this.telegramChat,
    required this.telegramMessageId,
    required this.ingestBaseUrl,
    required this.episodes,
    required this.createdAt,
  });

  final String id;
  final String title;
  final MediaType type;
  final String genre;
  final List<String> genres;
  final String quality;
  final String description;
  final String posterUrl;
  final String posterBase64;
  final String streamUrl;
  final String downloadUrl;
  final List<MediaServerLink> watchLinks;
  final List<MediaServerLink> downloadLinks;
  final String telegramUrl;
  final String telegramChat;
  final int? telegramMessageId;
  final String ingestBaseUrl;
  final List<MediaEpisode> episodes;
  final DateTime? createdAt;

  factory MediaContent.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return MediaContent.fromMap(doc.id, data);
  }

  factory MediaContent.fromMap(String id, Map<String, dynamic> data) {
    final typeValue = (data['type'] ?? 'movie').toString().toLowerCase();
    final genres = _genresFromData(data['genres'], data['genre']);
    return MediaContent(
      id: id,
      title: (data['title'] ?? 'Untitled').toString(),
      type: typeValue == 'series' ? MediaType.series : MediaType.movie,
      genre: genres.isEmpty ? 'General' : genres.first,
      genres: genres,
      quality: (data['quality'] ?? 'HD').toString(),
      description: (data['description'] ?? '').toString(),
      posterUrl: (data['posterUrl'] ?? '').toString(),
      posterBase64: (data['posterBase64'] ?? '').toString(),
      streamUrl: (data['streamUrl'] ?? '').toString(),
      downloadUrl: (data['downloadUrl'] ?? '').toString(),
      watchLinks: _linksFromData(data['watchLinks'], data['streamUrl']),
      downloadLinks: _linksFromData(data['downloadLinks'], data['downloadUrl']),
      telegramUrl: (data['telegramUrl'] ?? '').toString(),
      telegramChat: (data['telegramChat'] ?? '').toString(),
      telegramMessageId: data['telegramMessageId'] is int
          ? data['telegramMessageId'] as int
          : int.tryParse((data['telegramMessageId'] ?? '').toString()),
      ingestBaseUrl: (data['ingestBaseUrl'] ?? '').toString(),
      episodes: _episodesFromData(data['episodes']),
      createdAt: data['createdAt'] is Timestamp
          ? (data['createdAt'] as Timestamp).toDate()
          : null,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'title': title,
      'type': type == MediaType.series ? 'series' : 'movie',
      'genre': genre,
      'genres': genres,
      'quality': quality,
      'description': description,
      'posterUrl': posterUrl,
      'posterBase64': posterBase64,
      'streamUrl': streamUrl,
      'downloadUrl': downloadUrl,
      'watchLinks': watchLinks.map((link) => link.toMap()).toList(),
      'downloadLinks': downloadLinks.map((link) => link.toMap()).toList(),
      'telegramUrl': telegramUrl,
      'telegramChat': telegramChat,
      'telegramMessageId': telegramMessageId,
      'ingestBaseUrl': ingestBaseUrl,
      'episodes': episodes.map((episode) => episode.toMap()).toList(),
      'createdAt': FieldValue.serverTimestamp(),
    };
  }

  IconData get icon =>
      type == MediaType.series ? Icons.live_tv_rounded : Icons.local_movies;

  String get genreLabel => genres.isEmpty ? genre : genres.join(', ');
}

List<String> _genresFromData(dynamic value, dynamic legacyGenre) {
  final genres = <String>[];
  if (value is List) {
    for (final entry in value) {
      final genre = entry.toString().trim();
      if (genre.isNotEmpty && !genres.contains(genre)) genres.add(genre);
    }
  }
  final fallback = (legacyGenre ?? '').toString().trim();
  if (genres.isEmpty && fallback.isNotEmpty) {
    for (final part in fallback.split(',')) {
      final genre = part.trim();
      if (genre.isNotEmpty && !genres.contains(genre)) genres.add(genre);
    }
  }
  if (genres.isEmpty) genres.add('General');
  return genres;
}

List<MediaEpisode> _episodesFromData(dynamic value) {
  final episodes = <MediaEpisode>[];
  if (value is List) {
    for (final entry in value) {
      if (entry is Map) {
        episodes.add(
          MediaEpisode.fromMap(
            Map<String, dynamic>.from(entry),
            episodes.length,
          ),
        );
      }
    }
  }
  return episodes;
}

List<MediaServerLink> _linksFromData(dynamic value, dynamic legacyUrl) {
  final links = <MediaServerLink>[];
  if (value is List) {
    for (final entry in value) {
      if (entry is Map) {
        final link = MediaServerLink.fromMap(
          Map<String, dynamic>.from(entry),
          links.length,
        );
        if (link.url.trim().isNotEmpty) {
          links.add(link);
        }
      } else if (entry is String && entry.trim().isNotEmpty) {
        links.add(
          MediaServerLink(
            label: 'Server ${links.length + 1}',
            url: entry.trim(),
          ),
        );
      }
    }
  }
  final fallback = (legacyUrl ?? '').toString().trim();
  if (links.isEmpty && fallback.isNotEmpty) {
    links.add(MediaServerLink(label: 'Server 1', url: fallback));
  }
  return links;
}
