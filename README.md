# Pixel Control Center — Universal Android Edition 📱⚡

A high-performance **Universal Android** desktop control center, remote screen controller, and **Zero-ADB Live Wi-Fi Screen Caster** built with **Flutter Desktop** (Windows & Linux) and **100% Native Kotlin** (`MediaProjection`).

Born during **Hacktoberfest Hack Day Yaoundé** when a cracked phone screen inspired an emergency ADB bridge, **Pixel Control Center** works out of the box with **every Android smartphone (Android 8.0 API 26 through Android 17)** — including **Samsung (OneUI)**, **Xiaomi / Redmi / POCO (HyperOS / MIUI)**, **Tecno (HiOS)**, **Infinix (XOS)**, **Oppo / Realme**, **Vivo**, **OnePlus**, **Motorola**, and **Google Pixel**!

---

## ✨ Dual-Mode Architecture (For Everyone & Power Users)

### 1. 📡 Consumer Mode: Zero-ADB Live Wi-Fi Cast (No Developer Options Needed!)
Designed for everyday users whose touchscreen still works and who just want to project their phone onto a bigger screen **without enabling Developer Mode, USB Debugging, or ADB**:
- **Companion Native Android App (`android_cast_sender/`, 0.86 MB APK, 0 dependencies):** Uses Android's standard `MediaProjection` consent prompt + Android 14/15 compliant `FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION`.
- **Automatic PC Discovery on LAN (`UDP :5958`):** Automatically discovers any PC running Pixel Control Center on the same Wi-Fi or phone hotspot (**0 MB of mobile internet consumed**).
- **Ultra-Low-Latency `PCST` Binary Frame Stream (`TCP :5959`):** Streams real-time compressed frames directly into the Flutter Desktop stage (with 90° rotation, live FPS/resolution counter, and frame freeze) while leaving the phone's physical touchscreen 100% free.
- **Built-in Web & Smart TV MJPEG Server (`HTTP :8080`):** Also serves a zero-install HTML5/MJPEG live stream (`http://<phone-ip>:8080`) viewable on any browser (Chrome, Edge, Safari, Smart TV).
- **1-Click Windows Miracast Shortcut:** Quick launcher for native Smart View / Cast wireless projection (`ms-settings:project`).

### 2. 🛠️ Power & Broken-Screen Mode: Full Desktop Control (`Scrcpy` + `ADB`)
Designed for developers, power users, or rescuing a phone with a broken touch digitizer:
- **Universal Multi-OEM Adaptation:**
  - **Samsung, Xiaomi, Tecno, Infinix, Oppo, Qualcomm & MediaTek:** Uses native hardware `--turn-screen-off` in Screen-Off Mode and multi-interface Wi-Fi routing discovery (`wlan0`, `swlan0`, `wlan1`, `ap0`, filtering out cellular `rmnet`/`ccmni` interfaces).
  - **Android 8–10 Legacy Compatibility:** Automatically adapts UHID keyboard and audio flags when `ro.build.version.sdk < 30` so older kernels never fail input injection.
  - **Google Pixel / Tensor G2–G4 Auto-Detection:** Detects `ro.product.brand == google` and automatically replaces `POWER_MODE_OFF` (which blanks Tensor hardware video encoders) with temporary manual brightness dimming (`screen_brightness 0`), restoring the user's **exact** prior brightness and Adaptive Brightness mode on exit.
- **4-Tier Zero-Config Wi-Fi ADB Discovery:** Probes active wireless endpoints, USB interface routes, ADB mDNS services, and parallel `/24` subnet sockets on port `5555`.
- **Ghost Virtual Display Prevention:** Enforces `--display-id=0` and cleans up lingering `app_process` daemons.

---

## 🗂️ Project Structure

```text
pixel-control-center/
├── lib/
│   ├── main.dart                              # Flutter Desktop entrypoint
│   ├── models/
│   │   ├── cast_frame.dart                    # Decoded Wi-Fi Cast JPEG frame model
│   │   ├── connection_mode.dart               # USB vs Wi-Fi transport enum
│   │   ├── device_info.dart                   # Multi-OEM Android telemetry & brand detection
│   │   └── scrcpy_options.dart                # Universal & SDK-aware scrcpy flag builder
│   ├── services/
│   │   ├── adb_service.dart                   # Dynamic ADB locator, telemetry & brightness state
│   │   ├── network_discovery_service.dart     # 4-tier multi-interface LAN IP discovery
│   │   ├── scrcpy_service.dart                # Subprocess supervisor & auto brightness restore
│   │   └── wifi_cast_service.dart             # Zero-ADB TCP (:5959), UDP (:5958) & MJPEG receiver
│   └── ui/
│       ├── screens/
│       │   ├── dashboard_screen.dart          # Unified Consumer Cast + Full ADB Control hub
│       │   └── wifi_cast_screen.dart          # Live gapless Wi-Fi Cast stage
│       └── widgets/                           # Modular Material 3 desktop panels
├── android_cast_sender/                       # Companion 100% Native Kotlin Wi-Fi Cast Sender (0.86 MB)
│   └── app/src/main/kotlin/com/pixelcontrol/wificast/
│       ├── MainActivity.kt                    # UDP PC auto-discovery & 1-tap Cast UI
│       └── ScreenCastService.kt               # MediaProjection -> TCP PCST + HTTP :8080 MJPEG
├── test/                                      # Automated unit & socket integration tests
├── windows/                                   # Windows native C++ desktop runner
└── linux/                                     # Linux native GTK desktop runner
```

---

## 🚀 Getting Started

### Option A — Cast Screen Over Wi-Fi (No Developer Mode / No ADB Required)
1. Launch **Pixel Control Center** on your Windows or Linux PC and click **"Ouvrir le Récepteur Cast Wi-Fi Direct"**.
2. Install the lightweight companion app (`android_cast_sender`, `0.86 MB`) on **any Android 8.0+ phone**:
   ```powershell
   cd android_cast_sender
   .\gradlew.bat assembleDebug
   # APK output: app/build/outputs/apk/debug/app-debug.apk
   ```
3. Connect both devices to the same Wi-Fi (or turn on your phone's Wi-Fi Hotspot), tap your PC's name in **Android Wi-Fi Cast**, and accept Android's standard screen-sharing prompt!

### Option B — Full Desktop Mouse & Keyboard Control (USB / Wi-Fi ADB)
1. Install **Flutter SDK** (3.24+) and **Scrcpy** (`winget install Genymobile.scrcpy` on Windows or `sudo apt install scrcpy adb` on Linux).
2. Enable **USB Debugging** (or **Wireless Debugging**) on your Android phone.
3. Run the desktop app:
   ```bash
   flutter pub get
   flutter test
   flutter run -d windows   # or: flutter run -d linux
   ```

---

## 📄 License

Open-source under the Apache 2.0 License.
