import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:audio_service/audio_service.dart';
import 'services/audio_handler.dart';
import 'screens/search_screen.dart';
import 'screens/downloader_screen.dart';
import 'screens/downloads_screen.dart';
import 'screens/qr_scan_screen.dart';
import 'screens/playlists_screen.dart';
import 'widgets/global_mini_player.dart';

import 'package:shared_preferences/shared_preferences.dart';
import 'services/theme_service.dart';
import 'services/isar_service.dart';

late IsarService isarService;
late ThemeService themeService;
late MyAudioHandler audioHandler;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  isarService = IsarService();
  final prefs = await SharedPreferences.getInstance();
  themeService = ThemeService(prefs);

  try {
    audioHandler = await AudioService.init(
      builder: () => MyAudioHandler(),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.example.videodownloader.channel.audio',
        androidNotificationChannelName: 'Audio Playback',
        androidNotificationOngoing: true,
        androidStopForegroundOnPause: true,
        androidNotificationIcon: 'mipmap/launcher_icon',
        notificationColor: Colors.red,
      ),
    );
    runApp(const MyApp());
  } catch (e, st) {
    // If it fails, show the error on screen instead of a black screen
    runApp(MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('Startup Error')),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Text(
            'Error starting AudioService:\n$e\n\n$st',
            style: const TextStyle(color: Colors.red, fontSize: 14),
          ),
        ),
      ),
    ));
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: themeService,
      builder: (context, child) {
        return MaterialApp(
          title: 'Mouse Music',
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(seedColor: Colors.red, brightness: Brightness.light),
            useMaterial3: true,
            scaffoldBackgroundColor: Colors.grey[50],
            appBarTheme: const AppBarTheme(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              elevation: 0,
            ),
          ),
          darkTheme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.red, 
              brightness: Brightness.dark,
              surface: const Color(0xFF1E1E1E),
            ),
            useMaterial3: true,
            scaffoldBackgroundColor: const Color(0xFF121212),
            appBarTheme: const AppBarTheme(
              backgroundColor: Color(0xFF1E1E1E),
              foregroundColor: Colors.white,
              elevation: 0,
            ),
            bottomNavigationBarTheme: const BottomNavigationBarThemeData(
              backgroundColor: Color(0xFF1E1E1E),
            ),
          ),
          themeMode: themeService.themeMode,
          builder: (context, child) {
            return SafeArea(
              child: child!,
            );
          },
          home: const HomeScreen(),
          debugShowCheckedModeBanner: false,
        );
      },
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _requestPermissions();
  }

  Future<void> _requestPermissions() async {
    await Permission.storage.request();
    await Permission.manageExternalStorage.request();
    await Permission.camera.request();
    await Permission.microphone.request(); // For voice search
    await Permission.locationWhenInUse.request();
    await Permission.notification.request(); // Android 13+ notification permission
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          Container(
            decoration: BoxDecoration(
              color: Theme.of(context).appBarTheme.backgroundColor ?? Theme.of(context).primaryColor,
              boxShadow: const [
                BoxShadow(
                  color: Colors.black12,
                  blurRadius: 4,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: SafeArea(
              bottom: false,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Image.asset(
                              'assets/logo2.png',
                              width: 28,
                              height: 28,
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              'Mouse Music',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            IconButton(
                              icon: Icon(
                                Theme.of(context).brightness == Brightness.dark
                                    ? Icons.light_mode
                                    : Icons.dark_mode,
                                color: Colors.white,
                              ),
                              onPressed: () {
                                themeService.toggleTheme();
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.qr_code_scanner, color: Colors.white),
                              onPressed: () {
                                Navigator.push(context, MaterialPageRoute(builder: (_) => const QrScanScreen()));
                              },
                            ),
                          ],
                        )
                      ],
                    ),
                  ),
                  TabBar(
                    controller: _tabController,
                    indicatorColor: Colors.white,
                    labelColor: Colors.white,
                    unselectedLabelColor: Colors.white70,
                    tabs: const [
                      Tab(icon: Icon(Icons.search), text: 'Search'),
                      Tab(icon: Icon(Icons.link), text: 'URL'),
                      Tab(icon: Icon(Icons.library_music), text: 'Downloads'),
                      Tab(icon: Icon(Icons.queue_music), text: 'Playlists'),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: const [
                SearchScreen(),
                DownloaderScreen(),
                DownloadsScreen(),
                PlaylistsScreen(),
              ],
            ),
          ),
          GlobalMiniPlayer(tabController: _tabController),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }
}
