import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'models/media_content.dart';
import 'services/access_service.dart';
import 'services/android_telethon_service.dart';
import 'services/download_service.dart';
import 'services/firebase_bootstrap.dart';
import 'services/local_telethon_service.dart';
import 'services/media_repository.dart';
import 'services/notification_service.dart';
import 'services/telethon_resolver.dart';
import 'services/telegram_auth_service.dart';

final appNavigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final firebaseReady = await FirebaseBootstrap.initialize();
  runApp(RelaxationApp(firebaseReady: firebaseReady));
}

class RelaxationApp extends StatelessWidget {
  const RelaxationApp({super.key, required this.firebaseReady});

  final bool firebaseReady;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: appNavigatorKey,
      title: 'Relaxation',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF050812),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF33F0B0),
          brightness: Brightness.dark,
          primary: const Color(0xFF33F0B0),
          secondary: const Color(0xFFFFC857),
          surface: const Color(0xFF101827),
        ),
      ),
      home: firebaseReady
          ? const AuthGate()
          : RelaxationHome(firebaseReady: firebaseReady),
    );
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  final _access = AccessService();
  Future<void>? _anonymousSignIn;

  Future<void> _ensureAnonymousSignIn() {
    return _anonymousSignIn ??= _access.signInAnonymously();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: _access.authStateChanges(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return FutureBuilder<void>(
            future: _ensureAnonymousSignIn(),
            builder: (context, signInSnapshot) {
              if (signInSnapshot.hasError) {
                return RelaxationHome(
                  firebaseReady: true,
                  accessService: _access,
                );
              }
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            },
          );
        }
        NotificationService.instance.start();
        return StreamBuilder<AccessState>(
          stream: _access.watchAccess(),
          builder: (context, accessSnapshot) {
            return RelaxationHome(
              firebaseReady: true,
              accessState: accessSnapshot.data,
              accessService: _access,
            );
          },
        );
      },
    );
  }
}

class TelegramSignInScreen extends StatefulWidget {
  const TelegramSignInScreen({super.key, required this.access});

  final AccessService access;

  @override
  State<TelegramSignInScreen> createState() => _TelegramSignInScreenState();
}

class _TelegramSignInScreenState extends State<TelegramSignInScreen> {
  final _telegramAuth = TelegramAuthService();
  final _phone = TextEditingController(text: '+95');
  final _code = TextEditingController();
  final _password = TextEditingController();
  _TelegramLoginStep _step = _TelegramLoginStep.phone;
  bool _busy = false;
  bool _checking = true;

  @override
  void initState() {
    super.initState();
    _checkExisting();
  }

  Future<void> _checkExisting() async {
    try {
      final state = await _telegramAuth.status();
      if (state.authorized) {
        await _ensureFirebaseAccess();
      }
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  void dispose() {
    _phone.dispose();
    _code.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    if (_phone.text.trim().length < 8) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter your Telegram phone number.')),
      );
      return;
    }
    await _runBusy(() async {
      await _telegramAuth.sendCode(_phone.text);
      setState(() => _step = _TelegramLoginStep.code);
    });
  }

  Future<void> _verifyCode() async {
    if (_code.text.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Enter the Telegram code.')));
      return;
    }
    await _runBusy(() async {
      final complete = await _telegramAuth.signInWithCode(
        _phone.text,
        _code.text,
      );
      if (complete) {
        await _ensureFirebaseAccess();
      } else {
        setState(() => _step = _TelegramLoginStep.password);
      }
    });
  }

  Future<void> _verifyPassword() async {
    if (_password.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter your Telegram 2FA password.')),
      );
      return;
    }
    await _runBusy(() async {
      await _telegramAuth.signInWithPassword(_password.text);
      await _ensureFirebaseAccess();
    });
  }

  Future<void> _ensureFirebaseAccess() async {
    if (widget.access.auth.currentUser == null) {
      await widget.access.signInAnonymously();
    }
    await widget.access.startTrialAfterTelegramLogin();
    if (mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _runBusy(Future<void> Function() action) async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(22),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 440),
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: const Color(0xFF101827),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: const Color(0xFF263247)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Relaxation',
                    style: TextStyle(fontSize: 34, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Use your Telegram account to stream public channel videos. No Gmail login required.',
                    style: TextStyle(color: Color(0xFFB8C4D8)),
                  ),
                  const SizedBox(height: 22),
                  if (_step == _TelegramLoginStep.phone) ...[
                    TextField(
                      controller: _phone,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'Telegram phone number',
                        hintText: '+959...',
                        prefixIcon: Icon(Icons.phone_rounded),
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => _sendCode(),
                    ),
                  ] else if (_step == _TelegramLoginStep.code) ...[
                    TextField(
                      controller: _code,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Telegram code',
                        prefixIcon: Icon(Icons.sms_rounded),
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => _verifyCode(),
                    ),
                    const SizedBox(height: 10),
                    TextButton.icon(
                      onPressed: _busy
                          ? null
                          : () => setState(
                              () => _step = _TelegramLoginStep.phone,
                            ),
                      icon: const Icon(Icons.edit_rounded),
                      label: const Text('Change phone number'),
                    ),
                  ] else ...[
                    TextField(
                      controller: _password,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Telegram 2FA password',
                        prefixIcon: Icon(Icons.lock_rounded),
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => _verifyPassword(),
                    ),
                  ],
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _busy
                          ? null
                          : _step == _TelegramLoginStep.phone
                          ? _sendCode
                          : _step == _TelegramLoginStep.code
                          ? _verifyCode
                          : _verifyPassword,
                      icon: Icon(
                        _step == _TelegramLoginStep.phone
                            ? Icons.send_rounded
                            : Icons.login_rounded,
                      ),
                      label: Text(
                        _busy
                            ? 'Please wait...'
                            : _step == _TelegramLoginStep.phone
                            ? 'Send Telegram Code'
                            : _step == _TelegramLoginStep.code
                            ? 'Verify Code'
                            : 'Verify Password',
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Telegram does not provide one-click MTProto login. A phone code is required so the app can stream video links directly.',
                    style: TextStyle(color: Color(0xFF91A1BC), fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

enum _TelegramLoginStep { phone, code, password }

class RelaxationHome extends StatelessWidget {
  RelaxationHome({
    super.key,
    required this.firebaseReady,
    this.accessState,
    AccessService? accessService,
  }) : accessService = accessService ?? AccessService();

  final bool firebaseReady;
  final AccessState? accessState;
  final AccessService accessService;
  final MediaRepository _repository = MediaRepository();

  @override
  Widget build(BuildContext context) {
    if (!firebaseReady) {
      return Scaffold(
        drawer: RelaxationDrawer(
          firebaseReady: false,
          accessState: null,
          accessService: accessService,
        ),
        body: SafeArea(
          child: _HomeCatalog(
            items: MediaRepository.demoItems,
            ads: MediaRepository.demoAds,
            genreSections: MediaRepository.demoGenreSections,
            firebaseReady: false,
            accessState: null,
            accessService: accessService,
          ),
        ),
      );
    }

    return Scaffold(
      drawer: RelaxationDrawer(
        firebaseReady: true,
        accessState: accessState,
        accessService: accessService,
      ),
      body: SafeArea(
        child: StreamBuilder<List<MediaContent>>(
          stream: _repository.watchMedia(),
          builder: (context, mediaSnapshot) {
            return StreamBuilder<List<AdminAd>>(
              stream: _repository.watchAds(),
              builder: (context, adSnapshot) {
                return StreamBuilder<List<GenreSection>>(
                  stream: _repository.watchGenreSections(),
                  builder: (context, genreSnapshot) {
                    return _HomeCatalog(
                      items: mediaSnapshot.data ?? MediaRepository.demoItems,
                      ads: adSnapshot.data ?? MediaRepository.demoAds,
                      genreSections:
                          genreSnapshot.data ??
                          MediaRepository.demoGenreSections,
                      firebaseReady: true,
                      accessState: accessState,
                      accessService: accessService,
                    );
                  },
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _HomeCatalog extends StatefulWidget {
  const _HomeCatalog({
    required this.items,
    required this.ads,
    required this.genreSections,
    required this.firebaseReady,
    required this.accessState,
    required this.accessService,
  });

  final List<MediaContent> items;
  final List<AdminAd> ads;
  final List<GenreSection> genreSections;
  final bool firebaseReady;
  final AccessState? accessState;
  final AccessService accessService;

  @override
  State<_HomeCatalog> createState() => _HomeCatalogState();
}

class _HomeCatalogState extends State<_HomeCatalog> {
  final _pageController = PageController(viewportFraction: .88);
  int _heroIndex = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final newestMovies = widget.items
        .where((item) => item.type == MediaType.movie)
        .take(15)
        .toList();
    final newestSeries = widget.items
        .where((item) => item.type == MediaType.series)
        .take(15)
        .toList();
    final genres = _groupByGenre(widget.items);

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _TopChrome(firebaseReady: widget.firebaseReady),
                if (widget.firebaseReady) ...[
                  const SizedBox(height: 12),
                  AccessStatusBar(
                    state: widget.accessState,
                    accessService: widget.accessService,
                  ),
                ],
                const SizedBox(height: 18),
                _FeaturedSlider(
                  controller: _pageController,
                  items: widget.items.take(6).toList(),
                  currentIndex: _heroIndex,
                  accessState: widget.accessState,
                  accessService: widget.accessService,
                  onChanged: (value) => setState(() => _heroIndex = value),
                ),
                const SizedBox(height: 16),
                _AdminAdsRail(ads: widget.ads),
                if (!widget.firebaseReady) ...[
                  const SizedBox(height: 14),
                  const _DemoModeNotice(),
                ],
                const SizedBox(height: 22),
                if (newestMovies.isNotEmpty)
                  MediaRail(
                    title: 'Newest Movies',
                    items: newestMovies,
                    allItems: widget.items
                        .where((item) => item.type == MediaType.movie)
                        .toList(),
                    accessState: widget.accessState,
                    accessService: widget.accessService,
                  ),
                if (newestSeries.isNotEmpty)
                  MediaRail(
                    title: 'Newest Series',
                    items: newestSeries,
                    allItems: widget.items
                        .where((item) => item.type == MediaType.series)
                        .toList(),
                    accessState: widget.accessState,
                    accessService: widget.accessService,
                  ),
                ..._orderedGenreEntries(genres, widget.genreSections).map(
                  (entry) => MediaRail(
                    title: entry.key,
                    items: entry.value,
                    allItems: entry.value,
                    accessState: widget.accessState,
                    accessService: widget.accessService,
                  ),
                ),
                const SizedBox(height: 34),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Map<String, List<MediaContent>> _groupByGenre(List<MediaContent> items) {
    final grouped = <String, List<MediaContent>>{};
    for (final item in items) {
      final genre = item.genre.trim().isEmpty ? 'General' : item.genre.trim();
      grouped.putIfAbsent(genre, () => []).add(item);
    }
    return Map.fromEntries(
      grouped.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
    );
  }

  List<MapEntry<String, List<MediaContent>>> _orderedGenreEntries(
    Map<String, List<MediaContent>> genres,
    List<GenreSection> sections,
  ) {
    final visible = sections.where((section) => section.visible).toList();
    final ordered = <MapEntry<String, List<MediaContent>>>[];
    for (final section in visible) {
      final items = genres.remove(section.title);
      if (items != null && items.isNotEmpty) {
        ordered.add(MapEntry(section.title, items));
      }
    }
    ordered.addAll(genres.entries);
    return ordered;
  }
}

class AccessStatusBar extends StatelessWidget {
  const AccessStatusBar({
    super.key,
    required this.state,
    required this.accessService,
  });

  final AccessState? state;
  final AccessService accessService;

  @override
  Widget build(BuildContext context) {
    final text = state == null
        ? 'Checking access...'
        : state!.hasAccess
        ? state!.isPremium
              ? 'Premium active • ${state!.daysLeft} days left'
              : 'Free trial • ${state!.daysLeft} days left'
        : state!.trialExpiresAt == null
        ? 'Login with Telegram to start 3-day trial'
        : 'Trial expired • Activate license';
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () => showLicenseDialog(context, accessService),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: const Color(0xFF101827),
          border: Border.all(color: const Color(0xFF263247)),
        ),
        child: Row(
          children: [
            Icon(
              state?.hasAccess == true
                  ? Icons.verified_rounded
                  : Icons.lock_clock_rounded,
              color: state?.hasAccess == true
                  ? const Color(0xFF33F0B0)
                  : const Color(0xFFFFC857),
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(text)),
            const Icon(Icons.key_rounded, size: 18),
          ],
        ),
      ),
    );
  }
}

class RelaxationDrawer extends StatelessWidget {
  const RelaxationDrawer({
    super.key,
    required this.firebaseReady,
    required this.accessState,
    required this.accessService,
  });

  final bool firebaseReady;
  final AccessState? accessState;
  final AccessService accessService;

  @override
  Widget build(BuildContext context) {
    final user = firebaseReady ? accessService.auth.currentUser : null;
    final expireDate = accessState == null
        ? 'Checking...'
        : accessState!.expiryDate == null
        ? accessState!.trialExpiresAt == null
              ? 'Not started'
              : 'Expired'
        : formatDate(accessState!.expiryDate!);
    return Drawer(
      backgroundColor: const Color(0xFF080D18),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 68,
                height: 68,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(22),
                  gradient: const LinearGradient(
                    colors: [Color(0xFF33F0B0), Color(0xFF5B8DEF)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: const [
                    BoxShadow(color: Color(0x6633F0B0), blurRadius: 30),
                  ],
                ),
                child: const Icon(
                  Icons.play_circle_fill_rounded,
                  color: Color(0xFF05100B),
                  size: 42,
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'Relaxation',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 4),
              const Text(
                'Movies & Series',
                style: TextStyle(color: Color(0xFF91A1BC)),
              ),
              const SizedBox(height: 22),
              _DrawerInfoTile(
                icon: Icons.account_circle_rounded,
                label: 'User account',
                value:
                    user?.email ??
                    (firebaseReady ? 'Not signed in' : 'Demo mode'),
              ),
              const SizedBox(height: 10),
              _DrawerInfoTile(
                icon: Icons.event_available_rounded,
                label: 'Expire date',
                value: expireDate,
              ),
              const SizedBox(height: 14),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(
                  Icons.download_done_rounded,
                  color: Color(0xFF33F0B0),
                ),
                title: const Text('Downloads'),
                subtitle: const Text(
                  'Saved videos and active downloads',
                  style: TextStyle(color: Color(0xFF91A1BC)),
                ),
                onTap: () {
                  Navigator.of(context).pop();
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const DownloadHistoryScreen(),
                    ),
                  );
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(
                  Icons.support_agent_rounded,
                  color: Color(0xFF33F0B0),
                ),
                title: const Text('Contact to admin'),
                subtitle: const Text(
                  'Telegram message: Relaxation',
                  style: TextStyle(color: Color(0xFF91A1BC)),
                ),
                onTap: () => openAdminContact(),
              ),
              if (firebaseReady && user != null)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.logout_rounded),
                  title: const Text('Logout'),
                  onTap: () {
                    Navigator.of(context).pop();
                    accessService.signOut();
                  },
                ),
              const Spacer(),
              const Divider(color: Color(0xFF263247)),
              const SizedBox(height: 8),
              const Text(
                'App Version 1.0.0',
                style: TextStyle(
                  color: Color(0xFF91A1BC),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DrawerInfoTile extends StatelessWidget {
  const _DrawerInfoTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF101827),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF263247)),
      ),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF33F0B0)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: Color(0xFF91A1BC),
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TopChrome extends StatelessWidget {
  const _TopChrome({required this.firebaseReady});

  final bool firebaseReady;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Builder(
          builder: (context) {
            return IconButton.filledTonal(
              tooltip: 'Menu',
              onPressed: () => Scaffold.of(context).openDrawer(),
              icon: const Icon(Icons.menu_rounded),
            );
          },
        ),
        const SizedBox(width: 10),
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: const LinearGradient(
              colors: [Color(0xFF33F0B0), Color(0xFF5B8DEF)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: const [
              BoxShadow(color: Color(0x4433F0B0), blurRadius: 22),
            ],
          ),
          child: const Icon(
            Icons.play_circle_fill_rounded,
            color: Color(0xFF05100B),
            size: 32,
          ),
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Relaxation',
                style: TextStyle(
                  fontSize: 25,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0,
                ),
              ),
              Text(
                'Movies & Series',
                style: TextStyle(color: Color(0xFF91A1BC), fontSize: 13),
              ),
            ],
          ),
        ),
        AnimatedContainer(
          duration: const Duration(milliseconds: 260),
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: firebaseReady
                ? const Color(0x2233F0B0)
                : const Color(0x22FFC857),
            borderRadius: BorderRadius.circular(15),
            border: Border.all(
              color: firebaseReady
                  ? const Color(0x6633F0B0)
                  : const Color(0x66FFC857),
            ),
          ),
          child: Icon(
            firebaseReady ? Icons.cloud_done_rounded : Icons.cloud_off_rounded,
            color: firebaseReady
                ? const Color(0xFF33F0B0)
                : const Color(0xFFFFC857),
          ),
        ),
      ],
    );
  }
}

class _FeaturedSlider extends StatelessWidget {
  const _FeaturedSlider({
    required this.controller,
    required this.items,
    required this.currentIndex,
    required this.accessState,
    required this.accessService,
    required this.onChanged,
  });

  final PageController controller;
  final List<MediaContent> items;
  final int currentIndex;
  final AccessState? accessState;
  final AccessService accessService;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      children: [
        SizedBox(
          height: 250,
          child: PageView.builder(
            controller: controller,
            onPageChanged: onChanged,
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              return AnimatedScale(
                duration: const Duration(milliseconds: 280),
                scale: currentIndex == index ? 1 : .94,
                child: Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: FeaturedCard(
                    item: item,
                    accessState: accessState,
                    accessService: accessService,
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(items.length, (index) {
            final active = index == currentIndex;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              width: active ? 24 : 7,
              height: 7,
              margin: const EdgeInsets.symmetric(horizontal: 3),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(99),
                color: active
                    ? const Color(0xFF33F0B0)
                    : const Color(0xFF334057),
              ),
            );
          }),
        ),
      ],
    );
  }
}

class FeaturedCard extends StatelessWidget {
  const FeaturedCard({
    super.key,
    required this.item,
    required this.accessState,
    required this.accessService,
  });

  final MediaContent item;
  final AccessState? accessState;
  final AccessService accessService;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(30),
      onTap: () => openDetails(context, item, accessState, accessService),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(30),
          gradient: const LinearGradient(
            colors: [Color(0xFF182238), Color(0xFF101827), Color(0xFF172820)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(color: const Color(0xFF263247)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x77000000),
              blurRadius: 26,
              offset: Offset(0, 18),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Positioned.fill(
              child: PosterFrame(item: item, fit: BoxFit.cover),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.black.withValues(alpha: .05),
                      Colors.black.withValues(alpha: .78),
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
              ),
            ),
            Positioned(
              left: 18,
              right: 18,
              bottom: 18,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 28,
                      height: 1,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${item.type.label} • ${item.genre} • ${item.quality}',
                    style: const TextStyle(
                      color: Color(0xFFE6ECF7),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AdminAdsRail extends StatelessWidget {
  const _AdminAdsRail({required this.ads});

  final List<AdminAd> ads;

  @override
  Widget build(BuildContext context) {
    if (ads.isEmpty) {
      return const SizedBox.shrink();
    }
    return SizedBox(
      height: 86,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemBuilder: (context, index) => _AdCard(ad: ads[index]),
        separatorBuilder: (context, index) => const SizedBox(width: 10),
        itemCount: ads.length,
      ),
    );
  }
}

class _AdCard extends StatelessWidget {
  const _AdCard({required this.ad});

  final AdminAd ad;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: ad.actionUrl.isEmpty ? null : () => openExternal(ad.actionUrl),
      child: Container(
        width: 260,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: const LinearGradient(
            colors: [Color(0xFF211834), Color(0xFF123126)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(color: const Color(0xFF30415B)),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: const Color(0x2233F0B0),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(
                Icons.campaign_rounded,
                color: Color(0xFF33F0B0),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    ad.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    ad.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFFB8C4D8),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DemoModeNotice extends StatelessWidget {
  const _DemoModeNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: const Color(0x22FFC857),
        border: Border.all(color: const Color(0x66FFC857)),
      ),
      child: const Row(
        children: [
          Icon(Icons.info_outline_rounded, color: Color(0xFFFFC857)),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Demo mode. Firebase configure လုပ်ပြီးရင် admin data တွေ realtime ပေါ်မယ်။',
              style: TextStyle(color: Color(0xFFFFE4A3)),
            ),
          ),
        ],
      ),
    );
  }
}

class MediaRail extends StatelessWidget {
  const MediaRail({
    super.key,
    required this.title,
    required this.items,
    required this.allItems,
    required this.accessState,
    required this.accessService,
  });

  final String title;
  final List<MediaContent> items;
  final List<MediaContent> allItems;
  final AccessState? accessState;
  final AccessService accessService;

  @override
  Widget build(BuildContext context) {
    final visibleItems = items.take(15).toList();
    if (visibleItems.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0,
                  ),
                ),
              ),
              if (allItems.length > 15)
                TextButton.icon(
                  onPressed: () => openSeeMore(
                    context,
                    title,
                    allItems,
                    accessState,
                    accessService,
                  ),
                  icon: const Icon(Icons.grid_view_rounded, size: 18),
                  label: const Text('See more'),
                )
              else
                const Icon(
                  Icons.arrow_forward_rounded,
                  color: Color(0xFF91A1BC),
                ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 190,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemBuilder: (context, index) => TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: Duration(milliseconds: 260 + index * 28),
                curve: Curves.easeOutCubic,
                builder: (context, value, child) {
                  return Opacity(
                    opacity: value,
                    child: Transform.translate(
                      offset: Offset(18 * (1 - value), 0),
                      child: child,
                    ),
                  );
                },
                child: MediaPosterCard(
                  item: visibleItems[index],
                  accessState: accessState,
                  accessService: accessService,
                ),
              ),
              separatorBuilder: (context, index) => const SizedBox(width: 12),
              itemCount: visibleItems.length,
            ),
          ),
        ],
      ),
    );
  }
}

class SeeMoreScreen extends StatefulWidget {
  const SeeMoreScreen({
    super.key,
    required this.title,
    required this.items,
    required this.accessState,
    required this.accessService,
  });

  final String title;
  final List<MediaContent> items;
  final AccessState? accessState;
  final AccessService accessService;

  @override
  State<SeeMoreScreen> createState() => _SeeMoreScreenState();
}

class _SeeMoreScreenState extends State<SeeMoreScreen> {
  static const _pageSize = 100;
  int _page = 0;

  @override
  Widget build(BuildContext context) {
    final pageCount = (widget.items.length / _pageSize).ceil().clamp(1, 9999);
    final start = _page * _pageSize;
    final end = (start + _pageSize).clamp(0, widget.items.length);
    final pageItems = widget.items.sublist(start, end);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: const Color(0xFF050812),
      ),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 16),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${widget.items.length} videos • Page ${_page + 1} / $pageCount',
                      style: const TextStyle(
                        color: Color(0xFF91A1BC),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton.filledTonal(
                    tooltip: 'Previous page',
                    onPressed: _page == 0
                        ? null
                        : () => setState(() => _page -= 1),
                    icon: const Icon(Icons.chevron_left_rounded),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    tooltip: 'Next page',
                    onPressed: _page >= pageCount - 1
                        ? null
                        : () => setState(() => _page += 1),
                    icon: const Icon(Icons.chevron_right_rounded),
                  ),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
            sliver: SliverGrid.builder(
              itemCount: pageItems.length,
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 150,
                mainAxisExtent: 202,
                crossAxisSpacing: 12,
                mainAxisSpacing: 18,
              ),
              itemBuilder: (context, index) {
                return TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: 1),
                  duration: Duration(milliseconds: 220 + (index % 20) * 18),
                  curve: Curves.easeOutCubic,
                  builder: (context, value, child) {
                    return Opacity(
                      opacity: value,
                      child: Transform.translate(
                        offset: Offset(0, 20 * (1 - value)),
                        child: child,
                      ),
                    );
                  },
                  child: MediaPosterCard(
                    item: pageItems[index],
                    accessState: widget.accessState,
                    accessService: widget.accessService,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class MediaPosterCard extends StatelessWidget {
  const MediaPosterCard({
    super.key,
    required this.item,
    required this.accessState,
    required this.accessService,
  });

  final MediaContent item;
  final AccessState? accessState;
  final AccessService accessService;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () => openDetails(context, item, accessState, accessService),
      child: SizedBox(
        width: 124,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Hero(
              tag: 'poster-${item.id}',
              child: Container(
                height: 148,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFF273247)),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x77000000),
                      blurRadius: 18,
                      offset: Offset(0, 10),
                    ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: PosterFrame(item: item, fit: BoxFit.cover),
              ),
            ),
            const SizedBox(height: 9),
            Text(
              item.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                height: 1.1,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class PosterFrame extends StatelessWidget {
  const PosterFrame({super.key, required this.item, this.fit = BoxFit.cover});

  final MediaContent item;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final bytes = decodeBase64Image(item.posterBase64);
    if (bytes != null) {
      return Image.memory(
        bytes,
        fit: fit,
        width: double.infinity,
        height: double.infinity,
      );
    }
    if (item.posterUrl.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: item.posterUrl,
        fit: fit,
        width: double.infinity,
        height: double.infinity,
        errorWidget: (context, url, error) => _PosterFallback(item: item),
      );
    }
    return _PosterFallback(item: item);
  }
}

class _PosterFallback extends StatelessWidget {
  const _PosterFallback({required this.item});

  final MediaContent item;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF17233A), Color(0xFF112820)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Icon(item.icon, size: 42, color: const Color(0xFF33F0B0)),
      ),
    );
  }
}

class MediaDetailScreen extends StatelessWidget {
  const MediaDetailScreen({
    super.key,
    required this.item,
    required this.accessState,
    required this.accessService,
  });

  final MediaContent item;
  final AccessState? accessState;
  final AccessService accessService;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 380,
            pinned: true,
            stretch: true,
            backgroundColor: const Color(0xFF050812),
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  Hero(
                    tag: 'poster-${item.id}',
                    child: PosterFrame(item: item),
                  ),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.transparent,
                          const Color(0xFF050812).withValues(alpha: .96),
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                  ),
                  Positioned(
                    left: 20,
                    right: 20,
                    bottom: 28,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.title,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 32,
                            height: 1,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          '${item.type.label} • ${item.genre} • ${item.quality}',
                          style: const TextStyle(
                            color: Color(0xFFDFE7F3),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 30),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                Text(
                  item.description.isEmpty
                      ? 'No description added yet.'
                      : item.description,
                  style: const TextStyle(
                    color: Color(0xFFD8E2F1),
                    height: 1.55,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 24),
                if (item.type == MediaType.series && item.episodes.isNotEmpty)
                  EpisodeSection(
                    item: item,
                    accessState: accessState,
                    accessService: accessService,
                  )
                else ...[
                  ServerSection(
                    title: 'Watch',
                    icon: Icons.play_circle_fill_rounded,
                    itemTitle: item.title,
                    links: _linksWithTelegramFallback(
                      item.watchLinks,
                      item.telegramUrl,
                    ),
                    telegramSourceUrl: item.telegramUrl,
                    ingestBaseUrl: item.ingestBaseUrl,
                    mode: ServerAction.watch,
                    accessState: accessState,
                    accessService: accessService,
                  ),
                  const SizedBox(height: 18),
                  ServerSection(
                    title: 'Download',
                    icon: Icons.download_rounded,
                    itemTitle: item.title,
                    links: _linksWithTelegramFallback(
                      item.downloadLinks,
                      item.telegramUrl,
                    ),
                    telegramSourceUrl: item.telegramUrl,
                    ingestBaseUrl: item.ingestBaseUrl,
                    mode: ServerAction.download,
                    accessState: accessState,
                    accessService: accessService,
                  ),
                ],
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

enum ServerAction { watch, download }

class ServerSection extends StatelessWidget {
  const ServerSection({
    super.key,
    required this.title,
    required this.icon,
    required this.itemTitle,
    required this.links,
    required this.telegramSourceUrl,
    required this.ingestBaseUrl,
    required this.mode,
    required this.accessState,
    required this.accessService,
  });

  final String title;
  final IconData icon;
  final String itemTitle;
  final List<MediaServerLink> links;
  final String telegramSourceUrl;
  final String ingestBaseUrl;
  final ServerAction mode;
  final AccessState? accessState;
  final AccessService accessService;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF101827),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFF263247)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: const Color(0xFF33F0B0)),
              const SizedBox(width: 10),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (links.isEmpty)
            Text(
              mode == ServerAction.watch
                  ? 'No watch source is available yet.'
                  : 'No download source is available yet.',
              style: TextStyle(color: Color(0xFF91A1BC)),
            )
          else
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: List.generate(links.length, (index) {
                final link = links[index];
                return FilledButton.icon(
                  onPressed: () => openProtectedServerLink(
                    context,
                    link.url,
                    mode,
                    itemTitle,
                    telegramSourceUrl,
                    ingestBaseUrl,
                    accessState,
                    accessService,
                  ),
                  icon: Icon(
                    mode == ServerAction.watch
                        ? Icons.play_arrow_rounded
                        : Icons.download_rounded,
                  ),
                  label: Text(
                    mode == ServerAction.watch
                        ? (links.length == 1
                              ? 'Watch now'
                              : 'Watch ${index + 1}')
                        : (links.length == 1
                              ? 'Download'
                              : 'Download ${index + 1}'),
                  ),
                );
              }),
            ),
        ],
      ),
    );
  }
}

class EpisodeSection extends StatelessWidget {
  const EpisodeSection({
    super.key,
    required this.item,
    required this.accessState,
    required this.accessService,
  });

  final MediaContent item;
  final AccessState? accessState;
  final AccessService accessService;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF101827),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFF263247)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.playlist_play_rounded, color: Color(0xFF33F0B0)),
              SizedBox(width: 10),
              Text(
                'Episodes',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...List.generate(item.episodes.length, (index) {
            final episode = item.episodes[index];
            final watchLinks = _linksWithTelegramFallback(
              episode.watchLinks,
              episode.telegramUrl,
            );
            final downloadLinks = _linksWithTelegramFallback(
              episode.downloadLinks,
              episode.telegramUrl,
            );
            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF0B1220),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF263247)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: const Color(0x2233F0B0),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Center(
                      child: Text(
                        '${index + 1}',
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      episode.label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                  IconButton.filledTonal(
                    tooltip: 'Watch',
                    onPressed: watchLinks.isEmpty
                        ? null
                        : () => openProtectedServerLink(
                            context,
                            watchLinks.first.url,
                            ServerAction.watch,
                            '${item.title} - ${episode.label}',
                            episode.telegramUrl,
                            item.ingestBaseUrl,
                            accessState,
                            accessService,
                          ),
                    icon: const Icon(Icons.play_arrow_rounded),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    tooltip: 'Download',
                    onPressed: downloadLinks.isEmpty
                        ? null
                        : () => openProtectedServerLink(
                            context,
                            downloadLinks.first.url,
                            ServerAction.download,
                            '${item.title} - ${episode.label}',
                            episode.telegramUrl,
                            item.ingestBaseUrl,
                            accessState,
                            accessService,
                          ),
                    icon: const Icon(Icons.download_rounded),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

class VideoWatchScreen extends StatefulWidget {
  const VideoWatchScreen({super.key, required this.url});

  final String url;

  @override
  State<VideoWatchScreen> createState() => _VideoWatchScreenState();
}

class _VideoWatchScreenState extends State<VideoWatchScreen> {
  late final VideoPlayerController _controller;
  late final Future<void> _initialize;
  bool _showControls = true;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    _initialize = _controller.initialize().then((_) {
      if (mounted) setState(() {});
    });
    _controller.addListener(_onVideoChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onVideoChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onVideoChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.black),
      body: Center(
        child: FutureBuilder<void>(
          future: _initialize,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.error_outline_rounded,
                      color: Color(0xFFFFC857),
                      size: 48,
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Video could not be loaded.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: () => openExternal(widget.url),
                      icon: const Icon(Icons.open_in_new_rounded),
                      label: const Text('Open source'),
                    ),
                  ],
                ),
              );
            }
            if (snapshot.connectionState != ConnectionState.done) {
              return const CircularProgressIndicator();
            }
            final value = _controller.value;
            final duration = value.duration;
            final position = value.position;
            final maxSeconds = duration.inMilliseconds <= 0
                ? 1.0
                : duration.inMilliseconds.toDouble();
            final seconds = position.inMilliseconds
                .clamp(0, duration.inMilliseconds)
                .toDouble();
            return GestureDetector(
              onTap: () => setState(() => _showControls = !_showControls),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  AspectRatio(
                    aspectRatio: value.aspectRatio == 0
                        ? 16 / 9
                        : value.aspectRatio,
                    child: VideoPlayer(_controller),
                  ),
                  if (_showControls) ...[
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.black.withValues(alpha: .55),
                            Colors.transparent,
                            Colors.black.withValues(alpha: .7),
                          ],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                      ),
                      child: const SizedBox.expand(),
                    ),
                    IconButton.filled(
                      iconSize: 58,
                      onPressed: () {
                        value.isPlaying
                            ? _controller.pause()
                            : _controller.play();
                      },
                      icon: Icon(
                        value.isPlaying
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                      ),
                    ),
                    Positioned(
                      left: 16,
                      right: 16,
                      bottom: 18,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Slider(
                            min: 0,
                            max: maxSeconds,
                            value: seconds,
                            onChanged: (next) {
                              _controller.seekTo(
                                Duration(milliseconds: next.round()),
                              );
                            },
                          ),
                          Row(
                            children: [
                              Text(_formatVideoTime(position)),
                              const Spacer(),
                              IconButton(
                                tooltip: 'Replay 10 seconds',
                                onPressed: () {
                                  final next =
                                      position - const Duration(seconds: 10);
                                  _controller.seekTo(
                                    next.isNegative ? Duration.zero : next,
                                  );
                                },
                                icon: const Icon(Icons.replay_10_rounded),
                              ),
                              IconButton(
                                tooltip: 'Forward 10 seconds',
                                onPressed: () {
                                  final next =
                                      position + const Duration(seconds: 10);
                                  _controller.seekTo(
                                    next > duration ? duration : next,
                                  );
                                },
                                icon: const Icon(Icons.forward_10_rounded),
                              ),
                              Text(_formatVideoTime(duration)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

String _formatVideoTime(Duration duration) {
  String two(int value) => value.toString().padLeft(2, '0');
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  final seconds = duration.inSeconds.remainder(60);
  return hours > 0
      ? '$hours:${two(minutes)}:${two(seconds)}'
      : '${two(minutes)}:${two(seconds)}';
}

class TelegramWebWatchScreen extends StatefulWidget {
  const TelegramWebWatchScreen({super.key, required this.url});

  final String url;

  @override
  State<TelegramWebWatchScreen> createState() => _TelegramWebWatchScreenState();
}

class _TelegramWebWatchScreenState extends State<TelegramWebWatchScreen> {
  late final WebViewController _controller;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF050812))
      ..loadRequest(Uri.parse(_telegramEmbedUrl(widget.url)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF050812),
      appBar: AppBar(
        title: const Text('Video'),
        actions: [
          IconButton(
            tooltip: 'Open source',
            onPressed: () => openExternal(_telegramAppUrl(widget.url)),
            icon: const Icon(Icons.open_in_new_rounded),
          ),
        ],
      ),
      body: WebViewWidget(controller: _controller),
    );
  }
}

void openDetails(
  BuildContext context,
  MediaContent item,
  AccessState? accessState,
  AccessService accessService,
) {
  Navigator.of(context).push(
    PageRouteBuilder(
      transitionDuration: const Duration(milliseconds: 360),
      reverseTransitionDuration: const Duration(milliseconds: 260),
      pageBuilder: (context, animation, secondaryAnimation) =>
          MediaDetailScreen(
            item: item,
            accessState: accessState,
            accessService: accessService,
          ),
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, .04),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        );
      },
    ),
  );
}

void openSeeMore(
  BuildContext context,
  String title,
  List<MediaContent> items,
  AccessState? accessState,
  AccessService accessService,
) {
  Navigator.of(context).push(
    PageRouteBuilder(
      transitionDuration: const Duration(milliseconds: 320),
      pageBuilder: (context, animation, secondaryAnimation) => SeeMoreScreen(
        title: title,
        items: items,
        accessState: accessState,
        accessService: accessService,
      ),
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, .05),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        );
      },
    ),
  );
}

void openWatchLink(BuildContext context, String url) {
  if (_isTelegramWebUrl(url)) {
    if (_isMobilePlatform) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => TelegramWebWatchScreen(url: url)),
      );
    } else {
      openExternal(url);
    }
    return;
  }
  Navigator.of(
    context,
  ).push(MaterialPageRoute(builder: (_) => VideoWatchScreen(url: url)));
}

void openAdminContact() {
  openExternal(
    Uri(
      scheme: 'https',
      host: 't.me',
      path: '/mratom_619',
      queryParameters: {'text': 'Relaxation'},
    ).toString(),
  );
}

String formatDate(DateTime date) {
  final local = date.toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)}';
}

void openProtectedServerLink(
  BuildContext context,
  String url,
  ServerAction mode,
  String itemTitle,
  String telegramSourceUrl,
  String ingestBaseUrl,
  AccessState? state,
  AccessService accessService,
) async {
  if (state?.hasAccess != true) {
    showLicenseDialog(context, accessService);
    return;
  }
  var targetUrl = url;
  if (_isTelegramWebUrl(targetUrl)) {
    final resolved = await resolveTelegramOnDemand(
      context,
      telegramSourceUrl.isNotEmpty ? telegramSourceUrl : targetUrl,
      ingestBaseUrl,
      mode,
    );
    if (resolved == null) return;
    targetUrl = mode == ServerAction.watch
        ? resolved.streamUrl
        : resolved.downloadUrl;
  }
  if (!context.mounted) return;
  if (mode == ServerAction.watch) {
    openWatchLink(context, targetUrl);
  } else {
    downloadProtectedFile(context, targetUrl, itemTitle);
  }
}

Future<ResolvedTelegramMedia?> resolveTelegramOnDemand(
  BuildContext context,
  String telegramUrl,
  String ingestBaseUrl,
  ServerAction mode,
) async {
  final messenger = ScaffoldMessenger.of(context);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const AlertDialog(
      title: Text('Preparing video'),
      content: Row(
        children: [
          SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 14),
          Expanded(child: Text('Preparing playback...')),
        ],
      ),
    ),
  );
  try {
    if (AndroidTelethonService.instance.isSupported) {
      try {
        final resolved = await AndroidTelethonService.instance.resolve(
          telegramUrl,
        );
        if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
        return resolved;
      } catch (error) {
        if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
        if (!context.mounted) return null;
        final message = error.toString();
        if (message.contains('login') || message.contains('Session')) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Please login with Telegram to continue.'),
            ),
          );
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => TelegramSignInScreen(access: AccessService()),
            ),
          );
          return null;
        }
        messenger.showSnackBar(SnackBar(content: Text(message)));
        return null;
      }
    }
    final baseUrl = await effectiveTelethonBaseUrl(ingestBaseUrl);
    if (baseUrl.isEmpty) {
      if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
      if (!context.mounted) return null;
      if (telegramUrl.trim().isNotEmpty) {
        if (_isTelegramWebUrl(telegramUrl) && _isMobilePlatform) {
          if (mode == ServerAction.watch) {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => TelegramWebWatchScreen(url: telegramUrl),
              ),
            );
          } else {
            await openExternal(_telegramAppUrl(telegramUrl));
          }
        } else {
          await openExternal(telegramUrl);
        }
      }
      return null;
    }
    final resolved = await TelethonResolver().resolve(
      ingestBaseUrl: baseUrl,
      telegramUrl: telegramUrl,
    );
    if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
    return resolved;
  } catch (error) {
    if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
    messenger.showSnackBar(SnackBar(content: Text(error.toString())));
    return null;
  }
}

Future<String> effectiveTelethonBaseUrl(String mediaBaseUrl) async {
  final direct = mediaBaseUrl.trim();
  if (direct.isNotEmpty) return direct;
  final doc = await FirebaseFirestore.instance
      .collection('app_settings')
      .doc('telegram')
      .get();
  final data = doc.data() ?? {};
  final remote = (data['ingestBaseUrl'] ?? '').toString().trim();
  final status = (data['status'] ?? '').toString().trim().toLowerCase();
  final expiresAt = data['expiresAt'];
  final expiresAtDate = expiresAt is Timestamp ? expiresAt.toDate() : null;
  final remoteIsUsable =
      remote.isNotEmpty &&
      status != 'stopped' &&
      (expiresAtDate == null || expiresAtDate.isAfter(DateTime.now()));
  if (remoteIsUsable) return remote;

  final apiId = data['apiId'] is int
      ? data['apiId'] as int
      : int.tryParse((data['apiId'] ?? '').toString()) ?? 0;
  final apiHash = (data['apiHash'] ?? '').toString();
  final sessionString = (data['sessionString'] ?? '').toString();
  final config = LocalTelethonConfig(
    apiId: apiId,
    apiHash: apiHash,
    sessionString: sessionString,
  );
  if (!config.isUsable || !LocalTelethonService.instance.isSupported) {
    return '';
  }
  return LocalTelethonService.instance.ensureStarted(config);
}

bool get _isMobilePlatform {
  if (kIsWeb) return false;
  return defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;
}

String _telegramEmbedUrl(String url) {
  final uri = Uri.tryParse(url.trim());
  if (uri == null) return url;
  final host = uri.host.toLowerCase();
  if (!{'t.me', 'telegram.me', 'telegram.dog'}.contains(host)) return url;
  final parts = uri.pathSegments.where((part) => part.isNotEmpty).toList();
  if (parts.length < 2) return url;
  if (parts.first == 'c') return url;
  final channel = parts.first == 's' && parts.length >= 3 ? parts[1] : parts[0];
  final post = parts.first == 's' && parts.length >= 3 ? parts[2] : parts[1];
  return 'https://t.me/s/$channel/$post';
}

String _telegramAppUrl(String url) {
  final uri = Uri.tryParse(url.trim());
  if (uri == null) return url;
  final host = uri.host.toLowerCase();
  if (!{'t.me', 'telegram.me', 'telegram.dog'}.contains(host)) return url;
  final parts = uri.pathSegments.where((part) => part.isNotEmpty).toList();
  if (parts.length < 2) return url;
  if (parts.length >= 3 && parts.first == 'c') {
    return 'tg://privatepost?channel=${parts[1]}&post=${parts[2]}';
  }
  final channel = parts.first == 's' && parts.length >= 3 ? parts[1] : parts[0];
  final post = parts.first == 's' && parts.length >= 3 ? parts[2] : parts[1];
  return 'tg://resolve?domain=$channel&post=$post';
}

Future<void> downloadProtectedFile(
  BuildContext context,
  String url,
  String title,
) async {
  if (kIsWeb || _isTelegramWebUrl(url)) {
    openExternal(url);
    return;
  }
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) =>
          DownloadHistoryScreen(initialUrl: url, initialTitle: title),
    ),
  );
}

class DownloadHistoryScreen extends StatefulWidget {
  const DownloadHistoryScreen({super.key, this.initialUrl, this.initialTitle});

  final String? initialUrl;
  final String? initialTitle;

  @override
  State<DownloadHistoryScreen> createState() => _DownloadHistoryScreenState();
}

class _DownloadHistoryScreenState extends State<DownloadHistoryScreen> {
  final _downloadService = DownloadService();
  List<DownloadHistoryItem> _history = const [];
  double? _progress;
  String _status = 'Preparing Download/Relaxation...';
  String? _savedPath;
  String? _activeTitle;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _loadHistory();
    final url = widget.initialUrl;
    final title = widget.initialTitle;
    if (url != null && title != null) {
      _start(url, title);
    }
  }

  Future<void> _loadHistory() async {
    final history = await _downloadService.loadHistory();
    if (mounted) setState(() => _history = history);
  }

  Future<void> _start(String url, String title) async {
    setState(() {
      _progress = null;
      _savedPath = null;
      _activeTitle = title;
      _error = null;
      _status = 'Preparing Download/Relaxation...';
    });
    try {
      final result = await _downloadService.downloadToRelaxationFolder(
        url,
        title: title,
        onProgress: (received, total) {
          if (!mounted || total <= 0) return;
          setState(() {
            _progress = received / total;
            _status = '${_formatBytes(received)} / ${_formatBytes(total)}';
          });
        },
      );
      if (!mounted) return;
      setState(() {
        _progress = 1;
        _savedPath = result.path;
        _status = 'Download complete';
      });
      await _downloadService.addHistory(
        DownloadHistoryItem(
          title: title,
          path: result.path,
          savedAt: DateTime.now(),
        ),
      );
      await _loadHistory();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _status = 'Download failed';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final percent = ((_progress ?? 0) * 100).clamp(0, 100).toStringAsFixed(0);
    return Scaffold(
      appBar: AppBar(title: const Text('Downloads')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Download history',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 16),
              if (_activeTitle != null) ...[
                _DownloadCard(
                  icon: _error != null
                      ? Icons.error_rounded
                      : _savedPath != null
                      ? Icons.check_circle_rounded
                      : Icons.downloading_rounded,
                  iconColor: _error != null
                      ? const Color(0xFFFF6B6B)
                      : const Color(0xFF33F0B0),
                  title: _activeTitle!,
                  trailing: '$percent%',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      LinearProgressIndicator(value: _progress),
                      const SizedBox(height: 12),
                      Text(
                        _status,
                        style: const TextStyle(color: Color(0xFFB8C4D8)),
                      ),
                      if (_savedPath != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          _savedPath!,
                          style: const TextStyle(
                            color: Color(0xFF91A1BC),
                            fontSize: 12,
                          ),
                        ),
                      ],
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          _error.toString(),
                          style: const TextStyle(color: Color(0xFFFFB4B4)),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 18),
              ],
              if (_history.isEmpty)
                const Text(
                  'No downloads yet.',
                  style: TextStyle(color: Color(0xFF91A1BC)),
                )
              else
                ..._history.map((item) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _DownloadCard(
                      icon: Icons.movie_creation_rounded,
                      iconColor: const Color(0xFF33F0B0),
                      title: item.title,
                      trailing: formatDate(item.savedAt),
                      child: Text(
                        item.path,
                        style: const TextStyle(
                          color: Color(0xFF91A1BC),
                          fontSize: 12,
                        ),
                      ),
                    ),
                  );
                }),
            ],
          ),
        ),
      ),
    );
  }
}

class _DownloadCard extends StatelessWidget {
  const _DownloadCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.trailing,
    required this.child,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF101827),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF263247)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: iconColor),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Text(trailing),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

String _formatBytes(int value) {
  if (value < 1024) return '$value B';
  final kb = value / 1024;
  if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
  final mb = kb / 1024;
  if (mb < 1024) return '${mb.toStringAsFixed(1)} MB';
  return '${(mb / 1024).toStringAsFixed(1)} GB';
}

List<MediaServerLink> _linksWithTelegramFallback(
  List<MediaServerLink> links,
  String telegramUrl,
) {
  if (links.isNotEmpty) return links;
  if (telegramUrl.trim().isEmpty) return const [];
  return [MediaServerLink(label: 'Server 1', url: telegramUrl.trim())];
}

Future<void> showLicenseDialog(
  BuildContext context,
  AccessService accessService,
) async {
  final controller = TextEditingController();
  final messenger = ScaffoldMessenger.of(context);
  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      var busy = false;
      return StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text('သက်တမ်းတိုးရန်'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Free trial ပြည့်သွားပါပြီ။ Watch/Download ဆက်သုံးဖို့ license key ထည့်ပါ။',
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: controller,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    labelText: 'License key',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
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
                        try {
                          await accessService.activateLicense(controller.text);
                          if (dialogContext.mounted) {
                            Navigator.of(dialogContext).pop();
                          }
                          messenger.showSnackBar(
                            const SnackBar(content: Text('License activated')),
                          );
                        } catch (error) {
                          messenger.showSnackBar(
                            SnackBar(content: Text(error.toString())),
                          );
                        } finally {
                          setState(() => busy = false);
                        }
                      },
                child: Text(busy ? 'Checking...' : 'Activate'),
              ),
            ],
          );
        },
      );
    },
  );
  controller.dispose();
}

Future<void> openExternal(String url) async {
  if (url.trim().isEmpty) {
    return;
  }
  final uri = Uri.tryParse(url.trim());
  if (uri == null) return;
  try {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    // External apps and Telegram web can fail on emulators or blocked networks.
  }
}

Uint8List? decodeBase64Image(String value) {
  if (value.isEmpty) {
    return null;
  }
  try {
    final clean = value.contains(',') ? value.split(',').last : value;
    return base64Decode(clean);
  } catch (_) {
    return null;
  }
}

bool _isTelegramWebUrl(String value) {
  final uri = Uri.tryParse(value);
  if (uri == null) {
    return false;
  }
  return {
    't.me',
    'telegram.me',
    'telegram.dog',
  }.contains(uri.host.toLowerCase());
}

extension on MediaType {
  String get label => this == MediaType.series ? 'Series' : 'Movie';
}
