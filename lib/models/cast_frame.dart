import 'dart:typed_data';

/// Represents a single live screen image frame received over local Wi-Fi
/// without ADB or USB debugging.
class CastFrame {
  /// Encoded JPEG image bytes ready for GPU decoding.
  final Uint8List jpegBytes;

  /// Width of the captured frame in pixels (0 if unspecified by MJPEG source).
  final int width;

  /// Height of the captured frame in pixels (0 if unspecified by MJPEG source).
  final int height;

  /// Timestamp when the frame arrived on the receiver.
  final DateTime receivedAt;

  /// Creates a [CastFrame] instance.
  const CastFrame({
    required this.jpegBytes,
    required this.width,
    required this.height,
    required this.receivedAt,
  });
}
