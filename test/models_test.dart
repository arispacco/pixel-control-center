import 'package:flutter_test/flutter_test.dart';
import 'package:pixel_control_center/models/connection_mode.dart';
import 'package:pixel_control_center/models/device_info.dart';
import 'package:pixel_control_center/models/scrcpy_options.dart';

void main() {
  group('DeviceInfo', () {
    test('computes isUsb and isWifi correctly', () {
      const usbDev = DeviceInfo(
        serial: '28301FDH300557',
        model: 'Pixel 7 Pro',
        connectionMode: ConnectionMode.usb,
      );
      expect(usbDev.isUsb, isTrue);
      expect(usbDev.isWifi, isFalse);

      const wifiDev = DeviceInfo(
        serial: '192.168.100.178:5555',
        model: 'Pixel 7 Pro',
        connectionMode: ConnectionMode.wifi,
      );
      expect(wifiDev.isUsb, isFalse);
      expect(wifiDev.isWifi, isTrue);
    });

    test('copyWith updates specified fields', () {
      const dev = DeviceInfo(
        serial: 'test-serial',
        model: 'Pixel',
        connectionMode: ConnectionMode.usb,
      );
      final updated = dev.copyWith(batteryLevel: 88, batteryStatus: 'Pleine');
      expect(updated.batteryLevel, 88);
      expect(updated.batteryStatus, 'Pleine');
      expect(updated.serial, 'test-serial');
    });
  });

  group('ScrcpyOptions', () {
    test('generates expected flags for USB targeting', () {
      const dev = DeviceInfo(
        serial: '28301FDH300557',
        model: 'Pixel 7 Pro',
        connectionMode: ConnectionMode.usb,
      );
      const options = ScrcpyOptions();
      final args = options.toArguments(device: dev);

      expect(args, contains('-d'));
      expect(args, contains('--display-id=0'));
      expect(args, contains('--stay-awake'));
      expect(args, contains('--keyboard=uhid'));
      expect(args, isNot(contains('--no-audio')));
    });

    test('generates expected flags for Wi-Fi targeting', () {
      const dev = DeviceInfo(
        serial: '192.168.100.178:5555',
        model: 'Pixel 7 Pro',
        connectionMode: ConnectionMode.wifi,
      );
      const options = ScrcpyOptions(audioEnabled: false);
      final args = options.toArguments(device: dev);

      expect(args, contains('-s'));
      expect(args, contains('192.168.100.178:5555'));
      expect(args, contains('--no-audio'));
      expect(args, isNot(contains('-d')));
    });
  });
}
