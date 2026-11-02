/// Defines the supported physical or network connection channels between the
/// host workstation and the Android device.
enum ConnectionMode {
  /// Physical USB cable connection through the ADB daemon.
  usb,

  /// Wireless local area network connection over TCP/IP (port 5555).
  wifi,

  /// Unknown or disconnected state.
  disconnected,
}
