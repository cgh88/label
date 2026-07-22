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

class PrintTabView extends StatefulWidget {
  final int activeTabIndex;
  const PrintTabView({super.key, required this.activeTabIndex});

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
    _searchController.dispose();
    _staffController.dispose();
    _qtyController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _staffController.text = prefs.getString('staff_name') ?? '';
      // Label size is fixed at 55×20mm
      _labelWidth = 55.0;
      _labelHeight = 20.0;

      _showLine1 = prefs.getBool('layout_show_line_1') ?? true;
      _showLine2 = prefs.getBool('layout_show_line_2') ?? true;
      _showLine3 = prefs.getBool('layout_show_line_3') ?? true;
      _showLine4 = prefs.getBool('layout_show_line_4') ?? true;
      _fontSize1 = prefs.getDouble('layout_font_size_1') ?? 12.5;
      _fontSize2 = prefs.getDouble('layout_font_size_2') ?? 12.5;
      _fontSize3 = prefs.getDouble('layout_font_size_3') ?? 12.5;
      _fontSize4 = prefs.getDouble('layout_font_size_4') ?? 6.25;
      _leftPadding = prefs.getDouble('layout_left_padding') ?? 10.0;
      _verticalGap = prefs.getDouble('layout_vertical_gap') ?? 3.5;
    });
  }

  Future<void> _saveStaffName(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('staff_name', name);
  }

  void _onSearchChanged() {
    _filterIngredients();
  }

  String _getChosung(String str) {
    const cho = ["ㄱ","ㄲ","ㄴ","ㄷ","ㄸ","ㄹ","ㅁ","ㅂ","ㅃ","ㅅ","ㅆ","ㅇ","ㅈ","ㅉ","ㅊ","ㅋ","ㅌ","ㅍ","ㅎ"];
    var result = "";
    for (var i = 0; i < str.length; i++) {
      var code = str.codeUnitAt(i) - 44032;
      if (code >= 0 && code < 11172) {
        result += cho[(code / 588).floor()];
      } else {
        result += str[i];
      }
    }
    return result;
  }

  void _filterIngredients() {
    final query = _searchController.text.trim().toLowerCase();
    final queryChosung = _getChosung(query);

    setState(() {
      _filteredIngredients = DatabaseService.instance.ingredients.where((ing) {
        // First filter by category
        if (_selectedCategory != '전체' && ing.category != _selectedCategory) return false;

        if (query.isEmpty) return true;

        final name = ing.name.toLowerCase();
        final nameChosung = _getChosung(ing.name);
        final abbr = ing.abbr.toLowerCase();

        return name.contains(query) ||
            nameChosung.contains(queryChosung) ||
            abbr.contains(query);
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
        _selectIngredient(_filteredIngredients.first);
      }
    });
  }

  void _selectIngredient(Ingredient ing) {
    setState(() {
      _selectedIngredient = ing;
      // Default to first storage location if available, otherwise '입고'
      if (ing.storage.isNotEmpty) {
        _selectedStorage = ing.storage.keys.first;
      } else {
        _selectedStorage = '입고';
      }
    });
  }

  void _adjustTime(int amount, String unit) {
    setState(() {
      if (unit == 'h') {
        _prepTime = _prepTime.add(Duration(hours: amount));
      } else if (unit == 'd') {
        _prepTime = _prepTime.add(Duration(days: amount));
      }
    });
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

  String _formatShortDateTime(DateTime dt) {
    return DateFormat('yy.MM.dd HH:mm').format(dt);
  }

  Future<void> _printLabel() async {
    if (_selectedIngredient == null) return;

    // Check if Bluetooth printer is connected to print via TSPL commands directly
    final bluetoothPrintService = BluetoothPrintService.instance;
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
        leftPaddingPercent: _leftPadding,
        verticalGapPt: _verticalGap,
      );

      if (success) {
        await DatabaseService.instance.addPrintLog(
          ingredientName: _selectedIngredient!.name,
          category: _selectedIngredient!.category,
          abbr: _selectedIngredient!.abbr,
          storageLocation: storage,
          prepDate: prepStr,
          expireDate: expStr,
          staff: _staffController.text.isEmpty ? '-' : _staffController.text,
          quantity: qty,
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('블루투스 프린터로 ${qty}장의 라벨을 전송했습니다.')),
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
    pw.Font font;
    pw.Font fontBold;
    pw.Font outfitFont;
    try {
      final fontData = await rootBundle.load('fonts/NotoSansKR-VF.ttf');
      final outfitData = await rootBundle.load('fonts/Outfit-Black.ttf');
      font = pw.Font.ttf(fontData);
      fontBold = pw.Font.ttf(fontData);
      outfitFont = pw.Font.ttf(outfitData);
    } catch (e) {
      debugPrint('Font load failed, using built-in Helvetica: $e');
      font = pw.Font.helvetica();
      fontBold = pw.Font.helveticaBold();
      outfitFont = pw.Font.helveticaBold();
    }
    
    final qty = int.tryParse(_qtyController.text) ?? 1;
    final storage = _selectedStorage;
    final String storageDisplay = storage == '입고' ? '입고' : '$storage 보관';
    final String prepLabel = storage == '입고' ? '입고일시' : '준비일시';
    final bool isTiny = _labelHeight <= 22; // 초소형 라벨 모드 (≤22mm)

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

            final String storageDisplay = storage == '입고' ? '입고' : '$storage 보관';
            final String line1 = '[$storageDisplay] $name${abbr.isNotEmpty ? " ($abbr)" : ""}';
            final String line2 = '준비: ${_formatDateTime(_prepTime)}';
            
            final String expStr = storage == '입고'
                ? '상시 보관'
                : _formatDateTime(_computeExpiration(_selectedIngredient!, storage));
            final String line3 = '폐기: $expStr';
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

      final qty = int.tryParse(_qtyController.text) ?? 1;
      final prepStr = _formatDateTime(_prepTime);
      final expStr = storage != '입고'
          ? _formatDateTime(_computeExpiration(_selectedIngredient!, storage))
          : '';

      await DatabaseService.instance.addPrintLog(
        ingredientName: _selectedIngredient!.name,
        category: _selectedIngredient!.category,
        abbr: _selectedIngredient!.abbr,
        storageLocation: storage,
        prepDate: prepStr,
        expireDate: expStr,
        staff: _staffController.text.isEmpty ? '-' : _staffController.text,
        quantity: qty,
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

    final double scale = (_labelWidth / 50.0).clamp(0.5, 2.0);
    final double screenFontSize1 = _fontSize1 * 1.734 * scale;
    final double screenFontSize2 = _fontSize2 * 1.734 * scale;
    final double screenFontSize3 = _fontSize3 * 1.734 * scale;
    final double screenFontSize4 = _fontSize4 * 1.734 * scale;
    final double screenVerticalGap = _verticalGap * scale * 0.97;

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
                      hintStyle: TextStyle(color: isDark ? Colors.white.withOpacity(0.4) : Colors.black.withOpacity(0.4)),
                      prefixIcon: const Icon(Icons.search, color: Color(0xFF6366F1)),
                      filled: true,
                      fillColor: isDark ? const Color(0xFF13141F) : const Color(0xFFFFFFFF),
                      contentPadding: const EdgeInsets.symmetric(vertical: 14.0),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.08)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: Color(0xFF6366F1), width: 2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  SizedBox(
                    height: 42,
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
                              setState(() {
                                _selectedCategory = cat.name;
                                _filterIngredients();
                              });
                            },
                            borderRadius: BorderRadius.circular(10),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
                                    : (isDark ? Colors.white.withOpacity(0.03) : Colors.black.withOpacity(0.03)),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: isSelected
                                      ? Colors.transparent
                                      : (isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.08)),
                                  width: 1,
                                ),
                              ),
                              child: Center(
                                child: Text(
                                  '${cat.emoji} ${cat.name}',
                                  style: TextStyle(
                                    color: isSelected
                                        ? Colors.white
                                        : (isDark ? Colors.white70 : Colors.black87),
                                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                                    fontSize: 13,
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
                              style: TextStyle(color: isDark ? Colors.white.withOpacity(0.3) : Colors.black.withOpacity(0.3), fontSize: 15),
                            ),
                          )
                        : GridView.builder(
                            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 140,
                              mainAxisExtent: 90,
                              crossAxisSpacing: 10,
                              mainAxisSpacing: 10,
                            ),
                            itemCount: _filteredIngredients.length,
                            itemBuilder: (context, index) {
                              final ing = _filteredIngredients[index];
                              final isSelected = _selectedIngredient == ing;
                              final catColor = _getCategoryColor(ing.category);
                              
                              return InkWell(
                                onTap: () => _selectIngredient(ing),
                                child: Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? const Color(0xFF6366F1).withOpacity(0.08)
                                        : (isDark ? Colors.white.withOpacity(0.02) : Colors.black.withOpacity(0.02)),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: isSelected
                                          ? const Color(0xFF6366F1)
                                          : (isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.08)),
                                      width: isSelected ? 1.5 : 1.0,
                                    ),
                                    boxShadow: isSelected
                                        ? [
                                            BoxShadow(
                                              color: const Color(0xFF6366F1).withOpacity(0.25),
                                              blurRadius: 10,
                                            )
                                          ]
                                        : null,
                                  ),
                                  child: Stack(
                                    children: [
                                      Positioned(
                                        top: 0,
                                        left: 0,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                          decoration: BoxDecoration(
                                            color: catColor.withOpacity(0.15),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            ing.category,
                                            style: TextStyle(
                                              color: catColor,
                                              fontSize: 9,
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
                                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
                                            decoration: BoxDecoration(
                                              color: isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.05),
                                              borderRadius: BorderRadius.circular(3),
                                            ),
                                            child: Text(
                                              ing.abbr,
                                              style: TextStyle(
                                                color: isDark ? Colors.white70 : Colors.black87,
                                                fontSize: 9,
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                          ),
                                        ),
                                      Positioned.fill(
                                        child: Align(
                                          alignment: Alignment.bottomCenter,
                                          child: Padding(
                                            padding: const EdgeInsets.only(top: 20.0),
                                            child: Text(
                                              ing.name,
                                              style: TextStyle(
                                                color: isDark ? Colors.white : Colors.black,
                                                fontSize: 12,
                                                fontWeight: FontWeight.bold,
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

          Container(width: 1, color: isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.08)),

          Expanded(
            flex: 2,
            child: _selectedIngredient == null
                ? Center(
                    child: Text(
                      '인쇄할 재료를 선택해 주세요.',
                      style: TextStyle(color: isDark ? Colors.white.withOpacity(0.3) : Colors.black.withOpacity(0.3), fontSize: 15),
                    ),
                  )
                : SingleChildScrollView(
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
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            ..._selectedIngredient!.storage.keys.map((loc) {
                              final isSelected = _selectedStorage == loc;
                              return ChoiceChip(
                                label: Text(loc),
                                selected: isSelected,
                                onSelected: (val) {
                                  if (val) {
                                    setState(() {
                                      _selectedStorage = loc;
                                    });
                                  }
                                },
                                backgroundColor: isDark ? const Color(0xFF13141F) : const Color(0xFFFFFFFF),
                                selectedColor: const Color(0xFFFF1E1E),
                                labelStyle: TextStyle(
                                  color: isSelected ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  side: BorderSide(
                                    color: isSelected
                                        ? Colors.transparent
                                        : (isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.08)),
                                  ),
                                ),
                              );
                            }),
                            ChoiceChip(
                              label: const Text('입고'),
                              selected: _selectedStorage == '입고',
                              onSelected: (val) {
                                if (val) {
                                  setState(() {
                                    _selectedStorage = '입고';
                                  });
                                }
                              },
                              backgroundColor: isDark ? const Color(0xFF13141F) : const Color(0xFFFFFFFF),
                              selectedColor: const Color(0xFFFF1E1E),
                              labelStyle: TextStyle(
                                color: _selectedStorage == '입고' ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
                                fontWeight: _selectedStorage == '입고' ? FontWeight.bold : FontWeight.normal,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                                side: BorderSide(
                                  color: _selectedStorage == '입고'
                                      ? Colors.transparent
                                      : (isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.08)),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),

                        Text(
                          '준비일시 설정',
                          style: TextStyle(
                            color: isDark ? Colors.white : Colors.black,
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                                decoration: BoxDecoration(
                                  color: isDark ? const Color(0xFF13141F) : const Color(0xFFFFFFFF),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.08)),
                                ),
                                child: Text(
                                  _formatDateTime(_prepTime),
                                  style: TextStyle(
                                    color: isDark ? Colors.white : Colors.black87,
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton(
                              onPressed: () async {
                                final date = await showDatePicker(
                                  context: context,
                                  initialDate: _prepTime,
                                  firstDate: DateTime.now().subtract(const Duration(days: 365)),
                                  lastDate: DateTime.now().add(const Duration(days: 365)),
                                );
                                if (date != null) {
                                  final time = await showTimePicker(
                                    context: context,
                                    initialTime: TimeOfDay.fromDateTime(_prepTime),
                                  );
                                  if (time != null) {
                                    setState(() {
                                      _prepTime = DateTime(
                                        date.year,
                                        date.month,
                                        date.day,
                                        time.hour,
                                        time.minute,
                                      );
                                    });
                                  }
                                }
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFFF1E1E),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              child: const Icon(Icons.calendar_month, color: Colors.white),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(child: _buildTimeAdjustButton('-1일', () => setState(() => _prepTime = _prepTime.subtract(const Duration(days: 1))))),
                            const SizedBox(width: 4),
                            Expanded(child: _buildTimeAdjustButton('+1일', () => setState(() => _prepTime = _prepTime.add(const Duration(days: 1))))),
                            const SizedBox(width: 4),
                            Expanded(child: _buildTimeAdjustButton('-1시간', () => setState(() => _prepTime = _prepTime.subtract(const Duration(hours: 1))))),
                            const SizedBox(width: 4),
                            Expanded(child: _buildTimeAdjustButton('+1시간', () => setState(() => _prepTime = _prepTime.add(const Duration(hours: 1))))),
                            const SizedBox(width: 4),
                            Expanded(child: _buildTimeAdjustButton('현재', () => setState(() => _prepTime = DateTime.now()))),
                          ],
                        ),
                        const SizedBox(height: 24),

                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '담당자',
                                    style: TextStyle(
                                      color: isDark ? Colors.white : Colors.black,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  TextField(
                                    controller: _staffController,
                                    style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                                    decoration: InputDecoration(
                                      filled: true,
                                      fillColor: isDark ? const Color(0xFF13141F) : const Color(0xFFFFFFFF),
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                        borderSide: BorderSide(color: isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.08)),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                        borderSide: const BorderSide(color: Color(0xFF6366F1)),
                                      ),
                                    ),
                                    onChanged: _saveStaffName,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 16),
                            SizedBox(
                              width: 100,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '출력수량',
                                    style: TextStyle(
                                      color: isDark ? Colors.white : Colors.black,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  TextField(
                                    controller: _qtyController,
                                    keyboardType: TextInputType.number,
                                    style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                                    decoration: InputDecoration(
                                      filled: true,
                                      fillColor: isDark ? const Color(0xFF13141F) : const Color(0xFFFFFFFF),
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                        borderSide: BorderSide(color: isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.08)),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                        borderSide: const BorderSide(color: Color(0xFF6366F1)),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
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
                        Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Center(
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              width: _labelWidth * 6.4,
                              height: _labelHeight * 6.4,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 0.0,
                                vertical: 4.5,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                border: Border.all(color: const Color(0xFF94A3B8), width: 1),
                                borderRadius: BorderRadius.circular(4),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Colors.black12,
                                    blurRadius: 15,
                                    offset: Offset(0, 4),
                                  )
                                ],
                              ),
                              child: Padding(
                                padding: EdgeInsets.only(
                                  left: _labelWidth * (_leftPadding / 100.0) * 6.4,
                                  right: 13.5,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    if (_showLine1) ...[
                                      Text(
                                        '[${_selectedStorage == '입고' ? '입고' : '$_selectedStorage 보관'}] ${_selectedIngredient!.name}${_selectedIngredient!.abbr.isNotEmpty ? " (${_selectedIngredient!.abbr})" : ""}',
                                        style: TextStyle(
                                          color: Colors.black,
                                          fontSize: screenFontSize1,
                                          fontWeight: FontWeight.bold,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                    if (_showLine1 && (_showLine2 || _showLine3 || _showLine4))
                                      SizedBox(height: screenVerticalGap),
                                    if (_showLine2) ...[
                                      Text(
                                        '준비: ${_formatDateTime(_prepTime)}',
                                        style: TextStyle(
                                          color: Colors.black,
                                          fontSize: screenFontSize2,
                                          fontWeight: FontWeight.bold,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                    if (_showLine2 && (_showLine3 || _showLine4))
                                      SizedBox(height: screenVerticalGap),
                                    if (_showLine3) ...[
                                      Text(
                                        '폐기: ${_selectedStorage == '입고' ? '상시 보관' : _formatDateTime(_computeExpiration(_selectedIngredient!, _selectedStorage))}',
                                        style: TextStyle(
                                          color: Colors.black,
                                          fontSize: screenFontSize3,
                                          fontWeight: FontWeight.bold,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                    if (_showLine3 && _showLine4)
                                      SizedBox(height: screenVerticalGap),
                                    if (_showLine4) ...[
                                      Text(
                                        '(담당: ${_staffController.text.isEmpty ? '-' : _staffController.text})',
                                        style: TextStyle(
                                          color: Colors.black54,
                                          fontSize: screenFontSize4,
                                          fontWeight: FontWeight.bold,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),

                        ElevatedButton.icon(
                          onPressed: _printLabel,
                          icon: const Icon(Icons.print, color: Colors.white),
                          label: const Text('라벨 출력하기', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFFF1E1E),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            elevation: 4,
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

  Widget _buildTimeAdjustButton(String label, VoidCallback onPressed) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: isDark ? const Color(0xFF13141F) : const Color(0xFFFFFFFF),
        foregroundColor: isDark ? Colors.white70 : Colors.black87,
        padding: const EdgeInsets.symmetric(vertical: 14),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.08)),
        ),
      ),
      child: Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
    );
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
