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

  /// Builds request headers including the stored session cookie if available.
  static Future<Map<String, String>> authHeaders({bool jsonBody = false}) async {
    final headers = <String, String>{};
    if (jsonBody) headers['Content-Type'] = 'application/json';

    final prefs = await SharedPreferences.getInstance();
    final rawCookie = prefs.getString('session_cookie');
    if (rawCookie != null && rawCookie.isNotEmpty) {
      final token = rawCookie.split(';').first.trim();
      if (token.isNotEmpty) headers['Cookie'] = token;
    }
    return headers;
  }

  Future<SyncResult> performSync() async {
    return await performSyncWithProgress();
  }

  /// Performs server-to-client one-way database download and sync.
  /// No login required -- supports public download without authentication.
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

      // 1. Primary GET request
      http.Response response = await http.get(
        Uri.parse('$apiSyncUrl/api/sync/database'),
        headers: await authHeaders(),
      ).timeout(const Duration(seconds: 10));

      // 2. If 401 occurs, fallback to pure public request without any cookie headers
      if (response.statusCode == 401) {
        onProgress?.call(0.30, '공용 동기화 재시도 중...');
        response = await http.get(
          Uri.parse('$apiSyncUrl/api/sync/database'),
        ).timeout(const Duration(seconds: 10));
      }

      if (response.statusCode != 200) {
        onProgress?.call(1.0, '원격 데이터 읽기 실패 (${response.statusCode})');
        return SyncResult(
          success: false,
          message: '원격 서버 데이터를 읽지 못했습니다 (상태 코드: ${response.statusCode})',
        );
      }

      onProgress?.call(0.45, '서버 데이터 검증 및 버전 비교 중...');
      final remoteJsonContent = response.body;
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

  /// Checks whether the configured remote API server is reachable.
  Future<ServerConnectionStatus> checkServerConnection() async {
    if (!isConfigured()) {
      return ServerConnectionStatus(
        isReachable: false,
        message: '서버 주소가 설정되지 않았습니다.',
      );
    }

    try {
      final response = await http.get(
        Uri.parse('$apiSyncUrl/api/sync/database'),
        headers: await authHeaders(),
      ).timeout(const Duration(seconds: 3));

      if (response.statusCode == 200) {
        return ServerConnectionStatus(
          isReachable: true,
          message: '원격 서버 접속 가능 (상태: OK 200)',
          statusCode: 200,
        );
      } else {
        return ServerConnectionStatus(
          isReachable: false,
          message: '서버 응답 오류 (상태 코드: ${response.statusCode})',
          statusCode: response.statusCode,
        );
      }
    } catch (e) {
      return ServerConnectionStatus(
        isReachable: false,
        message: '서버 접속 불가 (네트워크 미연결 또는 서버 오프라인)',
      );
    }
  }

  /// Imports database JSON content provided manually as a backup file.
  Future<SyncResult> importDatabaseJsonString(String jsonContent) async {
    try {
      final decoded = jsonDecode(jsonContent);
      if (decoded is! Map<String, dynamic>) {
        return SyncResult(success: false, message: '올바른 JSON 형식의 데이터 파일이 아닙니다.');
      }
      if (!decoded.containsKey('ingredients_v2') && !decoded.containsKey('categories')) {
        return SyncResult(
          success: false,
          message: '라벨 프리셋 데이터베이스 포맷이 일치하지 않는 파일입니다.',
        );
      }

      await DatabaseService.instance.replaceDatabaseContent(jsonContent);
      final newVersion = DatabaseService.instance.dataVersionDisplay;
      return SyncResult(
        success: true,
        message: '제공된 백업 파일이 성공적으로 적용되었습니다.\n(버전: $newVersion)',
      );
    } catch (e) {
      return SyncResult(success: false, message: '파일 구조 해석 오류: $e');
    }
  }
}

class ServerConnectionStatus {
  final bool isReachable;
  final String message;
  final int? statusCode;

  ServerConnectionStatus({
    required this.isReachable,
    required this.message,
    this.statusCode,
  });
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
