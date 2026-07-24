import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:blue_thermal_printer/blue_thermal_printer.dart';
import 'package:flutter/foundation.dart';

class BluetoothPrintService {
  BluetoothPrintService._privateConstructor();
  static final BluetoothPrintService instance = BluetoothPrintService._privateConstructor();

  final BlueThermalPrinter _bluetooth = BlueThermalPrinter.instance;

  bool _isConnected = false;
  bool get isConnected => _isConnected;

  BluetoothDevice? _connectedDevice;
  BluetoothDevice? get connectedDevice => _connectedDevice;

  Future<List<BluetoothDevice>> getPairedDevices() async {
    try {
      final List<BluetoothDevice> devices = await _bluetooth.getBondedDevices();
      return devices;
    } catch (e) {
      debugPrint('Error fetching bluetooth devices: $e');
      return [];
    }
  }

  Future<bool> isDevicePaired(String? address) async {
    if (address == null || address.isEmpty) return false;
    final List<BluetoothDevice> devices = await getPairedDevices();
    return devices.any((d) => d.address == address);
  }

  Future<bool> connect(BluetoothDevice device) async {
    try {
      final bool paired = await isDevicePaired(device.address);
      if (!paired) {
        debugPrint('Device ${device.name} is not paired in system settings.');
        return false;
      }
      if (_isConnected) {
        await disconnect();
      }
      final bool? result = await _bluetooth.connect(device);
      if (result == true) {
        _isConnected = true;
        _connectedDevice = device;
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('Error connecting to Bluetooth printer: $e');
      return false;
    }
  }

  Future<void> disconnect() async {
    try {
      await _bluetooth.disconnect();
      _isConnected = false;
      _connectedDevice = null;
    } catch (e) {
      debugPrint('Error disconnecting Bluetooth printer: $e');
    }
  }

  Future<bool> checkBluetoothAvailable() async {
    try {
      final bool? isAvail = await _bluetooth.isAvailable;
      final bool? isOn = await _bluetooth.isOn;
      return isAvail == true && isOn == true;
    } catch (e) {
      debugPrint('Error checking bluetooth state: $e');
      return false;
    }
  }

  Future<bool> printTsplLabel({
    required double width,
    required double height,
    required String name,
    required String abbr,
    required String storage,
    required String prepDate,
    required String expDate,
    required String staff,
    int quantity = 1,
    bool showLine1 = true,
    bool showLine2 = true,
    bool showLine3 = true,
    bool showLine4 = false,
    double fontSize1 = 12.5,
    double fontSize2 = 12.5,
    double fontSize3 = 12.5,
    double fontSize4 = 6.25,
    double leftPaddingPercent = 10.0,
    double verticalGapPt = 3.5,
  }) async {
    if (!_isConnected) return false;

    try {
      final int widthDots = (width * 8).round(); // 8 dots/mm
      final int heightDots = (height * 8).round();
      final int widthBytes = (widthDots + 7) ~/ 8;

      final String storageDisplay = storage == '입고' ? '입고' : '$storage 보관';

      final List<String> visibleLines = [];
      final List<double> lineFontSizes = [];
      if (showLine1) {
        visibleLines.add('[$storageDisplay] $name${abbr.isNotEmpty ? " ($abbr)" : ""}');
        lineFontSizes.add(fontSize1);
      }
      if (showLine2) {
        visibleLines.add('준비: $prepDate');
        lineFontSizes.add(fontSize2);
      }
      if (showLine3) {
        visibleLines.add('폐기: ${expDate.isEmpty ? "상시 보관" : expDate}');
        lineFontSizes.add(fontSize3);
      }
      if (showLine4) {
        visibleLines.add('(담당: $staff)');
        lineFontSizes.add(fontSize4);
      }

      // Render the label to a 1-bit bitmap so Hangul no longer depends on any
      // printer-internal font. The previous TEXT "K" font does not exist on this
      // model, so text never rendered and the label came out blank.
      final Uint8List bitmap = await _renderLabelMonochrome(
        widthBytes: widthBytes,
        widthDots: widthDots,
        heightDots: heightDots,
        lines: visibleLines,
        lineFontSizes: lineFontSizes,
        leftPaddingPercent: leftPaddingPercent,
        verticalGapPt: verticalGapPt,
      );

      // TSPL command: ASCII header + binary BITMAP payload + PRINT.
      final BytesBuilder out = BytesBuilder();
      final String header = 'SIZE ${width.toInt()} mm, ${height.toInt()} mm\r\n'
          'GAP 2 mm, 0 mm\r\n'
          'DIRECTION 1\r\n'
          'CLS\r\n'
          'BITMAP 0,0,$widthBytes,$heightDots,0,';
      out.add(ascii.encode(header));
      out.add(bitmap);
      out.add(ascii.encode('\r\nPRINT $quantity\r\n'));

      await _bluetooth.writeBytes(out.toBytes());
      return true;
    } catch (e) {
      debugPrint('Error writing TSPL to Bluetooth printer: $e');
      return false;
    }
  }

  /// Renders the label text to a packed 1-bit-per-pixel bitmap for TSPL BITMAP.
  /// In TSPL BITMAP data a 0 bit prints a black dot and a 1 bit leaves it white,
  /// so the buffer starts all-white (0xFF) and each text pixel clears its bit.
  Future<Uint8List> _renderLabelMonochrome({
    required int widthBytes,
    required int widthDots,
    required int heightDots,
    required List<String> lines,
    required List<double> lineFontSizes,
    required double leftPaddingPercent,
    required double verticalGapPt,
  }) async {
    final int canvasWidth = widthBytes * 8;
    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final ui.Canvas canvas = ui.Canvas(recorder);
    canvas.drawRect(
      ui.Rect.fromLTWH(0, 0, canvasWidth.toDouble(), heightDots.toDouble()),
      ui.Paint()..color = const ui.Color(0xFFFFFFFF),
    );

    // This printer mirrors BITMAP output left-to-right under DIRECTION 1, which
    // made Hangul come out reversed. Pre-flip the canvas horizontally so the
    // printer's mirroring cancels back to a correctly readable label.
    canvas.translate(canvasWidth.toDouble(), 0);
    canvas.scale(-1, 1);

    final double x = (widthDots * (leftPaddingPercent / 100.0))
        .clamp(4, (widthDots - 8).toDouble())
        .toDouble();
    // Match the on-screen preview: it renders at 6.4 px/mm with
    // fontPx = pt * 1.734 * scale. This bitmap renders at 8 dots/mm, so multiply
    // by 8 / 6.4 = 1.25 to reproduce the same physical size on the label.
    final double scale = ((widthDots / 8.0) / 50.0).clamp(0.5, 2.0);
    const double ptToDot = 1.734 * 1.25;
    final int gap = (verticalGapPt * scale * 0.97 * 1.25).round().clamp(1, 40);

    ui.Paragraph buildPara(String text, double fontSize) {
      final builder = ui.ParagraphBuilder(ui.ParagraphStyle(
        textAlign: ui.TextAlign.left,
        fontSize: fontSize,
        fontWeight: ui.FontWeight.bold,
        maxLines: 1,
        ellipsis: '…',
      ))
        ..pushStyle(ui.TextStyle(color: const ui.Color(0xFF000000)))
        ..addText(text);
      final p = builder.build();
      p.layout(ui.ParagraphConstraints(width: canvasWidth - x));
      return p;
    }

    // Use per-line font sizes (pt, from settings) for accurate print output,
    // converted to bitmap dots the same way the preview computes its size.
    final List<ui.Paragraph> paras = [];
    for (int i = 0; i < lines.length; i++) {
      final double pt = i < lineFontSizes.length ? lineFontSizes[i] : 12.5;
      final double fs = pt * ptToDot * scale;
      paras.add(buildPara(lines[i], fs));
    }

    final double totalH = paras.fold<double>(0.0, (s, p) => s + p.height) +
        (paras.isEmpty ? 0 : gap * (paras.length - 1));
    double y = ((heightDots - totalH) / 2).clamp(2.0, heightDots.toDouble());
    for (final p in paras) {
      canvas.drawParagraph(p, ui.Offset(x, y));
      y += p.height + gap;
    }

    final ui.Image image =
        await recorder.endRecording().toImage(canvasWidth, heightDots);
    final ByteData? rgba =
        await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();

    final int total = widthBytes * heightDots;
    final Uint8List packed = Uint8List(total)..fillRange(0, total, 0xFF);
    if (rgba == null) return packed;

    final Uint8List px = rgba.buffer.asUint8List();
    for (int yy = 0; yy < heightDots; yy++) {
      for (int xx = 0; xx < canvasWidth; xx++) {
        final int idx = (yy * canvasWidth + xx) * 4;
        final int lum = (px[idx] + px[idx + 1] + px[idx + 2]) ~/ 3;
        if (lum < 128) {
          final int byteIndex = yy * widthBytes + (xx >> 3);
          final int bit = 7 - (xx & 7);
          packed[byteIndex] &= ~(1 << bit) & 0xFF;
        }
      }
    }
    return packed;
  }
}
