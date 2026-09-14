import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:blue_thermal_printer/blue_thermal_printer.dart';
import 'package:printing/printing.dart';
import 'package:file_picker/file_picker.dart';
import '../services/api_sync_service.dart';
import '../services/bluetooth_service.dart';
import '../services/usb_print_service.dart';
import '../services/database_service.dart';
import '../services/layout_events.dart';
import '../config/app_version.dart';

class SettingsTabView extends StatefulWidget {
  const SettingsTabView({super.key});

  @override
  State<SettingsTabView> createState() => _SettingsTabViewState();
}

class _SettingsTabViewState extends State<SettingsTabView> {
  final _widthController = TextEditingController();
  final _heightController = TextEditingController();

  final _apiUrlController = TextEditingController(
    text: 'https://labelprint.pji.co.kr/',
  );

  double _selectedWidth = 50;
  double _selectedHeight = 30;

  // Layout Fine-Tuning State
  bool _showLine1 = true;
  bool _showLine2 = true;
  bool _showLine3 = true;
  double _fontSize1 = 12.5;
  double _fontSize2 = 12.5;
  double _fontSize3 = 12.5;
  double _leftPadding = 10.0;
  double _verticalGap = 3.5;

  ServerConnectionStatus? _serverStatus;
  bool _isCheckingServer = false;

  List<BluetoothDevice> _devices = [];
  BluetoothDevice? _selectedDevice;
  bool _isBluetoothSupported = false;
  bool _isConnecting = false;
  bool _autoConnect = true;
  bool _isTestingUsb = false;

  @override
  void initState() {
    super.initState();
    _loadSettings().then((_) {
      if (mounted) {
        _checkServerConnection(showFeedback: false);
      }
    });

    final bool isAndroid =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
    if (isAndroid) {
      _initBluetooth();
      BluetoothPrintService.instance.connectionRevision.addListener(
        _onConnectionChanged,
      );
    }

    final bool isWindows =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;
    if (isWindows) {
      UsbPrintService.instance.init();
      UsbPrintService.instance.connectionRevision.addListener(
        _onUsbConnectionChanged,
      );
    }

    DatabaseService.instance.dataRevision.addListener(_onDataChanged);
  }

  @override
  void dispose() {
    final bool isAndroid =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
    if (isAndroid) {
      BluetoothPrintService.instance.connectionRevision.removeListener(
        _onConnectionChanged,
      );
    }

    final bool isWindows =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;
    if (isWindows) {
      UsbPrintService.instance.connectionRevision.removeListener(
        _onUsbConnectionChanged,
      );
    }

    DatabaseService.instance.dataRevision.removeListener(_onDataChanged);
    _widthController.dispose();
    _heightController.dispose();
    _apiUrlController.dispose();
    super.dispose();
  }

  void _onConnectionChanged() {
    if (mounted) {
      _loadBluetoothDevices();
    }
  }

  void _onUsbConnectionChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _onDataChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('layout_show_line_4', false);

    final bool isWindows =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;
    final double customWidth =
        isWindows ? (prefs.getDouble('label_width') ?? 55.0) : 55.0;
    final double customHeight =
        isWindows ? (prefs.getDouble('label_height') ?? 20.0) : 20.0;

    setState(() {
      _selectedWidth = customWidth;
      _selectedHeight = customHeight;
      _widthController.text = customWidth.toStringAsFixed(
        customWidth.truncateToDouble() == customWidth ? 0 : 1,
      );
      _heightController.text = customHeight.toStringAsFixed(
        customHeight.truncateToDouble() == customHeight ? 0 : 1,
      );

      _showLine1 = prefs.getBool('layout_show_line_1') ?? true;
      _showLine2 = prefs.getBool('layout_show_line_2') ?? true;
      _showLine3 = prefs.getBool('layout_show_line_3') ?? true;
      _fontSize1 = prefs.getDouble('layout_font_size_1') ?? 12.5;
      _fontSize2 = prefs.getDouble('layout_font_size_2') ?? 12.5;
      _fontSize3 = prefs.getDouble('layout_font_size_3') ?? 12.5;
      _leftPadding = prefs.getDouble('layout_left_padding') ?? 10.0;
      _verticalGap = prefs.getDouble('layout_vertical_gap') ?? 3.5;
    });

    final autoConn =
        await BluetoothPrintService.instance.isAutoConnectEnabled();
    if (mounted) {
      setState(() {
        _autoConnect = autoConn;
      });
    }

    await ApiSyncService.instance.loadConfig();
    setState(() {
      _apiUrlController.text = ApiSyncService.instance.apiSyncUrl;
    });
  }

  Future<void> _saveLayoutSetting(String key, dynamic value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value is bool) {
      await prefs.setBool(key, value);
    } else if (value is double) {
      await prefs.setDouble(key, value);
    }
    // Notify open previews (e.g. the print tab) to reload immediately.
    layoutSettingsRevision.value++;
  }

  Future<void> _performVersionUpdate() async {
    double progress = 0.05;
    String status = '업데이트 준비 중...';
    bool isDone = false;
    SyncResult? syncResult;
    StateSetter? dialogSetState;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            dialogSetState = setDialogState;
            final isDarkDialog = Theme.of(context).brightness == Brightness.dark;
            final bool isSuccess = syncResult?.success ?? false;

            return AlertDialog(
              backgroundColor: isDarkDialog ? const Color(0xFF1E2030) : Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Row(
                children: [
                  Icon(
                    isDone
                        ? (isSuccess ? Icons.check_circle : Icons.error)
                        : Icons.system_update_alt,
                    color: isDone
                        ? (isSuccess ? Colors.greenAccent : Colors.redAccent)
                        : const Color(0xFF6366F1),
                  ),
                  const SizedBox(width: 10),
                  const Text('서버 데이터 버전 업데이트', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    status,
                    style: TextStyle(
                      fontSize: 13,
                      color: isDarkDialog ? Colors.white70 : Colors.black87,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 16),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 10,
                      backgroundColor: isDarkDialog ? Colors.white12 : Colors.black12,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        isDone
                            ? (isSuccess ? Colors.greenAccent : Colors.redAccent)
                            : const Color(0xFF6366F1),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      '${(progress * 100).toInt()}%',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: isDone
                            ? (isSuccess ? Colors.greenAccent : Colors.redAccent)
                            : const Color(0xFF6366F1),
                      ),
                    ),
                  ),
                  if (isDone && syncResult != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      syncResult.message,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: isSuccess ? Colors.greenAccent : Colors.redAccent,
                      ),
                    ),
                    if (!isSuccess) ...[
                      const SizedBox(height: 14),
                      OutlinedButton.icon(
                        onPressed: () {
                          Navigator.of(dialogContext).pop();
                          _pickAndImportDatabaseFile();
                        },
                        icon: const Icon(Icons.file_upload_outlined, color: Color(0xFF10B981), size: 18),
                        label: const Text(
                          '백업 데이터 파일(.json) 수동 업로드',
                          style: TextStyle(color: Color(0xFF10B981), fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Color(0xFF10B981)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ],
                  ],
                ],
              ),
              actions: isDone
                  ? [
                      ElevatedButton(
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF6366F1),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        child: const Text('확인'),
                      ),
                    ]
                  : null,
            );
          },
        );
      },
    );

    syncResult = await ApiSyncService.instance.performSyncWithProgress(
      onProgress: (p, msg) {
        progress = p;
        status = msg;
        dialogSetState?.call(() {});
      },
    );

    isDone = true;
    progress = 1.0;
    status = syncResult.success ? '데이터 버전 확인 완료' : '동기화 오류 발생';
    dialogSetState?.call(() {});
  }

  Future<void> _checkServerConnection({bool showFeedback = false}) async {
    if (!mounted) return;
    setState(() {
      _isCheckingServer = true;
    });
    final status = await ApiSyncService.instance.checkServerConnection();
    if (mounted) {
      setState(() {
        _serverStatus = status;
        _isCheckingServer = false;
      });
      if (showFeedback) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor:
                status.isReachable ? const Color(0xFF10B981) : Colors.redAccent,
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: status.isReachable ? 2 : 3),
            content: Row(
              children: [
                Icon(
                  status.isReachable
                      ? Icons.check_circle
                      : Icons.error_outline,
                  color: Colors.white,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    status.isReachable
                        ? '서버 연결 확인 완료 (정상 접속 가능)'
                        : status.message,
                  ),
                ),
              ],
            ),
          ),
        );
      }
    }
  }

  Future<void> _pickAndImportDatabaseFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        withData: true,
      );

      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      String? jsonContent;

      if (file.bytes != null) {
        jsonContent = utf8.decode(file.bytes!);
      } else if (file.path != null) {
        jsonContent = await File(file.path!).readAsString();
      }

      if (jsonContent == null || jsonContent.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              backgroundColor: Colors.redAccent,
              content: Text('선택한 백업 파일을 읽을 수 없습니다.'),
            ),
          );
        }
        return;
      }

      final syncResult = await ApiSyncService.instance.importDatabaseJsonString(jsonContent);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: syncResult.success ? Colors.green : Colors.redAccent,
            content: Text(syncResult.message),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.redAccent,
            content: Text('파일 선택 및 업로드 오류: $e'),
          ),
        );
      }
    }
  }

  Future<void> _initBluetooth() async {
    final bool isAndroid =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
    if (!isAndroid) return;

    try {
      final isAvail =
          await BluetoothPrintService.instance.checkBluetoothAvailable();
      if (isAvail) {
        if (mounted) {
          setState(() {
            _isBluetoothSupported = true;
          });
        }
        await BluetoothPrintService.instance.autoConnect();
        if (mounted) {
          _loadBluetoothDevices();
        }
      }
    } catch (e) {
      debugPrint('Bluetooth init failed: $e');
    }
  }

  Future<void> _loadBluetoothDevices() async {
    final list = await BluetoothPrintService.instance.getPairedDevices();
    final conn = BluetoothPrintService.instance.connectedDevice;
    if (mounted) {
      setState(() {
        _devices = list;
        if (conn != null) {
          try {
            _selectedDevice = list.firstWhere((d) => d.address == conn.address);
          } catch (_) {
            _selectedDevice = conn;
          }
        } else if (list.isNotEmpty) {
          _selectedDevice = list.first;
        }
      });
    }
  }

  Future<void> _toggleBluetoothConnection() async {
    if (_selectedDevice == null) return;

    setState(() {
      _isConnecting = true;
    });

    if (BluetoothPrintService.instance.isConnected) {
      await BluetoothPrintService.instance.disconnect();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('블루투스 프린터 연결을 해제했습니다.')));
      }
    } else {
      final isPaired = await BluetoothPrintService.instance.isDevicePaired(
        _selectedDevice!.address,
      );
      if (!isPaired) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              backgroundColor: Colors.redAccent,
              content: Text(
                '선택한 프린터가 시스템 블루투스 설정에서 페어링 해제되어 있습니다. 페어링을 먼저 진행해 주세요.',
              ),
            ),
          );
        }
        setState(() {
          _isConnecting = false;
        });
        _loadBluetoothDevices();
        return;
      }

      final success = await BluetoothPrintService.instance.connect(
        _selectedDevice!,
      );
      if (mounted) {
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${_selectedDevice!.name} 프린터에 연결되었습니다.')),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              backgroundColor: Colors.redAccent,
              content: Text('프린터 연결에 실패했습니다. 전원 및 페어링 상태를 확인해 주세요.'),
            ),
          );
        }
      }
    }

    setState(() {
      _isConnecting = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isWindows =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

    final Widget leftColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          color: isDark ? const Color(0xFF1E2030) : Colors.white,
          elevation: 3,
          shadowColor: Colors.black12,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color:
                  isDark
                      ? Colors.white.withValues(alpha: 0.18)
                      : const Color(0xFFCBD5E1),
              width: 1.2,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.crop_free, color: Color(0xFFFF1E1E)),
                        const SizedBox(width: 8),
                        Text(
                          '라벨 규격 설정',
                          style: TextStyle(
                            color: isDark ? Colors.white : Colors.black87,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                    if (isWindows)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: const Color(0xFF10B981).withValues(alpha: 0.3),
                          ),
                        ),
                        child: const Text(
                          'Windows 커스텀 규격 지원',
                          style: TextStyle(
                            color: Color(0xFF10B981),
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 20),

                // Active preset indicator
                Row(
                  children: [
                    Text(
                      '현재 적용 규격: ',
                      style: TextStyle(
                        color: isDark ? Colors.white70 : Colors.black87,
                        fontSize: 13,
                      ),
                    ),
                    Text(
                      '${_selectedWidth.toStringAsFixed(_selectedWidth.truncateToDouble() == _selectedWidth ? 0 : 1)}mm × ${_selectedHeight.toStringAsFixed(_selectedHeight.truncateToDouble() == _selectedHeight ? 0 : 1)}mm',
                      style: const TextStyle(
                        color: Colors.greenAccent,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                if (isWindows) ...[
                  // Preset buttons
                  Text(
                    '빠른 규격 선택 (프리셋)',
                    style: TextStyle(
                      color: isDark ? Colors.white60 : Colors.black54,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _buildSizeChip(55, 20, '55×20mm (표준)', isDark),
                      _buildSizeChip(50, 30, '50×30mm', isDark),
                      _buildSizeChip(55, 30, '55×30mm', isDark),
                      _buildSizeChip(60, 40, '60×40mm', isDark),
                      _buildSizeChip(80, 50, '80×50mm', isDark),
                      _buildSizeChip(100, 60, '100×60mm', isDark),
                    ],
                  ),
                  const SizedBox(height: 18),

                  // Direct Custom Size Input
                  Text(
                    '직접 규격 입력 (mm 단위)',
                    style: TextStyle(
                      color: isDark ? Colors.white60 : Colors.black54,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _widthController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          style: TextStyle(
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                          decoration: InputDecoration(
                            labelText: '가로 (폭)',
                            hintText: '55',
                            suffixText: 'mm',
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            labelStyle: TextStyle(
                              color: isDark ? Colors.white60 : Colors.black54,
                            ),
                          ),
                          onSubmitted: (_) => _onCustomSizeSubmitted(),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Text(
                          '×',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white70 : Colors.black54,
                          ),
                        ),
                      ),
                      Expanded(
                        child: TextField(
                          controller: _heightController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          style: TextStyle(
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                          decoration: InputDecoration(
                            labelText: '세로 (높이)',
                            hintText: '20',
                            suffixText: 'mm',
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            labelStyle: TextStyle(
                              color: isDark ? Colors.white60 : Colors.black54,
                            ),
                          ),
                          onSubmitted: (_) => _onCustomSizeSubmitted(),
                        ),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton(
                        onPressed: _onCustomSizeSubmitted,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF6366F1),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 14,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: const Text('적용'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color:
                          isDark
                              ? Colors.white.withValues(alpha: 0.04)
                              : Colors.black.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color:
                            isDark
                                ? Colors.white.withValues(alpha: 0.1)
                                : Colors.black.withValues(alpha: 0.1),
                      ),
                    ),
                    child: Text(
                      '윈도우 버전에서는 장착된 라벨 용지 규격에 맞춰 가로×세로 크기를 자유롭게 설정할 수 있습니다.\n설정한 크기는 [라벨 인쇄] 탭의 미리보기 비율과 실제 프린터 출력 용지 크기에 즉시 반영됩니다.',
                      style: TextStyle(
                        color: isDark ? Colors.white70 : Colors.black87,
                        fontSize: 11.5,
                        height: 1.45,
                      ),
                    ),
                  ),
                ] else ...[
                  // Mobile / Fixed Size info
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color:
                          isDark
                              ? const Color(0xFF13141F)
                              : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: Colors.greenAccent.withValues(alpha: 0.5),
                        width: 1.2,
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.lock_outline,
                          color: Colors.greenAccent,
                          size: 18,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                '라벨 규격 고정',
                                style: TextStyle(
                                  color: Colors.greenAccent,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '55mm × 20mm (모바일 고정 규격)',
                                style: TextStyle(
                                  color: isDark ? Colors.white70 : Colors.black87,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        _buildLayoutSettingsCard(),
      ],
    );

    final Widget rightColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          color: isDark ? const Color(0xFF1E2030) : Colors.white,
          elevation: 3,
          shadowColor: Colors.black12,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color:
                  isDark
                      ? Colors.white.withValues(alpha: 0.18)
                      : const Color(0xFFCBD5E1),
              width: 1.2,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Icon(Icons.sync_alt, color: Color(0xFFFF1E1E)),
                    const SizedBox(width: 8),
                    Text(
                      'API 동기화 서버 설정',
                      style: TextStyle(
                        color: isDark ? Colors.white : Colors.black87,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '서버 접속 상태:',
                      style: TextStyle(
                        color: isDark ? Colors.white70 : Colors.black87,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Flexible(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: _serverStatus == null
                                  ? Colors.grey.withValues(alpha: 0.2)
                                  : (_serverStatus!.isReachable
                                      ? Colors.greenAccent.withValues(alpha: 0.2)
                                      : Colors.redAccent.withValues(alpha: 0.2)),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _serverStatus == null
                                      ? Icons.help_outline
                                      : (_serverStatus!.isReachable
                                          ? Icons.check_circle_outline
                                          : Icons.highlight_off),
                                  size: 14,
                                  color: _serverStatus == null
                                      ? Colors.grey
                                      : (_serverStatus!.isReachable
                                          ? Colors.greenAccent
                                          : Colors.redAccent),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  _serverStatus == null
                                      ? '접속 미확인'
                                      : (_serverStatus!.isReachable ? '접속 가능' : '접속 불가'),
                                  style: TextStyle(
                                    color: _serverStatus == null
                                        ? Colors.grey
                                        : (_serverStatus!.isReachable
                                            ? Colors.greenAccent
                                            : Colors.redAccent),
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: _isCheckingServer
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Icon(Icons.refresh, size: 18),
                            tooltip: '서버 다시 찾기',
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.only(left: 6),
                            constraints: const BoxConstraints(),
                            onPressed: _isCheckingServer
                                ? null
                                : () => _checkServerConnection(showFeedback: true),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '앱 프로그램 버전:',
                      style: TextStyle(
                        color: isDark ? Colors.white70 : Colors.black87,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Flexible(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF1E1E).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: const Color(0xFFFF1E1E).withValues(alpha: 0.25),
                          ),
                        ),
                        child: Text(
                          AppVersion.display,
                          style: const TextStyle(
                            color: Color(0xFFFF1E1E),
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '데이터베이스 버전:',
                      style: TextStyle(
                        color: isDark ? Colors.white70 : Colors.black87,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Flexible(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(
                            0xFF6366F1,
                          ).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: const Color(
                              0xFF6366F1,
                            ).withValues(alpha: 0.3),
                          ),
                        ),
                        child: Text(
                          DatabaseService.instance.dataVersionDisplay,
                          style: const TextStyle(
                            color: Color(0xFF6366F1),
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'monospace',
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _apiUrlController,
                  readOnly: true,
                  enabled: false,
                  style: TextStyle(
                    color: isDark ? Colors.white70 : Colors.black54,
                  ),
                  decoration: InputDecoration(
                    labelText: 'API 서버 주소 (고정 / 변경 불가)',
                    labelStyle: TextStyle(
                      color: isDark ? Colors.white60 : Colors.black54,
                    ),
                    hintText: 'https://labelprint.pji.co.kr/',
                    prefixIcon: Icon(
                      Icons.lock_outline,
                      color: isDark ? Colors.white60 : Colors.black54,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: _isCheckingServer
                      ? null
                      : () => _checkServerConnection(showFeedback: true),
                  icon: _isCheckingServer
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.sync, size: 20),
                  label: Text(
                    _isCheckingServer ? '서버 찾는 중...' : '서버 다시 찾기 / 연결 확인',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF1E1E),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _performVersionUpdate,
                  icon: const Icon(Icons.system_update_alt, color: Color(0xFF6366F1)),
                  label: const Text(
                    '최신 데이터 버전 업데이트',
                    style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF6366F1)),
                  ),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: const BorderSide(color: Color(0xFF6366F1), width: 1.2),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _pickAndImportDatabaseFile,
                  icon: const Icon(Icons.folder_open, color: Color(0xFF10B981)),
                  label: const Text(
                    '백업 데이터 파일(.json) 직접 업로드',
                    style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF10B981)),
                  ),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: const BorderSide(color: Color(0xFF10B981), width: 1.2),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) ...[
          _buildWindowsPrinterCard(isDark),
        ] else if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) ...[
          _buildBluetoothPrinterCard(isDark),
        ] else ...[
          _buildDesktopInfoCard(isDark),
        ],
      ],
    );

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final bool isWide = constraints.maxWidth >= 850;
              return SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24.0, 36.0, 24.0, 24.0),
                child:
                    isWide
                        ? Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: leftColumn),
                            const SizedBox(width: 24),
                            Expanded(child: rightColumn),
                          ],
                        )
                        : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            leftColumn,
                            const SizedBox(height: 24),
                            rightColumn,
                          ],
                        ),
              );
            },
          ),
          Positioned(
            top: 8,
            right: 24,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color:
                    isDark
                        ? Colors.white.withValues(alpha: 0.08)
                        : Colors.black.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color:
                      isDark
                          ? Colors.white.withValues(alpha: 0.12)
                          : Colors.black.withValues(alpha: 0.1),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.verified_outlined,
                    size: 13,
                    color: isDark ? const Color(0xFF60A5FA) : const Color(0xFF2563EB),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    AppVersion.display,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white70 : Colors.black87,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLayoutSettingsCard() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Card(
      color: isDark ? const Color(0xFF1E2030) : Colors.white,
      elevation: 3,
      shadowColor: Colors.black12,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color:
              isDark
                  ? Colors.white.withValues(alpha: 0.18)
                  : const Color(0xFFCBD5E1),
          width: 1.2,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.layers, color: Color(0xFFFF1E1E)),
                const SizedBox(width: 8),
                Text(
                  '라벨 레이아웃 상세 설정',
                  style: TextStyle(
                    color: isDark ? Colors.white : Colors.black87,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            _buildSliderRow(
              label: '좌측 여백 (가로 정렬 시작 위치)',
              value: _leftPadding,
              min: 0.0,
              max: 30.0,
              divisions: 60,
              displayValue: '${_leftPadding.toStringAsFixed(1)}%',
              onChanged: (val) {
                setState(() => _leftPadding = val);
                _saveLayoutSetting('layout_left_padding', val);
              },
            ),

            _buildSliderRow(
              label: '줄 간격 (세로 Spacing)',
              value: _verticalGap,
              min: 0.0,
              max: 15.0,
              divisions: 60,
              displayValue: '${_verticalGap.toStringAsFixed(1)} pt',
              onChanged: (val) {
                setState(() => _verticalGap = val);
                _saveLayoutSetting('layout_vertical_gap', val);
              },
            ),

            Divider(
              color: isDark ? Colors.white12 : Colors.black12,
              height: 24,
            ),

            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color:
                    isDark ? const Color(0xFF13141F) : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isDark ? Colors.white12 : const Color(0xFFCBD5E1),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.info_outline,
                    size: 16,
                    color: Color(0xFF6366F1),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '라벨(55 × 20mm) 인쇄 프리뷰 기준 권장 글씨 크기 — 1~3행: 12.5pt, 4행: 6.25pt',
                      style: TextStyle(
                        color: isDark ? Colors.white70 : Colors.black54,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            _buildLineSettingsTable(),
          ],
        ),
      ),
    );
  }

  Widget _buildSliderRow({
    required String label,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required String displayValue,
    required ValueChanged<double> onChanged,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: TextStyle(
                color: isDark ? Colors.white70 : Colors.black87,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              displayValue,
              style: const TextStyle(
                color: Colors.greenAccent,
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        Slider(
          value: value,
          min: min,
          max: max,
          divisions: divisions,
          activeColor: const Color(0xFFFF1E1E),
          inactiveColor:
              isDark ? const Color(0xFF252147) : const Color(0xFFE2E8F0),
          onChanged: onChanged,
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildLineSettingsTable() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Table(
      columnWidths: const {
        0: FlexColumnWidth(2.2),
        1: FlexColumnWidth(1.0),
        2: FlexColumnWidth(2.2),
      },
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        TableRow(
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: isDark ? Colors.white12 : Colors.black12,
                width: 1,
              ),
            ),
          ),
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                '인쇄 행 (Line)',
                style: TextStyle(
                  color: isDark ? Colors.white54 : Colors.black54,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Center(
                child: Text(
                  '표기 여부',
                  style: TextStyle(
                    color: isDark ? Colors.white54 : Colors.black54,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Center(
                child: Text(
                  '글씨 크기 조절 (pt)',
                  style: TextStyle(
                    color: isDark ? Colors.white54 : Colors.black54,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
        _buildLineRow(
          label: '1행 (보관위치 + 재료)',
          show: _showLine1,
          size: _fontSize1,
          sizeMin: 6.0,
          sizeMax: 28.0,
          onShowChanged: (val) {
            setState(() => _showLine1 = val);
            _saveLayoutSetting('layout_show_line_1', val);
          },
          onSizeChanged: (val) {
            setState(() => _fontSize1 = val);
            _saveLayoutSetting('layout_font_size_1', val);
          },
        ),
        _buildLineRow(
          label: '2행 (준비일시)',
          show: _showLine2,
          size: _fontSize2,
          sizeMin: 6.0,
          sizeMax: 28.0,
          onShowChanged: (val) {
            setState(() => _showLine2 = val);
            _saveLayoutSetting('layout_show_line_2', val);
          },
          onSizeChanged: (val) {
            setState(() => _fontSize2 = val);
            _saveLayoutSetting('layout_font_size_2', val);
          },
        ),
        _buildLineRow(
          label: '3행 (폐기일시)',
          show: _showLine3,
          size: _fontSize3,
          sizeMin: 6.0,
          sizeMax: 28.0,
          onShowChanged: (val) {
            setState(() => _showLine3 = val);
            _saveLayoutSetting('layout_show_line_3', val);
          },
          onSizeChanged: (val) {
            setState(() => _fontSize3 = val);
            _saveLayoutSetting('layout_font_size_3', val);
          },
        ),
      ],
    );
  }

  TableRow _buildLineRow({
    required String label,
    required bool show,
    required double size,
    required double sizeMin,
    required double sizeMax,
    required ValueChanged<bool> onShowChanged,
    required ValueChanged<double> onSizeChanged,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return TableRow(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: isDark ? Colors.white10 : Colors.black12,
            width: 0.5,
          ),
        ),
      ),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(
            label,
            style: TextStyle(
              color: isDark ? Colors.white : Colors.black87,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Center(
            child: SizedBox(
              height: 32,
              width: 32,
              child: Checkbox(
                value: show,
                activeColor: const Color(0xFFFF1E1E),
                onChanged: (val) => onShowChanged(val ?? true),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color:
                      isDark
                          ? const Color(0xFF13141F)
                          : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isDark ? Colors.white24 : const Color(0xFFCBD5E1),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Material(
                      color: isDark ? const Color(0xFF2D2F45) : Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () {
                          final newVal = (size - 0.5).clamp(sizeMin, sizeMax);
                          onSizeChanged(newVal);
                        },
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          child: Icon(
                            Icons.remove,
                            color: isDark ? Colors.white : Colors.black87,
                            size: 18,
                          ),
                        ),
                      ),
                    ),
                    Container(
                      constraints: const BoxConstraints(minWidth: 46),
                      alignment: Alignment.center,
                      child: Text(
                        '${size.toStringAsFixed(1)}pt',
                        style: const TextStyle(
                          color: Colors.greenAccent,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Material(
                      color: isDark ? const Color(0xFF2D2F45) : Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () {
                          final newVal = (size + 0.5).clamp(sizeMin, sizeMax);
                          onSizeChanged(newVal);
                        },
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          child: Icon(
                            Icons.add,
                            color: isDark ? Colors.white : Colors.black87,
                            size: 18,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _refreshUsbPrinters() async {
    final list = await UsbPrintService.instance.refreshPrinters();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${list.length}개의 프린터가 검색되었습니다.'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _testPrintUsb() async {
    final usbService = UsbPrintService.instance;
    final modeLabel = usbService.connectionTypeLabel;
    if (usbService.selectedPrinter == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text('테스트 인쇄할 $modeLabel 프린터를 먼저 선택해 주세요.'),
        ),
      );
      return;
    }

    setState(() {
      _isTestingUsb = true;
    });

    try {
      final success = await usbService.printTestLabel(
        widthMm: _selectedWidth,
        heightMm: _selectedHeight,
      );
      if (mounted) {
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: const Color(0xFF10B981),
              content: Text(
                '$modeLabel 프린터(${usbService.selectedPrinter!.name})로 테스트 라벨을 전송했습니다.',
              ),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: Colors.redAccent,
              content: Text('$modeLabel 테스트 인쇄 전송에 실패했습니다. 프린터 연결 및 전원을 확인해 주세요.'),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.redAccent,
            content: Text('테스트 인쇄 오류: $e'),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isTestingUsb = false;
        });
      }
    }
  }

  Widget _buildWindowsPrinterCard(bool isDark) {
    final usbService = UsbPrintService.instance;
    final isConnected =
        usbService.isEnabled && usbService.selectedPrinter != null;
    final modeLabel = usbService.connectionTypeLabel;
    final isBt = usbService.isBluetoothMode;

    return Card(
      color: isDark ? const Color(0xFF1E2030) : Colors.white,
      elevation: 3,
      shadowColor: Colors.black12,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color:
              isDark
                  ? Colors.white.withValues(alpha: 0.18)
                  : const Color(0xFFCBD5E1),
          width: 1.2,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(
                      isBt ? Icons.bluetooth : Icons.usb,
                      color: const Color(0xFF6366F1),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '프린터 연결 설정',
                      style: TextStyle(
                        color: isDark ? Colors.white : Colors.black87,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF6366F1).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: const Color(0xFF6366F1).withValues(alpha: 0.3),
                    ),
                  ),
                  child: Text(
                    'Windows ($modeLabel)',
                    style: const TextStyle(
                      color: Color(0xFF6366F1),
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Connection Type Selector (USB vs Bluetooth)
            Text(
              '연결 방식 선택',
              style: TextStyle(
                color: isDark ? Colors.white70 : Colors.black87,
                fontSize: 12.5,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () async {
                      await usbService.setConnectionType('usb');
                      if (mounted) setState(() {});
                    },
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: !isBt
                            ? const Color(0xFF6366F1).withValues(alpha: 0.18)
                            : (isDark
                                ? const Color(0xFF13141F)
                                : const Color(0xFFF1F5F9)),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: !isBt
                              ? const Color(0xFF6366F1)
                              : (isDark ? Colors.white12 : Colors.black12),
                          width: !isBt ? 2 : 1,
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.usb,
                            size: 18,
                            color: !isBt
                                ? const Color(0xFF6366F1)
                                : (isDark ? Colors.white60 : Colors.black54),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'USB 연결',
                            style: TextStyle(
                              fontWeight:
                                  !isBt ? FontWeight.bold : FontWeight.normal,
                              color: !isBt
                                  ? const Color(0xFF6366F1)
                                  : (isDark ? Colors.white70 : Colors.black87),
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: InkWell(
                    onTap: () async {
                      await usbService.setConnectionType('bluetooth');
                      if (mounted) setState(() {});
                    },
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: isBt
                            ? const Color(0xFF6366F1).withValues(alpha: 0.18)
                            : (isDark
                                ? const Color(0xFF13141F)
                                : const Color(0xFFF1F5F9)),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isBt
                              ? const Color(0xFF6366F1)
                              : (isDark ? Colors.white12 : Colors.black12),
                          width: isBt ? 2 : 1,
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.bluetooth,
                            size: 18,
                            color: isBt
                                ? const Color(0xFF6366F1)
                                : (isDark ? Colors.white60 : Colors.black54),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '블루투스 연결',
                            style: TextStyle(
                              fontWeight:
                                  isBt ? FontWeight.bold : FontWeight.normal,
                              color: isBt
                                  ? const Color(0xFF6366F1)
                                  : (isDark ? Colors.white70 : Colors.black87),
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Bluetooth helper guidance if in Bluetooth mode
            if (isBt) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF6366F1).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: const Color(0xFF6366F1).withValues(alpha: 0.25),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.info_outline,
                          size: 16,
                          color: Color(0xFF6366F1),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '블루투스 프린터 연결 안내',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Windows [설정 > Bluetooth 및 장치]에서 프린터를 먼저 페어링하신 후, 아래 목록에서 선택해 주세요.',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: isDark ? Colors.white70 : Colors.black87,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: () => usbService.openWindowsBluetoothSettings(),
                      icon: const Icon(Icons.settings_bluetooth, size: 16),
                      label: const Text(
                        'Windows Bluetooth 설정 열기',
                        style: TextStyle(fontSize: 11.5),
                      ),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        foregroundColor: const Color(0xFF6366F1),
                        side: const BorderSide(color: Color(0xFF6366F1)),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Switch
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$modeLabel 프린터 직접 인쇄 사용',
                        style: TextStyle(
                          color: isDark ? Colors.white : Colors.black87,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '인쇄 대화상자 없이 선택된 $modeLabel 프린터로 즉시 출력',
                        style: TextStyle(
                          color: isDark ? Colors.white60 : Colors.black54,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: usbService.isEnabled,
                  activeColor: const Color(0xFF6366F1),
                  onChanged: (val) async {
                    await usbService.setEnabled(val);
                    if (mounted) setState(() {});
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Connection status
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '연결 상태:',
                  style: TextStyle(
                    color: isDark ? Colors.white70 : Colors.black87,
                    fontSize: 13,
                  ),
                ),
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color:
                          isConnected
                              ? Colors.greenAccent.withValues(alpha: 0.2)
                              : Colors.amberAccent.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      isConnected
                          ? '연결됨 ($modeLabel: ${usbService.selectedPrinter?.name})'
                          : (usbService.isEnabled
                              ? '프린터를 선택해 주세요'
                              : '사용 안 함 (시스템 인쇄 대화상자 사용)'),
                      style: TextStyle(
                        color:
                            isConnected
                                ? Colors.greenAccent
                                : (isDark
                                    ? Colors.amberAccent
                                    : Colors.orange[800]),
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Dropdown
            if (usbService.printers.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10.0),
                child: Text(
                  usbService.isScanning
                      ? '프린터를 검색하는 중입니다...'
                      : '감지된 프린터가 없습니다. $modeLabel 연결 및 드라이버를 확인해 주세요.',
                  style: TextStyle(
                    color: isDark ? Colors.white60 : Colors.black54,
                    fontSize: 12,
                  ),
                ),
              )
            else
              DropdownButtonFormField<Printer>(
                dropdownColor:
                    isDark ? const Color(0xFF1E2030) : Colors.white,
                value: usbService.selectedPrinter,
                style: TextStyle(
                  color: isDark ? Colors.white : Colors.black87,
                ),
                decoration: InputDecoration(
                  labelText: '$modeLabel 프린터 선택',
                  labelStyle: TextStyle(
                    color: isDark ? Colors.white60 : Colors.black54,
                  ),
                ),
                items:
                    usbService.printers.map((printer) {
                      final isDefaultSuffix = printer.isDefault ? ' [기본]' : '';
                      return DropdownMenuItem<Printer>(
                        value: printer,
                        child: Text(
                          '${printer.name}$isDefaultSuffix',
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    }).toList(),
                onChanged: (val) async {
                  await usbService.setSelectedPrinter(val);
                  if (mounted) setState(() {});
                },
              ),
            const SizedBox(height: 20),

            // Buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: usbService.isScanning ? null : _refreshUsbPrinters,
                    icon: usbService.isScanning
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh),
                    label: Text(
                      usbService.isScanning ? '검색 중...' : '프린터 검색/갱신',
                      overflow: TextOverflow.ellipsis,
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor:
                          isDark ? Colors.white70 : Colors.black87,
                      side: BorderSide(
                        color:
                            isDark
                                ? Colors.white.withValues(alpha: 0.2)
                                : const Color(0xFFCBD5E1),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed:
                        usbService.selectedPrinter == null || _isTestingUsb
                            ? null
                            : _testPrintUsb,
                    icon: Icon(
                      _isTestingUsb ? Icons.hourglass_empty : Icons.print,
                    ),
                    label: Text(
                      _isTestingUsb ? '인쇄 중...' : '테스트 인쇄',
                      overflow: TextOverflow.ellipsis,
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6366F1),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color:
                    isDark
                        ? Colors.white.withValues(alpha: 0.04)
                        : Colors.black.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color:
                      isDark
                          ? Colors.white.withValues(alpha: 0.1)
                          : Colors.black.withValues(alpha: 0.1),
                ),
              ),
              child: Text(
                isBt
                    ? '블루투스로 연결된 무선 라벨 프린터를 선택하시면, [라벨 인쇄] 탭에서 대화상자 없이 설정된 규격으로 무선 즉시 인쇄됩니다.'
                    : 'USB 케이블로 연결된 라벨 프린터(TSC DA220 등)를 선택하시면, [라벨 인쇄] 탭에서 대화상자 없이 설정된 규격으로 즉시 인쇄됩니다.',
                style: TextStyle(
                  color: isDark ? Colors.white70 : Colors.black87,
                  fontSize: 11.5,
                  height: 1.45,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBluetoothPrinterCard(bool isDark) {
    return Card(
      color: isDark ? const Color(0xFF1E2030) : Colors.white,
      elevation: 3,
      shadowColor: Colors.black12,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color:
              isDark
                  ? Colors.white.withValues(alpha: 0.18)
                  : const Color(0xFFCBD5E1),
          width: 1.2,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.bluetooth, color: Color(0xFF6366F1)),
                const SizedBox(width: 8),
                Text(
                  '블루투스 프린터 설정',
                  style: TextStyle(
                    color: isDark ? Colors.white : Colors.black87,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            if (!_isBluetoothSupported) ...[
              const Text(
                '블루투스가 활성화되지 않았거나 사용할 수 없습니다. 설정에서 블루투스를 켜 주세요.',
                style: TextStyle(color: Colors.redAccent, fontSize: 12),
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: _initBluetooth,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6366F1),
                  foregroundColor: Colors.white,
                ),
                child: const Text('블루투스 재시도'),
              ),
            ] else ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '프린터 자동 연결',
                          style: TextStyle(
                            color: isDark ? Colors.white : Colors.black87,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '앱 실행 및 인쇄 시 저장된 프린터로 자동 연결',
                          style: TextStyle(
                            color: isDark ? Colors.white60 : Colors.black54,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: _autoConnect,
                    activeColor: const Color(0xFF6366F1),
                    onChanged: (val) async {
                      setState(() {
                        _autoConnect = val;
                      });
                      await BluetoothPrintService.instance
                          .setAutoConnectEnabled(val);
                      if (val) {
                        _initBluetooth();
                      }
                    },
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '연결 상태:',
                    style: TextStyle(
                      color: isDark ? Colors.white70 : Colors.black87,
                      fontSize: 13,
                    ),
                  ),
                  Flexible(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color:
                            BluetoothPrintService.instance.isConnected
                                ? Colors.greenAccent.withValues(alpha: 0.2)
                                : Colors.redAccent.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        BluetoothPrintService.instance.isConnected
                            ? '연결됨 (${BluetoothPrintService.instance.connectedDevice?.name})'
                            : '연결 안 됨',
                        style: TextStyle(
                          color:
                              BluetoothPrintService.instance.isConnected
                                  ? Colors.greenAccent
                                  : Colors.redAccent,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (_devices.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10.0),
                  child: Text(
                    '페어링된 블루투스 기기가 없습니다. 스마트폰 설정에서 프린터를 페어링해 주세요.',
                    style: TextStyle(
                      color: isDark ? Colors.white60 : Colors.black54,
                      fontSize: 12,
                    ),
                  ),
                )
              else
                DropdownButtonFormField<BluetoothDevice>(
                  dropdownColor:
                      isDark ? const Color(0xFF1E2030) : Colors.white,
                  value: _selectedDevice,
                  style: TextStyle(
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                  decoration: InputDecoration(
                    labelText: '프린터 선택',
                    labelStyle: TextStyle(
                      color: isDark ? Colors.white60 : Colors.black54,
                    ),
                  ),
                  items:
                      _devices.map((device) {
                        return DropdownMenuItem<BluetoothDevice>(
                          value: device,
                          child: Text(
                            device.name ?? '알 수 없는 기기',
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      }).toList(),
                  onChanged: (val) {
                    setState(() {
                      _selectedDevice = val;
                    });
                  },
                ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _loadBluetoothDevices,
                      icon: const Icon(Icons.refresh),
                      label: const Text(
                        '기기 갱신',
                        overflow: TextOverflow.ellipsis,
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor:
                            isDark ? Colors.white70 : Colors.black87,
                        side: BorderSide(
                          color:
                              isDark
                                  ? Colors.white.withValues(alpha: 0.2)
                                  : const Color(0xFFCBD5E1),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed:
                          _selectedDevice == null || _isConnecting
                              ? null
                              : _toggleBluetoothConnection,
                      icon: Icon(
                        _isConnecting
                            ? Icons.hourglass_empty
                            : (BluetoothPrintService.instance.isConnected
                                ? Icons.bluetooth_disabled
                                : Icons.bluetooth_connected),
                      ),
                      label: Text(
                        BluetoothPrintService.instance.isConnected
                            ? '연결 해제'
                            : '연결하기',
                        overflow: TextOverflow.ellipsis,
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                            BluetoothPrintService.instance.isConnected
                                ? Colors.redAccent
                                : const Color(0xFF6366F1),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDesktopInfoCard(bool isDark) {
    return Card(
      color: isDark ? const Color(0xFF1E2030) : Colors.white,
      elevation: 3,
      shadowColor: Colors.black12,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color:
              isDark
                  ? Colors.white.withValues(alpha: 0.18)
                  : const Color(0xFFCBD5E1),
          width: 1.2,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Text(
          '라벨 프린터 인쇄는 안드로이드(블루투스 직결) 및 윈도우(USB 프린터 직결) 환경을 지원합니다.',
          style: TextStyle(
            color: isDark ? Colors.white70 : Colors.black87,
            fontSize: 12,
            height: 1.5,
          ),
        ),
      ),
    );
  }

  Future<void> _applyLabelSize(double width, double height) async {
    final clampedW = width.clamp(20.0, 150.0);
    final clampedH = height.clamp(10.0, 150.0);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('label_width', clampedW);
    await prefs.setDouble('label_height', clampedH);

    setState(() {
      _selectedWidth = clampedW;
      _selectedHeight = clampedH;
      _widthController.text = clampedW.toStringAsFixed(
        clampedW.truncateToDouble() == clampedW ? 0 : 1,
      );
      _heightController.text = clampedH.toStringAsFixed(
        clampedH.truncateToDouble() == clampedH ? 0 : 1,
      );
    });

    layoutSettingsRevision.value++;

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '라벨 규격이 ${clampedW.toStringAsFixed(clampedW.truncateToDouble() == clampedW ? 0 : 1)}mm × ${clampedH.toStringAsFixed(clampedH.truncateToDouble() == clampedH ? 0 : 1)}mm (으)로 변경되었습니다.',
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _onCustomSizeSubmitted() {
    final double? w = double.tryParse(_widthController.text.trim());
    final double? h = double.tryParse(_heightController.text.trim());
    if (w == null || h == null || w <= 0 || h <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text('올바른 가로, 세로 크기(mm)를 입력해 주세요. (예: 55, 20)'),
        ),
      );
      return;
    }
    _applyLabelSize(w, h);
  }

  Widget _buildSizeChip(double w, double h, String label, bool isDark) {
    final bool isSelected =
        (_selectedWidth - w).abs() < 0.1 && (_selectedHeight - h).abs() < 0.1;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      selectedColor: const Color(0xFF6366F1).withValues(alpha: 0.25),
      backgroundColor:
          isDark ? const Color(0xFF13141F) : const Color(0xFFF1F5F9),
      labelStyle: TextStyle(
        color:
            isSelected
                ? const Color(0xFF6366F1)
                : (isDark ? Colors.white70 : Colors.black87),
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        fontSize: 12,
      ),
      side: BorderSide(
        color:
            isSelected
                ? const Color(0xFF6366F1)
                : (isDark ? Colors.white12 : Colors.black12),
        width: isSelected ? 1.5 : 1.0,
      ),
      onSelected: (selected) {
        if (selected) {
          _applyLabelSize(w, h);
        }
      },
    );
  }
}
