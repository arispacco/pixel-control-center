import 'dart:async';
import 'package:flutter/material.dart';

import '../../models/device_info.dart';
import '../../models/discovered_peer.dart';
import '../../models/scrcpy_options.dart';
import '../../services/adb_service.dart';
import '../../services/network_discovery_service.dart';
import '../../services/scrcpy_service.dart';
import '../../services/wifi_cast_service.dart';
import '../widgets/device_status_card.dart';
import '../widgets/log_console.dart';
import '../widgets/media_controls_panel.dart';
import '../widgets/quick_actions_panel.dart';
import 'wifi_cast_screen.dart';

/// Main desktop screen providing full device supervision, screen mirroring
/// triggers, remote control buttons, and real-time execution logs.
class DashboardScreen extends StatefulWidget {
  /// Creates the [DashboardScreen] widget.
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late final AdbService _adbService;
  late final ScrcpyService _scrcpyService;
  late final NetworkDiscoveryService _discoveryService;
  late final WifiCastService _wifiCastService;

  StreamSubscription<String>? _logSubscription;
  StreamSubscription<String>? _castLogSubscription;
  final List<String> _logs = [];
  bool _isCastScreenOpen = false;

  List<DeviceInfo> _devices = [];
  List<DiscoveredPeer> _lanPeers = [];
  DeviceInfo? _selectedDevice;
  bool _isScanning = false;

  @override
  void initState() {
    super.initState();
    _adbService = AdbService();
    _scrcpyService = ScrcpyService(adbService: _adbService);
    _discoveryService = NetworkDiscoveryService(adbService: _adbService);
    _wifiCastService = WifiCastService();

    _logSubscription = _scrcpyService.logStream.listen((logLine) {
      if (!mounted) return;
      setState(() {
        _logs.add(logLine);
      });
    });

    _castLogSubscription = _wifiCastService.logStream.listen((logLine) {
      if (!mounted) return;
      setState(() {
        _logs.add(logLine);
      });
    });

    _wifiCastService.connectedPeerNotifier.addListener(_onIncomingWifiCast);
    unawaited(_wifiCastService.startReceiver());

    _refreshDevices();
  }

  void _onIncomingWifiCast() {
    final peer = _wifiCastService.connectedPeerNotifier.value;
    if (peer != null && !_isCastScreenOpen && mounted) {
      unawaited(_startCastOnly());
    }
  }

  @override
  void dispose() {
    _wifiCastService.connectedPeerNotifier.removeListener(_onIncomingWifiCast);
    _logSubscription?.cancel();
    _castLogSubscription?.cancel();
    _scrcpyService.dispose();
    unawaited(_wifiCastService.dispose());
    super.dispose();
  }

  void _addLog(String message) {
    if (!mounted) return;
    setState(() {
      _logs.add(message);
    });
  }

  Future<void> _refreshDevices() async {
    setState(() {
      _isScanning = true;
    });

    try {
      var rawDevices = await _adbService.getConnectedDevices();
      final lanPeers = await _discoveryService.discoverLanPeers(
        knownUsbDevice: rawDevices.where((d) => d.isUsb).firstOrNull,
        scanFullSubnet: false,
      );

      // Auto-connect wireless ADB if a dynamic mDNS or :5555 endpoint was discovered.
      if (rawDevices.where((d) => d.isWifi).isEmpty) {
        final readyAdb = lanPeers.where((p) => p.adbPort != null).firstOrNull;
        if (readyAdb != null) {
          final connected = await _adbService.connectWifi(
            readyAdb.ip,
            port: readyAdb.adbPort!,
          );
          if (connected) {
            _addLog(
              '[AUTO-ADB] Connecté automatiquement à ${readyAdb.ip}:${readyAdb.adbPort}',
            );
            rawDevices = await _adbService.getConnectedDevices();
          }
        }
      }

      final enriched = <DeviceInfo>[];
      for (final dev in rawDevices) {
        final withBattery = await _adbService.enrichDeviceTelemetry(dev);
        enriched.add(withBattery);
      }

      if (!mounted) return;
      setState(() {
        _devices = enriched;
        _lanPeers = lanPeers;
        if (enriched.isNotEmpty) {
          // Prefer USB connection if available.
          _selectedDevice = enriched.firstWhere(
            (d) => d.isUsb,
            orElse: () => enriched.first,
          );
        } else {
          _selectedDevice = null;
        }
      });
    } finally {
      if (mounted) {
        setState(() {
          _isScanning = false;
        });
      }
    }
  }

  Future<void> _startUsbMirroring() async {
    if (_devices.where((d) => d.isUsb).isEmpty) {
      await _refreshDevices();
    }

    final usbDev = _devices.where((d) => d.isUsb).firstOrNull;
    if (usbDev == null) {
      _addLog(
        '[WARN] Aucun téléphone Android détecté en USB. Activez le débogage USB ou utilisez le Cast Wi-Fi Direct (sans débogage).',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Aucun téléphone Android détecté en USB. Vérifiez le câble / débogage USB ou utilisez le Cast Wi-Fi Direct.',
            ),
          ),
        );
      }
      return;
    }

    _addLog(
      '[ACTION] Lancement du contrôle USB pour ${usbDev.displayName} (${usbDev.serial})...',
    );
    final ok = await _scrcpyService.startMirroring(
      device: usbDev,
      options: const ScrcpyOptions(
        stayAwake: true,
      ),
    );

    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Impossible de lancer l\'affichage USB.')),
      );
    }
  }

  Future<void> _startWifiMirroring() async {
    final wifiDev = _devices.where((d) => d.isWifi).firstOrNull;

    if (wifiDev == null) {
      _addLog('[INFO] Aucun endpoint Wi-Fi actif, tentative d\'auto-détection...');
      await _autoConnectWifi();
      return;
    }

    _addLog(
      '[ACTION] Lancement du contrôle Wi-Fi pour ${wifiDev.displayName} (${wifiDev.serial})...',
    );
    final ok = await _scrcpyService.startMirroring(
      device: wifiDev,
      options: const ScrcpyOptions(
        stayAwake: true,
      ),
    );

    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Échec du démarrage de l\'affichage Wi-Fi.')),
      );
    }
  }

  Future<void> _startScreenOffMirroring() async {
    final dev = _selectedDevice;
    if (dev == null) {
      _addLog('[WARN] Veuillez connecter un appareil avant de lancer le mode écran éteint.');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Connectez d\'abord votre téléphone Android en USB ou Wi-Fi ADB.'),
          ),
        );
      }
      return;
    }

    _addLog(
      '[ACTION] Lancement en mode écran éteint pour ${dev.displayName}...',
    );
    await _scrcpyService.startMirroring(
      device: dev,
      options: const ScrcpyOptions(
        stayAwake: true,
        turnScreenOff: true,
      ),
    );
  }

  Future<void> _startCastOnly({String? initialEndpoint}) async {
    if (_isCastScreenOpen || !mounted) return;
    _isCastScreenOpen = true;
    _addLog(
      '[CAST] Ouverture du récepteur Cast Wi-Fi Direct (sans mode débogage ni ADB)...',
    );
    try {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => WifiCastScreen(
            castService: _wifiCastService,
            discoveryService: _discoveryService,
            initialMjpegEndpoint: initialEndpoint,
          ),
        ),
      );
    } finally {
      _isCastScreenOpen = false;
    }
  }

  Future<void> _autoConnectWifi() async {
    _addLog(
      '[DISCOVERY] Scan intelligent du réseau Wi-Fi / Hotspot (mDNS + Passerelle + ARP + ports 5555/8080)...',
    );
    setState(() {
      _isScanning = true;
    });

    try {
      final usbDev = _devices.where((d) => d.isUsb).firstOrNull;
      final peers = await _discoveryService.discoverLanPeers(
        knownUsbDevice: usbDev,
        scanFullSubnet: true,
      );

      if (mounted) {
        setState(() {
          _lanPeers = peers;
        });
      }

      if (peers.isEmpty) {
        _addLog('[ERROR] Aucun appareil actif détecté sur ce sous-réseau Wi-Fi.');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Aucun appareil détecté sur le Wi-Fi. Vérifiez que le téléphone et le PC sont sur le même réseau ou partage de connexion.',
              ),
            ),
          );
        }
        return;
      }

      // 1. Check if a phone is actively streaming Zero-ADB Wi-Fi Cast (:8080).
      final castPeer = peers.where((p) => p.castHttpPort != null).firstOrNull;
      if (castPeer != null &&
          peers.where((p) => p.adbPort != null).isEmpty &&
          usbDev == null) {
        final endpoint = '${castPeer.ip}:${castPeer.castHttpPort}';
        _addLog('[CAST] Flux Android Wi-Fi Cast détecté sur $endpoint ! Ouverture directe...');
        await _startCastOnly(initialEndpoint: endpoint);
        return;
      }

      // 2. Check if an ADB endpoint (classic :5555 or dynamic Android 11+ mDNS port) is open.
      final adbPeer = peers.where((p) => p.adbPort != null).firstOrNull;
      if (adbPeer != null) {
        final port = adbPeer.adbPort!;
        _addLog('[DISCOVERY] Endpoint ADB trouvé : ${adbPeer.ip}:$port. Connexion...');
        final connected = await _adbService.connectWifi(adbPeer.ip, port: port);
        if (connected) {
          _addLog('[SUCCESS] Connecté avec succès à ${adbPeer.ip}:$port !');
          await _refreshDevices();
          return;
        }
      }

      // 3. If USB cable is plugged in, enable tcpip 5555 on the phone and connect to its Wi-Fi IP.
      final targetIp = peers.first.ip;
      if (usbDev != null) {
        _addLog(
          '[INFO] Téléphone détecté sur $targetIp — activation du port TCP 5555 via le câble USB...',
        );
        await _adbService.switchDeviceToTcpip(usbDev);
        final retry = await _adbService.connectWifi(targetIp);
        if (retry) {
          _addLog('[SUCCESS] Connecté sans fil à $targetIp:5555 !');
          await _refreshDevices();
          return;
        }
      }

      // 4. Phone IP(s) ARE detected on Wi-Fi / Hotspot, explain clearly that ADB port is closed.
      final summary = peers.map((p) => p.summaryLabel).join(', ');
      _addLog(
        '[DISCOVERY] Appareil(s) trouvé(s) sur le Wi-Fi : $summary — port ADB fermé. Pour caster sans débogage, lancez "Android Wi-Fi Cast" sur le téléphone ; pour ADB, branchez 1 fois en USB.',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 6),
            content: Text(
              'Téléphone détecté sur $targetIp ! Port ADB fermé : ouvrez "Android Wi-Fi Cast" pour caster sans débogage, ou branchez 1x en USB.',
            ),
            action: SnackBarAction(
              label: 'Ouvrir Cast',
              onPressed: () => _startCastOnly(initialEndpoint: '$targetIp:8080'),
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isScanning = false;
        });
      }
    }
  }

  Future<void> _sendKeyEvent(int keyCode) async {
    final dev = _selectedDevice;
    if (dev == null) return;
    _addLog('[INPUT] Envoi du keyevent $keyCode...');
    await _adbService.sendKeyEvent(dev, keyCode);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(Icons.bolt, color: Colors.amber),
            const SizedBox(width: 8),
            const Text(
              'Pixel Control Center',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white10,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'Universal Android • v1.1.0',
                style: TextStyle(fontSize: 11, color: Colors.white70),
              ),
            ),
          ],
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          children: [
            DeviceStatusCard(
              device: _selectedDevice,
              lanPeers: _lanPeers,
              isScanning: _isScanning,
              onRefresh: _refreshDevices,
            ),
            const SizedBox(height: 8),
            QuickActionsPanel(
              device: _selectedDevice,
              isMirroring: _scrcpyService.isMirroring,
              onStartUsb: _startUsbMirroring,
              onStartWifi: _startWifiMirroring,
              onStartScreenOff: _startScreenOffMirroring,
              onStartCast: _startCastOnly,
              onAutoConnectWifi: _autoConnectWifi,
              onStopMirroring: () => _scrcpyService.stopMirroring(),
            ),
            const SizedBox(height: 8),
            MediaControlsPanel(
              device: _selectedDevice,
              onSendKeyEvent: _sendKeyEvent,
            ),
            const SizedBox(height: 8),
            LogConsole(
              logs: _logs,
              onClear: () {
                setState(() {
                  _logs.clear();
                });
              },
            ),
          ],
        ),
      ),
    );
  }
}
