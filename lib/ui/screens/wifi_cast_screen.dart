import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../models/cast_frame.dart';
import '../../models/discovered_peer.dart';
import '../../services/adb_service.dart';
import '../../services/network_discovery_service.dart';
import '../../services/wifi_cast_service.dart';
import '../theme.dart';

/// Dedicated zero-ADB live Wi-Fi screen casting view.
///
/// Displays live JPEG frames streamed directly over local Wi-Fi (`MediaProjection`
/// TCP push or outbound HTTP MJPEG pull) without requiring Developer Options,
/// USB Debugging, or ADB commands on the phone.
class WifiCastScreen extends StatefulWidget {
  /// Backing Wi-Fi receiver and MJPEG client service.
  final WifiCastService castService;

  /// Optional LAN discovery service used to auto-detect phone IPs on Wi-Fi / Hotspot.
  final NetworkDiscoveryService? discoveryService;

  /// Optional pre-discovered `host:port` stream to open immediately on launch.
  final String? initialMjpegEndpoint;

  /// Creates the [WifiCastScreen].
  const WifiCastScreen({
    super.key,
    required this.castService,
    this.discoveryService,
    this.initialMjpegEndpoint,
  });

  @override
  State<WifiCastScreen> createState() => _WifiCastScreenState();
}

class _WifiCastScreenState extends State<WifiCastScreen> {
  final TextEditingController _mjpegUrlController = TextEditingController();
  late final NetworkDiscoveryService _discoveryService;
  List<String> _localIps = const [];
  List<DiscoveredPeer> _detectedPeers = const [];
  int _quarterTurns = 0;
  bool _isPaused = false;
  CastFrame? _frozenFrame;
  bool _isConnectingMjpeg = false;
  bool _isScanningLan = false;

  @override
  void initState() {
    super.initState();
    _discoveryService = widget.discoveryService ??
        NetworkDiscoveryService(adbService: AdbService());
    if (widget.initialMjpegEndpoint != null &&
        widget.initialMjpegEndpoint!.isNotEmpty) {
      _mjpegUrlController.text = widget.initialMjpegEndpoint!;
    }
    _bootReceiver();
  }

  Future<void> _bootReceiver() async {
    if (!widget.castService.isListeningNotifier.value) {
      await widget.castService.startReceiver();
    }
    final ips = await widget.castService.getLocalLanAddresses();
    if (mounted) {
      setState(() {
        _localIps = ips;
      });
    }
    if (widget.initialMjpegEndpoint != null &&
        widget.initialMjpegEndpoint!.isNotEmpty) {
      await _connectToMjpeg();
    } else {
      unawaited(_scanWifiForPhones(autoConnectIfStreamOpen: true));
    }
  }

  Future<void> _scanWifiForPhones({bool autoConnectIfStreamOpen = true}) async {
    if (_isScanningLan || !mounted) return;
    setState(() {
      _isScanningLan = true;
    });

    try {
      final peers = await _discoveryService.discoverLanPeers(
        scanFullSubnet: true,
      );
      if (!mounted) return;

      setState(() {
        _detectedPeers = peers;
        if (_mjpegUrlController.text.trim().isEmpty && peers.isNotEmpty) {
          final first = peers.first;
          final port = first.castHttpPort ??
              NetworkDiscoveryService.defaultCastHttpPort;
          _mjpegUrlController.text = '${first.ip}:$port';
        }
      });

      if (autoConnectIfStreamOpen &&
          widget.castService.connectedPeerNotifier.value == null) {
        final activeCast =
            peers.where((p) => p.castHttpPort != null).firstOrNull;
        if (activeCast != null) {
          final target = '${activeCast.ip}:${activeCast.castHttpPort}';
          _mjpegUrlController.text = target;
          await _connectToMjpeg();
        }
      }
    } finally {
      if (mounted) {
        setState(() {
          _isScanningLan = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _mjpegUrlController.dispose();
    super.dispose();
  }

  Future<void> _connectToMjpeg() async {
    final target = _mjpegUrlController.text.trim();
    if (target.isEmpty) return;

    setState(() {
      _isConnectingMjpeg = true;
    });

    final ok = await widget.castService.connectMjpegStream(target);
    if (!mounted) return;

    setState(() {
      _isConnectingMjpeg = false;
    });

    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Impossible d\'ouvrir le flux Wi-Fi sur "$target". Vérifiez que le téléphone diffuse bien sur le même Wi-Fi.',
          ),
        ),
      );
    }
  }

  void _togglePause(CastFrame? current) {
    setState(() {
      _isPaused = !_isPaused;
      _frozenFrame = _isPaused ? current : null;
    });
  }

  void _rotateView() {
    setState(() {
      _quarterTurns = (_quarterTurns + 1) % 4;
    });
  }

  Future<void> _disconnectActiveStream() async {
    await widget.castService.stopReceiver();
    widget.castService.frameNotifier.value = null;
    setState(() {
      _isPaused = false;
      _frozenFrame = null;
    });
    await _bootReceiver();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.cast_connected, color: AppTheme.secondary),
            SizedBox(width: 10),
            Text(
              'Cast Wi-Fi en Direct (Sans Mode Débogage)',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
            ),
          ],
        ),
        actions: [
          ValueListenableBuilder<String?>(
            valueListenable: widget.castService.connectedPeerNotifier,
            builder: (context, peer, _) {
              if (peer == null) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: 'Pivoter l\'image (90°)',
                      onPressed: _rotateView,
                      icon: const Icon(Icons.screen_rotation_alt),
                    ),
                    IconButton(
                      tooltip: _isPaused
                          ? 'Reprendre le direct'
                          : 'Figer l\'image',
                      onPressed: () =>
                          _togglePause(widget.castService.frameNotifier.value),
                      icon: Icon(
                        _isPaused ? Icons.play_arrow : Icons.pause_circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    FilledButton.tonalIcon(
                      onPressed: _disconnectActiveStream,
                      icon: const Icon(Icons.stop, size: 18),
                      label: const Text('Arrêter'),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
      body: ValueListenableBuilder<String?>(
        valueListenable: widget.castService.connectedPeerNotifier,
        builder: (context, connectedPeer, _) {
          return ValueListenableBuilder<CastFrame?>(
            valueListenable: widget.castService.frameNotifier,
            builder: (context, liveFrame, _) {
              final displayFrame = _isPaused ? _frozenFrame : liveFrame;
              if (connectedPeer != null && displayFrame != null) {
                return _buildLiveStreamStage(connectedPeer, displayFrame);
              }
              return _buildWaitingGuide();
            },
          );
        },
      ),
    );
  }

  Widget _buildLiveStreamStage(String peer, CastFrame frame) {
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: Colors.black38,
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: _isPaused ? Colors.amber : Colors.greenAccent,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _isPaused
                        ? 'IMAGE FIGÉE • $peer'
                        : 'EN DIRECT PAR WI-FI • $peer',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (frame.width > 0 && frame.height > 0)
                    Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: Text(
                        '${frame.width} × ${frame.height} px',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ValueListenableBuilder<double>(
                    valueListenable: widget.castService.fpsNotifier,
                    builder: (context, fps, _) {
                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.surface,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${fps.toStringAsFixed(1)} FPS • Lecture seule (Tactile téléphone actif)',
                          style: const TextStyle(
                            color: AppTheme.secondary,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: Container(
            width: double.infinity,
            color: Colors.black,
            padding: const EdgeInsets.all(8),
            child: Center(
              child: RotatedBox(
                quarterTurns: _quarterTurns,
                child: Image.memory(
                  frame.jpegBytes,
                  gaplessPlayback: true,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.medium,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildWaitingGuide() {
    final hostName = Platform.localHostname;
    final ipSummary = _localIps.isEmpty
        ? 'Recherche Wi-Fi local...'
        : _localIps.map((ip) => '$ip:${widget.castService.boundTcpPort}').join('  •  ');

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: AppTheme.secondary.withValues(alpha: 0.16),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.wifi_tethering,
                              color: AppTheme.secondary,
                              size: 28,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Prêt à recevoir l\'écran en direct par Wi-Fi',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Ordinateur : $hostName  •  $ipSummary',
                                  style: const TextStyle(
                                    color: AppTheme.primary,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      const Divider(height: 1),
                      const SizedBox(height: 16),
                      const _SimpleStepTile(
                        number: '1',
                        title:
                            'Universel (Samsung, Xiaomi, Tecno, Infinix, Oppo, Pixel…) — Sans Mode Débogage',
                        subtitle:
                            'Connectez n\'importe quel téléphone Android (8.0+) et ce PC au même Wi-Fi, ou activez simplement le Partage de connexion du téléphone (0 Mo d\'internet consommé).',
                      ),
                      const SizedBox(height: 12),
                      _SimpleStepTile(
                        number: '2',
                        title:
                            'Ouvrez « Android Wi-Fi Cast » sur le téléphone et appuyez sur Caster',
                        subtitle:
                            'Cet ordinateur ($hostName) apparaît automatiquement sur votre téléphone. Acceptez la fenêtre standard Android « Commencer la diffusion » : l\'image s\'affiche aussitôt ici et le tactile de votre téléphone reste 100 % libre.',
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Expanded(
                            child: Text(
                              'Détection Automatique des Téléphones sur le Wi-Fi / Hotspot',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                          ),
                          OutlinedButton.icon(
                            onPressed: _isScanningLan
                                ? null
                                : () => _scanWifiForPhones(
                                      autoConnectIfStreamOpen: true,
                                    ),
                            icon: _isScanningLan
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.radar, size: 16),
                            label: Text(
                              _isScanningLan
                                  ? 'Scan Wi-Fi...'
                                  : 'Scanner le Wi-Fi',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Contourne automatiquement le pare-feu Windows Public : sélectionnez le téléphone détecté sur votre Wi-Fi ou entrez son adresse locale (ex: http://10.29.128.223:8080) :',
                        style: TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                      if (_detectedPeers.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _detectedPeers.map((peer) {
                            final port = peer.castHttpPort ??
                                NetworkDiscoveryService.defaultCastHttpPort;
                            final isReady = peer.castHttpPort != null;
                            return ActionChip(
                              avatar: Icon(
                                isReady
                                    ? Icons.cast_connected
                                    : Icons.smartphone,
                                size: 16,
                                color: isReady
                                    ? AppTheme.secondary
                                    : AppTheme.primary,
                              ),
                              label: Text(peer.summaryLabel),
                              onPressed: () {
                                _mjpegUrlController.text = '${peer.ip}:$port';
                                _connectToMjpeg();
                              },
                            );
                          }).toList(),
                        ),
                      ],
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _mjpegUrlController,
                              onSubmitted: (_) => _connectToMjpeg(),
                              decoration: const InputDecoration(
                                hintText: 'Ex: 192.168.100.45:8080',
                                prefixIcon: Icon(Icons.link),
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          FilledButton.icon(
                            onPressed:
                                _isConnectingMjpeg ? null : _connectToMjpeg,
                            icon: const Icon(Icons.play_circle_fill),
                            label: Text(
                              _isConnectingMjpeg
                                  ? 'Connexion...'
                                  : 'Ouvrir le Flux',
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              if (Platform.isWindows) ...[
                const SizedBox(height: 12),
                Card(
                  child: ListTile(
                    leading: const Icon(
                      Icons.desktop_windows_outlined,
                      color: AppTheme.wifiColor,
                    ),
                    title: const Text(
                      'Téléphones Samsung (Smart View), Xiaomi, Tecno ou Infinix ?',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: const Text(
                      'Ouvrir les paramètres natifs « Projection sur ce PC » (Miracast Windows) pour caster sans aucune application.',
                    ),
                    trailing: OutlinedButton(
                      onPressed: widget.castService.openWindowsMiracastSettings,
                      child: const Text('Miracast Windows'),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SimpleStepTile extends StatelessWidget {
  final String number;
  final String title;
  final String subtitle;

  const _SimpleStepTile({
    required this.number,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 14,
          backgroundColor: AppTheme.primary.withValues(alpha: 0.2),
          child: Text(
            number,
            style: const TextStyle(
              color: AppTheme.primary,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
