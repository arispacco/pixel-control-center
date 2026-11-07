import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../models/cast_frame.dart';

/// Zero-ADB live screen casting receiver over local Wi-Fi.
///
/// Works completely independently of USB Debugging, Developer Options, ADB,
/// or scrcpy by receiving real-time compressed image frames over a local
/// TCP socket (`PCST` binary framing) or pulling from an HTTP MJPEG stream,
/// paired with UDP LAN auto-discovery so non-technical users do not need to
/// type IP addresses.
class WifiCastService {
  /// Default TCP port used to receive pushed JPEG frames from Android.
  static const int defaultTcpPort = 5959;

  /// Default UDP port used for zero-config local network discovery.
  static const int defaultUdpDiscoveryPort = 5958;

  /// Magic header prefix (`PCST`) identifying a frame packet.
  static const List<int> frameMagic = [0x50, 0x43, 0x53, 0x54];

  /// Header size in bytes: 4 magic + 4 width + 4 height + 4 payload length.
  static const int headerByteLength = 16;

  /// Maximum allowed single JPEG frame size (8 MB) to guard against corruption.
  static const int maxFrameBytes = 8 * 1024 * 1024;

  ServerSocket? _tcpServer;
  Socket? _activeSenderSocket;
  RawDatagramSocket? _udpSocket;
  HttpClient? _mjpegHttpClient;
  StreamSubscription<List<int>>? _mjpegSubscription;

  final StreamController<String> _logController =
      StreamController<String>.broadcast();

  /// Notifies listeners with every decoded [CastFrame] for 60 FPS gapless UI.
  final ValueNotifier<CastFrame?> frameNotifier = ValueNotifier<CastFrame?>(
    null,
  );

  /// Notifies listeners with the measured incoming frame rate (frames/sec).
  final ValueNotifier<double> fpsNotifier = ValueNotifier<double>(0.0);

  /// Notifies listeners with the connected phone description (or null if idle).
  final ValueNotifier<String?> connectedPeerNotifier = ValueNotifier<String?>(
    null,
  );

  /// Notifies listeners whether the local Wi-Fi receiver is actively listening.
  final ValueNotifier<bool> isListeningNotifier = ValueNotifier<bool>(false);

  int _framesInWindow = 0;
  DateTime _windowStart = DateTime.now();

  /// Broadcast stream of human-readable status events.
  Stream<String> get logStream => _logController.stream;

  /// Bound TCP port once [startReceiver] succeeds, or 0 when stopped.
  int get boundTcpPort => _tcpServer?.port ?? 0;

  /// Bound UDP discovery port once [startReceiver] succeeds, or 0 when stopped.
  int get boundUdpPort => _udpSocket?.port ?? 0;

  /// Starts the local Wi-Fi TCP frame receiver and UDP discovery responder.
  Future<bool> startReceiver({
    int tcpPort = defaultTcpPort,
    int udpPort = defaultUdpDiscoveryPort,
    bool enableUdpDiscovery = true,
  }) async {
    await stopReceiver();

    try {
      _tcpServer = await ServerSocket.bind(
        InternetAddress.anyIPv4,
        tcpPort,
        shared: true,
      );
      isListeningNotifier.value = true;
      _emitLog(
        '[CAST] Récepteur Wi-Fi prêt sur le port TCP ${_tcpServer!.port} (sans ADB).',
      );

      _tcpServer!.listen(
        _handleIncomingSender,
        onError: (Object err) {
          _emitLog('[CAST-ERR] Erreur serveur TCP : $err');
        },
      );

      if (enableUdpDiscovery) {
        await _startUdpResponder(udpPort, _tcpServer!.port);
      }

      return true;
    } catch (e) {
      _emitLog('[CAST-ERR] Impossible de démarrer le récepteur Wi-Fi : $e');
      await stopReceiver();
      return false;
    }
  }

  Future<void> _startUdpResponder(int udpPort, int advertisedTcpPort) async {
    try {
      _udpSocket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        udpPort,
        reuseAddress: true,
      );
      _udpSocket!.broadcastEnabled = true;

      final hostName = _sanitizeHostName(Platform.localHostname);

      _udpSocket!.listen((RawSocketEvent event) {
        if (event != RawSocketEvent.read) return;
        final datagram = _udpSocket?.receive();
        if (datagram == null) return;

        final message = utf8.decode(datagram.data, allowMalformed: true).trim();
        if (message.startsWith('PIXEL_CAST_DISCOVER')) {
          final reply = utf8.encode(
            'PIXEL_CAST_HERE|$hostName|$advertisedTcpPort',
          );
          _udpSocket?.send(reply, datagram.address, datagram.port);
        }
      });

      _emitLog(
        '[CAST] Découverte auto Wi-Fi active sur UDP ${_udpSocket!.port}.',
      );
    } catch (e) {
      _emitLog(
        '[CAST-WARN] Découverte UDP indisponible ($e) ; connexion par IP directe active.',
      );
    }
  }

  String _sanitizeHostName(String raw) {
    final cleaned = raw.replaceAll('|', '-').trim();
    return cleaned.isEmpty ? 'PC-PixelCast' : cleaned;
  }

  void _handleIncomingSender(Socket client) {
    _activeSenderSocket?.destroy();
    _activeSenderSocket = client;
    client.setOption(SocketOption.tcpNoDelay, true);

    final peerLabel = '${client.remoteAddress.address}:${client.remotePort}';
    connectedPeerNotifier.value = peerLabel;
    _resetFpsCounter();
    _emitLog('[CAST] Téléphone connecté en direct depuis $peerLabel.');

    final buffer = BytesBuilder(copy: false);
    int readOffset = 0;
    Uint8List accumulated = Uint8List(0);

    client.listen(
      (Uint8List chunk) {
        if (readOffset >= accumulated.length) {
          accumulated = chunk;
          readOffset = 0;
        } else {
          buffer.clear();
          buffer.add(Uint8List.sublistView(accumulated, readOffset));
          buffer.add(chunk);
          accumulated = buffer.takeBytes();
          readOffset = 0;
        }

        while (accumulated.length - readOffset >= headerByteLength) {
          // Verify 'PCST' magic; resync byte-by-byte if stream drifted.
          if (accumulated[readOffset] != frameMagic[0] ||
              accumulated[readOffset + 1] != frameMagic[1] ||
              accumulated[readOffset + 2] != frameMagic[2] ||
              accumulated[readOffset + 3] != frameMagic[3]) {
            readOffset++;
            continue;
          }

          final headerView = ByteData.sublistView(
            accumulated,
            readOffset,
            readOffset + headerByteLength,
          );
          final width = headerView.getUint32(4, Endian.big);
          final height = headerView.getUint32(8, Endian.big);
          final payloadLength = headerView.getUint32(12, Endian.big);

          if (payloadLength == 0 || payloadLength > maxFrameBytes) {
            // Invalid length header; advance past magic to resynchronize.
            readOffset += 4;
            continue;
          }

          final totalPacketLength = headerByteLength + payloadLength;
          if (accumulated.length - readOffset < totalPacketLength) {
            // Wait for remaining JPEG payload bytes on next TCP packet.
            break;
          }

          final frameStart = readOffset + headerByteLength;
          final jpegCopy = Uint8List.fromList(
            Uint8List.sublistView(
              accumulated,
              frameStart,
              frameStart + payloadLength,
            ),
          );
          readOffset += totalPacketLength;

          _publishFrame(jpegCopy, width: width, height: height);
        }
      },
      onDone: () {
        if (_activeSenderSocket == client) {
          _activeSenderSocket = null;
          connectedPeerNotifier.value = null;
          fpsNotifier.value = 0.0;
          _emitLog('[CAST] Diffusion arrêtée par le téléphone ($peerLabel).');
        }
      },
      onError: (Object err) {
        if (_activeSenderSocket == client) {
          _activeSenderSocket = null;
          connectedPeerNotifier.value = null;
          fpsNotifier.value = 0.0;
          _emitLog('[CAST-WARN] Flux interrompu ($peerLabel) : $err');
        }
      },
      cancelOnError: true,
    );
  }

  /// Connects as a viewer to an HTTP MJPEG live screen stream hosted on the
  /// phone (e.g. `http://192.168.1.25:8080/stream` from Pixel Wi-Fi Cast or
  /// third-party MJPEG casters).
  Future<bool> connectMjpegStream(String rawInput) async {
    await disconnectMjpegStream();

    final uri = _normalizeStreamUri(rawInput);
    if (uri == null) {
      _emitLog('[CAST-ERR] Adresse de flux invalide : $rawInput');
      return false;
    }

    try {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 4);
      _mjpegHttpClient = client;

      final request = await client.getUrl(uri);
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        _emitLog(
          '[CAST-ERR] Le flux HTTP a répondu ${response.statusCode} sur $uri.',
        );
        await disconnectMjpegStream();
        return false;
      }

      connectedPeerNotifier.value = '${uri.host}:${uri.port}';
      _resetFpsCounter();
      _emitLog('[CAST] Connecté au flux MJPEG en direct : $uri');

      Uint8List pending = Uint8List(0);
      _mjpegSubscription = response.listen(
        (List<int> chunk) {
          final merged = Uint8List(pending.length + chunk.length);
          merged.setRange(0, pending.length, pending);
          merged.setRange(pending.length, merged.length, chunk);

          int searchFrom = 0;
          while (true) {
            final soi = _findMarker(merged, 0xFF, 0xD8, searchFrom);
            if (soi < 0) {
              // Keep at most the trailing byte in case 0xFF sits on boundary.
              pending = merged.isNotEmpty && merged.last == 0xFF
                  ? Uint8List.fromList([0xFF])
                  : Uint8List(0);
              break;
            }

            final eoi = _findMarker(merged, 0xFF, 0xD9, soi + 2);
            if (eoi < 0) {
              pending = Uint8List.fromList(Uint8List.sublistView(merged, soi));
              break;
            }

            final frameEnd = eoi + 2;
            final jpegBytes = Uint8List.fromList(
              Uint8List.sublistView(merged, soi, frameEnd),
            );
            _publishFrame(jpegBytes, width: 0, height: 0);
            searchFrom = frameEnd;

            if (searchFrom >= merged.length) {
              pending = Uint8List(0);
              break;
            }
          }
        },
        onDone: () {
          connectedPeerNotifier.value = null;
          fpsNotifier.value = 0.0;
          _emitLog('[CAST] Flux MJPEG terminé.');
        },
        onError: (Object e) {
          connectedPeerNotifier.value = null;
          fpsNotifier.value = 0.0;
          _emitLog('[CAST-WARN] Erreur lecture MJPEG : $e');
        },
        cancelOnError: true,
      );

      return true;
    } catch (e) {
      _emitLog('[CAST-ERR] Connexion MJPEG impossible vers $uri : $e');
      await disconnectMjpegStream();
      return false;
    }
  }

  Uri? _normalizeStreamUri(String rawInput) {
    var trimmed = rawInput.trim();
    if (trimmed.isEmpty) return null;
    if (!trimmed.startsWith('http://') && !trimmed.startsWith('https://')) {
      trimmed = 'http://$trimmed';
    }
    final parsed = Uri.tryParse(trimmed);
    if (parsed == null || parsed.host.isEmpty) return null;

    final port = parsed.hasPort ? parsed.port : 8080;
    final path = (parsed.path.isEmpty || parsed.path == '/')
        ? '/stream'
        : parsed.path;
    return parsed.replace(port: port, path: path);
  }

  int _findMarker(Uint8List data, int b1, int b2, int start) {
    final limit = data.length - 1;
    for (int i = start; i < limit; i++) {
      if (data[i] == b1 && data[i + 1] == b2) {
        return i;
      }
    }
    return -1;
  }

  void _publishFrame(
    Uint8List jpegBytes, {
    required int width,
    required int height,
  }) {
    final now = DateTime.now();
    frameNotifier.value = CastFrame(
      jpegBytes: jpegBytes,
      width: width,
      height: height,
      receivedAt: now,
    );

    _framesInWindow++;
    final elapsedMs = now.difference(_windowStart).inMilliseconds;
    if (elapsedMs >= 1000) {
      fpsNotifier.value = (_framesInWindow * 1000.0) / elapsedMs;
      _framesInWindow = 0;
      _windowStart = now;
    }
  }

  void _resetFpsCounter() {
    _framesInWindow = 0;
    _windowStart = DateTime.now();
    fpsNotifier.value = 0.0;
  }

  /// Disconnects any active HTTP MJPEG pull session.
  Future<void> disconnectMjpegStream() async {
    await _mjpegSubscription?.cancel();
    _mjpegSubscription = null;
    _mjpegHttpClient?.close(force: true);
    _mjpegHttpClient = null;
  }

  /// Stops both the TCP receiver, UDP discovery socket, and any MJPEG pull.
  Future<void> stopReceiver() async {
    await disconnectMjpegStream();
    _activeSenderSocket?.destroy();
    _activeSenderSocket = null;

    _udpSocket?.close();
    _udpSocket = null;

    await _tcpServer?.close();
    _tcpServer = null;

    isListeningNotifier.value = false;
    connectedPeerNotifier.value = null;
    fpsNotifier.value = 0.0;
  }

  /// Enumerates local IPv4 LAN addresses suitable for Wi-Fi casting.
  Future<List<String>> getLocalLanAddresses() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      final candidates = <String>[];
      for (final iface in interfaces) {
        final lowerName = iface.name.toLowerCase();
        // Skip common virtual hypervisor adapters so real Wi-Fi/LAN shows first.
        final isVirtual = lowerName.contains('vethernet') ||
            lowerName.contains('wsl') ||
            lowerName.contains('docker') ||
            lowerName.contains('vmware') ||
            lowerName.contains('virtualbox');

        for (final addr in iface.addresses) {
          final ip = addr.address;
          if (ip.startsWith('169.254.')) continue;
          if (isVirtual) {
            candidates.add(ip);
          } else {
            candidates.insert(0, ip);
          }
        }
      }
      return candidates.toSet().toList();
    } catch (_) {
      return const [];
    }
  }

  /// Opens Windows built-in Wireless Display / Miracast projection settings
  /// for phones supporting native Miracast (Samsung Smart View, Xiaomi, Tecno).
  Future<bool> openWindowsMiracastSettings() async {
    if (!Platform.isWindows) return false;
    try {
      await Process.run('cmd', ['/c', 'start', 'ms-settings:project']);
      return true;
    } catch (_) {
      return false;
    }
  }

  void _emitLog(String msg) {
    if (!_logController.isClosed) {
      _logController.add(msg);
    }
  }

  /// Releases all sockets and notifiers.
  Future<void> dispose() async {
    await stopReceiver();
    frameNotifier.dispose();
    fpsNotifier.dispose();
    connectedPeerNotifier.dispose();
    isListeningNotifier.dispose();
    await _logController.close();
  }
}
