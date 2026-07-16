import 'package:flutter/material.dart';
import '../services/database_service.dart';
import '../services/password_service.dart';

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
  final _formKey = GlobalKey<FormState>();
  String? _errorMessage;
  bool _isLoading = false;

  void _handleLogin() {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final username = _usernameController.text.trim();
    final password = _passwordController.text;

    // Check against local database users
    final dbUsers = DatabaseService.instance.users;
    bool authenticated = false;
    String role = 'staff';

    if (dbUsers.isEmpty) {
      // Fallback defaults when database isn't synced or has no users
      if (username == 'admin' && password == 'admin') {
        authenticated = true;
        role = 'admin';
      } else if (username == 'staff' && password == 'staff') {
        authenticated = true;
        role = 'staff';
      }
    } else {
      final user = dbUsers.firstWhere(
        (u) => u['username'].toString().toLowerCase() == username.toLowerCase(),
        orElse: () => <String, dynamic>{},
      );

      if (user.isNotEmpty) {
        final storedHash = user['password'].toString();
        if (PasswordService.verify(password, storedHash)) {
          authenticated = true;
          role = user['role'].toString();
        }
      }
    }

    setState(() {
      _isLoading = false;
    });

    if (authenticated) {
      widget.onLoginSuccess(username, role);
    } else {
      setState(() {
        _errorMessage = '아이디 또는 비밀번호가 올바르지 않습니다.';
      });
    }
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
                      color: isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.05),
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(isDark ? 0.5 : 0.08),
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
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? Colors.white.withOpacity(0.08)
                                  : const Color(0xFF0F172A).withOpacity(0.08),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.print_rounded,
                              size: 48,
                              color: isDark ? Colors.white : const Color(0xFF0F172A),
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
                            color: isDark ? Colors.white.withOpacity(0.6) : const Color(0xFF64748B),
                          ),
                        ),
                        const SizedBox(height: 32),

                        // Username input
                        TextFormField(
                          controller: _usernameController,
                          style: isDark ? const TextStyle(color: Colors.white) : const TextStyle(color: Color(0xFF0F172A)),
                          decoration: InputDecoration(
                            labelText: '사용자 ID',
                            labelStyle: isDark
                                ? TextStyle(color: Colors.white.withOpacity(0.6))
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
                                color: isDark ? Colors.white.withOpacity(0.05) : const Color(0xFFE2E8F0),
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
                                ? TextStyle(color: Colors.white.withOpacity(0.6))
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
                                color: isDark ? Colors.white.withOpacity(0.05) : const Color(0xFFE2E8F0),
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
