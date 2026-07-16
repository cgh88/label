import 'dart:typed_data';
import 'package:blue_thermal_printer/blue_thermal_printer.dart';
import 'package:flutter/foundation.dart';
import 'package:cp949_codec/cp949_codec.dart';

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
    bool showLine4 = true,
    double leftPaddingPercent = 10.0,
    double verticalGapPt = 3.5,
  }) async {
    if (!_isConnected) return false;

    try {
      final StringBuffer sb = StringBuffer();
      
      // TSPL Command Header
      sb.write('SIZE ${width.toInt()} mm, ${height.toInt()} mm\r\n');
      sb.write('GAP 2 mm, 0 mm\r\n');
      sb.write('DIRECTION 1\r\n');
      
      // Set codepage to Korean (949 / CP949) for Hangul support
      sb.write('CODEPAGE 949\r\n');
      sb.write('CLS\r\n');

      final String storageDisplay = storage == '입고' ? '입고' : '$storage 보관';

      // Build visible lines list
      final List<String> visibleLines = [];
      if (showLine1) {
        visibleLines.add('[$storageDisplay] $name${abbr.isNotEmpty ? " ($abbr)" : ""}');
      }
      if (showLine2) {
        visibleLines.add('준비: $prepDate');
      }
      if (showLine3) {
        final String expStr = expDate.isEmpty ? '상시 보관' : expDate;
        visibleLines.add('폐기: $expStr');
      }
      if (showLine4) {
        visibleLines.add('(담당: $staff)');
      }

      if (visibleLines.isNotEmpty) {
        final double totalDots = height * 8.0; // 8 dots/mm
        final int gapDots = (verticalGapPt * 2.8).toInt().clamp(2, 50);
        final int fontHeight = 24; // Font "K" is 24 dots height
        final int totalContentHeight = (visibleLines.length * fontHeight) + ((visibleLines.length - 1) * gapDots);

        // Center content vertically
        int currentY = ((totalDots - totalContentHeight) / 2).toInt().clamp(5, 120);
        int xDots = (width * 8.0 * (leftPaddingPercent / 100.0)).toInt().clamp(5, 200);

        for (final lineText in visibleLines) {
          sb.write('TEXT $xDots, $currentY, "K", 0, 1, 1, "$lineText"\r\n');
          currentY += fontHeight + gapDots;
        }
      }

      sb.write('PRINT $quantity\r\n');

      // Convert TSPL command string to EUC-KR / CP949 bytes
      final List<int> tsplBytes = cp949.encode(sb.toString());
      final Uint8List data = Uint8List.fromList(tsplBytes);

      await _bluetooth.writeBytes(data);
      return true;
    } catch (e) {
      debugPrint('Error writing TSPL to Bluetooth printer: $e');
      return false;
    }
  }
}
