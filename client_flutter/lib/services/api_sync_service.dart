import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'database_service.dart';

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
    if (!isConfigured()) {
      return SyncResult(success: false, message: '동기화 API 주소가 올바르지 않습니다.');
    }

    try {
      // 1. GET current remote database content
      final getResponse = await http.get(
        Uri.parse('$apiSyncUrl/api/sync/database'),
        headers: await authHeaders(),
      ).timeout(const Duration(seconds: 10));

      if (getResponse.statusCode != 200) {
        return SyncResult(
          success: false,
          message: '원격 데이터를 읽지 못했습니다 (상태 코드: ${getResponse.statusCode})',
        );
      }

      final remoteJsonContent = getResponse.body;
      final localJsonContent = await DatabaseService.instance.getRawJson();

      // Compare raw contents first
      if (remoteJsonContent.trim() == localJsonContent.trim()) {
        return SyncResult(success: true, message: '이미 최신 상태로 동기화되어 있습니다.');
      }

      // Always download remote database content to local (Server is master)
      await DatabaseService.instance.replaceDatabaseContent(remoteJsonContent);
      return SyncResult(
        success: true,
        message: '원격 서버의 최신 데이터를 로컬로 다운로드했습니다.',
      );
    } catch (e) {
      return SyncResult(success: false, message: '동기화 중 오류가 발생했습니다: $e');
    }
  }
}

class SyncResult {
  final bool success;
  final String message;

  SyncResult({required this.success, required this.message});
}
