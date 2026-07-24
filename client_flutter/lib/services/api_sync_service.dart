import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'database_service.dart';

typedef SyncProgressCallback = void Function(double progress, String statusMessage);

class ApiSyncService {
  static final ApiSyncService instance = ApiSyncService._();
  ApiSyncService._();

  String apiSyncUrl = 'http://localhost:3000';

  Future<void> loadConfig() async {
    final prefs = await SharedPreferences.getInstance();
    apiSyncUrl = prefs.getString('api_sync_url') ?? 'http://localhost:3000';
  }

  Future<void> saveConfig(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('api_sync_url', url);
    apiSyncUrl = url;
  }

  bool isConfigured() {
    final uri = Uri.tryParse(apiSyncUrl);
    return apiSyncUrl.isNotEmpty && uri != null && uri.hasScheme && uri.host.isNotEmpty;
  }

  /// Builds request headers including the stored session cookie (set at login).
  /// The server requires an authenticated session for the sync/print-log APIs.
  static Future<Map<String, String>> authHeaders({bool jsonBody = false}) async {
    final headers = <String, String>{};
    if (jsonBody) headers['Content-Type'] = 'application/json';

    final prefs = await SharedPreferences.getInstance();
    final rawCookie = prefs.getString('session_cookie');
    if (rawCookie != null && rawCookie.isNotEmpty) {
      // A raw Set-Cookie value carries attributes (Path, HttpOnly, ...);
      // send back only the leading `name=value` pair.
      final token = rawCookie.split(';').first.trim();
      if (token.isNotEmpty) headers['Cookie'] = token;
    }
    return headers;
  }

  Future<SyncResult> performSync() async {
    return await performSyncWithProgress();
  }

  /// Performs server-to-client one-way sync with step-by-step progress callbacks
  /// and data version comparison.
  Future<SyncResult> performSyncWithProgress({
    SyncProgressCallback? onProgress,
    bool forceDownload = false,
  }) async {
    if (!isConfigured()) {
      onProgress?.call(1.0, 'API 주소 오류');
      return SyncResult(success: false, message: '동기화 API 주소가 올바르지 않습니다.');
    }

    try {
      onProgress?.call(0.15, '서버 데이터 버전을 확인하는 중...');

      final getResponse = await http.get(
        Uri.parse('$apiSyncUrl/api/sync/database'),
        headers: await authHeaders(),
      ).timeout(const Duration(seconds: 10));

      if (getResponse.statusCode != 200) {
        onProgress?.call(1.0, '원격 데이터 읽기 실패');
        return SyncResult(
          success: false,
          message: '원격 서버 데이터를 읽지 못했습니다 (상태 코드: ${getResponse.statusCode})',
        );
      }

      onProgress?.call(0.45, '서버 데이터 검증 및 버전 비교 중...');
      final remoteJsonContent = getResponse.body;
      final localJsonContent = await DatabaseService.instance.getRawJson();

      Map<String, dynamic>? remoteParsed;
      Map<String, dynamic>? localParsed;
      try {
        remoteParsed = jsonDecode(remoteJsonContent) as Map<String, dynamic>;
        if (localJsonContent.isNotEmpty) {
          localParsed = jsonDecode(localJsonContent) as Map<String, dynamic>;
        }
      } catch (_) {}

      final String remoteLastUpdated = remoteParsed?['last_updated'] as String? ?? '';
      final String localLastUpdated = localParsed?['last_updated'] as String? ?? DatabaseService.instance.lastUpdated;

      // Version comparison logic
      bool isNewer = false;
      if (remoteLastUpdated.isNotEmpty && localLastUpdated.isNotEmpty) {
        try {
          final dtRemote = DateTime.parse(remoteLastUpdated);
          final dtLocal = DateTime.parse(localLastUpdated);
          isNewer = dtRemote.isAfter(dtLocal);
        } catch (_) {}
      }

      // Check if data is already up-to-date and not forced
      if (!forceDownload && !isNewer && remoteJsonContent.trim() == localJsonContent.trim()) {
        onProgress?.call(1.0, '최신 버전 확인 완료');
        final versionStr = DatabaseService.instance.dataVersionDisplay;
        return SyncResult(
          success: true,
          message: '이미 최신 데이터 버전입니다.\n($versionStr)',
          isUpToDate: true,
        );
      }

      onProgress?.call(0.75, '최신 데이터베이스 적용 중...');
      await DatabaseService.instance.replaceDatabaseContent(remoteJsonContent);

      onProgress?.call(1.0, '버전 업데이트 완료!');
      final newVersionStr = DatabaseService.instance.dataVersionDisplay;

      return SyncResult(
        success: true,
        message: '서버의 최신 데이터 버전으로 업데이트되었습니다.\n($newVersionStr)',
        isUpToDate: false,
      );
    } catch (e) {
      onProgress?.call(1.0, '동기화 오류 발생');
      return SyncResult(success: false, message: '동기화 중 오류가 발생했습니다: $e');
    }
  }
}

class SyncResult {
  final bool success;
  final String message;
  final bool isUpToDate;

  SyncResult({
    required this.success,
    required this.message,
    this.isUpToDate = false,
  });
}
