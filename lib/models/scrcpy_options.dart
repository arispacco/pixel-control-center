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

  /// Whether physical display backlight is lowered to 0 through software settings
  /// rather than invoking `--turn-screen-off`.
  ///
  /// On Google Tensor SoCs (such as the Pixel 7 Pro), hardware encoder buffers
  /// are blanked when `POWER_MODE_OFF` is triggered. Using software brightness
  /// prevents black output while still protecting OLED displays.
  final bool useBrightnessWorkaround;

  /// Whether audio streaming is forwarded from the phone to host speakers.
  final bool audioEnabled;

  /// Whether touch indicators are drawn on the mirrored stream.
  final bool showTouches;

  /// Whether physical hardware keyboard events are synthesized via Linux UHID.
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

  /// Creates a [ScrcpyOptions] instance with production-hardened defaults for
  /// Google Pixel hardware.
  const ScrcpyOptions({
    this.maxSize = 0,
    this.bitRate = 16000000,
    this.maxFps = 60,
    this.stayAwake = true,
    this.useBrightnessWorkaround = true,
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
      } else if (device.connectionMode == ConnectionMode.wifi) {
        args.addAll(['-s', device.serial]);
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
    if (stayAwake) {
      args.add('--stay-awake');
    }
    if (noControl) {
      args.add('--no-control');
    } else if (uhidKeyboard) {
      args.add('--keyboard=uhid');
    }
    if (showTouches) {
      args.add('--show-touches');
    }
    if (!audioEnabled) {
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
