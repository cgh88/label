import 'dart:convert';
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
    return apiSyncUrl.isNotEmpty && Uri.tryParse(apiSyncUrl)?.hasAbsolutePath == true;
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

      // Compare timestamps
      Map<String, dynamic> localData;
      Map<String, dynamic> remoteData;
      try {
        localData = jsonDecode(localJsonContent) as Map<String, dynamic>;
        remoteData = jsonDecode(remoteJsonContent) as Map<String, dynamic>;
      } catch (e) {
        return SyncResult(success: false, message: '데이터 파싱 오류: $e');
      }

      final localTimeStr = localData['last_updated'] as String? ?? '1970-01-01T00:00:00Z';
      final remoteTimeStr = remoteData['last_updated'] as String? ?? '1970-01-01T00:00:00Z';

      final localTime = DateTime.parse(localTimeStr);
      final remoteTime = DateTime.parse(remoteTimeStr);

      if (remoteTime.isAfter(localTime)) {
        // Download: remote is newer, replace local
        await DatabaseService.instance.replaceDatabaseContent(remoteJsonContent);
        return SyncResult(
          success: true,
          message: '원격 서버의 최신 데이터를 로컬로 다운로드했습니다.\n(원격: $remoteTimeStr, 로컬: $localTimeStr)',
        );
      } else {
        // Upload: local is newer, POST to remote
        final postResponse = await http.post(
          Uri.parse('$apiSyncUrl/api/sync/database'),
          headers: await authHeaders(jsonBody: true),
          body: localJsonContent,
        ).timeout(const Duration(seconds: 10));

        if (postResponse.statusCode == 200) {
          return SyncResult(
            success: true,
            message: '로컬의 최신 데이터를 원격 서버로 업로드했습니다.\n(로컬: $localTimeStr, 원격: $remoteTimeStr)',
          );
        } else {
          return SyncResult(
            success: false,
            message: '원격 서버 업로드에 실패했습니다 (상태 코드: ${postResponse.statusCode})',
          );
        }
      }
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
