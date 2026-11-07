import 'dart:async';
import 'package:flutter/material.dart';

import '../../models/device_info.dart';
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
      final rawDevices = await _adbService.getConnectedDevices();
      final enriched = <DeviceInfo>[];

      for (final dev in rawDevices) {
        final withBattery = await _adbService.enrichDeviceTelemetry(dev);
        enriched.add(withBattery);
      }

      if (!mounted) return;
      setState(() {
        _devices = enriched;
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

  Future<void> _startCastOnly() async {
    if (_isCastScreenOpen || !mounted) return;
    _isCastScreenOpen = true;
    _addLog(
      '[CAST] Ouverture du récepteur Cast Wi-Fi Direct (sans mode débogage ni ADB)...',
    );
    try {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => WifiCastScreen(castService: _wifiCastService),
        ),
      );
    } finally {
      _isCastScreenOpen = false;
    }
  }

  Future<void> _autoConnectWifi() async {
    _addLog('[DISCOVERY] Lancement de la découverte dynamique d\'adresse IP...');
    setState(() {
      _isScanning = true;
    });

    try {
      final ip = await _discoveryService.discoverDeviceIp(
        knownUsbDevice: _devices.where((d) => d.isUsb).firstOrNull,
      );

      if (ip == null) {
        _addLog('[ERROR] Aucune adresse IP trouvée sur le réseau local.');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Appareil introuvable. Vérifiez que le Wi-Fi et le débogage sans fil sont activés.',
              ),
            ),
          );
        }
        return;
      }

      _addLog('[DISCOVERY] IP trouvée : $ip. Connexion TCP/IP sur le port 5555...');
      final connected = await _adbService.connectWifi(ip);

      if (connected) {
        _addLog('[SUCCESS] Connecté avec succès à $ip:5555 !');
        await _refreshDevices();
      } else {
        _addLog('[WARN] Échec de connexion directe à $ip. Activation via USB...');
        final usbDev = _devices.where((d) => d.isUsb).firstOrNull;
        if (usbDev != null) {
          await _adbService.switchDeviceToTcpip(usbDev);
          final retry = await _adbService.connectWifi(ip);
          if (retry) {
            _addLog('[SUCCESS] Connecté avec succès après basculement TCP/IP !');
            await _refreshDevices();
          }
        }
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
