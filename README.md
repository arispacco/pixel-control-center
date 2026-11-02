# Pixel Control Center 📱⚡

A high-performance desktop control center and screen mirroring client for Google Pixel and Android devices, powered by Flutter and Scrcpy. Designed for Windows and Linux with zero-configuration dynamic Wi-Fi discovery, device supervision, and hardware-level optimizations for Google Tensor processors.

---

## ✨ Features

- **One-Click Screen Mirroring:** Seamless USB and low-latency Wi-Fi mirroring.
- **Dynamic Wi-Fi IP Discovery:** 4-tier discovery (Active ADB, USB routing table query, mDNS services, and multithreaded LAN socket probing on port 5555). No more static IP headaches when changing Wi-Fi networks!
- **Google Tensor / Pixel Hardware Optimizations:**
  - **Screen-Off Mirroring Workaround:** Android 17 on Google Tensor G2 blanks hardware encoder buffers when using standard `POWER_MODE_OFF`. Pixel Control Center applies an intelligent software brightness drop (`screen_brightness 0`) keeping the encoder active while saving battery and preventing screen burn-in.
  - **Ghost Virtual Display Prevention:** Enforces primary physical display binding (`--display-id=0`) to eliminate black screen bugs caused by lingering virtual displays.
  - **Virtual Keyboard Passthrough:** Ensures the on-screen soft keyboard remains active while simulating physical input (`uhid`).
- **Device Health & Quick Controls:** Battery percentage, temperature, power status, volume adjustment, display toggles, and rotation lock.
- **Modern Material 3 Desktop UI:** Native desktop performance built with Flutter, dark mode by default, and responsive layouts.

---

## 🛠️ Architecture

```
pixel-control-center/
├── lib/
│   ├── main.dart                      # Application entrypoint
│   ├── core/                          # Constants, theme, and process runners
│   ├── models/                        # DeviceInfo, ScrcpyOptions, ConnectionMode
│   ├── services/
│   │   ├── adb_service.dart           # ADB command execution & Pixel quirks
│   │   ├── scrcpy_service.dart        # Subprocess supervisor for scrcpy
│   │   └── discovery_service.dart     # Dynamic mDNS / socket IP discovery
│   └── ui/                            # Material 3 responsive dashboard
├── windows/                           # Windows native C++ desktop runner
├── linux/                             # Linux native GTK desktop runner
├── test/                              # Automated unit tests
├── app.py                             # Legacy CustomTkinter Python prototype
└── quick_wifi.py                      # Standalone Python dynamic launcher
```

---

## 🚀 Getting Started

### Prerequisites

1. **Flutter SDK** (3.24+ recommended) with desktop support enabled:
   ```bash
   flutter config --enable-windows-desktop
   flutter config --enable-linux-desktop
   ```
2. **Android Platform Tools (adb)** and **Scrcpy** (v2.0+ or v5.0+):
   - Windows:
     ```powershell
     winget install Genymobile.scrcpy
     ```
   - Linux:
     ```bash
     sudo apt install scrcpy adb
     ```

### Running Locally

```bash
flutter pub get
flutter run -d windows
# or for Linux:
flutter run -d linux
```

---

## 📄 License

Open-source under the Apache 2.0 License.
