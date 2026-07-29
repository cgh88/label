import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../models/models.dart';
import '../services/database_service.dart';
import '../services/bluetooth_service.dart';
import '../services/layout_events.dart';
import '../services/label_renderer.dart';

class PrintTabView extends StatefulWidget {
  final int activeTabIndex;
  final VoidCallback? onNavigateToSettings;
  const PrintTabView({
    super.key,
    required this.activeTabIndex,
    this.onNavigateToSettings,
  });

  @override
  State<PrintTabView> createState() => _PrintTabViewState();
}

class _PrintTabViewState extends State<PrintTabView> {
  final _searchController = TextEditingController();
  final _staffController = TextEditingController();
  final _qtyController = TextEditingController(text: '1');

  String _selectedCategory = '전체';
  Ingredient? _selectedIngredient;
  String _selectedStorage = '입고';
  bool _isStorageLocked = false;
  String? _lockedStorage;
  DateTime _prepTime = DateTime.now();

  List<Ingredient> _filteredIngredients = [];
  double _labelWidth = 55.0;
  double _labelHeight = 20.0;

  // Layout settings
  bool _showLine1 = true;
  bool _showLine2 = true;
  bool _showLine3 = true;
  bool _showLine4 = true;
  double _fontSize1 = 12.5;
  double _fontSize2 = 12.5;
  double _fontSize3 = 12.5;
  double _fontSize4 = 6.25;
  double _leftPadding = 10.0;
  double _verticalGap = 3.5;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _filterIngredients();
    _searchController.addListener(_onSearchChanged);
    // Reload label layout whenever it changes in the Settings tab, so the
    // preview reflects font/line changes immediately (not only on tab switch).
    layoutSettingsRevision.addListener(_loadSettings);
  }

  @override
  void didUpdateWidget(PrintTabView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.activeTabIndex == 0 && oldWidget.activeTabIndex != 0) {
      _loadSettings();
    }
  }

  @override
  void dispose() {
    _searchDebounceTimer?.cancel();
    layoutSettingsRevision.removeListener(_loadSettings);
    _searchController.dispose();
    _staffController.dispose();
    _qtyController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final staff = prefs.getString('staff_name') ?? '';
    final show1 = prefs.getBool('layout_show_line_1') ?? true;
    final show2 = prefs.getBool('layout_show_line_2') ?? true;
    final show3 = prefs.getBool('layout_show_line_3') ?? true;
    final show4 = prefs.getBool('layout_show_line_4') ?? true;
    final fs1 = prefs.getDouble('layout_font_size_1') ?? 12.5;
    final fs2 = prefs.getDouble('layout_font_size_2') ?? 12.5;
    final fs3 = prefs.getDouble('layout_font_size_3') ?? 12.5;
    final fs4 = prefs.getDouble('layout_font_size_4') ?? 6.25;
    final pad = prefs.getDouble('layout_left_padding') ?? 10.0;
    final gap = prefs.getDouble('layout_vertical_gap') ?? 3.5;

    if (_staffController.text != staff ||
        _showLine1 != show1 ||
        _showLine2 != show2 ||
        _showLine3 != show3 ||
        _showLine4 != show4 ||
        _fontSize1 != fs1 ||
        _fontSize2 != fs2 ||
        _fontSize3 != fs3 ||
        _fontSize4 != fs4 ||
        _leftPadding != pad ||
        _verticalGap != gap) {
      setState(() {
        _staffController.text = staff;
        _labelWidth = 55.0;
        _labelHeight = 20.0;
        _showLine1 = show1;
        _showLine2 = show2;
        _showLine3 = show3;
        _showLine4 = show4;
        _fontSize1 = fs1;
        _fontSize2 = fs2;
        _fontSize3 = fs3;
        _fontSize4 = fs4;
        _leftPadding = pad;
        _verticalGap = gap;
      });
    }
  }


  Timer? _searchDebounceTimer;

  void _onSearchChanged() {
    _searchDebounceTimer?.cancel();
    _searchDebounceTimer = Timer(const Duration(milliseconds: 150), () {
      if (mounted) {
        _filterIngredients();
      }
    });
  }

  static final Map<String, String> _chosungCache = <String, String>{};

  String _getChosung(String str) {
    final cached = _chosungCache[str];
    if (cached != null) return cached;

    const cho = ["ㄱ","ㄲ","ㄴ","ㄷ","ㄸ","ㄹ","ㅁ","ㅂ","ㅃ","ㅅ","ㅆ","ㅇ","ㅈ","ㅉ","ㅊ","ㅋ","ㅌ","ㅍ","ㅎ"];
    final sb = StringBuffer();
    for (var i = 0; i < str.length; i++) {
      final code = str.codeUnitAt(i) - 44032;
      if (code >= 0 && code < 11172) {
        sb.write(cho[(code / 588).floor()]);
      } else {
        sb.write(str[i]);
      }
    }
    final result = sb.toString();
    _chosungCache[str] = result;
    return result;
  }

  void _filterIngredients() {
    final query = _searchController.text.trim().toLowerCase();
    final bool hasQuery = query.isNotEmpty;
    final String queryChosung = hasQuery ? _getChosung(query) : '';

    _filteredIngredients = DatabaseService.instance.ingredients.where((ing) {
      // First filter by category
      if (_selectedCategory != '전체' && ing.category != _selectedCategory) return false;

      if (!hasQuery) return true;

      final name = ing.name.toLowerCase();
      if (name.contains(query)) return true;

      final abbr = ing.abbr.toLowerCase();
      if (abbr.isNotEmpty && abbr.contains(query)) return true;

      final nameChosung = _getChosung(ing.name);
      return nameChosung.contains(queryChosung);
    }).toList();

    // Reset selection if the currently selected ingredient isn't in the filtered list
    if (_selectedIngredient != null && !_filteredIngredients.contains(_selectedIngredient)) {
      if (_selectedCategory != '전체' && _selectedIngredient!.category != _selectedCategory) {
        _selectedIngredient = null;
        _selectedStorage = '입고';
      }
    }

    // Auto select first item if none selected
    if (_selectedIngredient == null && _filteredIngredients.isNotEmpty) {
      _selectIngredient(_filteredIngredients.first, notify: false);
    }

    setState(() {});
  }

  void _selectIngredient(Ingredient ing, {bool notify = true}) {
    _selectedIngredient = ing;
    // Prep time is no longer manually edited; use the current time.
    _prepTime = DateTime.now();

    // Check if the currently locked storage location is supported by this ingredient.
    // If not supported, automatically release the lock.
    if (_isStorageLocked && _lockedStorage != null) {
      final bool isSupported = _lockedStorage == '입고' || ing.storage.containsKey(_lockedStorage);
      if (isSupported) {
        _selectedStorage = _lockedStorage!;
      } else {
        _isStorageLocked = false;
        _lockedStorage = null;
        if (ing.storage.isNotEmpty) {
          _selectedStorage = ing.storage.keys.first;
        } else {
          _selectedStorage = '입고';
        }
      }
    } else {
      if (ing.storage.isNotEmpty) {
        _selectedStorage = ing.storage.keys.first;
      } else {
        _selectedStorage = '입고';
      }
    }
    if (notify) {
      setState(() {});
    }
  }


  DateTime _computeExpiration(Ingredient ing, String storageName) {
    if (storageName == '입고') return _prepTime;

    final limit = ing.storage[storageName];
    if (limit == null) return _prepTime;

    final shelfLifeValue = limit.days;

    if (storageName == '소스보틀') {
      return _prepTime.add(Duration(hours: shelfLifeValue));
    } else if (storageName == '분할') {
      if (shelfLifeValue == 22) {
        return DateTime(_prepTime.year, _prepTime.month, _prepTime.day, 22, 0);
      } else {
        return _prepTime.add(Duration(hours: shelfLifeValue));
      }
    } else {
      return _prepTime.add(Duration(days: shelfLifeValue));
    }
  }

  String _formatDateTime(DateTime dt) {
    final days = ['일', '월', '화', '수', '목', '금', '토'];
    final weekday = days[dt.weekday % 7];
    return DateFormat('yyyy-MM-dd (\'$weekday\') HH:mm').format(dt);
  }

  Future<void> _printLabel() async {
    if (_selectedIngredient == null) return;

    // Check if Bluetooth printer is connected to print via TSPL commands directly
    final bluetoothPrintService = BluetoothPrintService.instance;

    // If not connected, attempt automatic connection first.
    if (!bluetoothPrintService.isConnected) {
      final autoOk = await bluetoothPrintService.autoConnect();
      if (!autoOk) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('블루투스 프린터가 연결되어 있지 않습니다. 설정에서 프린터를 연결해 주세요.'),
            ),
          );
        }
        widget.onNavigateToSettings?.call();
        return;
      }
    }

    if (bluetoothPrintService.isConnected) {
      final qty = int.tryParse(_qtyController.text) ?? 1;
      final storage = _selectedStorage;
      final prepStr = _formatDateTime(_prepTime);
      final expStr = storage != '입고'
          ? _formatDateTime(_computeExpiration(_selectedIngredient!, storage))
          : '';

      final success = await bluetoothPrintService.printTsplLabel(
        width: _labelWidth,
        height: _labelHeight,
        name: _selectedIngredient!.name,
        abbr: _selectedIngredient!.abbr,
        storage: storage,
        prepDate: prepStr,
        expDate: expStr,
        staff: _staffController.text.isEmpty ? '-' : _staffController.text,
        quantity: qty,
        showLine1: _showLine1,
        showLine2: _showLine2,
        showLine3: _showLine3,
        showLine4: _showLine4,
        fontSize1: _fontSize1,
        fontSize2: _fontSize2,
        fontSize3: _fontSize3,
        fontSize4: _fontSize4,
        leftPaddingPercent: _leftPadding,
        verticalGapPt: _verticalGap,
      );

      if (success) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('블루투스 프린터로 $qty장의 라벨을 전송했습니다.')),
          );
        }
        return;
      }
    }
    
    final doc = pw.Document();
    
    // Convert mm to points (1 inch = 25.4 mm = 72 points)
    final double widthPt = _labelWidth * 72 / 25.4;
    final double heightPt = _labelHeight * 72 / 25.4;
    
    final pageFormat = PdfPageFormat(
      widthPt,
      heightPt,
      marginTop: 0,
      marginBottom: 0,
      marginLeft: 0,
      marginRight: 0,
    );

    // Load PDF-compatible Korean fonts from local TTF assets (no CDN dependency)
    // NOTE: Must use TTF format - CFF-based OTF files cause "invalid characters" errors
    pw.Font fontBold;
    try {
      final fontData = await rootBundle.load('fonts/NotoSansKR-VF.ttf');
      fontBold = pw.Font.ttf(fontData);
    } catch (e) {
      debugPrint('Font load failed, using built-in Helvetica: $e');
      fontBold = pw.Font.helveticaBold();
    }
    
    final qty = int.tryParse(_qtyController.text) ?? 1;
    final storage = _selectedStorage;

    for (int i = 0; i < qty; i++) {
      doc.addPage(
        pw.Page(
          pageFormat: pageFormat,
          build: (pw.Context context) {
            final String abbr = _selectedIngredient!.abbr;
            final String name = _selectedIngredient!.name;
            final String staff = _staffController.text.isEmpty ? '-' : _staffController.text;

            // Scale font size based on width
            final double scale = (_labelWidth / 50.0).clamp(0.5, 2.0);
            
            // Map settings to PDF points (12.5 screen font size translates to fontSize scale)
            final double pdfFontSize1 = (_fontSize1 * 9.6 / 12.5 * scale).clamp(5.0, 24.0);
            final double pdfFontSize2 = (_fontSize2 * 9.6 / 12.5 * scale).clamp(5.0, 24.0);
            final double pdfFontSize3 = (_fontSize3 * 9.6 / 12.5 * scale).clamp(5.0, 24.0);
            final double pdfFontSize4 = (_fontSize4 * 9.6 / 12.5 * scale).clamp(3.0, 15.0);

            final double pdfLeftPadding = widthPt * (_leftPadding / 100.0);
            final double pdfVerticalGap = _verticalGap * scale * 0.43; // Map spacing proportionally

            final double pdfAvailWidth = widthPt - pdfLeftPadding - 6.0;
            final String storageDisplay = storage;
            final String fullLine1 = '[$storageDisplay] $name${abbr.isNotEmpty ? " ($abbr)" : ""}';
            double estWidth = 0;
            for (final char in fullLine1.runes) {
              estWidth += (char > 128 ? pdfFontSize1 * 0.85 : pdfFontSize1 * 0.55);
            }
            final String line1 = (abbr.isNotEmpty && estWidth > pdfAvailWidth)
                ? '[$storageDisplay] $abbr'
                : fullLine1;
            final String line2 = '준비: ${_formatDateTime(_prepTime)}';
            
            final String line3 = storage == '입고'
                ? ''
                : '폐기: ${_formatDateTime(_computeExpiration(_selectedIngredient!, storage))}';
            final String line4 = '(담당: $staff)';

            return pw.Padding(
              padding: pw.EdgeInsets.only(
                left: pdfLeftPadding,
                right: 6.0,
                top: 2.0,
                bottom: 2.0,
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                mainAxisAlignment: pw.MainAxisAlignment.center,
                children: [
                  if (_showLine1) ...[
                    pw.Text(line1,
                      style: pw.TextStyle(font: fontBold, fontSize: pdfFontSize1, color: PdfColors.black),
                      maxLines: 1,
                      overflow: pw.TextOverflow.clip,
                    ),
                  ],
                  if (_showLine1 && (_showLine2 || _showLine3 || _showLine4))
                    pw.SizedBox(height: pdfVerticalGap),
                  if (_showLine2) ...[
                    pw.Text(line2,
                      style: pw.TextStyle(font: fontBold, fontSize: pdfFontSize2, color: PdfColors.black),
                      maxLines: 1,
                      overflow: pw.TextOverflow.clip,
                    ),
                  ],
                  if (_showLine2 && (_showLine3 || _showLine4))
                    pw.SizedBox(height: pdfVerticalGap),
                  if (_showLine3) ...[
                    pw.Text(line3,
                      style: pw.TextStyle(font: fontBold, fontSize: pdfFontSize3, color: PdfColors.black),
                      maxLines: 1,
                      overflow: pw.TextOverflow.clip,
                    ),
                  ],
                  if (_showLine3 && _showLine4)
                    pw.SizedBox(height: pdfVerticalGap),
                  if (_showLine4) ...[
                    pw.Text(line4,
                      style: pw.TextStyle(font: fontBold, fontSize: pdfFontSize4, color: PdfColors.black),
                      maxLines: 1,
                      overflow: pw.TextOverflow.clip,
                    ),
                  ],
                ],
              ),
            );
          },
        ),
      );
    }

    try {
      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => doc.save(),
        format: pageFormat,
        name: 'label_${_selectedIngredient!.name}_$storage',
      );
    } catch (e) {
      debugPrint('Printing error: $e');
      if (mounted) {
        final String errMsg = e.toString();
        if (errMsg.contains('MissingPluginException')) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              backgroundColor: Colors.redAccent,
              duration: Duration(seconds: 7),
              content: Text('인쇄 플러그인이 로드되지 않았습니다. 새 패키지가 설치된 후 Hot Restart만 하셨다면, 터미널/에디터에서 실행 중인 앱을 완전히 종료(Stop)하고 처음부터 다시 실행(Run)해 주세요.'),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: Colors.redAccent,
              content: Text('인쇄를 시작하는 도중 오류가 발생했습니다: $e'),
            ),
          );
        }
      }
    }
  }

  Color _getCategoryColor(String category) {
    switch (category) {
      case '도우': return const Color(0xFF3B82F6);
      case '미트': return const Color(0xFFEF4444);
      case '야채': return const Color(0xFF10B981);
      case '치즈': return const Color(0xFFF59E0B);
      case '소스': return const Color(0xFF8B5CF6);
      case '캔': return const Color(0xFF06B6D4);
      default: return const Color(0xFF64748B);
    }
  }

  @override
  Widget build(BuildContext context) {
    final categoriesList = DatabaseService.instance.categories;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Row(
        children: [
          Expanded(
            flex: 3,
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _searchController,
                    style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                    decoration: InputDecoration(
                      hintText: '재료명 또는 약어 초성 입력...',
                      hintStyle: TextStyle(color: isDark ? Colors.white.withValues(alpha: 0.4) : Colors.black.withValues(alpha: 0.4)),
                      prefixIcon: const Icon(Icons.search, color: Color(0xFF6366F1)),
                      filled: true,
                      fillColor: isDark ? const Color(0xFF13141F) : const Color(0xFFFFFFFF),
                      contentPadding: const EdgeInsets.symmetric(vertical: 14.0),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.08)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: Color(0xFF6366F1), width: 2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  SizedBox(
                    height: 46,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: categoriesList.length + 1,
                      itemBuilder: (context, index) {
                        final cat = index == 0
                            ? AppCategory(id: 0, name: '전체', emoji: '🔍', sortOrder: 0)
                            : categoriesList[index - 1];
                        final isSelected = cat.name == _selectedCategory;
                        return Padding(
                          padding: const EdgeInsets.only(right: 8.0),
                          child: InkWell(
                            onTap: () {
                              _selectedCategory = cat.name;
                              _filterIngredients();
                            },
                            borderRadius: BorderRadius.circular(10),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                              decoration: BoxDecoration(
                                gradient: isSelected
                                    ? const LinearGradient(
                                        colors: [Color(0xFF6366F1), Color(0xFFA855F7)],
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                      )
                                    : null,
                                color: isSelected
                                    ? null
                                    : (isDark ? const Color(0xFF1E2030) : Colors.white),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: isSelected
                                      ? Colors.transparent
                                      : (isDark ? Colors.white.withValues(alpha: 0.2) : const Color(0xFFCBD5E1)),
                                  width: isSelected ? 0 : 1.2,
                                ),
                                boxShadow: isSelected
                                    ? [
                                        BoxShadow(
                                          color: const Color(0xFF6366F1).withValues(alpha: 0.35),
                                          blurRadius: 8,
                                          offset: const Offset(0, 2),
                                        )
                                      ]
                                    : [
                                        BoxShadow(
                                          color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
                                          blurRadius: 4,
                                          offset: const Offset(0, 2),
                                        )
                                      ],
                              ),
                              child: Center(
                                child: Text(
                                  '${cat.emoji} ${cat.name}',
                                  style: TextStyle(
                                    color: isSelected
                                        ? Colors.white
                                        : (isDark ? Colors.white : const Color(0xFF1E293B)),
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 16),

                  Expanded(
                    child: _filteredIngredients.isEmpty
                        ? Center(
                            child: Text(
                              '해당하는 재료가 없습니다.',
                              style: TextStyle(color: isDark ? Colors.white.withValues(alpha: 0.4) : Colors.black.withValues(alpha: 0.4), fontSize: 16, fontWeight: FontWeight.w600),
                            ),
                          )
                        : GridView.builder(
                            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 165,
                              mainAxisExtent: 110,
                              crossAxisSpacing: 12,
                              mainAxisSpacing: 12,
                            ),
                            itemCount: _filteredIngredients.length,
                            itemBuilder: (context, index) {
                              final ing = _filteredIngredients[index];
                              final isSelected = _selectedIngredient == ing;
                              final catColor = _getCategoryColor(ing.category);
                              
                              return InkWell(
                                onTap: () => _selectIngredient(ing),
                                borderRadius: BorderRadius.circular(12),
                                child: Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? (isDark ? const Color(0xFF6366F1).withValues(alpha: 0.22) : const Color(0xFFEEF2FF))
                                        : (isDark ? const Color(0xFF1E2030) : Colors.white),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: isSelected
                                          ? (isDark ? const Color(0xFF818CF8) : const Color(0xFF4F46E5))
                                          : catColor.withValues(alpha: isDark ? 0.55 : 0.75),
                                      width: isSelected ? 2.5 : 1.6,
                                    ),
                                    boxShadow: isSelected
                                        ? [
                                            BoxShadow(
                                              color: const Color(0xFF6366F1).withValues(alpha: isDark ? 0.4 : 0.3),
                                              blurRadius: 10,
                                              offset: const Offset(0, 3),
                                            )
                                          ]
                                        : [
                                            BoxShadow(
                                              color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.05),
                                              blurRadius: 5,
                                              offset: const Offset(0, 2),
                                            )
                                          ],
                                  ),
                                  child: Stack(
                                    children: [
                                      Positioned(
                                        top: 0,
                                        left: 0,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: catColor,
                                            borderRadius: BorderRadius.circular(5),
                                          ),
                                          child: Text(
                                            ing.category,
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ),
                                      if (ing.abbr.isNotEmpty)
                                        Positioned(
                                          top: 0,
                                          right: 0,
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
                                            decoration: BoxDecoration(
                                              color: isDark ? Colors.white.withValues(alpha: 0.15) : const Color(0xFFE2E8F0),
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              ing.abbr,
                                              style: TextStyle(
                                                color: isDark ? Colors.white : const Color(0xFF1E293B),
                                                fontSize: 11,
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                          ),
                                        ),
                                      Positioned.fill(
                                        child: Align(
                                          alignment: Alignment.bottomCenter,
                                          child: Padding(
                                            padding: const EdgeInsets.only(top: 26.0),
                                            child: Text(
                                              ing.name,
                                              style: TextStyle(
                                                color: isDark ? Colors.white : Colors.black87,
                                                fontSize: 14,
                                                fontWeight: FontWeight.bold,
                                                height: 1.25,
                                              ),
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              textAlign: TextAlign.center,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),

          Container(width: 1, color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.08)),

          Expanded(
            flex: 2,
            child: _selectedIngredient == null
                ? Center(
                    child: Text(
                      '인쇄할 재료를 선택해 주세요.',
                      style: TextStyle(color: isDark ? Colors.white.withValues(alpha: 0.4) : Colors.black.withValues(alpha: 0.4), fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                  )
                : Column(
                    children: [
                      Expanded(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(24.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                '보관위치',
                                style: TextStyle(
                                  color: isDark ? Colors.white : Colors.black,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Builder(
                                builder: (context) {
                                  final Set<String> storageKeys = {
                                    ..._selectedIngredient!.storage.keys,
                                    '입고',
                                  };
                                  if (_isStorageLocked && _lockedStorage != null) {
                                    storageKeys.add(_lockedStorage!);
                                  }
                                  return Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: storageKeys
                                        .map((loc) => _buildStorageButton(loc, isDark))
                                        .toList(),
                                  );
                                },
                              ),
                              const SizedBox(height: 24),

                              Text(
                                '출력수량',
                                style: TextStyle(
                                  color: isDark ? Colors.white : Colors.black,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                              ),
                              const SizedBox(height: 8),
                              SizedBox(
                                width: 200,
                                child: Row(
                                  children: [
                                    _buildQtyButton(Icons.remove, () => _changeQty(-1), isDark),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: TextField(
                                        controller: _qtyController,
                                        keyboardType: TextInputType.number,
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          color: isDark ? Colors.white : Colors.black87,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                        ),
                                        decoration: InputDecoration(
                                          filled: true,
                                          fillColor: isDark ? const Color(0xFF13141F) : const Color(0xFFFFFFFF),
                                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                          enabledBorder: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(8),
                                            borderSide: BorderSide(color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.08)),
                                          ),
                                          focusedBorder: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(8),
                                            borderSide: const BorderSide(color: Color(0xFF6366F1)),
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    _buildQtyButton(Icons.add, () => _changeQty(1), isDark),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 32),

                              Text(
                                '출력 라벨 프리뷰',
                                style: TextStyle(
                                  color: isDark ? Colors.white : Colors.black,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                              ),
                              const SizedBox(height: 12),
                              GestureDetector(
                                onTap: _showPreviewDialog,
                                child: Container(
                                  padding: const EdgeInsets.all(24),
                                  decoration: BoxDecoration(
                                    color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Column(
                                    children: [
                                      Center(child: _buildLabelPreviewCard(6.4)),
                                      const SizedBox(height: 10),
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(Icons.zoom_in, size: 16, color: isDark ? Colors.white54 : Colors.black45),
                                          const SizedBox(width: 4),
                                          Text(
                                            '탭하여 크게 보기',
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                              color: isDark ? Colors.white54 : Colors.black45,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),
                            ],
                          ),
                        ),
                      ),

                      // Fixed Sticky Bottom Bar with Print Button
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF0F111A) : Colors.white,
                          border: Border(
                            top: BorderSide(
                              color: isDark ? Colors.white.withValues(alpha: 0.12) : const Color(0xFFCBD5E1),
                              width: 1.2,
                            ),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.08),
                              blurRadius: 10,
                              offset: const Offset(0, -3),
                            ),
                          ],
                        ),
                        child: SafeArea(
                          top: false,
                          child: ElevatedButton(
                            onPressed: _printLabel,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFFF1E1E),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              elevation: 4,
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.print, color: Colors.white, size: 26),
                                const SizedBox(width: 12),
                                Flexible(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _selectedIngredient!.name,
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      Text(
                                        '라벨 출력하기 (${int.tryParse(_qtyController.text) ?? 1}장)',
                                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  // Adjust the print quantity via the +/- buttons while keeping direct entry.
  void _changeQty(int delta) {
    final int current = int.tryParse(_qtyController.text) ?? 1;
    final int next = (current + delta).clamp(1, 999);
    _qtyController.text = next.toString();
    _qtyController.selection =
        TextSelection.collapsed(offset: _qtyController.text.length);
    setState(() {});
  }

  Widget _buildQtyButton(IconData icon, VoidCallback onTap, bool isDark) {
    return Material(
      color: isDark ? const Color(0xFF2D2F45) : Colors.white,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          width: 44,
          height: 46,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isDark ? Colors.white.withValues(alpha: 0.2) : const Color(0xFFCBD5E1),
              width: 1.2,
            ),
          ),
          child: Icon(icon, color: isDark ? Colors.white : const Color(0xFF1E293B), size: 22),
        ),
      ),
    );
  }

  // Button-style storage-location selector (replaces ChoiceChip so the layout
  // no longer shifts on selection).
  Widget _buildStorageButton(String loc, bool isDark) {
    final bool isSelected = _selectedStorage == loc;
    final bool isLocked = _isStorageLocked && _lockedStorage == loc;

    final Color bgColor;
    if (isLocked) {
      bgColor = const Color(0xFFF59E0B);
    } else if (isSelected) {
      bgColor = const Color(0xFFFF1E1E);
    } else {
      bgColor = isDark ? const Color(0xFF1E2030) : Colors.white;
    }

    return InkWell(
      onTap: () {
        setState(() {
          _selectedStorage = loc;
        });
      },
      onDoubleTap: () {
        setState(() {
          if (_isStorageLocked && _lockedStorage == loc) {
            _isStorageLocked = false;
            _lockedStorage = null;
          } else {
            _isStorageLocked = true;
            _lockedStorage = loc;
            _selectedStorage = loc;
          }
        });
      },
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isLocked
                ? const Color(0xFFFBBF24)
                : (isSelected
                    ? Colors.transparent
                    : (isDark ? Colors.white.withValues(alpha: 0.2) : const Color(0xFFCBD5E1))),
            width: (isLocked || isSelected) ? 0 : 1.2,
          ),
          boxShadow: isLocked
              ? [BoxShadow(color: const Color(0xFFF59E0B).withValues(alpha: 0.45), blurRadius: 8, offset: const Offset(0, 2))]
              : (isSelected
                  ? [BoxShadow(color: const Color(0xFFFF1E1E).withValues(alpha: 0.35), blurRadius: 8, offset: const Offset(0, 2))]
                  : [BoxShadow(color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04), blurRadius: 4, offset: const Offset(0, 2))]),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isLocked) ...[
              const Icon(Icons.lock, size: 15, color: Colors.white),
              const SizedBox(width: 5),
            ],
            Text(
              loc,
              style: TextStyle(
                color: (isSelected || isLocked)
                    ? Colors.white
                    : (isDark ? Colors.white : const Color(0xFF1E293B)),
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Renders the white label preview at a given pixel-per-mm scale, reused for
  // both the inline preview (6.4) and the enlarged popup (16.0).
  // Builds the visible label lines (with their pt font sizes) shared by the
  // preview and the print bitmap.
  List<LabelLine> _buildLabelLines() {
    final ing = _selectedIngredient!;
    final List<LabelLine> lines = [];
    if (_showLine1) {
      final String storageDisplay = _selectedStorage;
      final String line1Text = '[$storageDisplay] ${ing.name}${ing.abbr.isNotEmpty ? " (${ing.abbr})" : ""}';
      final String? fallbackText = ing.abbr.isNotEmpty ? '[$storageDisplay] ${ing.abbr}' : null;
      lines.add(LabelLine(
        line1Text,
        _fontSize1,
        fallbackText: fallbackText,
      ));
    }
    if (_showLine2) {
      lines.add(LabelLine('준비: ${_formatDateTime(_prepTime)}', _fontSize2));
    }
    if (_showLine3) {
      lines.add(LabelLine(
        _selectedStorage == '입고' ? '' : '폐기: ${_formatDateTime(_computeExpiration(ing, _selectedStorage))}',
        _fontSize3,
      ));
    }
    if (_showLine4) {
      lines.add(LabelLine('(담당: ${_staffController.text.isEmpty ? '-' : _staffController.text})', _fontSize4));
    }
    return lines;
  }

  Widget _buildLabelPreviewCard(double pxPerMm) {
    return Container(
      width: _labelWidth * pxPerMm,
      height: _labelHeight * pxPerMm,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFF94A3B8), width: 1),
        borderRadius: BorderRadius.circular(4),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 15, offset: Offset(0, 4))],
      ),
      // Paints with the exact same renderer used for the printed bitmap, so the
      // preview matches the physical label 1:1.
      child: CustomPaint(
        size: Size(_labelWidth * pxPerMm, _labelHeight * pxPerMm),
        painter: _LabelPainter(
          lines: _buildLabelLines(),
          widthMm: _labelWidth,
          heightMm: _labelHeight,
          leftPaddingPercent: _leftPadding,
          verticalGapPt: _verticalGap,
          pxPerMm: pxPerMm,
        ),
      ),
    );
  }

  void _showPreviewDialog() {
    if (_selectedIngredient == null) return;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final Size screen = MediaQuery.of(context).size;
    showDialog(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
                borderRadius: BorderRadius.circular(16),
              ),
              // Keep the exact 55:20 label ratio while scaling to fit the screen.
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: screen.width * 0.9 - 88,
                  maxHeight: screen.height * 0.55,
                ),
                child: FittedBox(
                  fit: BoxFit.contain,
                  child: _buildLabelPreviewCard(16.0),
                ),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () => Navigator.of(dialogContext).pop(),
              icon: const Icon(Icons.close, color: Colors.white),
              label: const Text('닫기', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF1E1E),
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LabelPainter extends CustomPainter {
  final List<LabelLine> lines;
  final double widthMm;
  final double heightMm;
  final double leftPaddingPercent;
  final double verticalGapPt;
  final double pxPerMm;

  _LabelPainter({
    required this.lines,
    required this.widthMm,
    required this.heightMm,
    required this.leftPaddingPercent,
    required this.verticalGapPt,
    required this.pxPerMm,
  });

  @override
  void paint(Canvas canvas, Size size) {
    paintLabel(
      canvas,
      widthMm: widthMm,
      heightMm: heightMm,
      lines: lines,
      leftPaddingPercent: leftPaddingPercent,
      verticalGapPt: verticalGapPt,
      pxPerMm: pxPerMm,
      fillBackground: false, // the Container already provides the white background
    );
  }

  @override
  bool shouldRepaint(covariant _LabelPainter oldDelegate) {
    if (oldDelegate.lines.length != lines.length) return true;
    for (int i = 0; i < lines.length; i++) {
      if (oldDelegate.lines[i].text != lines[i].text ||
          oldDelegate.lines[i].sizePt != lines[i].sizePt ||
          oldDelegate.lines[i].fallbackText != lines[i].fallbackText) {
        return true;
      }
    }
    return oldDelegate.widthMm != widthMm ||
        oldDelegate.heightMm != heightMm ||
        oldDelegate.leftPaddingPercent != leftPaddingPercent ||
        oldDelegate.verticalGapPt != verticalGapPt ||
        oldDelegate.pxPerMm != pxPerMm;
  }
}

class DashedDivider extends StatelessWidget {
  const DashedDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(double.infinity, 1),
      painter: DashedLinePainter(),
    );
  }
}

class DashedLinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    double dashWidth = 4, dashSpace = 3, startX = 0;
    final paint = Paint()
      ..color = const Color(0xFFCBD5E1)
      ..strokeWidth = 1;
    while (startX < size.width) {
      canvas.drawLine(Offset(startX, 0), Offset(startX + dashWidth, 0), paint);
      startX += dashWidth + dashSpace;
    }
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}
