import 'connection_mode.dart';
import 'device_info.dart';

/// Configuration options and hardware flags passed to the underlying
/// scrcpy mirroring binary.
class ScrcpyOptions {
  /// Maximum width or height of the mirrored video stream in pixels (0 for native).
  final int maxSize;

  /// Video stream encoding bitrate limit in bits per second (default 16 Mbps).
  final int bitRate;

  /// Target frame rate ceiling for the display pipeline.
  final int maxFps;

  /// Whether the device is kept awake while connected to the PC host.
  final bool stayAwake;

  /// Whether the phone's physical screen should be turned off during mirroring
  /// to save battery and protect OLED panels.
  ///
  /// On standard Android devices (Samsung, Xiaomi, Tecno, Infinix, Oppo, etc.),
  /// native `--turn-screen-off` is passed to `scrcpy`. On Google Pixel / Tensor
  /// devices where `POWER_MODE_OFF` blanks the hardware video encoder, software
  /// brightness dimming is automatically used instead.
  final bool turnScreenOff;

  /// Whether physical display backlight is forced to 0 through software settings
  /// rather than invoking `--turn-screen-off`.
  final bool useBrightnessWorkaround;

  /// Whether audio streaming is forwarded from the phone to host speakers.
  final bool audioEnabled;

  /// Whether touch indicators are drawn on the mirrored stream.
  final bool showTouches;

  /// Whether physical hardware keyboard events are synthesized via Linux UHID
  /// (automatically skipped on Android 8–10 devices with SDK < 30).
  final bool uhidKeyboard;

  /// Whether to disable computer input controls (mouse, keyboard, touch events).
  ///
  /// In cast/presentation mode (`--no-control`), the phone screen is simply
  /// projected to the PC monitor without intercepting input, leaving the physical
  /// device's touchscreen fully functional for normal use.
  final bool noControl;

  /// Target physical display identifier on Android (defaulting to 0).
  ///
  /// Explicitly specifying 0 prevents scrcpy from attaching to phantom or
  /// virtual displays created during previous sessions.
  final int displayId;

  /// Creates a [ScrcpyOptions] instance with universal defaults compatible
  /// across all Android smartphones (Android 8.0+).
  const ScrcpyOptions({
    this.maxSize = 0,
    this.bitRate = 16000000,
    this.maxFps = 60,
    this.stayAwake = true,
    this.turnScreenOff = false,
    this.useBrightnessWorkaround = false,
    this.audioEnabled = true,
    this.showTouches = false,
    this.uhidKeyboard = true,
    this.noControl = false,
    this.displayId = 0,
  });

  /// Computes the exact list of command line arguments for the scrcpy process.
  List<String> toArguments({DeviceInfo? device}) {
    final args = <String>[];

    // Explicit device targeting to avoid ADB multi-device ambiguity.
    if (device != null) {
      if (device.connectionMode == ConnectionMode.usb) {
        args.add('-d');
      } else {
        args.addAll(['-s', device.serial]);
      }
    }

    // Force binding to the primary physical display.
    args.add('--display-id=$displayId');

    // Resolution and performance constraints.
    if (maxSize > 0) {
      args.add('--max-size=$maxSize');
    }
    if (bitRate > 0) {
      args.add('--video-bit-rate=$bitRate');
    }
    if (maxFps > 0) {
      args.add('--max-fps=$maxFps');
    }

    // Power and input preferences.
    if (stayAwake && !noControl) {
      args.add('--stay-awake');
    }
    final isPixel = device?.isGooglePixel ?? false;
    if (turnScreenOff && !useBrightnessWorkaround && !isPixel && !noControl) {
      args.add('--turn-screen-off');
    }
    final supportsUhid = device?.sdkInt == null || device!.sdkInt! >= 30;
    if (noControl) {
      args.add('--no-control');
    } else if (uhidKeyboard && supportsUhid) {
      args.add('--keyboard=uhid');
    }
    if (showTouches) {
      args.add('--show-touches');
    }
    if (!audioEnabled || (device?.sdkInt != null && device!.sdkInt! < 30)) {
      args.add('--no-audio');
    }

    return args;
  }

  /// Returns a copy of these options with updated configuration values.
  ScrcpyOptions copyWith({
    int? maxSize,
    int? bitRate,
    int? maxFps,
    bool? stayAwake,
    bool? turnScreenOff,
    bool? useBrightnessWorkaround,
    bool? audioEnabled,
    bool? showTouches,
    bool? uhidKeyboard,
    bool? noControl,
    int? displayId,
  }) {
    return ScrcpyOptions(
      maxSize: maxSize ?? this.maxSize,
      bitRate: bitRate ?? this.bitRate,
      maxFps: maxFps ?? this.maxFps,
      stayAwake: stayAwake ?? this.stayAwake,
      turnScreenOff: turnScreenOff ?? this.turnScreenOff,
      useBrightnessWorkaround:
          useBrightnessWorkaround ?? this.useBrightnessWorkaround,
      audioEnabled: audioEnabled ?? this.audioEnabled,
      showTouches: showTouches ?? this.showTouches,
      uhidKeyboard: uhidKeyboard ?? this.uhidKeyboard,
      noControl: noControl ?? this.noControl,
      displayId: displayId ?? this.displayId,
    );
  }
}
