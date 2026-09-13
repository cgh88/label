import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:client_flutter/services/usb_print_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('UsbPrintService defaults and settings persistence', () async {
    final service = UsbPrintService.instance;
    expect(service.isEnabled, isTrue);
    expect(service.isDirectPrint, isTrue);
    expect(service.printers, isEmpty);

    await service.setEnabled(false);
    expect(service.isEnabled, isFalse);

    await service.setEnabled(true);
    expect(service.isEnabled, isTrue);

    await service.setDirectPrint(false);
    expect(service.isDirectPrint, isFalse);

    await service.setDirectPrint(true);
    expect(service.isDirectPrint, isTrue);

    expect(service.connectionType, 'usb');
    expect(service.isUsbMode, isTrue);
    expect(service.isBluetoothMode, isFalse);
    expect(service.connectionTypeLabel, 'USB');

    await service.setConnectionType('bluetooth');
    expect(service.connectionType, 'bluetooth');
    expect(service.isUsbMode, isFalse);
    expect(service.isBluetoothMode, isTrue);
    expect(service.connectionTypeLabel, '블루투스');

    await service.setConnectionType('usb');
    expect(service.connectionType, 'usb');
    expect(service.isUsbMode, isTrue);
    expect(service.connectionTypeLabel, 'USB');
  });
}
