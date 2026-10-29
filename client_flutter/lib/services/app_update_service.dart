import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import '../config/app_version.dart';
import 'api_sync_service.dart';

class AppUpdateInfo {
  final bool exists;
  final bool windowsExists;
  final String latestVersion;
  final int latestBuildNumber;
  final String? buildDate;
  final int? sizeBytes;
  final String? fileSizeMb;
  final String downloadUrl;
  final String windowsDownloadUrl;
  final bool hasUpdate;

  const AppUpdateInfo({
    required this.exists,
    required this.windowsExists,
    required this.latestVersion,
    required this.latestBuildNumber,
    this.buildDate,
    this.sizeBytes,
    this.fileSizeMb,
    required this.downloadUrl,
    required this.windowsDownloadUrl,
    required this.hasUpdate,
  });

  String get latestDisplay => 'v$latestVersion (#$latestBuildNumber)';
}

class AppUpdateService {
  AppUpdateService._();
  static final AppUpdateService instance = AppUpdateService._();

  static const MethodChannel _installerChannel = MethodChannel(
    'com.shelflife.labelprinter/installer',
  );

  bool _hasCheckedOnStartup = false;

  /// Compares [remoteVer] + [remoteBuild] with local [AppVersion].
  static bool isNewerVersion(String remoteVer, int remoteBuild) {
    final localParts =
        AppVersion.version
            .split('.')
            .map((e) => int.tryParse(e.trim()) ?? 0)
            .toList();
    final remoteParts =
        remoteVer
            .split('.')
            .map((e) => int.tryParse(e.trim()) ?? 0)
            .toList();

    final maxLen =
        localParts.length > remoteParts.length
            ? localParts.length
            : remoteParts.length;
    for (int i = 0; i < maxLen; i++) {
      final l = i < localParts.length ? localParts[i] : 0;
      final r = i < remoteParts.length ? remoteParts[i] : 0;
      if (r > l) return true;
      if (r < l) return false;
    }

    return remoteBuild > AppVersion.buildNumber;
  }

  /// Queries `/api/app-info` from the configured server.
  Future<AppUpdateInfo?> fetchUpdateInfo() async {
    try {
      await ApiSyncService.instance.loadConfig();
      final baseUrl = ApiSyncService.instance.apiSyncUrl;
      if (baseUrl.isEmpty) return null;

      final uri = Uri.parse('$baseUrl/api/app-info');
      final response = await http
          .get(uri)
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return null;

      final data = jsonDecode(utf8.decode(response.bodyBytes));
      if (data is! Map<String, dynamic>) return null;

      final exists = data['exists'] == true;
      final windowsExists = data['windowsExists'] == true;
      final latestVersion = (data['version']?.toString() ?? '1.0.0').trim();
      final latestBuildNumber =
          int.tryParse(data['buildNumber']?.toString() ?? '1') ?? 1;
      final buildDate = data['buildDate']?.toString();
      final sizeBytes =
          data['sizeBytes'] is int
              ? data['sizeBytes'] as int
              : int.tryParse(data['sizeBytes']?.toString() ?? '');
      final fileSizeMb = data['fileSizeMb']?.toString();
      final downloadPath =
          data['downloadUrl']?.toString() ?? '/download/app-release.apk';
      final winDownloadPath =
          data['windowsDownloadUrl']?.toString() ??
          '/download/PapaLabel_Windows_Release.zip';

      final fullDownloadUrl =
          downloadPath.startsWith('http')
              ? downloadPath
              : '$baseUrl${downloadPath.startsWith('/') ? '' : '/'}$downloadPath';
      final fullWinDownloadUrl =
          winDownloadPath.startsWith('http')
              ? winDownloadPath
              : '$baseUrl${winDownloadPath.startsWith('/') ? '' : '/'}$winDownloadPath';

      final hasUpdate = isNewerVersion(latestVersion, latestBuildNumber);

      return AppUpdateInfo(
        exists: exists,
        windowsExists: windowsExists,
        latestVersion: latestVersion,
        latestBuildNumber: latestBuildNumber,
        buildDate: buildDate,
        sizeBytes: sizeBytes,
        fileSizeMb: fileSizeMb,
        downloadUrl: fullDownloadUrl,
        windowsDownloadUrl: fullWinDownloadUrl,
        hasUpdate: hasUpdate,
      );
    } catch (e) {
      debugPrint('AppUpdateService.fetchUpdateInfo error: $e');
      return null;
    }
  }

  /// Automatically checks once per app session and prompts if a newer version exists.
  Future<void> checkOnStartupIfNeeded(BuildContext context) async {
    if (_hasCheckedOnStartup || kIsWeb) return;
    _hasCheckedOnStartup = true;

    final info = await fetchUpdateInfo();
    if (info == null || !info.hasUpdate) return;

    final isAndroid = defaultTargetPlatform == TargetPlatform.android;
    final isWindows = defaultTargetPlatform == TargetPlatform.windows;
    if (isAndroid && !info.exists) return;
    if (!isAndroid && !isWindows) return;

    if (!context.mounted) return;
    await _showUpdateConfirmDialog(context, info, manualTrigger: false);
  }

  /// Triggered when the user taps "앱 버전 업데이트 확인 / 설치" in Settings.
  Future<void> checkAndPromptUpdate(BuildContext context) async {
    if (kIsWeb) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (ctx) => const AlertDialog(
            content: Row(
              children: [
                SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
                SizedBox(width: 16),
                Expanded(child: Text('서버의 최신 앱 버전 정보를 확인하는 중...')),
              ],
            ),
          ),
    );

    final info = await fetchUpdateInfo();
    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
    }
    if (!context.mounted) return;

    if (info == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('❌ 서버에서 앱 버전 정보를 가져오지 못했습니다. 네트워크 연결을 확인해 주세요.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    final isAndroid = defaultTargetPlatform == TargetPlatform.android;
    if (isAndroid && !info.exists) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ 서버에 등록된 Android 설치 파일(APK)이 없습니다.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    await _showUpdateConfirmDialog(context, info, manualTrigger: true);
  }

  Future<void> _showUpdateConfirmDialog(
    BuildContext context,
    AppUpdateInfo info, {
    required bool manualTrigger,
  }) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isNewer = info.hasUpdate;

    String formattedDate = '';
    if (info.buildDate != null && info.buildDate!.isNotEmpty) {
      final parsed = DateTime.tryParse(info.buildDate!)?.toLocal();
      if (parsed != null) {
        formattedDate =
            '${parsed.year}-${parsed.month.toString().padLeft(2, '0')}-${parsed.day.toString().padLeft(2, '0')} '
            '${parsed.hour.toString().padLeft(2, '0')}:${parsed.minute.toString().padLeft(2, '0')}';
      }
    }

    final bool? shouldInstall = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: isDark ? const Color(0xFF1E2030) : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              Icon(
                isNewer ? Icons.system_update : Icons.verified_outlined,
                color:
                    isNewer
                        ? const Color(0xFFFF1E1E)
                        : const Color(0xFF10B981),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  isNewer ? '새로운 앱 업데이트 안내' : '앱 버전 확인 및 재설치',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isNewer
                    ? '서버에 새로운 버전의 앱이 배포되었습니다.\n지금 다운로드하여 바로 업데이트하시겠습니까?'
                    : '현재 최신 버전의 앱이 설치되어 있습니다.\n필요 시 서버의 설치 파일을 다시 받아 재설치할 수 있습니다.',
                style: TextStyle(
                  fontSize: 13.5,
                  height: 1.45,
                  color: isDark ? Colors.white70 : Colors.black87,
                ),
              ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color:
                      isDark
                          ? Colors.white.withValues(alpha: 0.05)
                          : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color:
                        isDark
                            ? Colors.white.withValues(alpha: 0.12)
                            : const Color(0xFFE2E8F0),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildInfoRow(
                      '현재 설치 버전',
                      AppVersion.shortDisplay,
                      isDark: isDark,
                    ),
                    const SizedBox(height: 6),
                    _buildInfoRow(
                      '서버 배포 버전',
                      info.latestDisplay,
                      isDark: isDark,
                      valueColor:
                          isNewer
                              ? const Color(0xFFFF1E1E)
                              : const Color(0xFF10B981),
                    ),
                    if (info.fileSizeMb != null) ...[
                      const SizedBox(height: 6),
                      _buildInfoRow(
                        '설치 파일 크기',
                        info.fileSizeMb!,
                        isDark: isDark,
                      ),
                    ],
                    if (formattedDate.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      _buildInfoRow(
                        '서버 빌드 일시',
                        formattedDate,
                        isDark: isDark,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(
                isNewer ? '나중에' : '닫기',
                style: TextStyle(
                  color: isDark ? Colors.white60 : Colors.black54,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            ElevatedButton.icon(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              icon: const Icon(Icons.download_rounded, size: 18),
              label: Text(
                isNewer ? '지금 업데이트' : '다시 다운로드 및 재설치',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    isNewer
                        ? const Color(0xFFFF1E1E)
                        : const Color(0xFF6366F1),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ],
        );
      },
    );

    if (shouldInstall == true && context.mounted) {
      await downloadAndInstallDialog(context, info);
    }
  }

  Widget _buildInfoRow(
    String label,
    String value, {
    required bool isDark,
    Color? valueColor,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: isDark ? Colors.white60 : Colors.black54,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.bold,
            color: valueColor ?? (isDark ? Colors.white : Colors.black87),
          ),
        ),
      ],
    );
  }

  /// Downloads the APK (or Windows ZIP) with a live progress dialog and triggers installation.
  Future<void> downloadAndInstallDialog(
    BuildContext context,
    AppUpdateInfo info,
  ) async {
    final bool isAndroid =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
    final String targetUrl =
        isAndroid ? info.downloadUrl : info.windowsDownloadUrl;

    double progress = 0.0;
    String statusText = '설치 파일 다운로드 준비 중...';
    String detailText = '';
    bool isDone = false;
    bool hasError = false;
    String? downloadedFilePath;
    StateSetter? dialogSetState;
    http.Client? activeClient;
    bool isCancelled = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            dialogSetState = setDialogState;
            final isDark = Theme.of(context).brightness == Brightness.dark;

            return AlertDialog(
              backgroundColor: isDark ? const Color(0xFF1E2030) : Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: Row(
                children: [
                  Icon(
                    hasError
                        ? Icons.error_outline
                        : (isDone
                            ? Icons.check_circle_outline
                            : Icons.downloading_rounded),
                    color:
                        hasError
                            ? Colors.redAccent
                            : (isDone
                                ? Colors.greenAccent
                                : const Color(0xFFFF1E1E)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      hasError
                          ? '업데이트 오류'
                          : (isDone ? '다운로드 완료 · 설치 진행' : '앱 업데이트 다운로드 중'),
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    statusText,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.4,
                      color: isDark ? Colors.white70 : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 16),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: progress > 0 ? progress : null,
                      minHeight: 10,
                      backgroundColor:
                          isDark ? Colors.white12 : Colors.black12,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        hasError
                            ? Colors.redAccent
                            : (isDone
                                ? Colors.greenAccent
                                : const Color(0xFFFF1E1E)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        detailText,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: isDark ? Colors.white54 : Colors.black54,
                        ),
                      ),
                      Text(
                        '${(progress * 100).clamp(0, 100).toInt()}%',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color:
                              hasError
                                  ? Colors.redAccent
                                  : (isDone
                                      ? Colors.greenAccent
                                      : const Color(0xFFFF1E1E)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              actions: [
                if (!isDone && !hasError)
                  TextButton(
                    onPressed: () {
                      isCancelled = true;
                      activeClient?.close();
                      Navigator.of(dialogContext).pop();
                    },
                    child: const Text(
                      '취소',
                      style: TextStyle(color: Colors.redAccent),
                    ),
                  ),
                if (isDone && isAndroid && downloadedFilePath != null)
                  ElevatedButton.icon(
                    onPressed: () async {
                      await _triggerAndroidInstaller(
                        downloadedFilePath!,
                        onNeedPermission: () {
                          dialogSetState?.call(() {
                            statusText =
                                '안드로이드 설정에서 "이 출처의 앱 허용"을 켠 뒤 아래 [설치 창 다시 열기]를 눌러주세요.';
                          });
                        },
                      );
                    },
                    icon: const Icon(Icons.install_mobile, size: 18),
                    label: const Text(
                      '설치 창 다시 열기',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF1E1E),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                if (isDone || hasError)
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: const Text(
                      '닫기',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
              ],
            );
          },
        );
      },
    );

    try {
      activeClient = http.Client();
      final request = http.Request('GET', Uri.parse(targetUrl));
      final streamedResponse = await activeClient
          .send(request)
          .timeout(const Duration(seconds: 30));

      if (streamedResponse.statusCode != 200) {
        throw Exception(
          '설치 파일을 다운로드할 수 없습니다 (HTTP ${streamedResponse.statusCode})',
        );
      }

      final int totalBytes =
          streamedResponse.contentLength ?? info.sizeBytes ?? 0;
      final Directory tempDir = await getTemporaryDirectory();
      final String fileName =
          isAndroid ? 'papalabel_update.apk' : 'PapaLabel_Windows_Release.zip';
      final File targetFile = File('${tempDir.path}/$fileName');
      if (await targetFile.exists()) {
        await targetFile.delete();
      }

      final IOSink sink = targetFile.openWrite();
      int receivedBytes = 0;

      dialogSetState?.call(() {
        statusText = '서버에서 최신 설치 파일을 내려받는 중입니다...';
      });

      await for (final chunk in streamedResponse.stream) {
        if (isCancelled) {
          await sink.close();
          return;
        }
        sink.add(chunk);
        receivedBytes += chunk.length;

        if (totalBytes > 0) {
          final double newProgress = (receivedBytes / totalBytes).clamp(
            0.0,
            0.99,
          );
          final String recMb = (receivedBytes / (1024 * 1024))
              .toStringAsFixed(1);
          final String totMb = (totalBytes / (1024 * 1024)).toStringAsFixed(1);
          dialogSetState?.call(() {
            progress = newProgress;
            detailText = '$recMb MB / $totMb MB';
          });
        } else {
          final String recMb = (receivedBytes / (1024 * 1024))
              .toStringAsFixed(1);
          dialogSetState?.call(() {
            progress = 0.5;
            detailText = '$recMb MB 다운로드됨';
          });
        }
      }

      await sink.flush();
      await sink.close();
      activeClient.close();

      if (isCancelled) return;

      downloadedFilePath = targetFile.path;
      dialogSetState?.call(() {
        progress = 1.0;
        isDone = true;
        statusText =
            isAndroid
                ? '다운로드가 완료되었습니다! 안드로이드 설치 화면에서 [설치] 또는 [업데이트]를 눌러주세요.'
                : '다운로드가 완료되었습니다! 압축 파일이 저장된 폴더를 열었습니다.';
      });

      if (isAndroid) {
        await _triggerAndroidInstaller(
          targetFile.path,
          onNeedPermission: () {
            dialogSetState?.call(() {
              statusText =
                  '최초 1회 "출처를 알 수 없는 앱 설치" 권한 허용이 필요합니다.\n권한을 켠 뒤 아래 [설치 창 다시 열기] 버튼을 눌러주세요.';
            });
          },
        );
      } else if (defaultTargetPlatform == TargetPlatform.windows) {
        await Process.run('explorer.exe', ['/select,', targetFile.path]);
      }
    } catch (e) {
      if (isCancelled) return;
      debugPrint('AppUpdateService download error: $e');
      dialogSetState?.call(() {
        hasError = true;
        statusText = '다운로드 중 오류가 발생했습니다:\n$e';
      });
    }
  }

  Future<void> _triggerAndroidInstaller(
    String filePath, {
    VoidCallback? onNeedPermission,
  }) async {
    final result = await _installerChannel.invokeMethod<String>(
      'installApk',
      {'filePath': filePath},
    );
    if (result == 'NEED_PERMISSION') {
      onNeedPermission?.call();
    }
  }
}

