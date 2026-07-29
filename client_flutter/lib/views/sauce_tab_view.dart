import 'dart:async';
import 'package:flutter/material.dart';
import '../models/sauce_item.dart';
import '../services/bluetooth_service.dart';
import '../services/database_service.dart';

class SauceTabView extends StatefulWidget {
  const SauceTabView({super.key});

  @override
  State<SauceTabView> createState() => _SauceTabViewState();
}

class _SauceTabViewState extends State<SauceTabView> {
  final TextEditingController _idInputController = TextEditingController();
  List<SauceItem> _sauceList = [];
  String? _selectedSauceId;
  DateTime _systemTime = DateTime.now();
  Timer? _timer;
  int _sequence = 1;

  // Selected label preview item
  SauceItem? _lastPrintedSauce;
  DateTime? _lastPrintedRawOutTime;

  @override
  void initState() {
    super.initState();
    _loadSauceList();
    _systemTime = DateTime.now();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {
          _systemTime = DateTime.now();
          _checkExpirations();
        });
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _idInputController.dispose();
    super.dispose();
  }

  void _loadSauceList() {
    setState(() {
      _sauceList = List<SauceItem>.from(DatabaseService.instance.sauceItems);
      // Auto sequence generation base
      if (_sauceList.isNotEmpty) {
        _sequence = _sauceList.length + 1;
      }
    });
  }

  void _saveSauceList() {
    DatabaseService.instance.saveSauceItems(_sauceList);
  }

  void _checkExpirations() {
    bool updated = false;
    for (final item in _sauceList) {
      if (item.updateExpirationCheck(_systemTime)) {
        updated = true;
      }
    }
    if (updated) {
      _saveSauceList();
    }
  }

  SauceItem? _getActiveOrSelectedSauce() {
    if (_selectedSauceId != null) {
      final found = _sauceList.where((item) => item.sourceId == _selectedSauceId);
      if (found.isNotEmpty) return found.first;
    }
    final active = _sauceList.where((item) => item.status != 'DISCARD');
    return active.isNotEmpty ? active.first : null;
  }

  void _triggerPrep() {
    String sourceId = _idInputController.text.trim().toUpperCase();
    if (sourceId.isEmpty) {
      final yyyy = _systemTime.year.toString();
      final mm = _systemTime.month.toString().padLeft(2, '0');
      final dd = _systemTime.day.toString().padLeft(2, '0');
      final seqStr = (_sequence++).toString().padLeft(3, '0');
      sourceId = 'S$yyyy$mm$dd-$seqStr';
    }

    if (_sauceList.any((item) => item.sourceId == sourceId)) {
      _showSnackBar('이미 존재하는 식별번호(ID)입니다.');
      return;
    }

    final newRecord = SauceItem.createPrep(
      sourceId: sourceId,
      now: DateTime.now(),
    );

    setState(() {
      _sauceList.insert(0, newRecord);
      _selectedSauceId = sourceId;
      _lastPrintedSauce = newRecord;
      _lastPrintedRawOutTime = null;
      _idInputController.clear();
    });

    _saveSauceList();
    _showSnackBar('신규 피자소스 [PREP] 개봉 완료: $sourceId');
  }

  void _triggerIn() {
    final item = _getActiveOrSelectedSauce();
    if (item == null) {
      _showSnackBar('냉장 보관할 소스를 선택하거나 ID를 입력하세요.');
      return;
    }

    if (item.status == 'DISCARD') {
      _showSnackBar('폐기된 소스는 냉장 보관할 수 없습니다.');
      return;
    }
    if (item.status == 'IN') {
      _showSnackBar('이미 냉장 보관 상태(IN)입니다.');
      return;
    }

    final now = DateTime.now();
    setState(() {
      item.triggerIn(now);
      _lastPrintedSauce = item;
      _lastPrintedRawOutTime = null;
    });

    _saveSauceList();
    _showSnackBar('피자소스 [IN] 냉장고 보관 처리 (차감 중지): ${item.sourceId}');
  }

  void _triggerOut() {
    final item = _getActiveOrSelectedSauce();
    if (item == null) {
      _showSnackBar('냉장 출고할 소스를 선택하거나 ID를 입력하세요.');
      return;
    }

    if (item.status == 'DISCARD') {
      _showSnackBar('폐기된 소스는 출고할 수 없습니다.');
      return;
    }
    if (item.status == 'PREP' || item.status == 'OUT') {
      _showSnackBar('이미 실온 사용 상태(PREP/OUT)입니다.');
      return;
    }

    final now = DateTime.now();
    setState(() {
      item.triggerOut(now);
      _lastPrintedSauce = item;
      _lastPrintedRawOutTime = now;
    });

    _saveSauceList();

    final isBefore11 = now.isBefore(DateTime(now.year, now.month, now.day, 11, 0, 0));
    final msg = isBefore11
        ? '피자소스 [OUT] 출고 완료 (오전 11시부터 차감 적용): ${item.sourceId}'
        : '피자소스 [OUT] 실온 출고 처리: ${item.sourceId}';
    _showSnackBar(msg);
  }

  void _deleteSauceItem(String id) {
    setState(() {
      _sauceList.removeWhere((item) => item.sourceId == id);
      if (_selectedSauceId == id) _selectedSauceId = null;
      if (_lastPrintedSauce?.sourceId == id) _lastPrintedSauce = null;
    });
    _saveSauceList();
  }

  void _clearAllSauces() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('피자소스 이력 초기화'),
        content: const Text('등록된 모든 소스 관리 목록을 삭제하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('취소'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () {
              Navigator.pop(ctx);
              setState(() {
                _sauceList.clear();
                _selectedSauceId = null;
                _lastPrintedSauce = null;
              });
              _saveSauceList();
              _showSnackBar('모든 소스 관리 데이터가 초기화되었습니다.');
            },
            child: const Text('초기화', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showSnackBar(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  String _formatDateTimeWithDay(DateTime? dt) {
    if (dt == null) return '-';
    const days = ['일', '월', '화', '수', '목', '금', '토'];
    final dayStr = days[dt.weekday % 7];
    final yyyy = dt.year;
    final mm = dt.month.toString().padLeft(2, '0');
    final dd = dt.day.toString().padLeft(2, '0');
    final hh = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    return '$yyyy-$mm-$dd ($dayStr) $hh:$min';
  }

  String _formatDateTime(DateTime? dt) {
    if (dt == null) return '-';
    final yyyy = dt.year;
    final mm = dt.month.toString().padLeft(2, '0');
    final dd = dt.day.toString().padLeft(2, '0');
    final hh = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    return '$yyyy-$mm-$dd $hh:$min';
  }

  String _formatDuration(double totalMin) {
    if (totalMin <= 0) return '00시간 00분';
    final hrs = (totalMin / 60).floor();
    final mins = (totalMin % 60).floor();
    return '${hrs.toString().padLeft(2, '0')}시간 ${mins.toString().padLeft(2, '0')}분';
  }

  String _formatDurationLabel(double totalMin) {
    if (totalMin <= 0) return '00:00';
    final hrs = (totalMin / 60).floor();
    final mins = (totalMin % 60).floor();
    return '${hrs.toString().padLeft(2, '0')}:${mins.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final activeCount = _sauceList.where((item) => item.status != 'DISCARD').length;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Card with System Clock & Status
              _buildHeaderCard(isDark, activeCount),
              const SizedBox(height: 16),

              // Main Responsive Layout: Control Panel & Printer Side-by-Side
              LayoutBuilder(
                builder: (context, constraints) {
                  if (constraints.maxWidth > 900) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 3,
                          child: Column(
                            children: [
                              _buildActionControlCard(isDark),
                              const SizedBox(height: 16),
                              _buildActiveSauceGridCard(isDark, activeCount),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          flex: 2,
                          child: _buildPrinterSimulatorCard(isDark),
                        ),
                      ],
                    );
                  } else {
                    return Column(
                      children: [
                        _buildActionControlCard(isDark),
                        const SizedBox(height: 16),
                        _buildPrinterSimulatorCard(isDark),
                        const SizedBox(height: 16),
                        _buildActiveSauceGridCard(isDark, activeCount),
                      ],
                    );
                  }
                },
              ),

              const SizedBox(height: 20),

              // Database Viewer Relation Table
              _buildDatabaseViewerCard(isDark),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderCard(bool isDark, int activeCount) {
    final yyyy = _systemTime.year;
    final mm = _systemTime.month.toString().padLeft(2, '0');
    final dd = _systemTime.day.toString().padLeft(2, '0');
    final hh = _systemTime.hour.toString().padLeft(2, '0');
    final min = _systemTime.minute.toString().padLeft(2, '0');
    final sec = _systemTime.second.toString().padLeft(2, '0');

    return Card(
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF6366F1).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.local_pizza, color: Color(0xFF6366F1), size: 28),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text(
                        '피자소스 유효기한 스마트 라벨링',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981).withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          '실시간 KDS',
                          style: TextStyle(color: Color(0xFF10B981), fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '개봉 후 실온 누적 10시간 관리 · 냉장 보관 차감 일시정지 · 11시 고정 차감 룰 적용',
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.white60 : Colors.black54,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E2030) : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: isDark ? Colors.white12 : Colors.black12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.access_time_filled, size: 16, color: Color(0xFF38BDF8)),
                  const SizedBox(width: 6),
                  Text(
                    '$yyyy-$mm-$dd $hh:$min:$sec',
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: Color(0xFF38BDF8),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionControlCard(bool isDark) {
    return Card(
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.qr_code_scanner, size: 20, color: Color(0xFF3B82F6)),
                const SizedBox(width: 8),
                const Text(
                  '소스 ID 바코드 스캔 및 액션 제어',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                if (_selectedSauceId != null)
                  Chip(
                    avatar: const Icon(Icons.check_circle, size: 16, color: Colors.blueAccent),
                    label: Text('선택됨: $_selectedSauceId', style: const TextStyle(fontSize: 12)),
                    onDeleted: () => setState(() => _selectedSauceId = null),
                  ),
              ],
            ),
            const SizedBox(height: 14),

            // Barcode Input Field
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _idInputController,
                    decoration: InputDecoration(
                      hintText: '소스통 ID 입력 (비워두면 자동 발급: 예 S20260729-001)',
                      prefixIcon: const Icon(Icons.barcode_reader),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () => _idInputController.clear(),
                      ),
                    ),
                    onSubmitted: (_) => _triggerPrep(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // 3 Action Buttons (PREP, IN, OUT)
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2563EB),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.new_releases),
                    label: const Text('PREP (최초개봉)', style: TextStyle(fontWeight: FontWeight.bold)),
                    onPressed: _triggerPrep,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFD97706),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.ac_unit),
                    label: const Text('IN (냉장보관)', style: TextStyle(fontWeight: FontWeight.bold)),
                    onPressed: _triggerIn,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF059669),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.outdoor_grill),
                    label: const Text('OUT (실온사용)', style: TextStyle(fontWeight: FontWeight.bold)),
                    onPressed: _triggerOut,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPrinterSimulatorCard(bool isDark) {
    final item = _lastPrintedSauce;

    return Card(
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.print, size: 20, color: Color(0xFF10B981)),
                    SizedBox(width: 8),
                    Text(
                      '가상 감열지 라벨 프린터',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black87,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  icon: const Icon(Icons.bluetooth_searching, size: 16),
                  label: const Text('실물 출력을 위해 BT 프린터 사용'),
                  onPressed: () {
                    if (item == null) {
                      _showSnackBar('출력할 라벨이 없습니다.');
                      return;
                    }
                    _printBluetoothLabel(item);
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Printer slot view
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF0B0F19) : const Color(0xFFE2E8F0),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: isDark ? Colors.white12 : Colors.black12),
              ),
              child: item == null
                  ? Container(
                      padding: const EdgeInsets.symmetric(vertical: 40),
                      alignment: Alignment.center,
                      child: Column(
                        children: [
                          Icon(Icons.receipt_long, size: 40, color: isDark ? Colors.white38 : Colors.black38),
                          const SizedBox(height: 8),
                          Text(
                            '[ 프린터 대기 중 ]\nPREP / IN / OUT 처리 시 감열 라벨 스티커가 출력됩니다.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 13,
                              color: isDark ? Colors.white54 : Colors.black54,
                            ),
                          ),
                        ],
                      ),
                    )
                  : _buildThermalLabelWidget(item, isDark),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildThermalLabelWidget(SauceItem item, bool isDark) {
    final remMin = item.getDynamicRemainingMin(_systemTime);

    String statusBadge = '[PREP]';
    if (item.status == 'IN') statusBadge = '[워크인 IN]';
    if (item.status == 'OUT') statusBadge = '[OUT]';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'PS 피자소스',
                style: TextStyle(color: Colors.black, fontSize: 18, fontWeight: FontWeight.bold),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  statusBadge,
                  style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const Divider(color: Colors.black45, thickness: 1.5, height: 16),
          Text(
            'ID : ${item.sourceId}',
            style: const TextStyle(color: Colors.black87, fontSize: 13, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
          ),
          const SizedBox(height: 4),
          if (item.status == 'PREP') ...[
            Text('Prep : ${_formatDateTimeWithDay(item.lastActionTime)}', style: const TextStyle(color: Colors.black87, fontSize: 13)),
            const SizedBox(height: 2),
            Text('폐기일: ${_formatDateTimeWithDay(item.estDiscardTime)}', style: const TextStyle(color: Colors.red, fontSize: 13, fontWeight: FontWeight.bold)),
          ] else if (item.status == 'IN') ...[
            Text('PREP : ${_formatDateTimeWithDay(item.prepTime)}', style: const TextStyle(color: Colors.black87, fontSize: 13)),
            const SizedBox(height: 2),
            Text('IN   : ${_formatDateTimeWithDay(item.lastActionTime)}', style: const TextStyle(color: Colors.black87, fontSize: 13)),
            const SizedBox(height: 2),
            const Text('※ 냉장 보관 중 (차감 일시정지)', style: TextStyle(color: Colors.blue, fontSize: 12, fontWeight: FontWeight.bold)),
          ] else if (item.status == 'OUT') ...[
            Text('OUT  : ${_formatDateTimeWithDay(_lastPrintedRawOutTime ?? item.lastActionTime)}', style: const TextStyle(color: Colors.black87, fontSize: 13)),
            const SizedBox(height: 2),
            Text('폐기 : ${_formatDateTimeWithDay(item.estDiscardTime)}', style: const TextStyle(color: Colors.red, fontSize: 13, fontWeight: FontWeight.bold)),
          ],
          const SizedBox(height: 4),
          Text(
            '잔여 : 시간 ${_formatDurationLabel(remMin)}',
            style: const TextStyle(color: Colors.black, fontSize: 14, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  void _printBluetoothLabel(SauceItem item) async {
    final remMin = item.getDynamicRemainingMin(_systemTime);
    String statusBadge = item.status;

    final textPayload = '''
================================
     피자소스 유효기한 스티커    
================================
ID      : ${item.sourceId}
상태    : $statusBadge
시작시각: ${_formatDateTime(item.lastActionTime)}
폐기시각: ${_formatDateTime(item.estDiscardTime)}
잔여시간: ${_formatDuration(remMin)}
================================
''';

    try {
      final success = await BluetoothPrintService.instance.printRawBytes(textPayload.codeUnits);
      if (success) {
        _showSnackBar('블루투스 프린터로 피자소스 라벨 전송 완료');
      } else {
        _showSnackBar('프린터 미연결 상태입니다. 가상 라벨을 참조하세요.');
      }
    } catch (e) {
      _showSnackBar('프린터 출력 실패: $e');
    }
  }

  Widget _buildActiveSauceGridCard(bool isDark, int activeCount) {
    return Card(
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  '실시간 메이크라인 소스 현황',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                Chip(
                  label: Text('활성 소스: $activeCount개'),
                  backgroundColor: const Color(0xFF6366F1).withValues(alpha: 0.15),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _sauceList.isEmpty
                ? Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 40),
                    alignment: Alignment.center,
                    child: Text(
                      '현재 관리 중인 피자소스가 없습니다.\nID를 입력하거나 PREP (최초개봉) 버튼을 클릭하여 소스통을 추가하세요.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: isDark ? Colors.white54 : Colors.black54),
                    ),
                  )
                : LayoutBuilder(
                    builder: (context, constraints) {
                      final crossAxisCount = constraints.maxWidth > 800 ? 3 : (constraints.maxWidth > 500 ? 2 : 1);
                      return GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: crossAxisCount,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                          childAspectRatio: 1.65,
                        ),
                        itemCount: _sauceList.length,
                        itemBuilder: (context, index) {
                          final item = _sauceList[index];
                          return _buildSauceCard(item, isDark);
                        },
                      );
                    },
                  ),
          ],
        ),
      ),
    );
  }

  Widget _buildSauceCard(SauceItem item, bool isDark) {
    final isSelected = _selectedSauceId == item.sourceId;
    final remMin = item.getDynamicRemainingMin(_systemTime);
    final pct = item.getProgressPercentage(_systemTime);

    Color statusColor;
    String statusLabel;
    if (item.status == 'PREP') {
      statusColor = const Color(0xFF3B82F6);
      statusLabel = 'PREP (최초개봉)';
    } else if (item.status == 'IN') {
      statusColor = const Color(0xFFF59E0B);
      statusLabel = 'IN (냉장보관)';
    } else if (item.status == 'OUT') {
      statusColor = const Color(0xFF10B981);
      statusLabel = 'OUT (실온사용)';
    } else {
      statusColor = const Color(0xFFEF4444);
      statusLabel = '폐기 (DISCARD)';
    }

    Color progressColor = const Color(0xFF3B82F6);
    if (pct < 15) {
      progressColor = const Color(0xFFEF4444);
    } else if (pct < 45) {
      progressColor = const Color(0xFFF59E0B);
    }
    if (item.status == 'IN') {
      progressColor = Colors.grey;
    }

    return InkWell(
      onTap: () {
        setState(() {
          _selectedSauceId = isSelected ? null : item.sourceId;
          _lastPrintedSauce = item;
        });
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF161826) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? const Color(0xFF6366F1)
                : (isDark ? Colors.white.withValues(alpha: 0.1) : const Color(0xFFCBD5E1)),
            width: isSelected ? 2.5 : 1.2,
          ),
          boxShadow: isSelected
              ? [BoxShadow(color: const Color(0xFF6366F1).withValues(alpha: 0.3), blurRadius: 8)]
              : [const BoxShadow(color: Colors.black12, blurRadius: 4)],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Header Row: Source ID & Status Badge
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    item.sourceId,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, fontFamily: 'monospace'),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    statusLabel,
                    style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),

            // Time Row: Last Action & Estimated Discard Time
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('최종시작', style: TextStyle(fontSize: 11, color: isDark ? Colors.white60 : Colors.black54)),
                    Text(_formatDateTime(item.lastActionTime), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500)),
                  ],
                ),
                const SizedBox(height: 2),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('예상폐기', style: TextStyle(fontSize: 11, color: isDark ? Colors.white60 : Colors.black54)),
                    Text(
                      _formatDateTime(item.estDiscardTime),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: item.status == 'DISCARD' || remMin <= 0 ? Colors.redAccent : null,
                      ),
                    ),
                  ],
                ),
              ],
            ),

            // Progress Bar & Countdown
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: (item.status == 'DISCARD' ? 0.0 : pct / 100.0).clamp(0.0, 1.0),
                    backgroundColor: isDark ? Colors.white10 : Colors.black12,
                    valueColor: AlwaysStoppedAnimation<Color>(progressColor),
                    minHeight: 6,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('잔여 유효시간', style: TextStyle(fontSize: 10, color: isDark ? Colors.white54 : Colors.black54)),
                    Text(
                      item.status == 'IN'
                          ? '차감 중지 (IN)'
                          : (item.status == 'DISCARD' ? '폐기 완료' : _formatDuration(remMin)),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: item.status == 'IN'
                            ? Colors.amber
                            : (item.status == 'DISCARD' ? Colors.redAccent : progressColor),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDatabaseViewerCard(bool isDark) {
    return Card(
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.storage, size: 20, color: Color(0xFF6366F1)),
                    SizedBox(width: 8),
                    Text(
                      '시스템 연동 실시간 Database Viewer (pizza_sauce)',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                if (_sauceList.isNotEmpty)
                  TextButton.icon(
                    style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
                    icon: const Icon(Icons.delete_sweep, size: 18),
                    label: const Text('전체 초기화'),
                    onPressed: _clearAllSauces,
                  ),
              ],
            ),
            const SizedBox(height: 12),

            _sauceList.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Center(child: Text('데이터베이스 기록이 비어있습니다.')),
                  )
                : SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      headingRowColor: WidgetStateProperty.all(
                        isDark ? const Color(0xFF1E2030) : const Color(0xFFF1F5F9),
                      ),
                      columns: const [
                        DataColumn(label: Text('Source_ID', style: TextStyle(fontWeight: FontWeight.bold))),
                        DataColumn(label: Text('Status', style: TextStyle(fontWeight: FontWeight.bold))),
                        DataColumn(label: Text('Total_Valid_Min', style: TextStyle(fontWeight: FontWeight.bold))),
                        DataColumn(label: Text('Accum_Used_Min', style: TextStyle(fontWeight: FontWeight.bold))),
                        DataColumn(label: Text('Rem_Valid_Min', style: TextStyle(fontWeight: FontWeight.bold))),
                        DataColumn(label: Text('Last_Action_Time', style: TextStyle(fontWeight: FontWeight.bold))),
                        DataColumn(label: Text('Est_Discard_Time', style: TextStyle(fontWeight: FontWeight.bold))),
                        DataColumn(label: Text('관리', style: TextStyle(fontWeight: FontWeight.bold))),
                      ],
                      rows: _sauceList.map((item) {
                        final rem = item.getDynamicRemainingMin(_systemTime);
                        return DataRow(
                          selected: _selectedSauceId == item.sourceId,
                          onSelectChanged: (_) {
                            setState(() {
                              _selectedSauceId = item.sourceId;
                              _lastPrintedSauce = item;
                            });
                          },
                          cells: [
                            DataCell(Text(item.sourceId, style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold))),
                            DataCell(
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: (item.status == 'PREP'
                                          ? Colors.blue
                                          : (item.status == 'IN'
                                              ? Colors.amber
                                              : (item.status == 'OUT' ? Colors.green : Colors.red)))
                                      .withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  item.status,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: item.status == 'PREP'
                                        ? Colors.blue
                                        : (item.status == 'IN'
                                            ? Colors.amber
                                            : (item.status == 'OUT' ? Colors.green : Colors.red)),
                                  ),
                                ),
                              ),
                            ),
                            DataCell(Text('${item.totalValidMin}')),
                            DataCell(Text('${item.accumUsedMin.round()}')),
                            DataCell(Text('${rem.round()}')),
                            DataCell(Text(_formatDateTime(item.lastActionTime))),
                            DataCell(Text(_formatDateTime(item.estDiscardTime))),
                            DataCell(
                              IconButton(
                                icon: const Icon(Icons.delete_outline, size: 18, color: Colors.redAccent),
                                onPressed: () => _deleteSauceItem(item.sourceId),
                                tooltip: '삭제',
                              ),
                            ),
                          ],
                        );
                      }).toList(),
                    ),
                  ),
          ],
        ),
      ),
    );
  }
}
