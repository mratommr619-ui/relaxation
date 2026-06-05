import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final firebaseReady = await _initializeFirebase();
  runApp(RelaxationStudio(firebaseReady: firebaseReady));
}

Future<bool> _initializeFirebase() async {
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    return true;
  } catch (_) {
    return false;
  }
}

class RelaxationStudio extends StatelessWidget {
  const RelaxationStudio({super.key, required this.firebaseReady});

  final bool firebaseReady;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Relaxation Studio',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF080B12),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF4EE6A8),
          brightness: Brightness.dark,
          primary: const Color(0xFF4EE6A8),
          surface: const Color(0xFF111827),
        ),
      ),
      home: StudioHome(firebaseReady: firebaseReady),
    );
  }
}

class StudioHome extends StatefulWidget {
  const StudioHome({super.key, required this.firebaseReady});

  final bool firebaseReady;

  @override
  State<StudioHome> createState() => _StudioHomeState();
}

class _StudioHomeState extends State<StudioHome> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _genre = TextEditingController(text: 'Action');
  final _quality = TextEditingController(text: '1080p');
  final _description = TextEditingController();
  final _posterUrl = TextEditingController();
  final _posterBase64 = TextEditingController();
  final _streamUrl = TextEditingController();
  final _downloadUrl = TextEditingController();
  final _watchLinks = TextEditingController();
  final _downloadLinks = TextEditingController();
  final _telegramUrl = TextEditingController();
  final _telegramChat = TextEditingController();
  final _telegramMessageId = TextEditingController();
  final _ingestBaseUrl = TextEditingController();
  final _episodesText = TextEditingController();
  final _genreTitle = TextEditingController();
  final _licenseName = TextEditingController();
  final _licenseDays = TextEditingController(text: '30');
  final _adTitle = TextEditingController();
  final _adSubtitle = TextEditingController();
  final _adImageUrl = TextEditingController();
  final _adImageBase64 = TextEditingController();
  final _adActionUrl = TextEditingController();
  final _notiTitle = TextEditingController();
  final _notiBody = TextEditingController();
  final _notiPhotoUrl = TextEditingController();
  final _notiLink = TextEditingController();
  final _notiMediaId = TextEditingController();
  String _type = 'movie';
  String? _editingMediaId;
  String? _editingAdId;
  List<String> _selectedGenres = ['Action'];
  bool _saving = false;

  void _openSection(_AdminSection section) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => StatefulBuilder(
          builder: (context, refreshPage) => _AdminSectionPage(
            section: section,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 920;
                return _sectionContent(section, wide, refreshPage);
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _sectionContent(
    _AdminSection section,
    bool wide,
    StateSetter refreshPage,
  ) {
    switch (section) {
      case _AdminSection.media:
        final editor = _EditorCard(
          formKey: _formKey,
          title: _title,
          selectedGenres: _selectedGenres,
          quality: _quality,
          description: _description,
          posterBase64: _posterBase64,
          telegramUrl: _telegramUrl,
          watchLinks: _watchLinks,
          downloadLinks: _downloadLinks,
          episodesText: _episodesText,
          type: _type,
          saving: _saving,
          editing: _editingMediaId != null,
          firebaseReady: widget.firebaseReady,
          onTypeChanged: (value) {
            _changeMediaType(value);
            refreshPage(() {});
          },
          onAddGenre: (value) {
            final genre = value.trim();
            if (genre.isEmpty || _selectedGenres.contains(genre)) return;
            setState(() => _selectedGenres = [..._selectedGenres, genre]);
            refreshPage(() {});
          },
          onRemoveGenre: (value) {
            setState(() {
              _selectedGenres = _selectedGenres
                  .where((genre) => genre != value)
                  .toList();
            });
            refreshPage(() {});
          },
          onApplyTelegramLink: () => _applyTelegramLink(),
          onSave: () {
            refreshPage(() {});
            _save().whenComplete(() => refreshPage(() {}));
          },
          onCancelEdit: () {
            _clearMediaForm();
            refreshPage(() {});
          },
          onPickPoster: _pickPosterImage,
        );
        final library = _LibraryPanel(
          firebaseReady: true,
          onEdit: (doc) {
            _editMedia(doc);
            refreshPage(() {});
          },
        );
        if (!wide) {
          return Column(
            children: [editor, const SizedBox(height: 20), library],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 5, child: editor),
            const SizedBox(width: 20),
            Expanded(flex: 4, child: library),
          ],
        );
      case _AdminSection.licenses:
        return _LicensePanel(
          nameController: _licenseName,
          daysController: _licenseDays,
          onCreate: _createLicense,
        );
      case _AdminSection.genres:
        return _GenreOrderPanel(titleController: _genreTitle, onAdd: _addGenre);
      case _AdminSection.ads:
        return _AdsPanel(
          titleController: _adTitle,
          subtitleController: _adSubtitle,
          imageUrlController: _adImageUrl,
          imageBase64Controller: _adImageBase64,
          actionUrlController: _adActionUrl,
          editing: _editingAdId != null,
          onSave: () {
            _saveAd().whenComplete(() => refreshPage(() {}));
            refreshPage(() {});
          },
          onCancel: () {
            setState(() {
              _editingAdId = null;
              _adTitle.clear();
              _adSubtitle.clear();
              _adImageUrl.clear();
              _adImageBase64.clear();
              _adActionUrl.clear();
            });
            refreshPage(() {});
          },
          onEdit: (doc) {
            _editAd(doc);
            refreshPage(() {});
          },
          onPickImage: _pickAdImage,
        );
      case _AdminSection.notifications:
        return _NotificationPanel(
          titleController: _notiTitle,
          bodyController: _notiBody,
          photoUrlController: _notiPhotoUrl,
          linkController: _notiLink,
          mediaIdController: _notiMediaId,
          onSend: _sendAdminNotification,
        );
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _genre.dispose();
    _quality.dispose();
    _description.dispose();
    _posterUrl.dispose();
    _posterBase64.dispose();
    _streamUrl.dispose();
    _downloadUrl.dispose();
    _watchLinks.dispose();
    _downloadLinks.dispose();
    _telegramUrl.dispose();
    _telegramChat.dispose();
    _telegramMessageId.dispose();
    _ingestBaseUrl.dispose();
    _episodesText.dispose();
    _genreTitle.dispose();
    _licenseName.dispose();
    _licenseDays.dispose();
    _adTitle.dispose();
    _adSubtitle.dispose();
    _adImageUrl.dispose();
    _adImageBase64.dispose();
    _adActionUrl.dispose();
    _notiTitle.dispose();
    _notiBody.dispose();
    _notiPhotoUrl.dispose();
    _notiLink.dispose();
    _notiMediaId.dispose();
    super.dispose();
  }

  bool _applyTelegramLink({bool showErrors = true}) {
    if (_telegramUrl.text.trim().isEmpty) {
      return true;
    }
    final parsed = parseTelegramPublicLink(_telegramUrl.text);
    if (parsed == null) {
      if (showErrors) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Paste a valid Telegram post link')),
        );
      }
      return false;
    }
    final chat = parsed.chat;
    final id = parsed.messageId;
    setState(() {
      _telegramChat.text = '@$chat';
      _telegramMessageId.text = id.toString();
    });
    return true;
  }

  Future<void> _save() async {
    if (!widget.firebaseReady || !_formKey.currentState!.validate()) {
      return;
    }
    if (!_hasPlayableSource()) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _type == 'series'
                ? 'Series အတွက် episode link အနည်းဆုံး ၁ ခုထည့်ပါ။'
                : 'Movie အတွက် Telegram link သို့မဟုတ် direct server link ထည့်ပါ။',
          ),
        ),
      );
      return;
    }
    if (!_applyTelegramLink()) {
      return;
    }
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final payload = {
        'title': _title.text.trim(),
        'type': _type,
        'genre': _selectedGenres.isEmpty ? 'General' : _selectedGenres.first,
        'genres': _selectedGenres.isEmpty ? ['General'] : _selectedGenres,
        'quality': _quality.text.trim(),
        'description': _description.text.trim(),
        'posterUrl': _posterUrl.text.trim(),
        'posterBase64': _posterBase64.text.trim(),
        'streamUrl': _streamUrl.text.trim(),
        'downloadUrl': _downloadUrl.text.trim(),
        'watchLinks': _serverLinksFromText(_watchLinks.text),
        'downloadLinks': _serverLinksFromText(_downloadLinks.text),
        'telegramUrl': _telegramUrl.text.trim(),
        'telegramChat': _telegramChat.text.trim(),
        'telegramMessageId': int.tryParse(_telegramMessageId.text.trim()),
        'ingestBaseUrl': _ingestBaseUrl.text.trim(),
        'episodes': _episodesFromText(_episodesText.text),
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (_editingMediaId == null) {
        await FirebaseFirestore.instance.collection('media').add({
          ...payload,
          'createdAt': FieldValue.serverTimestamp(),
        });
      } else {
        await FirebaseFirestore.instance
            .collection('media')
            .doc(_editingMediaId)
            .update(payload);
      }
      _clearMediaForm();
      messenger.showSnackBar(const SnackBar(content: Text('Media saved')));
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('Save failed: $error')));
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  void _clearMediaForm() {
    setState(() {
      _editingMediaId = null;
      _type = 'movie';
      _selectedGenres = ['Action'];
      _title.clear();
      _genre.text = 'Action';
      _quality.text = '1080p';
      _description.clear();
      _posterUrl.clear();
      _posterBase64.clear();
      _streamUrl.clear();
      _downloadUrl.clear();
      _watchLinks.clear();
      _downloadLinks.clear();
      _telegramUrl.clear();
      _telegramChat.clear();
      _telegramMessageId.clear();
      _ingestBaseUrl.clear();
      _episodesText.clear();
    });
  }

  void _changeMediaType(String value) {
    if (_type == value) return;
    setState(() {
      _type = value;
      _streamUrl.clear();
      _downloadUrl.clear();
      _watchLinks.clear();
      _downloadLinks.clear();
      _telegramUrl.clear();
      _telegramChat.clear();
      _telegramMessageId.clear();
      _episodesText.clear();
    });
  }

  bool _hasPlayableSource() {
    if (_type == 'series') {
      return _episodesFromText(_episodesText.text).isNotEmpty ||
          _watchLinks.text.trim().isNotEmpty ||
          _downloadLinks.text.trim().isNotEmpty ||
          _streamUrl.text.trim().isNotEmpty ||
          _downloadUrl.text.trim().isNotEmpty;
    }
    return _telegramUrl.text.trim().isNotEmpty ||
        _watchLinks.text.trim().isNotEmpty ||
        _downloadLinks.text.trim().isNotEmpty ||
        _streamUrl.text.trim().isNotEmpty ||
        _downloadUrl.text.trim().isNotEmpty;
  }

  void _editMedia(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    setState(() {
      _editingMediaId = doc.id;
      _title.text = (data['title'] ?? '').toString();
      _type = (data['type'] ?? 'movie').toString() == 'series'
          ? 'series'
          : 'movie';
      _selectedGenres = _genresFromData(data['genres'], data['genre']);
      _genre.text = _selectedGenres.join(', ');
      _quality.text = (data['quality'] ?? '').toString();
      _description.text = (data['description'] ?? '').toString();
      _posterUrl.text = (data['posterUrl'] ?? '').toString();
      _posterBase64.text = (data['posterBase64'] ?? '').toString();
      _streamUrl.text = (data['streamUrl'] ?? '').toString();
      _downloadUrl.text = (data['downloadUrl'] ?? '').toString();
      _watchLinks.text = _linksToText(data['watchLinks'], data['streamUrl']);
      _downloadLinks.text = _linksToText(
        data['downloadLinks'],
        data['downloadUrl'],
      );
      _telegramUrl.text = (data['telegramUrl'] ?? '').toString();
      _telegramChat.text = (data['telegramChat'] ?? '').toString();
      _telegramMessageId.text = (data['telegramMessageId'] ?? '').toString();
      _ingestBaseUrl.text = (data['ingestBaseUrl'] ?? '').toString();
      _episodesText.text = _episodesToText(data['episodes']);
    });
  }

  String _linksToText(dynamic links, dynamic fallback) {
    if (links is List && links.isNotEmpty) {
      return links
          .map((entry) {
            if (entry is Map) return (entry['url'] ?? '').toString();
            return entry.toString();
          })
          .where((url) => url.trim().isNotEmpty)
          .join('\n');
    }
    return (fallback ?? '').toString();
  }

  List<String> _genresFromData(dynamic value, dynamic fallback) {
    final genres = <String>[];
    if (value is List) {
      for (final entry in value) {
        final genre = entry.toString().trim();
        if (genre.isNotEmpty && !genres.contains(genre)) genres.add(genre);
      }
    }
    if (genres.isEmpty) {
      for (final part in (fallback ?? '').toString().split(',')) {
        final genre = part.trim();
        if (genre.isNotEmpty && !genres.contains(genre)) genres.add(genre);
      }
    }
    return genres.isEmpty ? ['General'] : genres;
  }

  List<Map<String, dynamic>> _episodesFromText(String text) {
    final episodes = <Map<String, dynamic>>[];
    for (final rawLine in text.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;
      final parts = line.split('|').map((part) => part.trim()).toList();
      final label = parts.length > 1 && parts.first.isNotEmpty
          ? parts.first
          : 'Episode ${episodes.length + 1}';
      final cleanUrls = (parts.length > 1 ? parts.sublist(1) : [parts.first])
          .map((url) => url.trim())
          .where((url) => url.isNotEmpty)
          .toList();
      if (cleanUrls.isEmpty) continue;
      final telegramUrl = cleanUrls.firstWhere(
        (url) => parseTelegramPublicLink(url) != null,
        orElse: () => '',
      );
      episodes.add({
        'label': label,
        'telegramUrl': telegramUrl,
        'watchLinks': _serverLinksFromText(cleanUrls.join('\n')),
        'downloadLinks': _serverLinksFromText(cleanUrls.join('\n')),
      });
    }
    return episodes;
  }

  String _episodesToText(dynamic value) {
    if (value is! List) return '';
    final lines = <String>[];
    for (final entry in value) {
      if (entry is! Map) continue;
      final label = (entry['label'] ?? '').toString();
      final links = _linksToText(entry['watchLinks'], entry['telegramUrl']);
      if (links.isNotEmpty) {
        lines.add(
          '${label.isEmpty ? 'Episode ${lines.length + 1}' : label} | ${links.split('\n').join(' | ')}',
        );
      }
    }
    return lines.join('\n');
  }

  Future<void> _addGenre() async {
    final title = _genreTitle.text.trim();
    if (title.isEmpty) return;
    final docs = await FirebaseFirestore.instance
        .collection('genre_sections')
        .orderBy('order', descending: true)
        .limit(1)
        .get();
    final lastOrder = docs.docs.isEmpty
        ? -1
        : ((docs.docs.first.data()['order'] as int?) ?? -1);
    await FirebaseFirestore.instance
        .collection('genre_sections')
        .doc(title)
        .set({
          'title': title,
          'order': lastOrder + 1,
          'visible': true,
          'updatedAt': FieldValue.serverTimestamp(),
        });
    _genreTitle.clear();
  }

  Future<void> _createLicense() async {
    final days = int.tryParse(_licenseDays.text.trim()) ?? 0;
    if (days <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('License days must be greater than 0')),
      );
      return;
    }
    final key = _newLicenseKey();
    await FirebaseFirestore.instance.collection('license_keys').doc(key).set({
      'key': key,
      'name': _licenseName.text.trim(),
      'days': days,
      'createdAt': FieldValue.serverTimestamp(),
      'usedByDeviceHash': '',
      'usedByUid': '',
    });
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Created license key: $key')));
  }

  Future<void> _saveAd() async {
    if (_adTitle.text.trim().isEmpty) return;
    final payload = {
      'title': _adTitle.text.trim(),
      'subtitle': _adSubtitle.text.trim(),
      'imageUrl': _adImageUrl.text.trim(),
      'imageBase64': _adImageBase64.text.trim(),
      'actionUrl': _adActionUrl.text.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (_editingAdId == null) {
      await FirebaseFirestore.instance.collection('ads').add({
        ...payload,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } else {
      await FirebaseFirestore.instance
          .collection('ads')
          .doc(_editingAdId)
          .update(payload);
    }
    setState(() {
      _editingAdId = null;
      _adTitle.clear();
      _adSubtitle.clear();
      _adImageUrl.clear();
      _adImageBase64.clear();
      _adActionUrl.clear();
    });
  }

  Future<void> _sendAdminNotification() async {
    if (_notiTitle.text.trim().isEmpty) return;
    await FirebaseFirestore.instance.collection('notifications').add({
      'title': _notiTitle.text.trim(),
      'body': _notiBody.text.trim(),
      'photoUrl': _notiPhotoUrl.text.trim(),
      'link': _notiLink.text.trim(),
      'mediaId': _notiMediaId.text.trim(),
      'createdAt': FieldValue.serverTimestamp(),
      'createdBy': FirebaseAuth.instance.currentUser?.email ?? '',
    });
    setState(() {
      _notiTitle.clear();
      _notiBody.clear();
      _notiPhotoUrl.clear();
      _notiLink.clear();
      _notiMediaId.clear();
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Notification sent to active users')),
    );
  }

  void _editAd(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    setState(() {
      _editingAdId = doc.id;
      _adTitle.text = (data['title'] ?? '').toString();
      _adSubtitle.text = (data['subtitle'] ?? '').toString();
      _adImageUrl.text = (data['imageUrl'] ?? '').toString();
      _adImageBase64.text = (data['imageBase64'] ?? '').toString();
      _adActionUrl.text = (data['actionUrl'] ?? '').toString();
    });
  }

  Future<void> _pickPosterImage() {
    return _pickImageAsBase64(_posterBase64);
  }

  Future<void> _pickAdImage() {
    return _pickImageAsBase64(_adImageBase64);
  }

  Future<void> _pickImageAsBase64(TextEditingController controller) async {
    final messenger = ScaffoldMessenger.of(context);
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 82,
      maxWidth: 1200,
    );
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    final mime = picked.mimeType ?? _mimeFromName(picked.name);
    setState(() {
      controller.text = 'data:$mime;base64,${base64Encode(bytes)}';
    });
    messenger.showSnackBar(
      SnackBar(content: Text('${picked.name} converted to base64')),
    );
  }

  String _newLicenseKey() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final random = Random.secure();
    String part() =>
        List.generate(4, (_) => chars[random.nextInt(chars.length)]).join();
    return 'RELAX-${part()}-${part()}-${part()}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 920;
            return ListView(
              padding: const EdgeInsets.all(24),
              children: [
                _StudioHeader(firebaseReady: widget.firebaseReady),
                const SizedBox(height: 24),
                if (!widget.firebaseReady) const _ConfigNotice(),
                if (!widget.firebaseReady) const SizedBox(height: 18),
                if (!widget.firebaseReady)
                  const _LoginDisabledCard()
                else
                  StreamBuilder<User?>(
                    stream: FirebaseAuth.instance.authStateChanges(),
                    builder: (context, authSnapshot) {
                      if (authSnapshot.data == null) {
                        return const _LoginCard();
                      }
                      return _AdminDashboard(wide: wide, onOpen: _openSection);
                    },
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

enum _AdminSection {
  media(
    title: 'Media',
    subtitle: 'Add movies, series episodes, posters, and Telegram links.',
    icon: Icons.video_library_rounded,
  ),
  licenses(
    title: 'License Keys',
    subtitle: 'Create keys and separate no use keys from used keys.',
    icon: Icons.key_rounded,
  ),
  genres(
    title: 'Genre Order',
    subtitle: 'Arrange user app sections and hide or show genres.',
    icon: Icons.sort_rounded,
  ),
  ads(
    title: 'Ads',
    subtitle: 'Create and edit banners shown in the user app.',
    icon: Icons.campaign_rounded,
  ),
  notifications(
    title: 'Notifications',
    subtitle: 'Send title, body, photo, link, or media deeplink.',
    icon: Icons.notifications_active_rounded,
  );

  const _AdminSection({
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  final String title;
  final String subtitle;
  final IconData icon;
}

class _AdminDashboard extends StatelessWidget {
  const _AdminDashboard({required this.wide, required this.onOpen});

  final bool wide;
  final ValueChanged<_AdminSection> onOpen;

  @override
  Widget build(BuildContext context) {
    final sections = _AdminSection.values;
    if (!wide) {
      return Column(
        children: [
          for (final section in sections) ...[
            _AdminSectionCard(section: section, onOpen: () => onOpen(section)),
            if (section != sections.last) const SizedBox(height: 12),
          ],
        ],
      );
    }
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: sections.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        childAspectRatio: 2.8,
      ),
      itemBuilder: (context, index) {
        final section = sections[index];
        return _AdminSectionCard(
          section: section,
          onOpen: () => onOpen(section),
        );
      },
    );
  }
}

class _AdminSectionCard extends StatelessWidget {
  const _AdminSectionCard({required this.section, required this.onOpen});

  final _AdminSection section;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _panelDecoration(),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: const Color(0xFF1C2A3D),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(section.icon, color: const Color(0xFF4EE6A8)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  section.title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  section.subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Color(0xFFAAB4C8)),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          TextButton.icon(
            onPressed: onOpen,
            icon: const Icon(Icons.arrow_forward_rounded),
            label: const Text('More'),
          ),
        ],
      ),
    );
  }
}

class _AdminSectionPage extends StatelessWidget {
  const _AdminSectionPage({required this.section, required this.child});

  final _AdminSection section;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(section.title),
        backgroundColor: const Color(0xFF080B12),
        surfaceTintColor: Colors.transparent,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _SectionTitle(section: section),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.section});

  final _AdminSection section;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(section.icon, color: const Color(0xFF4EE6A8)),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                section.title,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                section.subtitle,
                style: const TextStyle(color: Color(0xFFAAB4C8)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AppSettingsPanel extends StatefulWidget {
  const _AppSettingsPanel();

  @override
  State<_AppSettingsPanel> createState() => _AppSettingsPanelState();
}

class _AppSettingsPanelState extends State<_AppSettingsPanel> {
  final _ingestBaseUrl = TextEditingController();
  final _apiId = TextEditingController();
  final _apiHash = TextEditingController();
  final _sessionString = TextEditingController();
  bool _loaded = false;
  bool _saving = false;

  @override
  void dispose() {
    _ingestBaseUrl.dispose();
    _apiId.dispose();
    _apiHash.dispose();
    _sessionString.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _saving = true);
    try {
      await FirebaseFirestore.instance
          .collection('app_settings')
          .doc('telegram')
          .set({
            'ingestBaseUrl': _ingestBaseUrl.text.trim(),
            'apiId': int.tryParse(_apiId.text.trim()) ?? _apiId.text.trim(),
            'apiHash': _apiHash.text.trim(),
            'sessionString': _sessionString.text.trim(),
            'updatedAt': FieldValue.serverTimestamp(),
            'updatedBy': FirebaseAuth.instance.currentUser?.email ?? '',
          }, SetOptions(merge: true));
      messenger.showSnackBar(
        const SnackBar(content: Text('Global Telethon settings saved')),
      );
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('Settings save failed: $error')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _panelDecoration(),
      child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('app_settings')
            .doc('telegram')
            .snapshots(),
        builder: (context, snapshot) {
          final data = snapshot.data?.data();
          if (!_loaded && data != null) {
            _loaded = true;
            _ingestBaseUrl.text = (data['ingestBaseUrl'] ?? '').toString();
            _apiId.text = (data['apiId'] ?? '').toString();
            _apiHash.text = (data['apiHash'] ?? '').toString();
            _sessionString.text = (data['sessionString'] ?? '').toString();
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Global Telethon settings',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              const Text(
                'Set this once. Movie and episode posts only need Telegram links.',
                style: TextStyle(color: Color(0xFFAAB4C8)),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _ingestBaseUrl,
                decoration: const InputDecoration(
                  labelText: 'Telethon server URL (optional)',
                  hintText:
                      'Leave empty to use app-local Telethon where supported',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _apiId,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Telegram API ID',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _apiHash,
                      decoration: const InputDecoration(
                        labelText: 'Telegram API hash',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _sessionString,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Telegram StringSession',
                  hintText: 'Used by app-local Telethon fallback',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.settings_rounded),
                  label: Text(_saving ? 'Saving...' : 'Save global setting'),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _GenreOrderPanel extends StatelessWidget {
  const _GenreOrderPanel({required this.titleController, required this.onAdd});

  final TextEditingController titleController;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _panelDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Genre order',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: titleController,
                  decoration: const InputDecoration(
                    labelText: 'New genre',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => onAdd(),
                ),
              ),
              const SizedBox(width: 10),
              FilledButton.icon(
                onPressed: onAdd,
                icon: const Icon(Icons.add_rounded),
                label: const Text('Add'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _seedDefaultGenres(context),
              icon: const Icon(Icons.playlist_add_check_rounded),
              label: const Text('Add default genre list'),
            ),
          ),
          const SizedBox(height: 14),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('genre_sections')
                .orderBy('order')
                .snapshots(),
            builder: (context, snapshot) {
              final docs = snapshot.data?.docs ?? [];
              if (docs.isEmpty) {
                return const Text(
                  'No custom genre order yet. Add Action, Drama, etc.',
                  style: TextStyle(color: Color(0xFFAAB4C8)),
                );
              }
              return SizedBox(
                height: 360,
                child: ReorderableListView.builder(
                  itemCount: docs.length,
                  onReorder: (oldIndex, newIndex) async {
                    if (newIndex > oldIndex) newIndex -= 1;
                    final reordered = [...docs];
                    final item = reordered.removeAt(oldIndex);
                    reordered.insert(newIndex, item);
                    final batch = FirebaseFirestore.instance.batch();
                    for (var i = 0; i < reordered.length; i++) {
                      batch.update(reordered[i].reference, {'order': i});
                    }
                    await batch.commit();
                  },
                  itemBuilder: (context, index) {
                    final doc = docs[index];
                    final data = doc.data();
                    final visible = data['visible'] != false;
                    return ListTile(
                      key: ValueKey(doc.id),
                      leading: const Icon(Icons.drag_handle_rounded),
                      title: Text((data['title'] ?? doc.id).toString()),
                      subtitle: Text('Order ${data['order'] ?? index}'),
                      trailing: Wrap(
                        spacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Switch(
                            value: visible,
                            onChanged: (value) =>
                                doc.reference.update({'visible': value}),
                          ),
                          IconButton(
                            tooltip: 'Move up',
                            icon: const Icon(Icons.keyboard_arrow_up_rounded),
                            onPressed: index == 0
                                ? null
                                : () => _moveGenre(docs, index, -1),
                          ),
                          IconButton(
                            tooltip: 'Move down',
                            icon: const Icon(Icons.keyboard_arrow_down_rounded),
                            onPressed: index == docs.length - 1
                                ? null
                                : () => _moveGenre(docs, index, 1),
                          ),
                          IconButton(
                            tooltip: 'Rename',
                            icon: const Icon(Icons.edit_rounded),
                            onPressed: () => _showTextUpdateDialog(
                              context,
                              title: 'Rename genre',
                              initialValue: (data['title'] ?? doc.id)
                                  .toString(),
                              onSave: (value) => doc.reference.update({
                                'title': value,
                                'updatedAt': FieldValue.serverTimestamp(),
                              }),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Delete',
                            icon: const Icon(Icons.delete_outline_rounded),
                            onPressed: () => doc.reference.delete(),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Future<void> _moveGenre(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    int index,
    int delta,
  ) async {
    final targetIndex = index + delta;
    if (targetIndex < 0 || targetIndex >= docs.length) return;
    final reordered = [...docs];
    final item = reordered.removeAt(index);
    reordered.insert(targetIndex, item);
    final batch = FirebaseFirestore.instance.batch();
    for (var i = 0; i < reordered.length; i++) {
      batch.update(reordered[i].reference, {
        'order': i,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  }

  Future<void> _seedDefaultGenres(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final collection = FirebaseFirestore.instance.collection('genre_sections');
    final existing = await collection.get();
    final existingIds = existing.docs.map((doc) => doc.id).toSet();
    final batch = FirebaseFirestore.instance.batch();
    var added = 0;
    for (var i = 0; i < _defaultGenreChoices.length; i++) {
      final title = _defaultGenreChoices[i];
      if (existingIds.contains(title)) continue;
      batch.set(collection.doc(title), {
        'title': title,
        'order': i,
        'visible': true,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      added++;
    }
    if (added == 0) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Genres already exist')),
      );
      return;
    }
    await batch.commit();
    messenger.showSnackBar(SnackBar(content: Text('Added $added genres')));
  }
}

class _LicensePanel extends StatelessWidget {
  const _LicensePanel({
    required this.nameController,
    required this.daysController,
    required this.onCreate,
  });

  final TextEditingController nameController;
  final TextEditingController daysController;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _panelDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'License keys',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Owner / note',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: daysController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Days',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onCreate,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Create license key'),
            ),
          ),
          const SizedBox(height: 16),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('license_keys')
                .orderBy('createdAt', descending: true)
                .snapshots(),
            builder: (context, snapshot) {
              final docs = snapshot.data?.docs ?? [];
              if (docs.isEmpty) {
                return const Text(
                  'No license keys yet.',
                  style: TextStyle(color: Color(0xFFAAB4C8)),
                );
              }
              final unused = docs.where((doc) => !_licenseUsed(doc)).toList();
              final used = docs.where(_licenseUsed).toList();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _LicenseGroup(
                    title: 'No use keys',
                    icon: Icons.key_rounded,
                    emptyText: 'No unused keys.',
                    docs: unused,
                  ),
                  const SizedBox(height: 14),
                  _LicenseGroup(
                    title: 'Used keys',
                    icon: Icons.lock_rounded,
                    emptyText: 'No used keys yet.',
                    docs: used,
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  bool _licenseUsed(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    return (data['usedByDeviceHash'] ?? '').toString().isNotEmpty ||
        (data['usedByUid'] ?? '').toString().isNotEmpty;
  }
}

class _LicenseGroup extends StatelessWidget {
  const _LicenseGroup({
    required this.title,
    required this.icon,
    required this.emptyText,
    required this.docs,
  });

  final String title;
  final IconData icon;
  final String emptyText;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1422),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF263247)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: const Color(0xFF4EE6A8)),
              const SizedBox(width: 8),
              Text(
                '$title (${docs.length})',
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (docs.isEmpty)
            Text(emptyText, style: const TextStyle(color: Color(0xFFAAB4C8)))
          else
            ...docs.map((doc) => _LicenseTile(doc: doc)),
        ],
      ),
    );
  }
}

class _LicenseTile extends StatelessWidget {
  const _LicenseTile({required this.doc});

  final QueryDocumentSnapshot<Map<String, dynamic>> doc;

  @override
  Widget build(BuildContext context) {
    final data = doc.data();
    final used =
        (data['usedByDeviceHash'] ?? '').toString().isNotEmpty ||
        (data['usedByUid'] ?? '').toString().isNotEmpty;
    final note = (data['name'] ?? '').toString();
    final usedBy = (data['usedByEmail'] ?? data['usedByUid'] ?? '').toString();
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: SelectableText(
        doc.id,
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
      subtitle: Text(
        [
          '${data['days'] ?? 0} days',
          if (note.isNotEmpty) note,
          if (used && usedBy.isNotEmpty) 'used by $usedBy',
        ].join(' • '),
      ),
      trailing: Wrap(
        spacing: 4,
        children: [
          IconButton(
            tooltip: 'Edit note',
            icon: const Icon(Icons.edit_rounded),
            onPressed: () => _showTextUpdateDialog(
              context,
              title: 'Edit license note',
              initialValue: note,
              onSave: (value) => doc.reference.update({
                'name': value,
                'updatedAt': FieldValue.serverTimestamp(),
              }),
            ),
          ),
          IconButton(
            tooltip: 'Delete unused key',
            icon: const Icon(Icons.delete_outline_rounded),
            onPressed: used ? null : () => doc.reference.delete(),
          ),
        ],
      ),
    );
  }
}

class _AdsPanel extends StatelessWidget {
  const _AdsPanel({
    required this.titleController,
    required this.subtitleController,
    required this.imageUrlController,
    required this.imageBase64Controller,
    required this.actionUrlController,
    required this.editing,
    required this.onSave,
    required this.onCancel,
    required this.onEdit,
    required this.onPickImage,
  });

  final TextEditingController titleController;
  final TextEditingController subtitleController;
  final TextEditingController imageUrlController;
  final TextEditingController imageBase64Controller;
  final TextEditingController actionUrlController;
  final bool editing;
  final VoidCallback onSave;
  final VoidCallback onCancel;
  final ValueChanged<QueryDocumentSnapshot<Map<String, dynamic>>> onEdit;
  final VoidCallback onPickImage;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _panelDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            editing ? 'Edit admin ad' : 'Admin ads CRUD',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          _field(titleController, 'Ad title'),
          const SizedBox(height: 10),
          _field(subtitleController, 'Ad subtitle'),
          const SizedBox(height: 10),
          _field(imageUrlController, 'Ad photo link'),
          const SizedBox(height: 10),
          _ImageBase64Field(
            controller: imageBase64Controller,
            label: 'Ad image',
            onPick: onPickImage,
          ),
          const SizedBox(height: 10),
          _field(actionUrlController, 'Action URL'),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: onSave,
                  icon: const Icon(Icons.campaign_rounded),
                  label: Text(editing ? 'Update ad' : 'Create ad'),
                ),
              ),
              if (editing) ...[
                const SizedBox(width: 10),
                OutlinedButton.icon(
                  onPressed: onCancel,
                  icon: const Icon(Icons.close_rounded),
                  label: const Text('Cancel'),
                ),
              ],
            ],
          ),
          const SizedBox(height: 16),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('ads')
                .orderBy('createdAt', descending: true)
                .snapshots(),
            builder: (context, snapshot) {
              final docs = snapshot.data?.docs ?? [];
              if (docs.isEmpty) {
                return const Text(
                  'No admin ads yet.',
                  style: TextStyle(color: Color(0xFFAAB4C8)),
                );
              }
              return Column(
                children: docs.map((doc) {
                  final data = doc.data();
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.campaign_rounded),
                    title: Text((data['title'] ?? 'Ad').toString()),
                    subtitle: Text((data['subtitle'] ?? '').toString()),
                    trailing: Wrap(
                      spacing: 4,
                      children: [
                        IconButton(
                          tooltip: 'Edit',
                          icon: const Icon(Icons.edit_rounded),
                          onPressed: () => onEdit(doc),
                        ),
                        IconButton(
                          tooltip: 'Delete',
                          icon: const Icon(Icons.delete_outline_rounded),
                          onPressed: () => doc.reference.delete(),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    int maxLines = 1,
  }) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
    );
  }
}

class _ImageBase64Field extends StatelessWidget {
  const _ImageBase64Field({
    required this.controller,
    required this.label,
    required this.onPick,
  });

  final TextEditingController controller;
  final String label;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        final hasImage = value.text.trim().isNotEmpty;
        final previewBytes = _decodeBase64Image(value.text);
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFF5D6A7F)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Container(
                    width: 72,
                    height: 96,
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      color: const Color(0xFF0B1220),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFF263247)),
                    ),
                    child: previewBytes == null
                        ? Icon(
                            hasImage
                                ? Icons.broken_image_rounded
                                : Icons.add_photo_alternate,
                            color: const Color(0xFF4EE6A8),
                          )
                        : Image.memory(previewBytes, fit: BoxFit.cover),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      hasImage ? 'Image ready' : 'No image selected',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Color(0xFFAAB4C8)),
                    ),
                  ),
                  if (hasImage)
                    IconButton(
                      tooltip: 'Clear image',
                      onPressed: controller.clear,
                      icon: const Icon(Icons.close_rounded),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: onPick,
                  icon: const Icon(Icons.upload_rounded),
                  label: const Text('Choose image'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

Uint8List? _decodeBase64Image(String value) {
  if (value.trim().isEmpty) return null;
  try {
    final clean = value.contains(',') ? value.split(',').last : value;
    return base64Decode(clean);
  } catch (_) {
    return null;
  }
}

class _EpisodeListEditor extends StatefulWidget {
  const _EpisodeListEditor({super.key, required this.controller});

  final TextEditingController controller;

  @override
  State<_EpisodeListEditor> createState() => _EpisodeListEditorState();
}

class _EpisodeListEditorState extends State<_EpisodeListEditor> {
  late final List<_EpisodeDraft> _episodes;

  @override
  void initState() {
    super.initState();
    _episodes = _parse(widget.controller.text);
    if (_episodes.isEmpty) _episodes.add(_EpisodeDraft.empty(1));
  }

  @override
  void dispose() {
    for (final episode in _episodes) {
      episode.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF5D6A7F)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.playlist_add_rounded, color: Color(0xFF4EE6A8)),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Episodes',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                ),
              ),
              FilledButton.icon(
                onPressed: _addEpisode,
                icon: const Icon(Icons.add_rounded),
                label: const Text('Add episode'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            'Add one public Telegram post per episode. The user app will show only episode names and playback controls.',
            style: TextStyle(color: Color(0xFFAAB4C8), fontSize: 12),
          ),
          const SizedBox(height: 12),
          ...List.generate(_episodes.length, (index) {
            final episode = _episodes[index];
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: const Color(0x224EE6A8),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: Text(
                        '${index + 1}',
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      children: [
                        TextField(
                          controller: episode.label,
                          decoration: const InputDecoration(
                            labelText: 'Episode title',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          onChanged: (_) => _sync(),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: episode.url,
                          minLines: 1,
                          maxLines: 3,
                          decoration: const InputDecoration(
                            labelText: 'Episode links',
                            hintText: 'One Telegram/direct link per line',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          onChanged: (_) => _sync(),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: 'Remove episode',
                    onPressed: _episodes.length == 1
                        ? null
                        : () => _removeEpisode(index),
                    icon: const Icon(Icons.delete_outline_rounded),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  void _addEpisode() {
    setState(() => _episodes.add(_EpisodeDraft.empty(_episodes.length + 1)));
    _sync();
  }

  void _removeEpisode(int index) {
    final episode = _episodes.removeAt(index);
    episode.dispose();
    setState(() {});
    _sync();
  }

  void _sync() {
    final lines = <String>[];
    for (var index = 0; index < _episodes.length; index++) {
      final episode = _episodes[index];
      final url = episode.url.text.trim();
      if (url.isEmpty) continue;
      final urls = url
          .split(RegExp(r'[\n,]+'))
          .map((entry) => entry.trim())
          .where((entry) => entry.isNotEmpty)
          .toList();
      if (urls.isEmpty) continue;
      final label = episode.label.text.trim().isEmpty
          ? 'Episode ${index + 1}'
          : episode.label.text.trim();
      lines.add('$label | ${urls.join(' | ')}');
    }
    widget.controller.text = lines.join('\n');
  }

  List<_EpisodeDraft> _parse(String value) {
    final drafts = <_EpisodeDraft>[];
    for (final rawLine in value.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;
      final parts = line.split('|').map((part) => part.trim()).toList();
      final label = parts.length > 1 && parts.first.isNotEmpty
          ? parts.first
          : 'Episode ${drafts.length + 1}';
      final url = parts.length > 1 ? parts.sublist(1).join('\n') : parts.first;
      drafts.add(_EpisodeDraft(label: label, url: url));
    }
    return drafts;
  }
}

class _EpisodeDraft {
  _EpisodeDraft({required String label, required String url})
    : label = TextEditingController(text: label),
      url = TextEditingController(text: url);

  factory _EpisodeDraft.empty(int index) {
    return _EpisodeDraft(label: 'Episode $index', url: '');
  }

  final TextEditingController label;
  final TextEditingController url;

  void dispose() {
    label.dispose();
    url.dispose();
  }
}

class _NotificationPanel extends StatelessWidget {
  const _NotificationPanel({
    required this.titleController,
    required this.bodyController,
    required this.photoUrlController,
    required this.linkController,
    required this.mediaIdController,
    required this.onSend,
  });

  final TextEditingController titleController;
  final TextEditingController bodyController;
  final TextEditingController photoUrlController;
  final TextEditingController linkController;
  final TextEditingController mediaIdController;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _panelDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Send notification',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          _field(titleController, 'Notification title'),
          const SizedBox(height: 10),
          _field(bodyController, 'Message body', maxLines: 3),
          const SizedBox(height: 10),
          _field(photoUrlController, 'Photo URL'),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _field(linkController, 'Open link')),
              const SizedBox(width: 10),
              Expanded(child: _field(mediaIdController, 'Movie ID')),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onSend,
              icon: const Icon(Icons.notifications_active_rounded),
              label: const Text('Send notification'),
            ),
          ),
          const SizedBox(height: 16),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('notifications')
                .orderBy('createdAt', descending: true)
                .limit(20)
                .snapshots(),
            builder: (context, snapshot) {
              final docs = snapshot.data?.docs ?? [];
              if (docs.isEmpty) {
                return const Text(
                  'No notifications sent yet.',
                  style: TextStyle(color: Color(0xFFAAB4C8)),
                );
              }
              return Column(
                children: docs.map((doc) {
                  final data = doc.data();
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.notifications_rounded),
                    title: Text((data['title'] ?? 'Relaxation').toString()),
                    subtitle: Text((data['body'] ?? '').toString()),
                    trailing: IconButton(
                      tooltip: 'Delete',
                      icon: const Icon(Icons.delete_outline_rounded),
                      onPressed: () => doc.reference.delete(),
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    int maxLines = 1,
  }) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
    );
  }
}

Future<void> _showTextUpdateDialog(
  BuildContext context, {
  required String title,
  required String initialValue,
  required Future<void> Function(String value) onSave,
}) async {
  final controller = TextEditingController(text: initialValue);
  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      var busy = false;
      return StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: Text(title),
            content: TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(border: OutlineInputBorder()),
            ),
            actions: [
              TextButton(
                onPressed: busy ? null : () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: busy
                    ? null
                    : () async {
                        setState(() => busy = true);
                        await onSave(controller.text.trim());
                        if (dialogContext.mounted) {
                          Navigator.of(dialogContext).pop();
                        }
                      },
                child: Text(busy ? 'Saving...' : 'Save'),
              ),
            ],
          );
        },
      );
    },
  );
  controller.dispose();
}

String _mimeFromName(String name) {
  final lower = name.toLowerCase();
  if (lower.endsWith('.png')) return 'image/png';
  if (lower.endsWith('.webp')) return 'image/webp';
  if (lower.endsWith('.gif')) return 'image/gif';
  return 'image/jpeg';
}

class _StudioHeader extends StatelessWidget {
  const _StudioHeader({required this.firebaseReady});

  final bool firebaseReady;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 560;
        final brand = Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: const LinearGradient(
                  colors: [Color(0xFF4EE6A8), Color(0xFF5B8DEF)],
                ),
              ),
              child: const Icon(
                Icons.admin_panel_settings_rounded,
                color: Color(0xFF071018),
              ),
            ),
            const SizedBox(width: 14),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Relaxation Studio',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Add movies and episodes with Telegram links',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Color(0xFFAAB4C8)),
                  ),
                ],
              ),
            ),
          ],
        );
        final status = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Chip(
              avatar: Icon(
                firebaseReady
                    ? Icons.cloud_done_rounded
                    : Icons.cloud_off_rounded,
                size: 18,
              ),
              label: Text(firebaseReady ? 'Firestore ready' : 'Config needed'),
            ),
            if (firebaseReady) ...[
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Sign out',
                onPressed: () => FirebaseAuth.instance.signOut(),
                icon: const Icon(Icons.logout_rounded),
              ),
            ],
          ],
        );
        if (compact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [brand, const SizedBox(height: 12), status],
          );
        }
        return Row(
          children: [
            Expanded(child: brand),
            const SizedBox(width: 12),
            status,
          ],
        );
      },
    );
  }
}

class _LoginDisabledCard extends StatelessWidget {
  const _LoginDisabledCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _panelDecoration(),
      child: const Text('Configure Firebase before signing in to Studio.'),
    );
  }
}

class _LoginCard extends StatefulWidget {
  const _LoginCard();

  @override
  State<_LoginCard> createState() => _LoginCardState();
}

class _LoginCardState extends State<_LoginCard> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _email.text.trim(),
        password: _password.text,
      );
    } on FirebaseAuthException catch (error) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            error.message ??
                (error.code == 'invalid-credential'
                    ? 'Account not found or password is wrong.'
                    : error.code),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 460),
      padding: const EdgeInsets.all(18),
      decoration: _panelDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Admin sign in',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _email,
            decoration: const InputDecoration(
              labelText: 'Email',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _password,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Password',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => _login(),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _busy ? null : _login,
              icon: const Icon(Icons.login_rounded),
              label: Text(_busy ? 'Please wait...' : 'Sign in'),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConfigNotice extends StatelessWidget {
  const _ConfigNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0x22FFC857),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0x66FFC857)),
      ),
      child: const Text(
        'Firebase is not ready on this build. Rebuild after Firebase configuration is written.',
        style: TextStyle(color: Color(0xFFFFE4A3)),
      ),
    );
  }
}

class _EditorCard extends StatelessWidget {
  const _EditorCard({
    required this.formKey,
    required this.title,
    required this.selectedGenres,
    required this.quality,
    required this.description,
    required this.posterBase64,
    required this.telegramUrl,
    required this.watchLinks,
    required this.downloadLinks,
    required this.episodesText,
    required this.type,
    required this.saving,
    required this.editing,
    required this.firebaseReady,
    required this.onTypeChanged,
    required this.onAddGenre,
    required this.onRemoveGenre,
    required this.onApplyTelegramLink,
    required this.onSave,
    required this.onCancelEdit,
    required this.onPickPoster,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController title;
  final List<String> selectedGenres;
  final TextEditingController quality;
  final TextEditingController description;
  final TextEditingController posterBase64;
  final TextEditingController telegramUrl;
  final TextEditingController watchLinks;
  final TextEditingController downloadLinks;
  final TextEditingController episodesText;
  final String type;
  final bool saving;
  final bool editing;
  final bool firebaseReady;
  final ValueChanged<String> onTypeChanged;
  final ValueChanged<String> onAddGenre;
  final ValueChanged<String> onRemoveGenre;
  final VoidCallback onApplyTelegramLink;
  final VoidCallback onSave;
  final VoidCallback onCancelEdit;
  final VoidCallback onPickPoster;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _panelDecoration(),
      child: Form(
        key: formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              editing ? 'Edit media' : 'Add media',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: title,
              decoration: const InputDecoration(
                labelText: 'Title',
                border: OutlineInputBorder(),
              ),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Title is required'
                  : null,
            ),
            const SizedBox(height: 12),
            SegmentedButton<String>(
              selected: {type},
              segments: const [
                ButtonSegment(
                  value: 'movie',
                  label: Text('Movie'),
                  icon: Icon(Icons.movie_rounded),
                ),
                ButtonSegment(
                  value: 'series',
                  label: Text('Series'),
                  icon: Icon(Icons.live_tv_rounded),
                ),
              ],
              onSelectionChanged: (value) => onTypeChanged(value.first),
            ),
            const SizedBox(height: 12),
            Row(children: [Expanded(child: _field(quality, 'Quality'))]),
            const SizedBox(height: 12),
            _GenreMultiPicker(
              selectedGenres: selectedGenres,
              onAdd: onAddGenre,
              onRemove: onRemoveGenre,
            ),
            const SizedBox(height: 12),
            _field(description, 'Description', maxLines: 3),
            const SizedBox(height: 12),
            _ImageBase64Field(
              controller: posterBase64,
              label: 'Poster',
              onPick: onPickPoster,
            ),
            const SizedBox(height: 12),
            if (type == 'series')
              _EpisodeListEditor(
                key: ValueKey(episodesText.text.hashCode),
                controller: episodesText,
              )
            else ...[
              TextFormField(
                controller: telegramUrl,
                decoration: InputDecoration(
                  labelText: 'Movie Telegram link',
                  hintText: 'https://t.me/MagicChineseSeriesPage/18499',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    tooltip: 'Check link',
                    onPressed: () => onApplyTelegramLink(),
                    icon: const Icon(Icons.check_circle_rounded),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              _field(
                watchLinks,
                'Extra watch links (one link per line)',
                maxLines: 3,
              ),
              const SizedBox(height: 10),
              _field(
                downloadLinks,
                'Extra download links (one link per line)',
                maxLines: 3,
              ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: firebaseReady && !saving ? onSave : null,
                    icon: saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save_rounded),
                    label: Text(
                      saving
                          ? 'Saving...'
                          : editing
                          ? 'Update media'
                          : 'Save to Firestore',
                    ),
                  ),
                ),
                if (editing) ...[
                  const SizedBox(width: 10),
                  OutlinedButton.icon(
                    onPressed: saving ? null : onCancelEdit,
                    icon: const Icon(Icons.close_rounded),
                    label: const Text('Cancel'),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    int maxLines = 1,
  }) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
    );
  }
}

class _GenreMultiPicker extends StatelessWidget {
  const _GenreMultiPicker({
    required this.selectedGenres,
    required this.onAdd,
    required this.onRemove,
  });

  final List<String> selectedGenres;
  final ValueChanged<String> onAdd;
  final ValueChanged<String> onRemove;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('genre_sections')
          .orderBy('order')
          .snapshots(),
      builder: (context, snapshot) {
        final genres =
            snapshot.data?.docs
                .map((doc) => (doc.data()['title'] ?? doc.id).toString())
                .where((title) => title.trim().isNotEmpty)
                .toList() ??
            const <String>[];
        final choices = genres.isEmpty ? _defaultGenreChoices : genres;
        final available = choices
            .where((genre) => !selectedGenres.contains(genre))
            .toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DropdownButtonFormField<String>(
              initialValue: null,
              items: available
                  .map(
                    (genre) =>
                        DropdownMenuItem(value: genre, child: Text(genre)),
                  )
                  .toList(),
              onChanged: (value) {
                if (value != null) onAdd(value);
              },
              decoration: const InputDecoration(
                labelText: 'Add genre',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            if (selectedGenres.isEmpty)
              const Text(
                'No genre selected.',
                style: TextStyle(color: Color(0xFFAAB4C8)),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: selectedGenres
                    .map(
                      (genre) => InputChip(
                        label: Text(genre),
                        onDeleted: () => onRemove(genre),
                      ),
                    )
                    .toList(),
              ),
          ],
        );
      },
    );
  }
}

class _LibraryPanel extends StatefulWidget {
  const _LibraryPanel({required this.firebaseReady, required this.onEdit});

  final bool firebaseReady;
  final ValueChanged<QueryDocumentSnapshot<Map<String, dynamic>>> onEdit;

  @override
  State<_LibraryPanel> createState() => _LibraryPanelState();
}

class _LibraryPanelState extends State<_LibraryPanel> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _panelDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Firestore media',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _search,
            onChanged: (value) => setState(() => _query = value.trim()),
            decoration: InputDecoration(
              labelText: 'Search title, genre, quality',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear search',
                      onPressed: () {
                        _search.clear();
                        setState(() => _query = '');
                      },
                      icon: const Icon(Icons.close_rounded),
                    ),
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 14),
          if (!widget.firebaseReady)
            const Text(
              'Connect Firebase to see documents here.',
              style: TextStyle(color: Color(0xFFAAB4C8)),
            )
          else
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('media')
                  .orderBy('createdAt', descending: true)
                  .limit(200)
                  .snapshots(),
              builder: (context, snapshot) {
                final docs = (snapshot.data?.docs ?? [])
                    .where(_matches)
                    .toList();
                if (docs.isEmpty) {
                  return const Text(
                    'No media documents yet.',
                    style: TextStyle(color: Color(0xFFAAB4C8)),
                  );
                }
                return Column(
                  children: docs.map((doc) {
                    final data = doc.data();
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.video_library_rounded),
                      title: Text((data['title'] ?? 'Untitled').toString()),
                      subtitle: Text(
                        '${data['type'] ?? 'movie'} • ${data['quality'] ?? 'HD'}',
                      ),
                      trailing: Wrap(
                        spacing: 4,
                        children: [
                          IconButton(
                            tooltip: 'Edit',
                            icon: const Icon(Icons.edit_rounded),
                            onPressed: () => widget.onEdit(doc),
                          ),
                          IconButton(
                            tooltip: 'Delete',
                            icon: const Icon(Icons.delete_outline_rounded),
                            onPressed: () => doc.reference.delete(),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                );
              },
            ),
        ],
      ),
    );
  }

  bool _matches(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    if (_query.isEmpty) return true;
    final data = doc.data();
    final query = _query.toLowerCase();
    final genres = data['genres'] is List
        ? (data['genres'] as List).join(', ')
        : (data['genre'] ?? '').toString();
    return (data['title'] ?? '').toString().toLowerCase().contains(query) ||
        (data['type'] ?? '').toString().toLowerCase().contains(query) ||
        (data['quality'] ?? '').toString().toLowerCase().contains(query) ||
        genres.toLowerCase().contains(query);
  }
}

BoxDecoration _panelDecoration() {
  return BoxDecoration(
    color: const Color(0xFF111827),
    borderRadius: BorderRadius.circular(22),
    border: Border.all(color: const Color(0xFF263247)),
  );
}

const _defaultGenreChoices = [
  'Latest Movies',
  'Latest Series',
  'Ongoing Series',
  'Completed Series',
  'Action',
  'Adventure',
  'Animation',
  'Biography',
  'Comedy',
  'Crime',
  'Documentary',
  'Drama',
  'Family',
  'Fantasy',
  'Historical',
  'Horror',
  'Investigation',
  'Martial Arts',
  'Medical',
  'Mystery',
  'Political',
  'Romance',
  'Sci-Fi',
  'Sport',
  'Supernatural',
  'Thriller',
  'War',
  'Western',
  'Chinese',
  'Korean',
  'Thai',
  'Japanese',
  'Indian',
  'Hollywood',
  'Myanmar',
];

class TelegramPostRef {
  const TelegramPostRef({required this.chat, required this.messageId});

  final String chat;
  final int messageId;
}

TelegramPostRef? parseTelegramPublicLink(String value) {
  var input = value.trim();
  if (input.isEmpty) {
    return null;
  }
  if (!input.contains('://') && RegExp(r'^[A-Za-z0-9_]+/\d+').hasMatch(input)) {
    input = 'https://t.me/$input';
  }

  final uri = Uri.tryParse(input);
  if (uri == null) {
    return null;
  }
  final host = uri.host.toLowerCase();
  if (!{'t.me', 'telegram.me', 'telegram.dog'}.contains(host)) {
    return null;
  }
  final rawSegments = uri.pathSegments
      .where((segment) => segment.isNotEmpty)
      .toList();
  if (rawSegments.length >= 3 && rawSegments[0] == 'c') {
    final privateChannelId = int.tryParse(rawSegments[1]);
    final messageId = int.tryParse(rawSegments[2]);
    if (privateChannelId == null || messageId == null) {
      return null;
    }
    return TelegramPostRef(chat: '-100$privateChannelId', messageId: messageId);
  }
  final segments = rawSegments.where((segment) => segment != 's').toList();
  if (segments.length < 2) {
    return null;
  }
  final chat = segments[0];
  final messageId = int.tryParse(segments[1]);
  if (chat.isEmpty || messageId == null) {
    return null;
  }
  return TelegramPostRef(chat: chat, messageId: messageId);
}

List<Map<String, String>> _serverLinksFromText(String value) {
  final links = <Map<String, String>>[];
  final lines = value
      .split(RegExp(r'[\r\n]+'))
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty);
  for (final line in lines) {
    links.add({'label': 'Server ${links.length + 1}', 'url': line});
  }
  return links;
}
