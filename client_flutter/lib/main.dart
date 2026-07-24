import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'services/api_sync_service.dart';
import 'services/database_service.dart';
import 'views/login_view.dart';
import 'views/print_tab_view.dart';
import 'views/manage_tab_view.dart';
import 'views/settings_tab_view.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await DatabaseService.instance.init();
  // Load the saved server address before the login screen builds; otherwise
  // apiSyncUrl stays at its localhost default and the first login (which runs
  // before the Settings tab is ever opened) can never reach a remote server.
  await ApiSyncService.instance.loadConfig();
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  ThemeMode _themeMode = ThemeMode.dark;

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
          background: Color(0xFFF1F5F9),
        ),
        fontFamily: 'NotoSansKR',
        scaffoldBackgroundColor: const Color(0xFFF1F5F9),
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
          background: Color(0xFF0F111A),
        ),
        fontFamily: 'NotoSansKR',
        cardTheme: CardTheme(
          color: const Color(0xFF161826),
          elevation: 4,
          shadowColor: Colors.black54,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: Colors.white.withOpacity(0.18), width: 1.2),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF1E1F29),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: Colors.white.withOpacity(0.2)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: Colors.white.withOpacity(0.15)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFFFF1E1E), width: 2),
          ),
        ),
      ),
      home: DashboardScreen(toggleTheme: toggleTheme, themeMode: _themeMode),
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
            color: isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.08),
            width: 1,
          ),
        ),
        title: Row(
          children: [
            const Icon(Icons.print, color: Color(0xFFFF1E1E)),
            const SizedBox(width: 8),
            Text(
              'SHELFLIFE LABEL SYSTEM',
              style: TextStyle(
                color: isDark ? Colors.white : Colors.black,
                fontWeight: FontWeight.bold,
                fontSize: 18,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: _userRole == 'admin' ? Colors.redAccent.withOpacity(0.2) : Colors.blueAccent.withOpacity(0.2),
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
          const SizedBox(width: 8),
          Center(
            child: Text(
              '$_currentUser 님',
              style: TextStyle(
                color: isDark ? Colors.white : Colors.black,
                fontSize: 14,
              ),
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
              color: isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.08),
              width: 1,
            ),
          ),
        ),
        child: BottomNavigationBar(
          currentIndex: _activeTabIndex,
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
              icon: Icon(Icons.manage_accounts),
              label: '등록 재료 관리',
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
          index: _activeTabIndex,
          children: [
            PrintTabView(activeTabIndex: _activeTabIndex),
            ManageTabView(userRole: _userRole!),
            const SettingsTabView(),
          ],
        ),
      ),
    );
  }
}
