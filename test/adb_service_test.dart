import 'package:flutter_test/flutter_test.dart';
import 'package:pixel_control_center/models/connection_mode.dart';
import 'package:pixel_control_center/models/device_info.dart';
import 'package:pixel_control_center/services/adb_service.dart';

void main() {
  group('AdbService parsing', () {
    late AdbService adbService;

    setUp(() {
      adbService = AdbService();
    });

    test('parseDevicesOutput extracts multi-brand Android USB and Wi-Fi devices', () {
      const mockOutput = '''
List of devices attached
R5CW21ABCD             device product:dm3qxxx model:SM_S918B device:dm3q transport_id:1
192.168.100.178:5555   device product:cheetah model:Pixel_7_Pro device:cheetah transport_id:2
0987654321ABCDEF       device product:CK7n_GL model:TECNO_CK7n device:TECNO-CK7n transport_id:4
unauthorized_serial    unauthorized transport_id:3
''';

      final devices = adbService.parseDevicesOutput(mockOutput);

      expect(devices.length, 3);

      final samsungUsb = devices[0];
      expect(samsungUsb.serial, 'R5CW21ABCD');
      expect(samsungUsb.model, 'SM S918B');
      expect(samsungUsb.connectionMode, ConnectionMode.usb);
      expect(samsungUsb.isUsb, isTrue);
      expect(samsungUsb.isGooglePixel, isFalse);

      final wifi = devices[1];
      expect(wifi.serial, '192.168.100.178:5555');
      expect(wifi.model, 'Pixel 7 Pro');
      expect(wifi.connectionMode, ConnectionMode.wifi);
      expect(wifi.ipAddress, '192.168.100.178');
      expect(wifi.port, 5555);
      expect(wifi.isWifi, isTrue);
      expect(wifi.isGooglePixel, isTrue);

      final tecnoUsb = devices[2];
      expect(tecnoUsb.serial, '0987654321ABCDEF');
      expect(tecnoUsb.model, 'TECNO CK7n');
      expect(tecnoUsb.isGooglePixel, isFalse);
    });

    test('getDeviceTargetFlags returns -d for USB and -s for Wi-Fi', () {
      const usbDev = DeviceInfo(
        serial: '28301FDH300557',
        model: 'Pixel 7 Pro',
        connectionMode: ConnectionMode.usb,
      );
      const wifiDev = DeviceInfo(
        serial: '192.168.100.178:5555',
        model: 'Pixel 7 Pro',
        connectionMode: ConnectionMode.wifi,
      );

      expect(adbService.getDeviceTargetFlags(usbDev), ['-d']);
      expect(adbService.getDeviceTargetFlags(wifiDev), ['-s', '192.168.100.178:5555']);
    });
  });
}
