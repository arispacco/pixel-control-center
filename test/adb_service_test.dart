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

    test('parseDevicesOutput extracts USB and Wi-Fi devices correctly', () {
      const mockOutput = '''
List of devices attached
28301FDH300557         device product:cheetah model:Pixel_7_Pro device:cheetah transport_id:1
192.168.100.178:5555   device product:cheetah model:Pixel_7_Pro device:cheetah transport_id:2
unauthorized_serial    unauthorized transport_id:3
''';

      final devices = adbService.parseDevicesOutput(mockOutput);

      expect(devices.length, 2);

      final usb = devices[0];
      expect(usb.serial, '28301FDH300557');
      expect(usb.model, 'Pixel 7 Pro');
      expect(usb.connectionMode, ConnectionMode.usb);
      expect(usb.isUsb, isTrue);

      final wifi = devices[1];
      expect(wifi.serial, '192.168.100.178:5555');
      expect(wifi.model, 'Pixel 7 Pro');
      expect(wifi.connectionMode, ConnectionMode.wifi);
      expect(wifi.ipAddress, '192.168.100.178');
      expect(wifi.port, 5555);
      expect(wifi.isWifi, isTrue);
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
