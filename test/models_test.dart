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

    test('copyWith updates specified fields and detects OEM brand accurately', () {
      const samsung = DeviceInfo(
        serial: 'R5CW21ABCD',
        model: 'SM-S918B',
        brand: 'samsung',
        sdkInt: 34,
        connectionMode: ConnectionMode.usb,
      );
      expect(samsung.isGooglePixel, isFalse);
      expect(samsung.displayName, 'Samsung SM-S918B');

      const tecno = DeviceInfo(
        serial: '0987654321ABCDEF',
        model: 'TECNO CK7n',
        brand: 'TECNO',
        sdkInt: 33,
        connectionMode: ConnectionMode.usb,
      );
      expect(tecno.isGooglePixel, isFalse);
      expect(tecno.displayName, 'TECNO CK7n');

      const pixel = DeviceInfo(
        serial: '28301FDH300557',
        model: 'Pixel 7 Pro',
        brand: 'google',
        sdkInt: 35,
        connectionMode: ConnectionMode.usb,
      );
      expect(pixel.isGooglePixel, isTrue);

      final updated = samsung.copyWith(batteryLevel: 88, batteryStatus: 'Pleine');
      expect(updated.batteryLevel, 88);
      expect(updated.batteryStatus, 'Pleine');
      expect(updated.serial, 'R5CW21ABCD');
    });
  });

  group('ScrcpyOptions', () {
    test('generates universal non-dimming defaults for standard USB targeting', () {
      const dev = DeviceInfo(
        serial: 'R5CW21ABCD',
        model: 'SM-S918B',
        brand: 'samsung',
        sdkInt: 34,
        connectionMode: ConnectionMode.usb,
      );
      const options = ScrcpyOptions();
      expect(options.useBrightnessWorkaround, isFalse);
      expect(options.turnScreenOff, isFalse);

      final args = options.toArguments(device: dev);

      expect(args, contains('-d'));
      expect(args, contains('--display-id=0'));
      expect(args, contains('--stay-awake'));
      expect(args, contains('--keyboard=uhid'));
      expect(args, isNot(contains('--turn-screen-off')));
      expect(args, isNot(contains('--no-audio')));
    });

    test('uses native --turn-screen-off on Samsung/Xiaomi/Tecno and software dim on Pixel', () {
      const xiaomi = DeviceInfo(
        serial: 'eb912345',
        model: '2312DRA50G',
        brand: 'Xiaomi',
        sdkInt: 34,
        connectionMode: ConnectionMode.usb,
      );
      const pixel = DeviceInfo(
        serial: '28301FDH300557',
        model: 'Pixel 7 Pro',
        brand: 'google',
        sdkInt: 35,
        connectionMode: ConnectionMode.usb,
      );
      const screenOffOptions = ScrcpyOptions(turnScreenOff: true);

      final xiaomiArgs = screenOffOptions.toArguments(device: xiaomi);
      expect(xiaomiArgs, contains('--turn-screen-off'));

      final pixelArgs = screenOffOptions.toArguments(device: pixel);
      expect(pixelArgs, isNot(contains('--turn-screen-off')));
    });

    test('automatically adapts UHID keyboard and audio flags on Android 8-10 (SDK < 30)', () {
      const legacyInfinix = DeviceInfo(
        serial: '05432123456',
        model: 'Infinix X650B',
        brand: 'Infinix',
        sdkInt: 28,
        connectionMode: ConnectionMode.usb,
      );
      const options = ScrcpyOptions();
      final args = options.toArguments(device: legacyInfinix);

      expect(args, isNot(contains('--keyboard=uhid')));
      expect(args, contains('--no-audio'));
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

    test('generates --no-control flag and suppresses uhid keyboard in cast-only mode', () {
      const dev = DeviceInfo(
        serial: '28301FDH300557',
        model: 'Pixel 7 Pro',
        connectionMode: ConnectionMode.usb,
      );
      const options = ScrcpyOptions(noControl: true);
      final args = options.toArguments(device: dev);

      expect(args, contains('--no-control'));
      expect(args, isNot(contains('--keyboard=uhid')));
    });
  });
}
