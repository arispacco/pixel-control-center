"""
Lancement rapide et intelligent de Scrcpy (USB prioritaire, sinon Wi-Fi automatique)
Optimisé avec --display-id=0 pour cibler systématiquement l'écran principal
"""

import os
import sys
import glob
import shutil
import subprocess
import re
import socket
import concurrent.futures
import time


def _locate_scrcpy_dir():
    local_app_data = os.environ.get("LOCALAPPDATA", "")
    if local_app_data:
        pattern = os.path.join(
            local_app_data,
            "Microsoft",
            "WinGet",
            "Packages",
            "Genymobile.scrcpy*",
            "scrcpy-*",
        )
        for folder in sorted(glob.glob(pattern), reverse=True):
            if os.path.isfile(os.path.join(folder, "scrcpy.exe")):
                return folder
    found = shutil.which("scrcpy")
    return os.path.dirname(os.path.abspath(found)) if found else None


SCRCPY_DIR = _locate_scrcpy_dir()
SCRCPY_EXE = os.path.join(SCRCPY_DIR, "scrcpy.exe") if SCRCPY_DIR and os.name == "nt" else "scrcpy"
ADB_EXE = os.path.join(SCRCPY_DIR, "adb.exe") if SCRCPY_DIR and os.name == "nt" else "adb"


def run_adb(args):
    try:
        res = subprocess.run([ADB_EXE] + args, capture_output=True, text=True, timeout=8, creationflags=subprocess.CREATE_NO_WINDOW if os.name == 'nt' else 0)
        return res.stdout.strip()
    except Exception:
        return ""


def discover_endpoint():
    out = run_adb(["devices"])
    for line in out.splitlines():
        parts = line.split()
        if len(parts) >= 2 and parts[1] == "device":
            serial = parts[0]
            if serial.startswith("emulator-") or serial.startswith("127.0.0.1"):
                continue
            if ":" in serial:
                ip, port = serial.split(":", 1)
                return ip.strip(), port.strip()

    usb_route = run_adb(["-d", "shell", "ip", "route"])
    if "src" in usb_route:
        for line in usb_route.splitlines():
            low = line.lower()
            if "src" in low and ("wlan" in low or "swlan" in low or "ap" in low):
                parts = line.split()
                try:
                    ip = parts[parts.index("src") + 1]
                    run_adb(["-d", "tcpip", "5555"])
                    return ip, "5555"
                except Exception:
                    pass

    mdns_out = run_adb(["mdns", "services"])
    for line in mdns_out.splitlines():
        if "_adb-tls-pairing._tcp" in line:
            continue
        m = re.search(r"(\d+\.\d+\.\d+\.\d+):(\d+)", line)
        if m and m.group(1) != "127.0.0.1":
            return m.group(1), m.group(2)

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
                with socket.create_connection((host, 5555), timeout=0.4):
                    return host
            except Exception:
                return None

        ips = [f"{subnet}.{i}" for i in range(1, 255) if f"{subnet}.{i}" != my_ip]
        with concurrent.futures.ThreadPoolExecutor(max_workers=50) as ex:
            for r in ex.map(probe, ips):
                if r and r != "127.0.0.1":
                    return r, "5555"

    return None, "5555"


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
        ip, port = discover_endpoint()
        if not ip:
            ip = "192.168.100.178"

        endpoint = f"{ip}:{port}"
        target_flags = ["-s", endpoint]
        run_adb(["connect", endpoint])
        # Nettoyer les processus zombies et réveiller
        run_adb(target_flags + ["shell", "pkill", "-9", "-f", "app_process"])
        run_adb(target_flags + ["shell", "input", "keyevent", "224"])
        run_adb(target_flags + ["shell", "wm", "dismiss-keyguard"])

        cmd = [
            SCRCPY_EXE,
            "-s", endpoint,
            "--display-id=0",
            "--max-size=1200",
            "--video-bit-rate=8M",
            "--stay-awake",
            "--keyboard=uhid"
        ]

    subprocess.Popen(cmd, cwd=SCRCPY_DIR if SCRCPY_DIR and os.path.isdir(SCRCPY_DIR) else None)


if __name__ == "__main__":
    main()
