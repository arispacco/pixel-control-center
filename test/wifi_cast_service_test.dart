import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pixel_control_center/models/cast_frame.dart';
import 'package:pixel_control_center/services/wifi_cast_service.dart';

void main() {
  group('WifiCastService (Zero-ADB Wi-Fi Image Streaming)', () {
    late WifiCastService service;

    setUp(() {
      service = WifiCastService();
    });

    tearDown(() async {
      await service.dispose();
    });

    test('responds to UDP PIXEL_CAST_DISCOVER with advertised TCP port', () async {
      final started = await service.startReceiver(tcpPort: 0, udpPort: 0);
      expect(started, isTrue);
      expect(service.boundTcpPort, greaterThan(0));
      expect(service.boundUdpPort, greaterThan(0));

      final completer = Completer<String>();
      final clientUdp = await RawDatagramSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      addTearDown(clientUdp.close);

      clientUdp.listen((event) {
        if (event == RawSocketEvent.read) {
          final dg = clientUdp.receive();
          if (dg != null && !completer.isCompleted) {
            completer.complete(utf8.decode(dg.data));
          }
        }
      });

      clientUdp.send(
        utf8.encode('PIXEL_CAST_DISCOVER'),
        InternetAddress.loopbackIPv4,
        service.boundUdpPort,
      );

      final reply = await completer.future.timeout(const Duration(seconds: 2));
      expect(reply, startsWith('PIXEL_CAST_HERE|'));
      expect(reply, endsWith('|${service.boundTcpPort}'));
    });

    test('decodes fragmented TCP PCST JPEG frames accurately', () async {
      final started = await service.startReceiver(
        tcpPort: 0,
        enableUdpDiscovery: false,
      );
      expect(started, isTrue);

      final fakeJpeg = Uint8List.fromList([
        0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0xFF, 0xD9,
      ]);

      final packet = BytesBuilder();
      packet.add(WifiCastService.frameMagic);
      final meta = ByteData(12)
        ..setUint32(0, 720, Endian.big)
        ..setUint32(4, 1560, Endian.big)
        ..setUint32(8, fakeJpeg.length, Endian.big);
      packet.add(meta.buffer.asUint8List());
      packet.add(fakeJpeg);
      final fullBytes = packet.toBytes();

      final frameCompleter = Completer<CastFrame>();
      service.frameNotifier.addListener(() {
        final f = service.frameNotifier.value;
        if (f != null && !frameCompleter.isCompleted) {
          frameCompleter.complete(f);
        }
      });

      final sender = await Socket.connect(
        InternetAddress.loopbackIPv4,
        service.boundTcpPort,
      );
      addTearDown(sender.destroy);

      // Deliberately split header and body across two TCP writes.
      sender.add(fullBytes.sublist(0, 7));
      await sender.flush();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      sender.add(fullBytes.sublist(7));
      await sender.flush();

      final received = await frameCompleter.future.timeout(
        const Duration(seconds: 2),
      );
      expect(received.width, 720);
      expect(received.height, 1560);
      expect(received.jpegBytes, equals(fakeJpeg));
    });

    test('pulls JPEG frames from an HTTP MJPEG stream endpoint', () async {
      final sampleJpeg = Uint8List.fromList([
        0xFF, 0xD8, 0x01, 0x02, 0x03, 0x04, 0xFF, 0xD9,
      ]);

      final mjpegServer = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      addTearDown(() => mjpegServer.close(force: true));

      mjpegServer.listen((HttpRequest req) async {
        req.response.statusCode = HttpStatus.ok;
        req.response.headers.set(
          HttpHeaders.contentTypeHeader,
          'multipart/x-mixed-replace; boundary=frame',
        );
        req.response.bufferOutput = false;
        req.response.add(
          utf8.encode(
            '--frame\r\nContent-Type: image/jpeg\r\nContent-Length: ${sampleJpeg.length}\r\n\r\n',
          ),
        );
        req.response.add(sampleJpeg);
        req.response.add(utf8.encode('\r\n'));
        await req.response.flush();
        await req.response.close();
      });

      final frameCompleter = Completer<CastFrame>();
      service.frameNotifier.addListener(() {
        final f = service.frameNotifier.value;
        if (f != null && !frameCompleter.isCompleted) {
          frameCompleter.complete(f);
        }
      });

      final connected = await service.connectMjpegStream(
        '127.0.0.1:${mjpegServer.port}',
      );
      expect(connected, isTrue);

      final received = await frameCompleter.future.timeout(
        const Duration(seconds: 2),
      );
      expect(received.jpegBytes, equals(sampleJpeg));
    });
  });
}
