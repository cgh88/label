import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_sync_service.dart';
import '../services/bluetooth_service.dart';

class LoginView extends StatefulWidget {
  final Function(String username, String role) onLoginSuccess;
  final VoidCallback toggleTheme;
  final ThemeMode themeMode;

  const LoginView({
    super.key,
    required this.onLoginSuccess,
    required this.toggleTheme,
    required this.themeMode,
  });

  @override
  State<LoginView> createState() => _LoginViewState();
}

class _LoginViewState extends State<LoginView> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _serverUrlController =
      TextEditingController(text: ApiSyncService.instance.apiSyncUrl);
  final _formKey = GlobalKey<FormState>();
  String? _errorMessage;
  bool _isLoading = false;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _serverUrlController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final username = _usernameController.text.trim();
    final password = _passwordController.text;

    // Normalize and persist the server address entered on the login screen so
    // login (and later sync/print) all target the same server.
    var baseUrl = _serverUrlController.text.trim();
    if (!baseUrl.startsWith('http://') && !baseUrl.startsWith('https://')) {
      baseUrl = 'http://$baseUrl';
    }
    baseUrl = baseUrl.replaceAll(RegExp(r'/+$'), '');

    if (baseUrl.contains('labelprint.pji.co.kr')) {
      setState(() {
        _isLoading = false;
        _errorMessage = '해당 외부 서버 주소(labelprint.pji.co.kr)는 태블릿에서 접속할 수 없습니다. (내부/로컬 서버 주소를 입력해 주세요.)';
      });
      return;
    }
    await ApiSyncService.instance.saveConfig(baseUrl);
    final loginUrl = '$baseUrl/api/auth/login';

    try {
      final response = await http.post(
        Uri.parse(loginUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'username': username,
          'password': password,
        }),
      ).timeout(const Duration(seconds: 8));

      final Map<String, dynamic> body = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode == 200 && body['success'] == true) {
        final user = body['user'] as Map<String, dynamic>? ?? {};
        final role = user['role']?.toString() ?? 'staff';
        final returnedUsername = user['username']?.toString() ?? username;

        final prefs = await SharedPreferences.getInstance();
        final jwtToken = body['token']?.toString();
        if (jwtToken != null && jwtToken.isNotEmpty) {
          await prefs.setString('jwt_token', jwtToken);
        }

        final rawCookie = response.headers['set-cookie'];
        if (rawCookie != null) {
          await prefs.setString('session_cookie', rawCookie);
        }

        if (mounted) {
          setState(() {
            _isLoading = false;
          });
          widget.onLoginSuccess(returnedUsername, role);
        }

        // Perform sync and Bluetooth autoConnect in the background without blocking screen transition
        unawaited(Future(() async {
          try {
            await ApiSyncService.instance.performSync();
          } catch (e) {
            debugPrint('Background sync error after login: $e');
          }
          try {
            await BluetoothPrintService.instance.autoConnect();
          } catch (e) {
            debugPrint('Background BT autoConnect error after login: $e');
          }
        }));
      } else {
        final errorMsg = body['error']?.toString() ?? '아이디 또는 비밀번호가 올바르지 않습니다.';
        final isIpBlocked = response.statusCode == 403 || body['ipBlocked'] == true || errorMsg.contains('허용되지 않은 IP');

        if (mounted) {
          setState(() {
            _isLoading = false;
            _errorMessage = isIpBlocked ? null : errorMsg;
          });
          if (isIpBlocked) {
            _showAccessDeniedDialog(errorMsg, body['clientIp']?.toString() ?? '알 수 없음');
          }
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = '서버 연결에 실패했습니다. 아래 [서버 없이 바로 테스트] 버튼을 터치하여 바로 사용해 보세요.';
        });
      }
    }
  }

  void _showAccessDeniedDialog(String message, String clientIp) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.shield_outlined, color: Colors.redAccent),
            SizedBox(width: 8),
            Text('접속 불가 (Access Denied)', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message, style: const TextStyle(fontSize: 14)),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '현재 접속 IP: $clientIp',
                style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('확인'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.themeMode == ThemeMode.dark;

    return Scaffold(
      body: Stack(
        children: [
          // Background Gradient (Black/Dark grey for Dark Mode, Light grey/White for Light Mode)
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isDark
                    ? [const Color(0xFF000000), const Color(0xFF0F0F12)]
                    : [const Color(0xFFF1F5F9), const Color(0xFFE2E8F0)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Center(
              child: SingleChildScrollView(
                child: Container(
                  width: 400,
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF16161A) : Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.05),
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: isDark ? 0.5 : 0.08),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Header logo/icon (without purple tint)
                        Center(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: Image.asset(
                              'assets/images/app_logo_3.png',
                              width: 72,
                              height: 72,
                              fit: BoxFit.contain,
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        Text(
                          'SHELFLIFE LABEL SYSTEM',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : const Color(0xFF0F172A),
                            letterSpacing: 1.5,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '라벨 출력 및 관리 시스템',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 14,
                            color: isDark ? Colors.white.withValues(alpha: 0.6) : const Color(0xFF64748B),
                          ),
                        ),
                        const SizedBox(height: 32),

                        // Server address input (required before the first login;
                        // the tablet cannot reach the PC server via localhost).
                        TextFormField(
                          controller: _serverUrlController,
                          keyboardType: TextInputType.url,
                          autocorrect: false,
                          style: isDark ? const TextStyle(color: Colors.white) : const TextStyle(color: Color(0xFF0F172A)),
                          decoration: InputDecoration(
                            labelText: '서버 주소 (예: http://192.168.0.25:3000)',
                            labelStyle: isDark
                                ? TextStyle(color: Colors.white.withValues(alpha: 0.6))
                                : const TextStyle(color: Color(0xFF64748B)),
                            prefixIcon: Icon(
                              Icons.dns_outlined,
                              color: isDark ? Colors.white70 : const Color(0xFF64748B),
                            ),
                            filled: true,
                            fillColor: isDark ? const Color(0xFF1E1F24) : const Color(0xFFF8FAFC),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                color: isDark ? Colors.white.withValues(alpha: 0.05) : const Color(0xFFE2E8F0),
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                color: isDark ? Colors.white30 : const Color(0xFF0F172A),
                                width: 2,
                              ),
                            ),
                            errorStyle: const TextStyle(color: Colors.redAccent),
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return '서버 주소를 입력해 주세요.';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 20),

                        // Username input
                        TextFormField(
                          controller: _usernameController,
                          style: isDark ? const TextStyle(color: Colors.white) : const TextStyle(color: Color(0xFF0F172A)),
                          decoration: InputDecoration(
                            labelText: '사용자 ID',
                            labelStyle: isDark
                                ? TextStyle(color: Colors.white.withValues(alpha: 0.6))
                                : const TextStyle(color: Color(0xFF64748B)),
                            prefixIcon: Icon(
                              Icons.person_outline,
                              color: isDark ? Colors.white70 : const Color(0xFF64748B),
                            ),
                            filled: true,
                            fillColor: isDark ? const Color(0xFF1E1F24) : const Color(0xFFF8FAFC),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                color: isDark ? Colors.white.withValues(alpha: 0.05) : const Color(0xFFE2E8F0),
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                color: isDark ? Colors.white30 : const Color(0xFF0F172A),
                                width: 2,
                              ),
                            ),
                            errorStyle: const TextStyle(color: Colors.redAccent),
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return '아이디를 입력해 주세요.';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 20),

                        // Password input
                        TextFormField(
                          controller: _passwordController,
                          obscureText: true,
                          style: isDark ? const TextStyle(color: Colors.white) : const TextStyle(color: Color(0xFF0F172A)),
                          decoration: InputDecoration(
                            labelText: '비밀번호',
                            labelStyle: isDark
                                ? TextStyle(color: Colors.white.withValues(alpha: 0.6))
                                : const TextStyle(color: Color(0xFF64748B)),
                            prefixIcon: Icon(
                              Icons.lock_outline,
                              color: isDark ? Colors.white70 : const Color(0xFF64748B),
                            ),
                            filled: true,
                            fillColor: isDark ? const Color(0xFF1E1F24) : const Color(0xFFF8FAFC),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                color: isDark ? Colors.white.withValues(alpha: 0.05) : const Color(0xFFE2E8F0),
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                color: isDark ? Colors.white30 : const Color(0xFF0F172A),
                                width: 2,
                              ),
                            ),
                            errorStyle: const TextStyle(color: Colors.redAccent),
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return '비밀번호를 입력해 주세요.';
                            }
                            return null;
                          },
                          onFieldSubmitted: (_) => _handleLogin(),
                        ),
                        const SizedBox(height: 12),

                        if (_errorMessage != null) ...[
                          Text(
                            _errorMessage!,
                            style: const TextStyle(
                              color: Colors.redAccent,
                              fontSize: 13,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 12),
                        ],

                        const SizedBox(height: 16),

                        // Submit button (Black / White theme)
                        ElevatedButton(
                          onPressed: _isLoading ? null : _handleLogin,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: isDark ? Colors.white : const Color(0xFF0F172A),
                            foregroundColor: isDark ? Colors.black : Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 4,
                          ),
                          child: _isLoading
                              ? SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      isDark ? Colors.black : Colors.white,
                                    ),
                                  ),
                                )
                              : const Text(
                                  '로그인',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                        ),
                        const SizedBox(height: 20),

                        Row(
                          children: [
                            Expanded(child: Divider(color: isDark ? Colors.white24 : Colors.black12)),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              child: Text(
                                '오프라인 / 테스트 모드',
                                style: TextStyle(
                                  color: isDark ? Colors.white54 : Colors.black45,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            Expanded(child: Divider(color: isDark ? Colors.white24 : Colors.black12)),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // Offline Test Mode Direct Start Button
                        OutlinedButton.icon(
                          onPressed: () => widget.onLoginSuccess('테스트 관리자', 'admin'),
                          icon: const Icon(Icons.flash_on, color: Colors.amberAccent, size: 20),
                          label: const Text(
                            '서버 없이 바로 테스트 (관리자)',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: isDark ? Colors.white : const Color(0xFF0F172A),
                            side: BorderSide(
                              color: isDark ? Colors.white38 : const Color(0xFF94A3B8),
                              width: 1.5,
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),

                        TextButton(
                          onPressed: () => widget.onLoginSuccess('테스트 스태프', 'staff'),
                          child: Text(
                            '서버 없이 일반 사용자 모드로 테스트',
                            style: TextStyle(
                              color: isDark ? Colors.white60 : Colors.black54,
                              fontSize: 13,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          // Theme Toggle Button in Top-Right
          Positioned(
            top: 24,
            right: 24,
            child: IconButton(
              icon: Icon(
                widget.themeMode == ThemeMode.dark ? Icons.light_mode : Icons.dark_mode,
                color: isDark ? Colors.white70 : const Color(0xFF0F172A),
              ),
              onPressed: widget.toggleTheme,
              tooltip: '테마 변경',
            ),
          ),
        ],
      ),
    );
  }
}
