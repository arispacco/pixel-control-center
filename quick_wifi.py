"""
Lancement rapide et intelligent de Scrcpy (USB prioritaire, sinon Wi-Fi automatique)
Optimisé avec --display-id=0 pour cibler systématiquement l'écran principal
"""

import os
import sys
import subprocess
import re
import socket
import concurrent.futures
import time

SCRCPY_DIR = r"C:\Users\pacco\AppData\Local\Microsoft\WinGet\Packages\Genymobile.scrcpy_Microsoft.Winget.Source_8wekyb3d8bbwe\scrcpy-win64-v5.0.1"
SCRCPY_EXE = os.path.join(SCRCPY_DIR, "scrcpy.exe")
ADB_EXE = os.path.join(SCRCPY_DIR, "adb.exe")


def run_adb(args):
    try:
        res = subprocess.run([ADB_EXE] + args, capture_output=True, text=True, timeout=8, creationflags=subprocess.CREATE_NO_WINDOW if os.name == 'nt' else 0)
        return res.stdout.strip()
    except Exception:
        return ""


def discover_ip():
    out = run_adb(["devices"])
    for line in out.splitlines():
        parts = line.split()
        if len(parts) >= 2 and parts[1] == "device":
            serial = parts[0]
            if serial.startswith("emulator-"):
                continue
            if ":5555" in serial:
                return serial.split(":")[0].strip()

    usb_route = run_adb(["-d", "shell", "ip", "route"])
    if "src" in usb_route:
        for line in usb_route.splitlines():
            if "src" in line and ("wlan" in line or "ap_br" in line):
                parts = line.split()
                try:
                    ip = parts[parts.index("src") + 1]
                    run_adb(["-d", "tcpip", "5555"])
                    return ip
                except Exception:
                    pass

    mdns_out = run_adb(["mdns", "services"])
    m = re.findall(r'(\d+\.\d+\.\d+\.\d+):(\d+)', mdns_out)
    if m:
        for candidate_ip, port in m:
            if candidate_ip != "127.0.0.1":
                return candidate_ip

    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect(("8.8.8.8", 80))
        my_ip = s.getsockname()[0]
    except Exception:
        my_ip = "127.0.0.1"
    finally:
        s.close()

    parts = my_ip.split(".")
    if len(parts) == 4 and my_ip != "127.0.0.1":
        subnet = ".".join(parts[:3])

        def probe(host):
            try:
                with socket.create_connection((host, 5555), timeout=0.8):
                    return host
            except Exception:
                return None

        ips = [f"{subnet}.{i}" for i in range(1, 255) if f"{subnet}.{i}" != my_ip]
        with concurrent.futures.ThreadPoolExecutor(max_workers=50) as ex:
            for r in ex.map(probe, ips):
                if r and r != "127.0.0.1":
                    return r

    return None


def main():
    # Détecter si le câble USB est branché (en ignorant les émulateurs BlueStacks)
    devices_out = run_adb(["devices"])
    usb_connected = False
    for line in devices_out.splitlines():
        parts = line.split()
        if len(parts) >= 2 and parts[1] == "device":
            serial = parts[0]
            if serial.startswith("emulator-") or serial.startswith("127.0.0.1"):
                continue
            if ":" not in serial:
                usb_connected = True
                break

    if usb_connected:
        target_flags = ["-d"]
        # Nettoyer les processus zombies et réveiller
        run_adb(target_flags + ["shell", "pkill", "-9", "-f", "app_process"])
        run_adb(target_flags + ["shell", "input", "keyevent", "224"])
        run_adb(target_flags + ["shell", "wm", "dismiss-keyguard"])
        cmd = [
            SCRCPY_EXE,
            "-d",
            "--display-id=0",
            "--max-size=1200",
            "--video-bit-rate=8M",
            "--stay-awake",
            "--keyboard=uhid"
        ]
    else:
        ip = discover_ip()
        if not ip:
            ip = "192.168.100.178"

        target_flags = ["-s", f"{ip}:5555"]
        run_adb(["connect", f"{ip}:5555"])
        # Nettoyer les processus zombies et réveiller
        run_adb(target_flags + ["shell", "pkill", "-9", "-f", "app_process"])
        run_adb(target_flags + ["shell", "input", "keyevent", "224"])
        run_adb(target_flags + ["shell", "wm", "dismiss-keyguard"])

        cmd = [
            SCRCPY_EXE,
            "-s", f"{ip}:5555",
            "--display-id=0",
            "--max-size=1200",
            "--video-bit-rate=8M",
            "--stay-awake",
            "--keyboard=uhid"
        ]

    subprocess.Popen(cmd, cwd=SCRCPY_DIR)


if __name__ == "__main__":
    main()
