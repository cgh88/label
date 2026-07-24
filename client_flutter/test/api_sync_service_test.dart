import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:client_flutter/services/api_sync_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('ApiSyncService defaults and config checking', () async {
    final service = ApiSyncService.instance;
    await service.loadConfig();
    expect(service.isConfigured(), isTrue);
    expect(service.apiSyncUrl, contains('http'));
  });

  test('SyncResult holds success status and message correctly', () {
    final result = SyncResult(success: true, message: '원격 서버의 최신 데이터를 로컬로 다운로드했습니다.');
    expect(result.success, isTrue);
    expect(result.message, contains('다운로드'));
  });
}
