import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/device_info.dart';
import '../models/scrcpy_options.dart';
import 'adb_service.dart';

/// Supervises and monitors the lifecycle of the external `scrcpy` mirroring process.
///
/// Handles command construction, subprocess launching, standard stream streaming,
/// and automatic screen brightness restoration upon termination.
class ScrcpyService {
  /// Executable name or file system path to the `scrcpy` binary.
  final String scrcpyPath;

  /// Underlying ADB service utilized for device configuration and hardware fixes.
  final AdbService adbService;

  /// Active subprocess instance, or `null` when mirroring is inactive.
  Process? _activeProcess;

  /// Stream controller broadcasting log output lines captured from scrcpy.
  final StreamController<String> _logController =
      StreamController<String>.broadcast();

  /// Stream of textual log messages emitted by standard out and standard error.
  Stream<String> get logStream => _logController.stream;

  /// Whether an active scrcpy mirroring session is currently running.
  bool get isMirroring => _activeProcess != null;

  /// Creates a [ScrcpyService] instance with the specified [adbService] and
  /// optional custom binary path.
  ScrcpyService({
    required this.adbService,
    String? customScrcpyPath,
  }) : scrcpyPath =
            customScrcpyPath ?? AdbService.findBundledExecutable('scrcpy');

  /// Launches a new scrcpy mirroring session targeted at [device] with the
  /// given [options].
  ///
  /// Automatically adapts to all Android OEMs (Samsung, Xiaomi, Tecno, Infinix,
  /// Oppo, Vivo, OnePlus, Google Pixel): applies native `--turn-screen-off` on
  /// standard chipsets and falls back to software brightness preservation on
  /// Google Tensor hardware.
  Future<bool> startMirroring({
    required DeviceInfo device,
    ScrcpyOptions options = const ScrcpyOptions(),
  }) async {
    if (isMirroring) {
      _logController.add('[WARN] Une session scrcpy est déjà en cours d\'exécution.');
      return false;
    }

    final shouldDimSoftware = options.useBrightnessWorkaround ||
        (options.turnScreenOff && device.isGooglePixel);
    ScreenBrightnessSnapshot? savedBrightness;

    // Prepare Android display and input state before launch.
    await adbService.terminateRemoteServerProcesses(device);
    if (!options.noControl) {
      await adbService.sendKeyEvent(device, 224);
      await adbService.unlockKeyguard(device);
      await adbService.ensureVirtualKeyboardVisible(device);
    }

    if (shouldDimSoftware) {
      _logController.add(
        '[INFO] Extinction logicielle OLED activée (compatibilité Google Tensor) — sauvegarde de la luminosité actuelle...',
      );
      savedBrightness = await adbService.captureAndDimScreen(device);
    } else if (options.turnScreenOff) {
      _logController.add(
        '[INFO] Extinction matérielle de l\'écran activée (--turn-screen-off) pour ${device.displayName}...',
      );
    }

    final arguments = options.toArguments(device: device);
    _logController.add('[RUN] $scrcpyPath ${arguments.join(' ')}');

    try {
      final process = await Process.start(
        scrcpyPath,
        arguments,
        mode: ProcessStartMode.normal,
      );

      _activeProcess = process;

      // Pipe standard out into the log stream.
      process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        _logController.add('[STDOUT] $line');
      });

      // Pipe standard error into the log stream.
      process.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        _logController.add('[STDERR] $line');
      });

      // Handle process completion asynchronously.
      unawaited(process.exitCode.then((code) async {
        _logController.add('[INFO] Session scrcpy terminée avec le code de sortie: $code');
        _activeProcess = null;

        // Restore exact saved brightness and adaptive mode when session finishes.
        if (shouldDimSoftware) {
          _logController.add('[INFO] Restauration de la luminosité d\'origine...');
          await adbService.restoreScreenBrightness(device, savedBrightness);
        }
      }));

      return true;
    } catch (e) {
      _logController.add('[ERROR] Échec du lancement de scrcpy: $e');
      _activeProcess = null;

      if (shouldDimSoftware) {
        await adbService.restoreScreenBrightness(device, savedBrightness);
      }
      return false;
    }
  }

  /// Terminates the running mirroring process if active.
  Future<void> stopMirroring() async {
    final process = _activeProcess;
    if (process != null) {
      _logController.add('[INFO] Arrêt manuel de la session scrcpy...');
      process.kill();
      _activeProcess = null;
    }
  }

  /// Closes internal stream controllers and releases system resources.
  void dispose() {
    _logController.close();
  }
}
