import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:blue_thermal_printer/blue_thermal_printer.dart';
import 'package:flutter/foundation.dart';
import 'label_renderer.dart';

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

      final List<LabelLine> labelLines = [];
      if (showLine1) {
        final String line1Text = '[$storageDisplay] $name${abbr.isNotEmpty ? " ($abbr)" : ""}';
        final String? fallbackText = abbr.isNotEmpty ? '[$storageDisplay] $abbr' : null;
        labelLines.add(LabelLine(line1Text, fontSize1, fallbackText: fallbackText));
      }
      if (showLine2) {
        labelLines.add(LabelLine('준비: $prepDate', fontSize2));
      }
      if (showLine3) {
        labelLines.add(LabelLine('폐기: ${expDate.isEmpty ? "상시 보관" : expDate}', fontSize3));
      }
      if (showLine4) {
        labelLines.add(LabelLine('(담당: $staff)', fontSize4));
      }

      // Render the label to a 1-bit bitmap so Hangul no longer depends on any
      // printer-internal font. The previous TEXT "K" font does not exist on this
      // model, so text never rendered and the label came out blank.
      final Uint8List bitmap = await _renderLabelMonochrome(
        widthBytes: widthBytes,
        widthDots: widthDots,
        heightDots: heightDots,
        lines: labelLines,
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
    required List<LabelLine> lines,
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

    // Draw with the exact same renderer the on-screen preview uses, at the
    // printer's 8 dots/mm, so the printed label matches the preview 1:1.
    paintLabel(
      canvas,
      widthMm: widthDots / 8.0,
      heightMm: heightDots / 8.0,
      lines: lines,
      leftPaddingPercent: leftPaddingPercent,
      verticalGapPt: verticalGapPt,
      pxPerMm: 8.0,
      fillBackground: false, // background already filled before the mirror
    );

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
