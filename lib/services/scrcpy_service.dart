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
  }) : scrcpyPath = customScrcpyPath ?? _findScrcpyExecutable();

  /// Locates the `scrcpy` executable on the host machine.
  static String _findScrcpyExecutable() {
    if (Platform.isWindows) {
      final localAppData = Platform.environment['LOCALAPPDATA'] ?? '';
      final wingetPath =
          '$localAppData\\Microsoft\\WinGet\\Packages\\Genymobile.scrcpy_Microsoft.Winget.Source_8wekyb3d8bbwe\\scrcpy-win64-v5.0.1\\scrcpy.exe';
      if (File(wingetPath).existsSync()) {
        return wingetPath;
      }
      return 'scrcpy.exe';
    }
    return 'scrcpy';
  }

  /// Launches a new scrcpy mirroring session targeted at [device] with the
  /// given [options].
  ///
  /// Applies Pixel 7 Pro hardware fixes (virtual keyboard visibility and OLED
  /// brightness dimming) prior to launching.
  Future<bool> startMirroring({
    required DeviceInfo device,
    ScrcpyOptions options = const ScrcpyOptions(),
  }) async {
    if (isMirroring) {
      _logController.add('[WARN] Une session scrcpy est déjà en cours d\'exécution.');
      return false;
    }

    // Apply Android hardware settings before launch.
    await adbService.ensureVirtualKeyboardVisible(device);
    if (options.useBrightnessWorkaround) {
      _logController.add('[INFO] Réduction de la luminosité écran (workaround Tensor G2)...');
      await adbService.setScreenBrightness(device, dim: true);
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

        // Restore screen brightness when session finishes.
        if (options.useBrightnessWorkaround) {
          _logController.add('[INFO] Restauration de la luminosité écran normale...');
          await adbService.setScreenBrightness(device, dim: false);
        }
      }));

      return true;
    } catch (e) {
      _logController.add('[ERROR] Échec du lancement de scrcpy: $e');
      _activeProcess = null;

      if (options.useBrightnessWorkaround) {
        await adbService.setScreenBrightness(device, dim: false);
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
