import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:blue_thermal_printer/blue_thermal_printer.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'label_renderer.dart';

class BluetoothPrintService {
  BluetoothPrintService._privateConstructor() {
    _initAutoReconnectListener();
  }
  static final BluetoothPrintService instance = BluetoothPrintService._privateConstructor();

  final BlueThermalPrinter _bluetooth = BlueThermalPrinter.instance;

  bool _isConnected = false;
  bool get isConnected => _isConnected;

  bool _isAutoConnecting = false;
  bool get isAutoConnecting => _isAutoConnecting;

  BluetoothDevice? _connectedDevice;
  BluetoothDevice? get connectedDevice => _connectedDevice;

  /// Notifier for UI components to listen to Bluetooth connection state changes.
  final ValueNotifier<int> connectionRevision = ValueNotifier<int>(0);

  static const String _prefLastAddress = 'last_bluetooth_printer_address';
  static const String _prefLastName = 'last_bluetooth_printer_name';
  static const String _prefAutoConnect = 'pref_auto_connect_bt';

  void _notifyConnectionChange() {
    connectionRevision.value++;
  }

  void _initAutoReconnectListener() {
    try {
      _bluetooth.onStateChanged().listen((state) {
        // state 12 = STATE_ON, 10 = STATE_OFF, 13 = STATE_TURNING_OFF, 11 = STATE_TURNING_ON
        if (state == 12) {
          debugPrint('Bluetooth hardware turned ON - triggering autoConnect...');
          autoConnect();
        } else if (state == 10 || state == 13) {
          _isConnected = false;
          _connectedDevice = null;
          _notifyConnectionChange();
        }
      });
    } catch (e) {
      debugPrint('Error setting up bluetooth state listener: $e');
    }
  }

  Future<bool> isAutoConnectEnabled() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_prefAutoConnect) ?? true;
    } catch (e) {
      return true;
    }
  }

  Future<void> setAutoConnectEnabled(bool enabled) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefAutoConnect, enabled);
    } catch (e) {
      debugPrint('Failed to save autoConnect preference: $e');
    }
  }

  Future<void> _saveLastDevice(BluetoothDevice device) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (device.address != null) {
        await prefs.setString(_prefLastAddress, device.address!);
      }
      if (device.name != null) {
        await prefs.setString(_prefLastName, device.name!);
      }
    } catch (e) {
      debugPrint('Failed to save last bluetooth device: $e');
    }
  }

  Future<String?> getLastSavedAddress() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_prefLastAddress);
    } catch (e) {
      return null;
    }
  }

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

      final bool? currentlyConnected = await _bluetooth.isConnected;
      if (currentlyConnected == true && _connectedDevice?.address == device.address) {
        _isConnected = true;
        _notifyConnectionChange();
        return true;
      }

      if (currentlyConnected == true) {
        await disconnect();
      }

      final bool? result = await _bluetooth.connect(device);
      if (result == true) {
        _isConnected = true;
        _connectedDevice = device;
        await _saveLastDevice(device);
        _notifyConnectionChange();
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('Error connecting to Bluetooth printer: $e');
      _isConnected = false;
      _notifyConnectionChange();
      return false;
    }
  }

  Future<void> disconnect() async {
    try {
      await _bluetooth.disconnect();
    } catch (e) {
      debugPrint('Error disconnecting Bluetooth printer: $e');
    } finally {
      _isConnected = false;
      _connectedDevice = null;
      _notifyConnectionChange();
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

  /// Automatically connects to the last saved printer or an available paired printer.
  Future<bool> autoConnect() async {
    if (_isAutoConnecting) return _isConnected;

    final bool enabled = await isAutoConnectEnabled();
    if (!enabled) {
      debugPrint('Bluetooth autoConnect is disabled in settings.');
      return false;
    }

    _isAutoConnecting = true;

    try {
      // 1. Check if already connected cleanly
      final bool? isConn = await _bluetooth.isConnected;
      if (isConn == true && _connectedDevice != null) {
        _isConnected = true;
        _isAutoConnecting = false;
        _notifyConnectionChange();
        return true;
      }

      // 2. Check if Bluetooth hardware is available and ON
      final bool avail = await checkBluetoothAvailable();
      if (!avail) {
        _isConnected = false;
        _isAutoConnecting = false;
        _notifyConnectionChange();
        return false;
      }

      // 3. Get paired devices
      final List<BluetoothDevice> bonded = await getPairedDevices();
      if (bonded.isEmpty) {
        _isConnected = false;
        _isAutoConnecting = false;
        _notifyConnectionChange();
        return false;
      }

      BluetoothDevice? targetDevice;

      // Check for saved last address
      final String? lastAddr = await getLastSavedAddress();
      if (lastAddr != null && lastAddr.isNotEmpty) {
        try {
          targetDevice = bonded.firstWhere((d) => d.address == lastAddr);
        } catch (_) {
          targetDevice = null;
        }
      }

      // If no valid target from last address
      if (targetDevice == null) {
        if (_connectedDevice != null && bonded.any((d) => d.address == _connectedDevice!.address)) {
          targetDevice = _connectedDevice;
        } else if (bonded.length == 1) {
          targetDevice = bonded.first;
        } else {
          // Look for printer keywords
          try {
            targetDevice = bonded.firstWhere((d) {
              final n = (d.name ?? '').toLowerCase();
              return n.contains('printer') ||
                  n.contains('label') ||
                  n.contains('xprinter') ||
                  n.contains('pos') ||
                  n.contains('tspl') ||
                  n.contains('bt');
            });
          } catch (_) {
            targetDevice = bonded.first;
          }
        }
      }

      if (targetDevice != null) {
        debugPrint('Attempting autoConnect to printer: ${targetDevice.name} (${targetDevice.address})');
        final bool success = await connect(targetDevice);
        _isAutoConnecting = false;
        return success;
      }
    } catch (e) {
      debugPrint('Auto-connect exception: $e');
    }

    _isConnected = false;
    _isAutoConnecting = false;
    _notifyConnectionChange();
    return false;
  }

  Future<bool> printRawBytes(List<int> bytes) async {
    final bool? isConn = await _bluetooth.isConnected;
    if (!_isConnected || isConn != true) {
      final bool autoOk = await autoConnect();
      if (!autoOk) return false;
    }
    try {
      await _bluetooth.writeBytes(Uint8List.fromList(bytes));
      _isConnected = true;
      _notifyConnectionChange();
      return true;
    } catch (e) {
      debugPrint('Error writing raw bytes to printer: $e');
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
    // 1. Check connection status and auto-connect if disconnected
    final bool? isConn = await _bluetooth.isConnected;
    if (!_isConnected || isConn != true) {
      debugPrint('Bluetooth not connected before printing, attempting autoConnect...');
      final bool autoOk = await autoConnect();
      if (!autoOk) return false;
    }

    try {
      return await _executeTsplPrint(
        width: width,
        height: height,
        name: name,
        abbr: abbr,
        storage: storage,
        prepDate: prepDate,
        expDate: expDate,
        staff: staff,
        quantity: quantity,
        showLine1: showLine1,
        showLine2: showLine2,
        showLine3: showLine3,
        showLine4: showLine4,
        fontSize1: fontSize1,
        fontSize2: fontSize2,
        fontSize3: fontSize3,
        fontSize4: fontSize4,
        leftPaddingPercent: leftPaddingPercent,
        verticalGapPt: verticalGapPt,
      );
    } catch (e) {
      debugPrint('Error writing TSPL to Bluetooth printer: $e');
      _isConnected = false;
      _notifyConnectionChange();
      // Do not duplicate execute the print here as the buffer might have already been sent.
      return false;
    }
  }

  Future<bool> _executeTsplPrint({
    required double width,
    required double height,
    required String name,
    required String abbr,
    required String storage,
    required String prepDate,
    required String expDate,
    required String staff,
    required int quantity,
    required bool showLine1,
    required bool showLine2,
    required bool showLine3,
    required bool showLine4,
    required double fontSize1,
    required double fontSize2,
    required double fontSize3,
    required double fontSize4,
    required double leftPaddingPercent,
    required double verticalGapPt,
  }) async {
    final int widthDots = (width * 8).round(); // 8 dots/mm
    final int heightDots = (height * 8).round();
    final int widthBytes = (widthDots + 7) ~/ 8;

    final String storageDisplay = storage;

    final List<LabelLine> labelLines = [];
    if (showLine1) {
      final String line1Text = '[$storageDisplay] $name${abbr.isNotEmpty ? " ($abbr)" : ""}';
      final String? fallbackText = abbr.isNotEmpty ? '[$storageDisplay] $abbr' : null;
      labelLines.add(LabelLine(line1Text, fontSize1, fallbackText: fallbackText));
    }
    if (showLine2) {
      String line2Text = prepDate;
      final String prefix = storage == '입고' ? '입고' : '준비';
      if (!line2Text.startsWith('준비') &&
          !line2Text.startsWith('입고') &&
          !line2Text.startsWith('Prep') &&
          !line2Text.startsWith('PREP') &&
          !line2Text.startsWith('OUT') &&
          !line2Text.startsWith('IN')) {
        line2Text = '$prefix: $line2Text';
      }
      labelLines.add(LabelLine(line2Text, fontSize2));
    }
    if (showLine3) {
      String line3Text = expDate;
      if (line3Text.isNotEmpty &&
          !line3Text.startsWith('폐기') &&
          !line3Text.startsWith('IN') &&
          !line3Text.startsWith('※')) {
        line3Text = '폐기: $line3Text';
      }
      if (line3Text.isNotEmpty) {
        labelLines.add(LabelLine(line3Text, fontSize3));
      }
    }

    final Uint8List bitmap = await _renderLabelMonochrome(
      widthBytes: widthBytes,
      widthDots: widthDots,
      heightDots: heightDots,
      lines: labelLines,
      leftPaddingPercent: leftPaddingPercent,
      verticalGapPt: verticalGapPt,
    );

    final BytesBuilder out = BytesBuilder();
    final String header = 'SIZE ${width.toInt()} mm, ${height.toInt()} mm\r\n'
        'GAP 2 mm, 0 mm\r\n'
        'DIRECTION 1\r\n'
        'CLS\r\n'
        'BITMAP 0,0,$widthBytes,$heightDots,0,';
    out.add(ascii.encode(header));
    out.add(bitmap);
    out.add(ascii.encode('\r\nPRINT $quantity,1\r\n'));

    await _bluetooth.writeBytes(out.toBytes());
    _isConnected = true;
    _notifyConnectionChange();
    return true;
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

    // NOTE: No horizontal pre-flip. The printer outputs BITMAP data as-is, and
    // a previous pre-flip (translate + scale(-1, 1)) caused mirrored labels.

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
