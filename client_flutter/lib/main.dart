import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'services/api_sync_service.dart';
import 'services/database_service.dart';
import 'views/login_view.dart';
import 'views/print_tab_view.dart';
import 'views/settings_tab_view.dart';

void main() {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    FlutterError.onError = (FlutterErrorDetails details) {
      FlutterError.presentError(details);
      debugPrint('Caught Flutter error cleanly: ${details.exception}');
    };
    runApp(const MyApp());
  }, (error, stack) {
    debugPrint('Uncaught error handled safely: $error\n$stack');
  });
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  ThemeMode _themeMode = ThemeMode.dark;
  bool _isInitialized = false;

  void toggleTheme() {
    setState(() {
      _themeMode = _themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Shelflife Label System',
      debugShowCheckedModeBanner: false,
      themeMode: _themeMode,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        colorScheme: const ColorScheme.light(
          primary: Color(0xFFFF1E1E),
          secondary: Color(0xFFFF1E1E),
          surface: Color(0xFFFFFFFF),
        ),
        fontFamily: 'NotoSansKR',
        scaffoldBackgroundColor: const Color(0xFFF1F5F9),
        textTheme: const TextTheme(
          displayLarge:  TextStyle(fontFamily: 'NotoSansKR', fontSize: 32, fontWeight: FontWeight.w700, height: 1.3, letterSpacing: -0.5),
          displayMedium: TextStyle(fontFamily: 'NotoSansKR', fontSize: 26, fontWeight: FontWeight.w700, height: 1.3, letterSpacing: -0.3),
          displaySmall:  TextStyle(fontFamily: 'NotoSansKR', fontSize: 22, fontWeight: FontWeight.w700, height: 1.35),
          headlineLarge: TextStyle(fontFamily: 'NotoSansKR', fontSize: 20, fontWeight: FontWeight.w700, height: 1.35, letterSpacing: -0.2),
          headlineMedium:TextStyle(fontFamily: 'NotoSansKR', fontSize: 18, fontWeight: FontWeight.w700, height: 1.4),
          headlineSmall: TextStyle(fontFamily: 'NotoSansKR', fontSize: 16, fontWeight: FontWeight.w700, height: 1.4),
          titleLarge:    TextStyle(fontFamily: 'NotoSansKR', fontSize: 16, fontWeight: FontWeight.w700, height: 1.45, letterSpacing: 0.1),
          titleMedium:   TextStyle(fontFamily: 'NotoSansKR', fontSize: 15, fontWeight: FontWeight.w700, height: 1.45),
          titleSmall:    TextStyle(fontFamily: 'NotoSansKR', fontSize: 14, fontWeight: FontWeight.w700, height: 1.5),
          bodyLarge:     TextStyle(fontFamily: 'NotoSansKR', fontSize: 15, fontWeight: FontWeight.w400, height: 1.6, letterSpacing: 0.1),
          bodyMedium:    TextStyle(fontFamily: 'NotoSansKR', fontSize: 14, fontWeight: FontWeight.w400, height: 1.6),
          bodySmall:     TextStyle(fontFamily: 'NotoSansKR', fontSize: 13, fontWeight: FontWeight.w400, height: 1.6),
          labelLarge:    TextStyle(fontFamily: 'NotoSansKR', fontSize: 14, fontWeight: FontWeight.w700, height: 1.4, letterSpacing: 0.2),
          labelMedium:   TextStyle(fontFamily: 'NotoSansKR', fontSize: 13, fontWeight: FontWeight.w700, height: 1.4),
          labelSmall:    TextStyle(fontFamily: 'NotoSansKR', fontSize: 11, fontWeight: FontWeight.w700, height: 1.4, letterSpacing: 0.5),
        ),
        cardTheme: CardTheme(
          color: Colors.white,
          elevation: 3,
          shadowColor: Colors.black12,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0xFFCBD5E1), width: 1.2),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFFCBD5E1), width: 1.2),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFFCBD5E1), width: 1.2),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFFFF1E1E), width: 2),
          ),
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF06070A),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFFF1E1E),
          secondary: Color(0xFFFF1E1E),
          surface: Color(0xFF161826),
        ),
        fontFamily: 'NotoSansKR',
        textTheme: const TextTheme(
          displayLarge:  TextStyle(fontFamily: 'NotoSansKR', fontSize: 32, fontWeight: FontWeight.w700, color: Color(0xFFF1F5F9), height: 1.3, letterSpacing: -0.5),
          displayMedium: TextStyle(fontFamily: 'NotoSansKR', fontSize: 26, fontWeight: FontWeight.w700, color: Color(0xFFF1F5F9), height: 1.3, letterSpacing: -0.3),
          displaySmall:  TextStyle(fontFamily: 'NotoSansKR', fontSize: 22, fontWeight: FontWeight.w700, color: Color(0xFFF1F5F9), height: 1.35),
          headlineLarge: TextStyle(fontFamily: 'NotoSansKR', fontSize: 20, fontWeight: FontWeight.w700, color: Color(0xFFF1F5F9), height: 1.35, letterSpacing: -0.2),
          headlineMedium:TextStyle(fontFamily: 'NotoSansKR', fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFFE2E8F0), height: 1.4),
          headlineSmall: TextStyle(fontFamily: 'NotoSansKR', fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFFE2E8F0), height: 1.4),
          titleLarge:    TextStyle(fontFamily: 'NotoSansKR', fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFFE2E8F0), height: 1.45, letterSpacing: 0.1),
          titleMedium:   TextStyle(fontFamily: 'NotoSansKR', fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFFE2E8F0), height: 1.45),
          titleSmall:    TextStyle(fontFamily: 'NotoSansKR', fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFFCBD5E1), height: 1.5),
          bodyLarge:     TextStyle(fontFamily: 'NotoSansKR', fontSize: 15, fontWeight: FontWeight.w400, color: Color(0xFFCBD5E1), height: 1.6, letterSpacing: 0.1),
          bodyMedium:    TextStyle(fontFamily: 'NotoSansKR', fontSize: 14, fontWeight: FontWeight.w400, color: Color(0xFFCBD5E1), height: 1.6),
          bodySmall:     TextStyle(fontFamily: 'NotoSansKR', fontSize: 13, fontWeight: FontWeight.w400, color: Color(0xFF94A3B8), height: 1.6),
          labelLarge:    TextStyle(fontFamily: 'NotoSansKR', fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFFE2E8F0), height: 1.4, letterSpacing: 0.2),
          labelMedium:   TextStyle(fontFamily: 'NotoSansKR', fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFFCBD5E1), height: 1.4),
          labelSmall:    TextStyle(fontFamily: 'NotoSansKR', fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF94A3B8), height: 1.4, letterSpacing: 0.5),
        ),
        cardTheme: CardTheme(
          color: const Color(0xFF161826),
          elevation: 4,
          shadowColor: Colors.black54,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: Colors.white.withValues(alpha: 0.18), width: 1.2),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF13141F),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08), width: 1.2),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08), width: 1.2),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFF6366F1), width: 2),
          ),
        ),
      ),
      home: _isInitialized
          ? DashboardScreen(
              toggleTheme: toggleTheme,
              themeMode: _themeMode,
            )
          : SplashScreen(
              onInitComplete: () {
                setState(() {
                  _isInitialized = true;
                });
              },
            ),
    );
  }
}

class SplashScreen extends StatefulWidget {
  final VoidCallback onInitComplete;

  const SplashScreen({super.key, required this.onInitComplete});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  double _progress = 0.15;
  String _statusMessage = '시스템 초기화 준비 중...';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _initializeAppServices();
      }
    });
  }

  Future<void> _initializeAppServices() async {
    final Stopwatch stopwatch = Stopwatch()..start();
    // Minimum time the splash stays visible so it never flickers by on fast
    // startups; real initialization below usually finishes well within this.
    const Duration minVisible = Duration(milliseconds: 400);

    try {
      if (mounted) {
        setState(() {
          _progress = 0.4;
          _statusMessage = '데이터를 불러오는 중...';
        });
      }

      // Actual initialization work (no artificial delays).
      try {
        await DatabaseService.instance.init();
      } catch (e) {
        debugPrint('Database init error caught: $e');
      }
      if (mounted) setState(() => _progress = 0.8);

      try {
        await ApiSyncService.instance.loadConfig();
      } catch (e) {
        debugPrint('Config load error caught: $e');
      }
      if (mounted) {
        setState(() {
          _progress = 1.0;
          _statusMessage = '준비 완료';
        });
      }

      final Duration remaining = minVisible - stopwatch.elapsed;
      if (remaining > Duration.zero) {
        await Future.delayed(remaining);
      }
      if (mounted) widget.onInitComplete();
    } catch (e) {
      debugPrint('Overall Splash init error caught: $e');
      if (mounted) widget.onInitComplete();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF020617),
      resizeToAvoidBottomInset: false,
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF0F172A), Color(0xFF020617)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 20.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'SHELFLIFE LABEL SYSTEM',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      letterSpacing: 2.0,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '스마트 라벨 출력 및 유통기한 관리 시스템',
                    style: TextStyle(
                      fontSize: 14,
                      color: Color(0xFF94A3B8),
                      letterSpacing: 0.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 40),

                  // Modern Progress Bar Container
                  Container(
                    width: double.infinity,
                    constraints: const BoxConstraints(maxWidth: 380),
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B).withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.12), width: 1.2),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black38,
                          blurRadius: 16,
                          offset: Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Progress Track
                        Container(
                          height: 12,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F172A),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              final fillWidth = constraints.maxWidth * _progress.clamp(0.02, 1.0);
                              return Align(
                                alignment: Alignment.centerLeft,
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 300),
                                  curve: Curves.easeOutCubic,
                                  width: fillWidth,
                                  height: 12,
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      colors: [Color(0xFFFF1E1E), Color(0xFFA855F7), Color(0xFF6366F1)],
                                    ),
                                    borderRadius: BorderRadius.circular(6),
                                    boxShadow: const [
                                      BoxShadow(
                                        color: Color(0xFF6366F1),
                                        blurRadius: 6,
                                        offset: Offset(0, 1),
                                      )
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Status & Percentage Text Row
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                _statusMessage,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: Color(0xFFCBD5E1),
                                  fontWeight: FontWeight.w500,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '${(_progress * 100).toInt()}%',
                              style: const TextStyle(
                                fontSize: 14,
                                color: Color(0xFF818CF8),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
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

class DashboardScreen extends StatefulWidget {
  final VoidCallback toggleTheme;
  final ThemeMode themeMode;

  const DashboardScreen({super.key, required this.toggleTheme, required this.themeMode});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  String? _currentUser = '테스트 관리자';
  String? _userRole = 'admin';
  int _activeTabIndex = 0;
  String _orientationMode = 'auto';

  @override
  void initState() {
    super.initState();
    _loadOrientationPreference();
  }

  void _navigateToSettings() {
    setState(() {
      _activeTabIndex = 1;
    });
  }

  Future<void> _loadOrientationPreference() async {
    final prefs = await SharedPreferences.getInstance();
    final mode = prefs.getString('app_orientation_mode') ?? 'auto';
    _applyOrientation(mode, save: false);
  }

  Future<void> _applyOrientation(String mode, {bool save = true}) async {
    setState(() {
      _orientationMode = mode;
    });

    if (mode == 'landscape') {
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } else if (mode == 'portrait') {
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);
    } else {
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    }

    if (save) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('app_orientation_mode', mode);
    }
  }

  void _onLoginSuccess(String username, String role) {
    setState(() {
      _currentUser = username;
      _userRole = role;
    });
  }

  void _handleLogout() {
    setState(() {
      _currentUser = null;
      _userRole = null;
      _activeTabIndex = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_currentUser == null || _userRole == null) {
      return LoginView(
        onLoginSuccess: _onLoginSuccess,
        toggleTheme: widget.toggleTheme,
        themeMode: widget.themeMode,
      );
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF0F111A) : const Color(0xFFFFFFFF),
        elevation: 0,
        shape: Border(
          bottom: BorderSide(
            color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.08),
            width: 1,
          ),
        ),
        title: Row(
          children: [
            const Icon(Icons.print, color: Color(0xFFFF1E1E)),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                'SHELFLIFE LABEL SYSTEM',
                style: TextStyle(
                  color: isDark ? Colors.white : Colors.black,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  letterSpacing: 1.2,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: _userRole == 'admin' ? Colors.redAccent.withValues(alpha: 0.2) : Colors.blueAccent.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                _userRole == 'admin' ? '관리자' : '일반',
                style: TextStyle(
                  color: _userRole == 'admin' ? Colors.redAccent : Colors.blueAccent,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            icon: Icon(
              _orientationMode == 'landscape'
                  ? Icons.stay_current_landscape
                  : (_orientationMode == 'portrait' ? Icons.stay_current_portrait : Icons.screen_rotation),
              color: _orientationMode == 'auto'
                  ? (isDark ? Colors.white70 : Colors.black87)
                  : Colors.amberAccent,
            ),
            tooltip: '화면 방향 설정 (가로/세로 고정)',
            onSelected: (mode) => _applyOrientation(mode),
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'landscape',
                child: Row(
                  children: [
                    Icon(Icons.stay_current_landscape, size: 20, color: _orientationMode == 'landscape' ? Colors.amberAccent : null),
                    const SizedBox(width: 8),
                    Text('🖥️ 가로 모드 고정', style: TextStyle(fontWeight: _orientationMode == 'landscape' ? FontWeight.bold : FontWeight.normal)),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'portrait',
                child: Row(
                  children: [
                    Icon(Icons.stay_current_portrait, size: 20, color: _orientationMode == 'portrait' ? Colors.amberAccent : null),
                    const SizedBox(width: 8),
                    Text('📱 세로 모드 고정', style: TextStyle(fontWeight: _orientationMode == 'portrait' ? FontWeight.bold : FontWeight.normal)),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'auto',
                child: Row(
                  children: [
                    Icon(Icons.screen_rotation, size: 20, color: _orientationMode == 'auto' ? Colors.amberAccent : null),
                    const SizedBox(width: 8),
                    Text('🔄 자동 회전', style: TextStyle(fontWeight: _orientationMode == 'auto' ? FontWeight.bold : FontWeight.normal)),
                  ],
                ),
              ),
            ],
          ),
          IconButton(
            icon: Icon(
              widget.themeMode == ThemeMode.dark ? Icons.light_mode : Icons.dark_mode,
              color: isDark ? Colors.white70 : Colors.black87,
            ),
            onPressed: widget.toggleTheme,
          ),
          const SizedBox(width: 4),
          Center(
            child: Text(
              '$_currentUser 님',
              style: TextStyle(
                color: isDark ? Colors.white : Colors.black,
                fontSize: 13,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.redAccent),
            onPressed: _handleLogout,
            tooltip: '로그아웃',
          ),
          const SizedBox(width: 16),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(
              color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.08),
              width: 1,
            ),
          ),
        ),
        child: BottomNavigationBar(
          currentIndex: _activeTabIndex > 1 ? 0 : _activeTabIndex,
          onTap: (index) {
            setState(() {
              _activeTabIndex = index;
            });
          },
          backgroundColor: isDark ? const Color(0xFF0F111A) : const Color(0xFFFFFFFF),
          selectedItemColor: const Color(0xFF6366F1),
          unselectedItemColor: isDark ? Colors.white38 : Colors.black38,
          elevation: 0,
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.print),
              label: '라벨 인쇄',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.settings),
              label: '설정',
            ),
          ],
        ),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: isDark
              ? const RadialGradient(
                  colors: [Color(0xFF0F111A), Color(0xFF06070A)],
                  center: Alignment.center,
                  radius: 1.2,
                )
              : const RadialGradient(
                  colors: [Color(0xFFF8FAFC), Color(0xFFE2E8F0)],
                  center: Alignment.center,
                  radius: 1.2,
                ),
        ),
        child: IndexedStack(
          index: _activeTabIndex > 1 ? 0 : _activeTabIndex,
          children: [
            PrintTabView(
              activeTabIndex: _activeTabIndex,
              onNavigateToSettings: _navigateToSettings,
            ),
            const SettingsTabView(),
          ],
        ),
      ),
    );
  }
}
