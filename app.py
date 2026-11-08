"""
Pixel Control Center - Application de contrôle et miroir d'écran pour Google Pixel / Android
Avec Détection et Reconnexion Automatique d'IP sur n'importe quel réseau Wi-Fi
"""

import os
import sys
import subprocess
import threading
import time
import json
import re
import socket
import concurrent.futures
import tkinter as tk
from tkinter import messagebox
import customtkinter as ctk

import glob
import shutil

# Configuration de l'apparence
ctk.set_appearance_mode("Dark")
ctk.set_default_color_theme("blue")


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
    return os.path.dirname(os.path.abspath(found)) if found else ""


SCRCPY_DIR = _locate_scrcpy_dir()
SCRCPY_EXE = os.path.join(SCRCPY_DIR, "scrcpy.exe") if SCRCPY_DIR and os.name == "nt" else "scrcpy"
ADB_EXE = os.path.join(SCRCPY_DIR, "adb.exe") if SCRCPY_DIR and os.name == "nt" else "adb"
CONFIG_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "config.json")

if not os.path.exists(SCRCPY_EXE):
    SCRCPY_EXE = "scrcpy"
    ADB_EXE = "adb"


class PixelControlApp(ctk.CTk):
    def __init__(self):
        super().__init__()

        self.title("Pixel Control Center - Miroir & Contrôle PC")
        self.geometry("800x780")
        self.minsize(720, 720)

        # Processus scrcpy actif
        self.scrcpy_proc = None
        self.auto_reconnect_active = False
        self.reconnect_thread = None
        self.is_discovering = False

        self.load_config()
        self.create_widgets()

        # Lancer immédiatement la détection des appareils et de l'IP Wi-Fi
        self.refresh_devices_async()

    def load_config(self):
        self.config = {
            "last_ip": "192.168.100.178",
            "last_port": "5555",
            "turn_off_screen": True,
            "stay_awake": True,
            "always_on_top": False,
            "fullscreen": False,
            "audio": True,
            "uhid_keyboard": True,
            "resolution": "1080p (Full HD)",
            "bitrate": "8 Mbps (Standard)",
            "fps": "60 FPS (Très fluide)"
        }
        if os.path.exists(CONFIG_FILE):
            try:
                with open(CONFIG_FILE, "r", encoding="utf-8") as f:
                    self.config.update(json.load(f))
            except Exception:
                pass

    def save_config(self):
        try:
            with open(CONFIG_FILE, "w", encoding="utf-8") as f:
                json.dump(self.config, f, indent=4)
        except Exception:
            pass

    def run_adb(self, args, timeout=10):
        try:
            cmd = [ADB_EXE] + args
            flags = subprocess.CREATE_NO_WINDOW if os.name == 'nt' else 0
            res = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout, creationflags=flags)
            return res.stdout.strip()
        except Exception as e:
            return f"Error: {e}"

    def get_connected_devices(self):
        out = self.run_adb(["devices"])
        usb = []
        wifi = []
        for line in out.splitlines():
            parts = line.split()
            if len(parts) >= 2 and parts[1] == "device":
                serial = parts[0]
                if serial.startswith("emulator-") or serial.startswith("127.0.0.1"):
                    continue
                if ":" in serial:
                    wifi.append(serial)
                else:
                    usb.append(serial)
        return usb, wifi

    def get_target(self):
        usb, wifi = self.get_connected_devices()
        if usb:
            return ["-d"]
        elif wifi:
            return ["-s", wifi[0]]
        return []

    def update_ip_entry(self, ip):
        self.entry_ip.delete(0, "end")
        self.entry_ip.insert(0, ip)
        self.config["last_ip"] = ip
        self.save_config()

    def create_widgets(self):
        # Header
        header_frame = ctk.CTkFrame(self, corner_radius=12, fg_color=("#1f2937", "#111827"))
        header_frame.pack(fill="x", padx=16, pady=(16, 8))

        title_label = ctk.CTkLabel(
            header_frame,
            text="📱 Pixel Control Center",
            font=ctk.CTkFont(size=22, weight="bold"),
            text_color="#60a5fa"
        )
        title_label.pack(side="left", padx=16, pady=12)

        self.status_badge = ctk.CTkLabel(
            header_frame,
            text="● Détection réseau...",
            font=ctk.CTkFont(size=13, weight="bold"),
            text_color="#fbbf24"
        )
        self.status_badge.pack(side="right", padx=16, pady=12)

        # Tabview
        self.tabview = ctk.CTkTabview(self, corner_radius=12)
        self.tabview.pack(fill="both", expand=True, padx=16, pady=8)

        self.tab_conn = self.tabview.add("Connexion & Miroir")
        self.tab_config = self.tabview.add("Personnalisation & Options")
        self.tab_remote = self.tabview.add("Télécommande & Outils")

        self.build_conn_tab()
        self.build_config_tab()
        self.build_remote_tab()

        # Bottom Bar: Actions & Log
        bottom_frame = ctk.CTkFrame(self, corner_radius=10)
        bottom_frame.pack(fill="x", padx=16, pady=(8, 16))

        self.btn_refresh = ctk.CTkButton(
            bottom_frame,
            text="🔄 Actualiser & Scanner",
            command=self.refresh_devices_async,
            width=180,
            fg_color="#374151",
            hover_color="#4b5563"
        )
        self.btn_refresh.pack(side="left", padx=12, pady=10)

        self.btn_stop = ctk.CTkButton(
            bottom_frame,
            text="⏹ Fermer le miroir",
            command=self.stop_scrcpy,
            fg_color="#ef4444",
            hover_color="#dc2626",
            width=150
        )
        self.btn_stop.pack(side="right", padx=12, pady=10)

        self.info_label = ctk.CTkLabel(
            bottom_frame,
            text="Prêt",
            font=ctk.CTkFont(size=12),
            text_color="#9ca3af"
        )
        self.info_label.pack(side="right", padx=12, pady=10)

    # ------------------ TAB 1 : CONNEXION ------------------
    def build_conn_tab(self):
        info_frame = ctk.CTkFrame(self.tab_conn, corner_radius=10)
        info_frame.pack(fill="x", padx=12, pady=10)

        ctk.CTkLabel(
            info_frame,
            text="Statut du Pixel",
            font=ctk.CTkFont(size=15, weight="bold")
        ).pack(anchor="w", padx=14, pady=(10, 4))

        self.lbl_device_info = ctk.CTkLabel(
            info_frame,
            text="Recherche du Google Pixel et de son adresse IP...",
            font=ctk.CTkFont(size=13),
            justify="left"
        )
        self.lbl_device_info.pack(anchor="w", padx=14, pady=(0, 10))

        # Split: USB vs Wi-Fi
        modes_frame = ctk.CTkFrame(self.tab_conn, fg_color="transparent")
        modes_frame.pack(fill="both", expand=True, padx=6, pady=6)
        modes_frame.columnconfigure(0, weight=1)
        modes_frame.columnconfigure(1, weight=1)

        # Box 1: Mode Câble USB
        usb_box = ctk.CTkFrame(modes_frame, corner_radius=12)
        usb_box.grid(row=0, column=0, sticky="nsew", padx=6, pady=6)

        ctk.CTkLabel(
            usb_box,
            text="🔌 Connexion Câble USB",
            font=ctk.CTkFont(size=15, weight="bold")
        ).pack(anchor="w", padx=14, pady=(14, 6))

        ctk.CTkLabel(
            usb_box,
            text="Stabilité maximale et recharge du téléphone en même temps.",
            text_color="#9ca3af",
            font=ctk.CTkFont(size=12),
            wraplength=280,
            justify="left"
        ).pack(anchor="w", padx=14, pady=(0, 14))

        self.btn_launch_usb = ctk.CTkButton(
            usb_box,
            text="🚀 Afficher l'écran (USB)",
            command=lambda: self.launch_scrcpy(mode="usb"),
            height=42,
            font=ctk.CTkFont(size=14, weight="bold"),
            fg_color="#2563eb",
            hover_color="#1d4ed8"
        )
        self.btn_launch_usb.pack(fill="x", padx=14, pady=(0, 14))

        # Box 2: Mode Wi-Fi Sans Fil
        wifi_box = ctk.CTkFrame(modes_frame, corner_radius=12)
        wifi_box.grid(row=0, column=1, sticky="nsew", padx=6, pady=6)

        ctk.CTkLabel(
            wifi_box,
            text="📶 Connexion Sans Fil (Wi-Fi)",
            font=ctk.CTkFont(size=15, weight="bold")
        ).pack(anchor="w", padx=14, pady=(14, 6))

        ctk.CTkLabel(
            wifi_box,
            text="Fonctionne sur n'importe quel Wi-Fi ou partage de connexion !",
            text_color="#9ca3af",
            font=ctk.CTkFont(size=12),
            wraplength=280,
            justify="left"
        ).pack(anchor="w", padx=14, pady=(0, 8))

        # IP Field with Auto-detect button
        ip_frame = ctk.CTkFrame(wifi_box, fg_color="transparent")
        ip_frame.pack(fill="x", padx=14, pady=4)
        ctk.CTkLabel(ip_frame, text="Adresse IP :", font=ctk.CTkFont(size=12)).pack(side="left")

        self.entry_ip = ctk.CTkEntry(ip_frame, width=130, placeholder_text="192.168.x.x")
        self.entry_ip.insert(0, self.config.get("last_ip", "192.168.100.178"))
        self.entry_ip.pack(side="left", padx=6)

        self.btn_auto_ip = ctk.CTkButton(
            ip_frame,
            text="🔍 Détecter",
            width=70,
            height=28,
            font=ctk.CTkFont(size=11),
            fg_color="#374151",
            hover_color="#4b5563",
            command=self.trigger_ip_scan_async
        )
        self.btn_auto_ip.pack(side="right")

        # Port Field
        port_frame = ctk.CTkFrame(wifi_box, fg_color="transparent")
        port_frame.pack(fill="x", padx=14, pady=4)
        ctk.CTkLabel(port_frame, text="Port TCP :", font=ctk.CTkFont(size=12)).pack(side="left")
        self.entry_port = ctk.CTkEntry(port_frame, width=80, placeholder_text="5555")
        self.entry_port.insert(0, self.config.get("last_port", "5555"))
        self.entry_port.pack(side="right")

        # Action Wi-Fi
        self.btn_launch_wifi = ctk.CTkButton(
            wifi_box,
            text="🚀 Afficher l'écran (Wi-Fi)",
            command=lambda: self.launch_scrcpy(mode="wifi"),
            height=42,
            font=ctk.CTkFont(size=14, weight="bold"),
            fg_color="#059669",
            hover_color="#047857"
        )
        self.btn_launch_wifi.pack(fill="x", padx=14, pady=(12, 14))

        # Auto-reconnect banner
        reconnect_box = ctk.CTkFrame(self.tab_conn, corner_radius=10)
        reconnect_box.pack(fill="x", padx=12, pady=(4, 8))

        self.sw_autoreconnect = ctk.CTkSwitch(
            reconnect_box,
            text="Mode Reconnexion Automatique (Surveille et relance l'écran en permanence)",
            font=ctk.CTkFont(size=13, weight="bold"),
            command=self.toggle_autoreconnect
        )
        self.sw_autoreconnect.pack(anchor="w", padx=14, pady=12)

    # ------------------ TAB 2 : CONFIGURATION ------------------
    def build_config_tab(self):
        container = ctk.CTkScrollableFrame(self.tab_config, corner_radius=10)
        container.pack(fill="both", expand=True, padx=8, pady=8)

        ctk.CTkLabel(
            container,
            text="Options d'affichage & Économie d'énergie",
            font=ctk.CTkFont(size=15, weight="bold"),
            text_color="#60a5fa"
        ).pack(anchor="w", padx=10, pady=(10, 8))

        # 1. Turn screen off
        self.sw_turn_off = ctk.CTkSwitch(
            container,
            text="Éteindre l'écran physique du smartphone (Écran Noir)",
            font=ctk.CTkFont(size=13)
        )
        if self.config.get("turn_off_screen", True):
            self.sw_turn_off.select()
        self.sw_turn_off.pack(anchor="w", padx=10, pady=8)
        ctk.CTkLabel(
            container,
            text="  ➜ Empêche la dalle cassée de chauffer, économise la batterie et supprime les faux contacts.",
            font=ctk.CTkFont(size=11),
            text_color="#9ca3af"
        ).pack(anchor="w", padx=10, pady=(0, 8))

        # 2. Stay awake
        self.sw_stay_awake = ctk.CTkSwitch(
            container,
            text="Empêcher le smartphone de se mettre en veille (Stay Awake)",
            font=ctk.CTkFont(size=13)
        )
        if self.config.get("stay_awake", True):
            self.sw_stay_awake.select()
        self.sw_stay_awake.pack(anchor="w", padx=10, pady=8)

        # 3. Always on top
        self.sw_always_on_top = ctk.CTkSwitch(
            container,
            text="Garder la fenêtre toujours au premier plan (Always on Top)",
            font=ctk.CTkFont(size=13)
        )
        if self.config.get("always_on_top", False):
            self.sw_always_on_top.select()
        self.sw_always_on_top.pack(anchor="w", padx=10, pady=8)

        # 4. Fullscreen
        self.sw_fullscreen = ctk.CTkSwitch(
            container,
            text="Ouvrir directement en mode Plein Écran (Fullscreen)",
            font=ctk.CTkFont(size=13)
        )
        if self.config.get("fullscreen", False):
            self.sw_fullscreen.select()
        self.sw_fullscreen.pack(anchor="w", padx=10, pady=8)

        # 5. Audio
        self.sw_audio = ctk.CTkSwitch(
            container,
            text="Transmettre le son du smartphone sur les haut-parleurs du PC",
            font=ctk.CTkFont(size=13)
        )
        if self.config.get("audio", True):
            self.sw_audio.select()
        self.sw_audio.pack(anchor="w", padx=10, pady=8)

        # 6. Mode Clavier Physique Matériel (UHID)
        self.sw_uhid = ctk.CTkSwitch(
            container,
            text="Mode Clavier Physique (UHID - pour composer les numéros d'appel au clavier)",
            font=ctk.CTkFont(size=13)
        )
        if self.config.get("uhid_keyboard", True):
            self.sw_uhid.select()
        self.sw_uhid.pack(anchor="w", padx=10, pady=8)
        ctk.CTkLabel(
            container,
            text="  ➜ Fait reconnaître le clavier de votre PC comme un vrai clavier branché au téléphone.",
            font=ctk.CTkFont(size=11),
            text_color="#9ca3af"
        ).pack(anchor="w", padx=10, pady=(0, 8))

        # Divider
        ctk.CTkFrame(container, height=2, fg_color="#374151").pack(fill="x", padx=10, pady=14)

        ctk.CTkLabel(
            container,
            text="Performances & Qualité vidéo (Idéal pour le Wi-Fi)",
            font=ctk.CTkFont(size=15, weight="bold"),
            text_color="#60a5fa"
        ).pack(anchor="w", padx=10, pady=(6, 8))

        # Resolution
        res_row = ctk.CTkFrame(container, fg_color="transparent")
        res_row.pack(fill="x", padx=10, pady=6)
        ctk.CTkLabel(res_row, text="Résolution maximale :", width=180, anchor="w").pack(side="left")
        self.opt_resolution = ctk.CTkOptionMenu(
            res_row,
            values=["Originale (Sans limite)", "1080p (Full HD)", "720p (HD Rapide)", "480p (Fluide Wi-Fi)"]
        )
        self.opt_resolution.set(self.config.get("resolution", "Originale (Sans limite)"))
        self.opt_resolution.pack(side="left", padx=10)

        # Bitrate
        bitrate_row = ctk.CTkFrame(container, fg_color="transparent")
        bitrate_row.pack(fill="x", padx=10, pady=6)
        ctk.CTkLabel(bitrate_row, text="Débit vidéo (Bitrate) :", width=180, anchor="w").pack(side="left")
        self.opt_bitrate = ctk.CTkOptionMenu(
            bitrate_row,
            values=["8 Mbps (Standard)", "4 Mbps (Économique Wi-Fi)", "16 Mbps (Haute Définition)", "2 Mbps (Faible réseau)"]
        )
        self.opt_bitrate.set(self.config.get("bitrate", "8 Mbps (Standard)"))
        self.opt_bitrate.pack(side="left", padx=10)

        # FPS
        fps_row = ctk.CTkFrame(container, fg_color="transparent")
        fps_row.pack(fill="x", padx=10, pady=6)
        ctk.CTkLabel(fps_row, text="Fréquence d'images (FPS) :", width=180, anchor="w").pack(side="left")
        self.opt_fps = ctk.CTkOptionMenu(
            fps_row,
            values=["60 FPS (Très fluide)", "30 FPS (Économique)", "Max (Sans limite)"]
        )
        self.opt_fps.set(self.config.get("fps", "60 FPS (Très fluide)"))
        self.opt_fps.pack(side="left", padx=10)

    # ------------------ TAB 3 : TÉLÉCOMMANDE ------------------
    def build_remote_tab(self):
        container = ctk.CTkScrollableFrame(self.tab_remote, corner_radius=10)
        container.pack(fill="both", expand=True, padx=8, pady=8)

        ctk.CTkLabel(
            container,
            text="Boutons de Contrôle Rapide",
            font=ctk.CTkFont(size=15, weight="bold"),
            text_color="#60a5fa"
        ).pack(anchor="w", padx=10, pady=(10, 10))

        # Action grid
        grid = ctk.CTkFrame(container, fg_color="transparent")
        grid.pack(fill="x", padx=10, pady=4)
        for i in range(3):
            grid.columnconfigure(i, weight=1)

        ctk.CTkButton(grid, text="⚡ Déverrouiller / Allumer", command=self.unlock_phone, height=40).grid(row=0, column=0, padx=6, pady=6, sticky="ew")
        ctk.CTkButton(grid, text="🔒 Verrouiller (Écran off)", command=lambda: self.send_key(26), height=40).grid(row=0, column=1, padx=6, pady=6, sticky="ew")
        ctk.CTkButton(grid, text="📸 Capture d'écran PC", command=self.take_screenshot, height=40).grid(row=0, column=2, padx=6, pady=6, sticky="ew")

        ctk.CTkButton(grid, text="🏠 Accueil (Home)", command=lambda: self.send_key(3), height=40).grid(row=1, column=0, padx=6, pady=6, sticky="ew")
        ctk.CTkButton(grid, text="↩ Retour (Back)", command=lambda: self.send_key(4), height=40).grid(row=1, column=1, padx=6, pady=6, sticky="ew")
        ctk.CTkButton(grid, text="📑 Applications Récentes", command=lambda: self.send_key(187), height=40).grid(row=1, column=2, padx=6, pady=6, sticky="ew")

        ctk.CTkButton(grid, text="🔊 Volume +", command=lambda: self.send_key(24), height=40).grid(row=2, column=0, padx=6, pady=6, sticky="ew")
        ctk.CTkButton(grid, text="🔉 Volume -", command=lambda: self.send_key(25), height=40).grid(row=2, column=1, padx=6, pady=6, sticky="ew")
        ctk.CTkButton(grid, text="🔇 Couper le son (Mute)", command=lambda: self.send_key(164), height=40).grid(row=2, column=2, padx=6, pady=6, sticky="ew")

        # Raccourcis clavier scrcpy rappel
        tips_frame = ctk.CTkFrame(container, corner_radius=10, fg_color=("#1f2937", "#111827"))
        tips_frame.pack(fill="x", padx=10, pady=(18, 10))

        ctk.CTkLabel(
            tips_frame,
            text="💡 Raccourcis clavier directement dans la fenêtre de l'écran :",
            font=ctk.CTkFont(size=13, weight="bold"),
            text_color="#93c5fd"
        ).pack(anchor="w", padx=12, pady=(10, 6))

        shortcuts_text = (
            "• Alt + o : Éteindre ou rallumer l'écran physique du smartphone\n"
            "• Alt + f : Basculer en mode Plein Écran\n"
            "• Clic molette : Retourner à l'accueil (Home)\n"
            "• Clic droit : Retour (Back)\n"
            "• Glisser-Déposer un fichier : Transfère photos, vidéos ou installe un APK\n"
            "• Ctrl + v : Colle le presse-papiers de votre PC directement sur le smartphone"
        )
        ctk.CTkLabel(
            tips_frame,
            text=shortcuts_text,
            font=ctk.CTkFont(size=12),
            justify="left",
            text_color="#d1d5db"
        ).pack(anchor="w", padx=12, pady=(0, 10))

    # ------------------ DÉTECTION AUTOMATIQUE D'IP ------------------
    def _extract_gateway_and_arp_peers(self, subnet_prefix):
        candidates = []
        if os.name == "nt":
            try:
                ipcfg = subprocess.run(
                    ["ipconfig"],
                    capture_output=True,
                    text=True,
                    timeout=3,
                    creationflags=subprocess.CREATE_NO_WINDOW,
                ).stdout
                for line in ipcfg.splitlines():
                    low = line.lower()
                    if "passerelle" in low or "gateway" in low:
                        for ip in re.findall(r"(\d+\.\d+\.\d+\.\d+)", line):
                            if ip.startswith(subnet_prefix + ".") and not ip.endswith(".255"):
                                if ip not in candidates:
                                    candidates.append(ip)
            except Exception:
                pass

        try:
            arp_out = subprocess.run(
                ["arp", "-a"],
                capture_output=True,
                text=True,
                timeout=3,
                creationflags=subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0,
            ).stdout
            for line in arp_out.splitlines():
                m = re.search(r"(\d+\.\d+\.\d+\.\d+)", line)
                if not m:
                    continue
                ip = m.group(1)
                if ip.startswith(subnet_prefix + ".") and not ip.endswith(".255") and not ip.endswith(".0"):
                    if ip not in candidates:
                        candidates.append(ip)
        except Exception:
            pass

        return candidates

    def discover_pixel_ip(self):
        devices_out = self.run_adb(["devices"])
        for line in devices_out.splitlines():
            parts = line.split()
            if len(parts) >= 2 and parts[1] == "device" and ":" in parts[0]:
                serial = parts[0]
                if not serial.startswith("127.0.0.1") and not serial.startswith("emulator-"):
                    ip, port = serial.split(":", 1)
                    return ip.strip(), port.strip()

        usb_route = self.run_adb(["-d", "shell", "ip", "route"])
        if "src" in usb_route:
            for line in usb_route.splitlines():
                low = line.lower()
                if "src" in low and ("wlan" in low or "swlan" in low or "ap" in low):
                    parts = line.split()
                    try:
                        ip = parts[parts.index("src") + 1]
                        self.run_adb(["-d", "tcpip", "5555"])
                        return ip, "5555"
                    except Exception:
                        pass

        mdns_out = self.run_adb(["mdns", "services"])
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
            priority_hosts = [
                h for h in self._extract_gateway_and_arp_peers(subnet) if h != my_ip
            ]

            def probe_service(host):
                for p in (5555, 8080):
                    try:
                        with socket.create_connection((host, p), timeout=0.22):
                            return host, str(p)
                    except Exception:
                        pass
                return None

            for h in priority_hosts:
                hit = probe_service(h)
                if hit:
                    return hit

            ips = [
                f"{subnet}.{i}"
                for i in range(1, 255)
                if f"{subnet}.{i}" != my_ip and f"{subnet}.{i}" not in priority_hosts
            ]
            with concurrent.futures.ThreadPoolExecutor(max_workers=60) as ex:
                for r in ex.map(probe_service, ips):
                    if r and r[0] != "127.0.0.1":
                        return r

            # Fallback: return alive ARP / Hotspot Gateway peer so the user sees the phone IP!
            for h in priority_hosts:
                try:
                    ping_args = (
                        ["ping", "-n", "1", "-w", "300", h]
                        if os.name == "nt"
                        else ["ping", "-c", "1", "-W", "1", h]
                    )
                    res = subprocess.run(
                        ping_args,
                        capture_output=True,
                        text=True,
                        timeout=2,
                        creationflags=subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0,
                    )
                    if "ttl=" in res.stdout.lower():
                        return h, None
                except Exception:
                    pass

        return None, None

    def trigger_ip_scan_async(self):
        if self.is_discovering:
            return
        self.is_discovering = True
        self.btn_auto_ip.configure(text="⏳ ...", state="disabled")
        self.info_label.configure(text="Recherche automatique de l'IP sur le Wi-Fi / Hotspot...")

        def task():
            ip, port = self.discover_pixel_ip()
            def update_ui():
                self.is_discovering = False
                self.btn_auto_ip.configure(text="🔍 Détecter", state="normal")
                if ip and port == "8080":
                    self.update_ip_entry(ip)
                    self.info_label.configure(
                        text=f"Flux Cast Wi-Fi détecté sur http://{ip}:8080 !"
                    )
                elif ip and port:
                    self.update_ip_entry(ip)
                    self.entry_port.delete(0, "end")
                    self.entry_port.insert(0, port)
                    self.config["last_port"] = port
                    self.save_config()
                    self.info_label.configure(text=f"Appareil ADB trouvé : {ip}:{port}")
                    self.run_adb(["connect", f"{ip}:{port}"])
                    self.refresh_devices_async()
                elif ip:
                    self.update_ip_entry(ip)
                    self.info_label.configure(
                        text=f"Téléphone détecté sur {ip} (port ADB fermé : lancez Android Wi-Fi Cast ou branchez 1x en USB)."
                    )
                else:
                    self.info_label.configure(text="Aucun appareil détecté sur ce réseau Wi-Fi.")
            self.after(0, update_ui)

        threading.Thread(target=task, daemon=True).start()

    # ------------------ LOGIC ------------------
    def refresh_devices_async(self):
        self.status_badge.configure(text="● Actualisation...", text_color="#fbbf24")
        self.info_label.configure(text="Recherche des appareils connectés...")

        def task():
            current_ip = self.entry_ip.get().strip()
            current_port = self.entry_port.get().strip() or "5555"
            if current_ip:
                self.run_adb(["connect", f"{current_ip}:{current_port}"], timeout=3)

            usb, wifi = self.get_connected_devices()
            device_names = []
            if usb:
                device_names.append(f"USB ({usb[0]})")
            if wifi:
                device_names.append(f"Wi-Fi ({wifi[0]})")

            discovered_ip = None
            discovered_port = "5555"
            if not wifi:
                discovered_ip, det_port = self.discover_pixel_ip()
                if discovered_ip and det_port and det_port != "8080":
                    discovered_port = det_port
                    conn_out = self.run_adb(["connect", f"{discovered_ip}:{discovered_port}"], timeout=4)
                    if "connected" in conn_out.lower():
                        wifi.append(f"{discovered_ip}:{discovered_port}")
                        device_names.append(f"Wi-Fi ({discovered_ip}:{discovered_port})")

            target = self.get_target()
            level = "Inconnu"
            temp = ""
            if target:
                battery_info = self.run_adb(target + ["shell", "dumpsys", "battery"])
                for b_line in battery_info.splitlines():
                    if "level:" in b_line:
                        level = b_line.split(":")[-1].strip() + "%"
                    elif "temperature:" in b_line:
                        try:
                            t_val = int(b_line.split(":")[-1].strip()) / 10.0
                            temp = f" • {t_val:.1f}°C"
                        except Exception:
                            pass
                self.run_adb(target + ["shell", "settings", "put", "secure", "show_ime_with_hard_keyboard", "1"])

            def update_ui():
                if discovered_ip:
                    self.update_ip_entry(discovered_ip)

                if usb and wifi:
                    self.status_badge.configure(text="● Connecté (USB & Wi-Fi)", text_color="#34d399")
                elif usb:
                    self.status_badge.configure(text="● Connecté (Câble USB)", text_color="#60a5fa")
                elif wifi:
                    self.status_badge.configure(text="● Connecté (Sans Fil Wi-Fi)", text_color="#34d399")
                else:
                    self.status_badge.configure(text="● Aucun appareil détecté", text_color="#ef4444")

                txt = f"Appareils : {', '.join(device_names) if device_names else 'Aucun'}\nBatterie : {level}{temp}"
                self.lbl_device_info.configure(text=txt)
                self.info_label.configure(text="Appareils actualisés avec succès.")

            self.after(0, update_ui)

        threading.Thread(target=task, daemon=True).start()

    def launch_scrcpy(self, mode="auto"):
        self.stop_scrcpy()
        time.sleep(0.3)

        self.info_label.configure(text=f"Vérification de la connexion ({mode.upper()})...")

        def task():
            usb, wifi = self.get_connected_devices()
            target_mode = mode

            # 1. Gestion du mode USB
            if mode == "usb":
                if not usb:
                    if wifi:
                        target_mode = "wifi"
                        self.after(0, lambda: self.info_label.configure(text="USB non branché. Bascule automatique en Wi-Fi !"))
                    else:
                        def notify_no_usb():
                            messagebox.showwarning(
                                "Câble USB non détecté",
                                "Aucun smartphone Pixel n'est détecté en USB.\n\n"
                                "1. Assurez-vous que le câble USB est bien branché entre votre PC et le téléphone.\n"
                                "2. Si vous n'avez pas de câble, cliquez sur 'Afficher l'écran (Wi-Fi)'."
                            )
                            self.info_label.configure(text="Échec : câble USB non branché.")
                        self.after(0, notify_no_usb)
                        return

            # 2. Gestion du mode Wi-Fi
            ip = self.entry_ip.get().strip()
            port = self.entry_port.get().strip() or "5555"

            if target_mode == "wifi":
                # Vérifier si l'appareil est déjà connecté
                if not wifi or not any(ip in w for w in wifi):
                    self.after(0, lambda: self.info_label.configure(text="Connexion Wi-Fi au Pixel..."))
                    conn_res = self.run_adb(["connect", f"{ip}:{port}"], timeout=8)
                    if "connected" not in conn_res.lower():
                        new_ip, _ = self.discover_pixel_ip()
                        if new_ip:
                            ip = new_ip
                            self.after(0, lambda: self.update_ip_entry(new_ip))
                            self.run_adb(["connect", f"{ip}:{port}"], timeout=8)
                        else:
                            def notify_no_wifi():
                                messagebox.showerror(
                                    "Pixel introuvable en Wi-Fi",
                                    "Impossible de joindre le Pixel sur le réseau Wi-Fi.\n\n"
                                    "• Vérifiez que votre PC et votre Pixel sont bien sur la même box / Wi-Fi.\n"
                                    "• Si vous venez de redémarrer le téléphone, branchez-le une fois en USB."
                                )
                                self.info_label.configure(text="Pixel introuvable en Wi-Fi.")
                            self.after(0, notify_no_wifi)
                            return

            target_adb = ["-d"] if target_mode == "usb" else ["-s", f"{ip}:{port}"]

            # 3. Nettoyer les écrans virtuels fantômes et réveiller le téléphone
            self.run_adb(target_adb + ["shell", "pkill", "-9", "-f", "app_process"])
            time.sleep(0.2)

            args = ["--display-id=0"]
            if target_mode == "usb":
                args.append("-d")
            else:
                args.extend(["-s", f"{ip}:{port}"])

            self.run_adb(target_adb + ["shell", "input", "keyevent", "224"])
            self.run_adb(target_adb + ["shell", "wm", "dismiss-keyguard"])

            if self.sw_turn_off.get():
                # Sur Google Pixel Tensor, turn-screen-off coupe le flux vidéo et produit un écran noir sur PC.
                # On règle la luminosité à 0 (noir OLED) pour protéger la dalle tout en gardant l'image sur PC !
                self.run_adb(target_adb + ["shell", "settings", "put", "system", "screen_brightness", "0"])
            else:
                self.run_adb(target_adb + ["shell", "settings", "put", "system", "screen_brightness", "100"])

            self.run_adb(target_adb + ["shell", "settings", "put", "secure", "show_ime_with_hard_keyboard", "1"])
            if self.sw_stay_awake.get():
                args.append("--stay-awake")
            if self.sw_always_on_top.get():
                args.append("--always-on-top")
            if self.sw_fullscreen.get():
                args.append("--fullscreen")
            if not self.sw_audio.get():
                args.append("--no-audio")
            if self.sw_uhid.get():
                args.append("--keyboard=uhid")

            # Résolution
            res_map = {"1080p (Full HD)": "1080", "720p (HD Rapide)": "720", "480p (Fluide Wi-Fi)": "480"}
            if self.opt_resolution.get() in res_map:
                args.append(f"--max-size={res_map[self.opt_resolution.get()]}")

            # Bitrate
            bit_map = {"8 Mbps (Standard)": "8M", "4 Mbps (Économique Wi-Fi)": "4M", "16 Mbps (Haute Définition)": "16M", "2 Mbps (Faible réseau)": "2M"}
            if self.opt_bitrate.get() in bit_map:
                args.append(f"--video-bit-rate={bit_map[self.opt_bitrate.get()]}")

            # FPS
            fps_map = {"60 FPS (Très fluide)": "60", "30 FPS (Économique)": "30"}
            if self.opt_fps.get() in fps_map:
                args.append(f"--max-fps={fps_map[self.opt_fps.get()]}")

            cmd = [SCRCPY_EXE] + args

            def start_gui():
                try:
                    self.scrcpy_proc = subprocess.Popen(
                        cmd,
                        cwd=SCRCPY_DIR if os.path.exists(SCRCPY_DIR) else None,
                        stderr=subprocess.PIPE,
                        stdout=subprocess.PIPE,
                        text=True
                    )
                    self.info_label.configure(text=f"Miroir actif ({target_mode.upper()})")

                    def monitor_crash(proc):
                        time.sleep(2)
                        if proc.poll() is not None:
                            err_out = proc.stderr.read() or proc.stdout.read()
                            def show_err():
                                if err_out.strip():
                                    messagebox.showwarning("Fermeture du miroir", f"L'affichage n'a pas pu démarrer :\n{err_out}")
                                self.info_label.configure(text="Miroir arrêté.")
                            self.after(0, show_err)

                    threading.Thread(target=monitor_crash, args=(self.scrcpy_proc,), daemon=True).start()

                except Exception as e:
                    messagebox.showerror("Erreur de lancement", f"Impossible de lancer scrcpy :\n{e}")
                    self.info_label.configure(text="Erreur au lancement.")

            self.after(0, start_gui)

        threading.Thread(target=task, daemon=True).start()

    def stop_scrcpy(self):
        if self.scrcpy_proc and self.scrcpy_proc.poll() is None:
            self.scrcpy_proc.terminate()
            self.scrcpy_proc = None

        try:
            if os.name == 'nt':
                subprocess.run(["taskkill", "/F", "/IM", "scrcpy.exe"], capture_output=True, creationflags=subprocess.CREATE_NO_WINDOW)
        except Exception:
            pass

        self.info_label.configure(text="Miroir arrêté.")

    def toggle_autoreconnect(self):
        self.auto_reconnect_active = self.sw_autoreconnect.get()
        if self.auto_reconnect_active:
            self.info_label.configure(text="Mode auto-reconnexion actif...")
            if not self.reconnect_thread or not self.reconnect_thread.is_alive():
                self.reconnect_thread = threading.Thread(target=self.auto_reconnect_loop, daemon=True)
                self.reconnect_thread.start()
        else:
            self.info_label.configure(text="Mode auto-reconnexion désactivé.")

    def auto_reconnect_loop(self):
        while self.auto_reconnect_active:
            if self.scrcpy_proc is None or self.scrcpy_proc.poll() is not None:
                usb, wifi = self.get_connected_devices()
                if usb or wifi:
                    self.launch_scrcpy(mode="usb" if usb else "wifi")
            time.sleep(3)

    def send_key(self, code):
        def task():
            target = self.get_target()
            if target:
                self.run_adb(target + ["shell", "input", "keyevent", str(code)])
                self.info_label.configure(text=f"Commande touche envoyée (Code {code})")
        threading.Thread(target=task, daemon=True).start()

    def unlock_phone(self):
        def task():
            target = self.get_target()
            if target:
                self.run_adb(target + ["shell", "input", "keyevent", "224"])
                time.sleep(0.1)
                self.run_adb(target + ["shell", "wm", "dismiss-keyguard"])
                self.info_label.configure(text="Ordre de déverrouillage envoyé.")
        threading.Thread(target=task, daemon=True).start()

    def take_screenshot(self):
        self.info_label.configure(text="Capture d'écran en cours...")
        def task():
            target = self.get_target()
            if not target:
                return
            out_file = os.path.join(os.path.expanduser("~"), "Desktop", f"pixel_capture_{int(time.time())}.png")
            self.run_adb(target + ["shell", "screencap", "-p", "/sdcard/temp_screen.png"])
            self.run_adb(target + ["pull", "/sdcard/temp_screen.png", out_file])
            def done():
                self.info_label.configure(text="Capture enregistrée sur le Bureau !")
                if os.path.exists(out_file):
                    os.startfile(out_file)
            self.after(0, done)
        threading.Thread(target=task, daemon=True).start()


if __name__ == "__main__":
    app = PixelControlApp()
    app.mainloop()
