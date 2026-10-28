import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'print_settings.dart';

class UsbPrintService {
  UsbPrintService._privateConstructor();
  static final UsbPrintService instance = UsbPrintService._privateConstructor();

  static const String _prefConnectionType = 'pref_win_printer_connection_type';
  static const String _prefUsbPrinterName = 'pref_win_usb_printer_name';
  static const String _prefUsbPrinterUrl = 'pref_win_usb_printer_url';
  static const String _prefBtPrinterName = 'pref_win_bt_printer_name';
  static const String _prefBtPrinterUrl = 'pref_win_bt_printer_url';
  static const String _prefEnabled = 'pref_win_usb_printer_enabled';
  static const String _prefDirectPrint = 'pref_win_usb_direct_print';

  final ValueNotifier<int> connectionRevision = ValueNotifier<int>(0);

  bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  String _connectionType = 'usb'; // 'usb' or 'bluetooth'
  String get connectionType => _connectionType;
  bool get isUsbMode => _connectionType == 'usb';
  bool get isBluetoothMode => _connectionType == 'bluetooth';
  String get connectionTypeLabel => isBluetoothMode ? '블루투스' : 'USB';

  bool _isEnabled = true;
  bool get isEnabled => _isEnabled;

  bool _isDirectPrint = true;
  bool get isDirectPrint => _isDirectPrint;

  bool _isScanning = false;
  bool get isScanning => _isScanning;

  List<Printer> _printers = [];
  List<Printer> get printers => List.unmodifiable(_printers);

  Printer? _selectedPrinter;
  Printer? get selectedPrinter => _selectedPrinter;

  bool _initialized = false;

  void _notify() {
    connectionRevision.value++;
  }

  Future<void> init() async {
    if (!isSupported) return;
    if (_initialized) return;
    _initialized = true;

    try {
      final prefs = await SharedPreferences.getInstance();
      _connectionType = prefs.getString(_prefConnectionType) ?? 'usb';
      _isEnabled = prefs.getBool(_prefEnabled) ?? true;
      _isDirectPrint = prefs.getBool(_prefDirectPrint) ?? true;

      final savedName = prefs.getString(
        isBluetoothMode ? _prefBtPrinterName : _prefUsbPrinterName,
      ) ?? prefs.getString(_prefUsbPrinterName);
      final savedUrl = prefs.getString(
        isBluetoothMode ? _prefBtPrinterUrl : _prefUsbPrinterUrl,
      ) ?? prefs.getString(_prefUsbPrinterUrl);

      await refreshPrinters(
        preferredName: savedName,
        preferredUrl: savedUrl,
      );
    } catch (e) {
      debugPrint('UsbPrintService init error: $e');
    }
  }

  Future<List<Printer>> refreshPrinters({
    String? preferredName,
    String? preferredUrl,
  }) async {
    if (!isSupported) return [];

    _isScanning = true;
    _notify();

    try {
      final list = await Printing.listPrinters();
      _printers = list;

      final prefs = await SharedPreferences.getInstance();
      final targetName = preferredName ??
          (prefs.getString(
                isBluetoothMode ? _prefBtPrinterName : _prefUsbPrinterName,
              ) ??
              prefs.getString(_prefUsbPrinterName));
      final targetUrl = preferredUrl ??
          (prefs.getString(
                isBluetoothMode ? _prefBtPrinterUrl : _prefUsbPrinterUrl,
              ) ??
              prefs.getString(_prefUsbPrinterUrl));

      Printer? matched;

      // 1. Try matching by URL
      if (targetUrl != null && targetUrl.isNotEmpty) {
        try {
          matched = list.firstWhere((p) => p.url == targetUrl);
        } catch (_) {}
      }

      // 2. Try matching by name
      if (matched == null && targetName != null && targetName.isNotEmpty) {
        try {
          matched = list.firstWhere((p) => p.name == targetName);
        } catch (_) {}
      }

      // 3. If still not matched, auto-detect known label/thermal USB printers
      if (matched == null && list.isNotEmpty) {
        try {
          matched = list.firstWhere((p) {
            final n = '${p.name} ${p.model ?? ''}'.toUpperCase();
            return n.contains('TSC') ||
                n.contains('DA220') ||
                n.contains('XPRINTER') ||
                n.contains('XP-') ||
                n.contains('LABEL') ||
                n.contains('THERMAL') ||
                n.contains('POS') ||
                n.contains('BIXOLON') ||
                n.contains('ZEBRA');
          });
        } catch (_) {}
      }

      // 4. Fallback to system default printer if available
      if (matched == null && list.isNotEmpty) {
        try {
          matched = list.firstWhere((p) => p.isDefault);
        } catch (_) {
          matched = list.first;
        }
      }

      _selectedPrinter = matched;
      if (matched != null) {
        await _savePrinter(matched);
      }
    } catch (e) {
      debugPrint('UsbPrintService refreshPrinters error: $e');
    } finally {
      _isScanning = false;
      _notify();
    }

    return _printers;
  }

  Future<void> setSelectedPrinter(Printer? printer) async {
    _selectedPrinter = printer;
    await _savePrinter(printer);
    _notify();
  }

  Future<void> setConnectionType(String type) async {
    if (_connectionType == type) return;
    _connectionType = type;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefConnectionType, type);

      final savedName = prefs.getString(
        type == 'bluetooth' ? _prefBtPrinterName : _prefUsbPrinterName,
      );
      final savedUrl = prefs.getString(
        type == 'bluetooth' ? _prefBtPrinterUrl : _prefUsbPrinterUrl,
      );

      Printer? matched;
      if (savedUrl != null && savedUrl.isNotEmpty) {
        try {
          matched = _printers.firstWhere((p) => p.url == savedUrl);
        } catch (_) {}
      }
      if (matched == null && savedName != null && savedName.isNotEmpty) {
        try {
          matched = _printers.firstWhere((p) => p.name == savedName);
        } catch (_) {}
      }

      if (matched == null && type == 'bluetooth' && _printers.isNotEmpty) {
        try {
          matched = _printers.firstWhere((p) {
            final n = '${p.name} ${p.model ?? ''} ${p.comment ?? ''}'.toUpperCase();
            return n.contains('BLUETOOTH') || n.contains('BT');
          });
        } catch (_) {}
      }

      _selectedPrinter = matched;
      if (matched != null) {
        await _savePrinter(matched);
      }
    } catch (e) {
      debugPrint('UsbPrintService setConnectionType error: $e');
    }
    _notify();
  }

  Future<void> openWindowsBluetoothSettings() async {
    try {
      await Process.run('cmd', ['/c', 'start', 'ms-settings:bluetooth']);
    } catch (e) {
      debugPrint('UsbPrintService openWindowsBluetoothSettings error: $e');
    }
  }

  Future<void> _savePrinter(Printer? printer) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final nameKey =
          isBluetoothMode ? _prefBtPrinterName : _prefUsbPrinterName;
      final urlKey =
          isBluetoothMode ? _prefBtPrinterUrl : _prefUsbPrinterUrl;

      if (printer != null) {
        await prefs.setString(nameKey, printer.name);
        await prefs.setString(urlKey, printer.url);
        await prefs.setString(_prefUsbPrinterName, printer.name);
        await prefs.setString(_prefUsbPrinterUrl, printer.url);
      } else {
        await prefs.remove(nameKey);
        await prefs.remove(urlKey);
      }
    } catch (e) {
      debugPrint('UsbPrintService _savePrinter error: $e');
    }
  }

  Future<void> setEnabled(bool value) async {
    _isEnabled = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefEnabled, value);
    } catch (e) {
      debugPrint('UsbPrintService setEnabled error: $e');
    }
    _notify();
  }

  Future<void> setDirectPrint(bool value) async {
    _isDirectPrint = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefDirectPrint, value);
    } catch (e) {
      debugPrint('UsbPrintService setDirectPrint error: $e');
    }
    _notify();
  }

  /// Directly sends a PDF document to the selected USB printer.
  Future<bool> printPdfDocument({
    required pw.Document doc,
    required PdfPageFormat format,
    String name = 'Label Print',
  }) async {
    if (!isSupported || _selectedPrinter == null) {
      debugPrint('UsbPrintService: printer not configured or unsupported.');
      return false;
    }

    try {
      return await Printing.directPrintPdf(
        printer: _selectedPrinter!,
        onLayout: (PdfPageFormat f) async => doc.save(),
        format: format,
        name: name,
        usePrinterSettings: false,
      );
    } catch (e) {
      debugPrint('UsbPrintService printPdfDocument error: $e');
      return false;
    }
  }

  /// Prints a test label with specified or saved custom dimensions.
  Future<bool> printTestLabel({
    double? widthMm,
    double? heightMm,
  }) async {
    if (!isSupported || _selectedPrinter == null) return false;

    try {
      final prefs = await SharedPreferences.getInstance();
      final double effectiveW =
          widthMm ?? prefs.getDouble('label_width') ?? 55.0;
      final double effectiveH =
          heightMm ?? prefs.getDouble('label_height') ?? 20.0;

      final doc = pw.Document();
      final double widthPt = effectiveW * 72 / 25.4;
      final double heightPt = effectiveH * 72 / 25.4;

      final pageFormat = PdfPageFormat(
        widthPt,
        heightPt,
        marginTop: 0,
        marginBottom: 0,
        marginLeft: 0,
        marginRight: 0,
      );

      pw.Font fontBold;
      try {
        final fontData = await rootBundle.load('fonts/NotoSansKR-VF.ttf');
        fontBold = pw.Font.ttf(fontData);
      } catch (e) {
        fontBold = pw.Font.helveticaBold();
      }

      final nowStr = DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());
      final bool mirror = await PrintSettings.isMirrorHorizontal();

      doc.addPage(
        pw.Page(
          pageFormat: pageFormat,
          build: (pw.Context context) {
            return PrintSettings.wrapPdf(mirror: mirror, pw.Padding(
              padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                mainAxisAlignment: pw.MainAxisAlignment.center,
                children: [
                  pw.Text(
                    '[USB 테스트] 연결 성공',
                    style: pw.TextStyle(
                      font: fontBold,
                      fontSize: 10,
                      color: PdfColors.black,
                    ),
                    maxLines: 1,
                  ),
                  pw.SizedBox(height: 2),
                  pw.Text(
                    '프린터: ${_selectedPrinter!.name}',
                    style: pw.TextStyle(
                      font: fontBold,
                      fontSize: 8,
                      color: PdfColors.black,
                    ),
                    maxLines: 1,
                  ),
                  pw.SizedBox(height: 2),
                  pw.Text(
                    '출력: $nowStr',
                    style: pw.TextStyle(
                      font: fontBold,
                      fontSize: 7.5,
                      color: PdfColors.black,
                    ),
                    maxLines: 1,
                  ),
                ],
              ),
            ));
          },
        ),
      );

      return await printPdfDocument(
        doc: doc,
        format: pageFormat,
        name: '${isBluetoothMode ? "BT" : "USB"}_Test_Label',
      );
    } catch (e) {
      debugPrint('UsbPrintService printTestLabel error: $e');
      return false;
    }
  }

  /// Convenience method to build and print sauce label on Windows.
  Future<bool> printSauceLabel({
    required double widthMm,
    required double heightMm,
    required String name,
    required String abbr,
    required String storage,
    required String prepDate,
    required String expDate,
    required String staff,
    int quantity = 1,
    double fontSize1 = 13.0,
    double fontSize2 = 12.0,
    double fontSize3 = 13.0,
    double leftPaddingPercent = 5.0,
    double verticalGapPt = 3.0,
  }) async {
    if (!isSupported || _selectedPrinter == null) return false;

    try {
      final doc = pw.Document();
      final double widthPt = widthMm * 72 / 25.4;
      final double heightPt = heightMm * 72 / 25.4;

      final pageFormat = PdfPageFormat(
        widthPt,
        heightPt,
        marginTop: 0,
        marginBottom: 0,
        marginLeft: 0,
        marginRight: 0,
      );

      pw.Font fontBold;
      try {
        final fontData = await rootBundle.load('fonts/NotoSansKR-VF.ttf');
        fontBold = pw.Font.ttf(fontData);
      } catch (e) {
        fontBold = pw.Font.helveticaBold();
      }

      final double scale = (widthMm / 50.0).clamp(0.5, 2.0);
      final double pdfFontSize1 = (fontSize1 * 9.6 / 12.5 * scale).clamp(5.0, 24.0);
      final double pdfFontSize2 = (fontSize2 * 9.6 / 12.5 * scale).clamp(5.0, 24.0);
      final double pdfFontSize3 = (fontSize3 * 9.6 / 12.5 * scale).clamp(5.0, 24.0);
      final double pdfLeftPadding = widthPt * (leftPaddingPercent / 100.0);
      final double pdfVerticalGap = verticalGapPt * scale * 0.43;
      final bool mirror = await PrintSettings.isMirrorHorizontal();

      for (int i = 0; i < quantity; i++) {
        doc.addPage(
          pw.Page(
            pageFormat: pageFormat,
            build: (pw.Context context) {
              return PrintSettings.wrapPdf(mirror: mirror, pw.Padding(
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
                    pw.Text(
                      '[$storage] $name ($abbr)',
                      style: pw.TextStyle(
                        font: fontBold,
                        fontSize: pdfFontSize1,
                        color: PdfColors.black,
                      ),
                      maxLines: 1,
                      overflow: pw.TextOverflow.clip,
                    ),
                    pw.SizedBox(height: pdfVerticalGap),
                    pw.Text(
                      prepDate,
                      style: pw.TextStyle(
                        font: fontBold,
                        fontSize: pdfFontSize2,
                        color: PdfColors.black,
                      ),
                      maxLines: 1,
                      overflow: pw.TextOverflow.clip,
                    ),
                    if (expDate.isNotEmpty) ...[
                      pw.SizedBox(height: pdfVerticalGap),
                      pw.Text(
                        expDate,
                        style: pw.TextStyle(
                          font: fontBold,
                          fontSize: pdfFontSize3,
                          color: PdfColors.black,
                        ),
                        maxLines: 1,
                        overflow: pw.TextOverflow.clip,
                      ),
                    ],
                  ],
                ),
              ));
            },
          ),
        );
      }

      return await printPdfDocument(
        doc: doc,
        format: pageFormat,
        name: 'sauce_label_${abbr}_$storage',
      );
    } catch (e) {
      debugPrint('UsbPrintService printSauceLabel error: $e');
      return false;
    }
  }
}
