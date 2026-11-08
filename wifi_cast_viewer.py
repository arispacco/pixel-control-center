"""
Module de réception Cast Wi-Fi en direct (Zéro ADB / Sans Mode Débogage)
Compatible avec l'application Android Wi-Fi Cast (TCP PCST :5959, UDP :5958 et HTTP MJPEG :8080).
"""

import io
import os
import re
import socket
import struct
import threading
import time
from tkinter import messagebox

import customtkinter as ctk
from PIL import Image


def get_local_lan_ip():
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
        return ip if ip and not ip.startswith("127.") else "127.0.0.1"
    except Exception:
        return "127.0.0.1"
    finally:
        s.close()


def _read_exact(sock, size):
    buf = bytearray()
    while len(buf) < size:
        chunk = sock.recv(size - len(buf))
        if not chunk:
            return None
        buf.extend(chunk)
    return bytes(buf)


class WifiCastReceiverService:
    UDP_PORT = 5958
    TCP_PORT = 5959
    HTTP_PORT = 8080

    def __init__(self, on_frame, on_status):
        self.on_frame = on_frame
        self.on_status = on_status
        self.running = False
        self._udp_sock = None
        self._tcp_server = None
        self._http_stop = threading.Event()
        self._http_thread = None

    def start(self):
        if self.running:
            return
        self.running = True
        threading.Thread(target=self._udp_discovery_loop, daemon=True).start()
        threading.Thread(target=self._tcp_accept_loop, daemon=True).start()

    def stop(self):
        self.running = False
        self.disconnect_http()
        for s in (self._udp_sock, self._tcp_server):
            if s:
                try:
                    s.close()
                except Exception:
                    pass
        self._udp_sock = None
        self._tcp_server = None

    def disconnect_http(self):
        self._http_stop.set()

    def connect_http_mjpeg(self, host, port=8080):
        self.disconnect_http()
        time.sleep(0.08)
        self._http_stop = threading.Event()
        self._http_thread = threading.Thread(
            target=self._http_mjpeg_loop,
            args=(host.strip(), int(port)),
            daemon=True,
        )
        self._http_thread.start()

    def _udp_discovery_loop(self):
        try:
            sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            sock.bind(("0.0.0.0", self.UDP_PORT))
            sock.settimeout(1.0)
            self._udp_sock = sock
            pc_name = socket.gethostname() or "PC-Windows"

            while self.running:
                try:
                    data, addr = sock.recvfrom(512)
                except socket.timeout:
                    continue
                except OSError:
                    break

                msg = data.decode("utf-8", errors="ignore").strip()
                if msg.startswith("PIXEL_CAST_DISCOVER") or msg.startswith("PCC_DISCOVER"):
                    reply = f"PIXEL_CAST_HERE|{pc_name}|{self.TCP_PORT}".encode("utf-8")
                    try:
                        sock.sendto(reply, addr)
                    except OSError:
                        pass
        except Exception:
            pass

    def _tcp_accept_loop(self):
        try:
            srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            srv.bind(("0.0.0.0", self.TCP_PORT))
            srv.listen(4)
            srv.settimeout(1.0)
            self._tcp_server = srv
            local_ip = get_local_lan_ip()
            self.on_status(f"Prêt • Écoute Wi-Fi directe sur {local_ip}:{self.TCP_PORT}")

            while self.running:
                try:
                    client, addr = srv.accept()
                except socket.timeout:
                    continue
                except OSError:
                    break
                threading.Thread(
                    target=self._handle_tcp_client,
                    args=(client, addr[0]),
                    daemon=True,
                ).start()
        except Exception as exc:
            self.on_status(f"Port TCP {self.TCP_PORT} occupé ({exc}) • Utilisez le flux Web :8080")

    def _handle_tcp_client(self, client, sender_ip):
        self.on_status(f"● EN DIRECT (TCP) depuis {sender_ip}")
        try:
            client.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
            client.settimeout(6.0)
            while self.running:
                hdr = _read_exact(client, 16)
                if not hdr:
                    break
                magic, width, height, length = struct.unpack(">4sIII", hdr)
                if magic != b"PCST" or length <= 0 or length > 8_000_000:
                    break
                jpeg_bytes = _read_exact(client, length)
                if not jpeg_bytes:
                    break
                self.on_frame(jpeg_bytes, width, height, f"TCP {sender_ip}")
        except Exception:
            pass
        finally:
            try:
                client.close()
            except Exception:
                pass
            if self.running:
                self.on_status(f"Flux {sender_ip} terminé • En attente...")

    def _http_mjpeg_loop(self, host, port):
        stop_ev = self._http_stop
        self.on_status(f"Connexion à http://{host}:{port}/stream ...")
        sock = None
        try:
            sock = socket.create_connection((host, port), timeout=3.5)
            sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
            sock.settimeout(6.0)
            req = (
                f"GET /stream HTTP/1.1\r\n"
                f"Host: {host}:{port}\r\n"
                f"Accept: multipart/x-mixed-replace, image/jpeg, */*\r\n"
                f"Connection: close\r\n\r\n"
            ).encode("ascii")
            sock.sendall(req)

            buf = bytearray()
            self.on_status(f"● EN DIRECT (Web Wi-Fi) depuis {host}:{port}")

            while self.running and not stop_ev.is_set():
                chunk = sock.recv(65536)
                if not chunk:
                    break
                buf.extend(chunk)

                # Extract frames via Content-Length when available, or SOI..EOI markers
                while True:
                    cl_match = re.search(rb"Content-Length:\s*(\d+)\r\n\r\n", buf, re.IGNORECASE)
                    if cl_match:
                        jpeg_start = cl_match.end()
                        jpeg_len = int(cl_match.group(1))
                        if len(buf) < jpeg_start + jpeg_len:
                            break
                        jpeg_bytes = bytes(buf[jpeg_start : jpeg_start + jpeg_len])
                        del buf[: jpeg_start + jpeg_len]
                        self.on_frame(jpeg_bytes, 0, 0, f"Wi-Fi {host}:{port}")
                    else:
                        soi = buf.find(b"\xff\xd8")
                        if soi < 0:
                            if len(buf) > 4096:
                                del buf[:-16]
                            break
                        eoi = buf.find(b"\xff\xd9", soi + 2)
                        if eoi < 0:
                            if soi > 0:
                                del buf[:soi]
                            break
                        jpeg_bytes = bytes(buf[soi : eoi + 2])
                        del buf[: eoi + 2]
                        self.on_frame(jpeg_bytes, 0, 0, f"Wi-Fi {host}:{port}")
        except Exception as exc:
            if not stop_ev.is_set():
                self.on_status(
                    f"Flux Web {host}:{port} non actif ({exc}). Lancez 'Android Wi-Fi Cast' sur le téléphone."
                )
        finally:
            if sock:
                try:
                    sock.close()
                except Exception:
                    pass


class WifiCastWindow(ctk.CTkToplevel):
    """Fenêtre dédiée d'affichage en direct par Wi-Fi sans débogage USB."""

    def __init__(self, master, service: WifiCastReceiverService, initial_ip="", on_scan_ip=None):
        super().__init__(master)
        self.service = service
        self.on_scan_ip = on_scan_ip
        self.title("📡 Cast Wi-Fi en Direct (Sans Mode Débogage)")
        self.geometry("620x860")
        self.minsize(420, 560)
        self.configure(fg_color="#0b0f19")

        self._is_fullscreen = False
        self._latest_pil = None
        self._latest_jpeg = None
        self._render_pending = False
        self._frame_times = []

        self._build_ui(initial_ip)
        self.bind("<F11>", lambda _e: self.toggle_fullscreen())
        self.bind("<Escape>", lambda _e: self._exit_fullscreen())

    def _build_ui(self, initial_ip):
        # Top Control Bar
        self.top_bar = ctk.CTkFrame(self, corner_radius=10, fg_color="#111827")
        self.top_bar.pack(fill="x", padx=10, pady=(10, 6))

        row1 = ctk.CTkFrame(self.top_bar, fg_color="transparent")
        row1.pack(fill="x", padx=10, pady=(8, 4))

        self.lbl_live = ctk.CTkLabel(
            row1,
            text=f"● PC prêt ({get_local_lan_ip()}:5959) — En attente du téléphone...",
            font=ctk.CTkFont(size=13, weight="bold"),
            text_color="#34d399",
        )
        self.lbl_live.pack(side="left")

        ctk.CTkButton(
            row1,
            text="⛶ Plein écran",
            width=105,
            height=28,
            fg_color="#374151",
            hover_color="#4b5563",
            command=self.toggle_fullscreen,
        ).pack(side="right", padx=(6, 0))

        ctk.CTkButton(
            row1,
            text="📸 Photo",
            width=85,
            height=28,
            fg_color="#2563eb",
            hover_color="#1d4ed8",
            command=self.save_snapshot,
        ).pack(side="right")

        row2 = ctk.CTkFrame(self.top_bar, fg_color="transparent")
        row2.pack(fill="x", padx=10, pady=(2, 8))

        ctk.CTkLabel(
            row2,
            text="IP Téléphone :",
            font=ctk.CTkFont(size=12),
            text_color="#9ca3af",
        ).pack(side="left")

        self.entry_phone_ip = ctk.CTkEntry(row2, width=145, placeholder_text="10.x.x.x / 192.168.x.x")
        if initial_ip:
            self.entry_phone_ip.insert(0, initial_ip)
        self.entry_phone_ip.pack(side="left", padx=6)

        ctk.CTkButton(
            row2,
            text="▶️ Connecter au flux Wi-Fi (:8080)",
            height=30,
            fg_color="#0d9488",
            hover_color="#0f766e",
            font=ctk.CTkFont(size=12, weight="bold"),
            command=self.connect_selected_ip,
        ).pack(side="left", padx=4)

        if self.on_scan_ip:
            ctk.CTkButton(
                row2,
                text="🔍 Détecter IP",
                width=100,
                height=30,
                fg_color="#374151",
                hover_color="#4b5563",
                font=ctk.CTkFont(size=12),
                command=self._scan_and_connect,
            ).pack(side="right")

        # Video Stage
        self.stage = ctk.CTkFrame(self, corner_radius=12, fg_color="#050811")
        self.stage.pack(fill="both", expand=True, padx=10, pady=(0, 10))

        self.video_label = ctk.CTkLabel(
            self.stage,
            text=(
                "📱 Comment afficher votre écran sans mode débogage :\n\n"
                "1. Ouvrez l'application « Android Wi-Fi Cast » sur votre téléphone\n"
                "2. Appuyez sur « Caster vers mon PC » ou « Caster sur le Navigateur Web »\n"
                "3. Acceptez le partage d'écran Android : l'image apparaît ici instantanément !"
            ),
            font=ctk.CTkFont(size=14),
            text_color="#94a3b8",
            justify="center",
        )
        self.video_label.pack(fill="both", expand=True, padx=8, pady=8)

        # Auto-try connecting if initial_ip already streams on :8080
        if initial_ip:
            self.after(250, lambda: self._probe_and_connect_quietly(initial_ip))

    def _probe_and_connect_quietly(self, ip):
        def check():
            try:
                with socket.create_connection((ip, 8080), timeout=0.45):
                    self.service.connect_http_mjpeg(ip, 8080)
            except Exception:
                pass

        threading.Thread(target=check, daemon=True).start()

    def _scan_and_connect(self):
        if not self.on_scan_ip:
            return
        self.lbl_live.configure(text="⏳ Recherche du téléphone sur le Wi-Fi...", text_color="#fbbf24")

        def run():
            ip, port = self.on_scan_ip()

            def apply_res():
                if not self.winfo_exists():
                    return
                if ip:
                    self.entry_phone_ip.delete(0, "end")
                    self.entry_phone_ip.insert(0, ip)
                    if port == "8080":
                        self.service.connect_http_mjpeg(ip, 8080)
                    else:
                        self.lbl_live.configure(
                            text=f"Téléphone trouvé ({ip}) • Lancez 'Android Wi-Fi Cast' sur le mobile",
                            text_color="#60a5fa",
                        )
                        self._probe_and_connect_quietly(ip)
                else:
                    self.lbl_live.configure(
                        text="Aucun téléphone détecté sur ce Wi-Fi.",
                        text_color="#f87171",
                    )

            self.after(0, apply_res)

        threading.Thread(target=run, daemon=True).start()

    def connect_selected_ip(self):
        raw = self.entry_phone_ip.get().strip()
        if not raw:
            messagebox.showinfo("Adresse IP requise", "Saisissez ou détectez d'abord l'adresse IP du téléphone.")
            return
        raw = raw.replace("http://", "").replace("https://", "").split("/")[0]
        if ":" in raw:
            host, p_str = raw.split(":", 1)
            port = int(p_str) if p_str.isdigit() else 8080
        else:
            host, port = raw, 8080
        self.service.connect_http_mjpeg(host, port)

    def toggle_fullscreen(self):
        self._is_fullscreen = not self._is_fullscreen
        self.attributes("-fullscreen", self._is_fullscreen)

    def _exit_fullscreen(self):
        if self._is_fullscreen:
            self._is_fullscreen = False
            self.attributes("-fullscreen", False)

    def update_status_banner(self, text):
        if self.winfo_exists():
            self.lbl_live.configure(text=text)

    def push_jpeg_frame(self, jpeg_bytes, width, height, source_label):
        try:
            pil_img = Image.open(io.BytesIO(jpeg_bytes))
            pil_img.load()
        except Exception:
            return

        now = time.monotonic()
        self._frame_times.append(now)
        cutoff = now - 1.0
        while self._frame_times and self._frame_times[0] < cutoff:
            self._frame_times.pop(0)

        self._latest_pil = pil_img
        self._latest_jpeg = jpeg_bytes

        if not self._render_pending and self.winfo_exists():
            self._render_pending = True
            fps = len(self._frame_times)
            w, h = pil_img.size
            self.after(0, lambda: self._render_latest(w, h, fps, source_label))

    def _render_latest(self, w, h, fps, source_label):
        self._render_pending = False
        if not self.winfo_exists() or self._latest_pil is None:
            return

        stage_w = max(self.stage.winfo_width() - 20, 260)
        stage_h = max(self.stage.winfo_height() - 20, 360)
        scale = min(stage_w / max(w, 1), stage_h / max(h, 1))
        disp_w = max(int(w * scale), 1)
        disp_h = max(int(h * scale), 1)

        ctk_img = ctk.CTkImage(
            light_image=self._latest_pil,
            dark_image=self._latest_pil,
            size=(disp_w, disp_h),
        )
        self.video_label.configure(image=ctk_img, text="")
        self.video_label._image_ref = ctk_img
        self.lbl_live.configure(
            text=f"● EN DIRECT ({source_label}) • {w}×{h} • {fps} FPS",
            text_color="#4ade80",
        )

    def save_snapshot(self):
        if not self._latest_jpeg:
            messagebox.showinfo("Aucun flux", "Aucune image reçue pour le moment.")
            return
        desktop = os.path.join(os.path.expanduser("~"), "OneDrive", "Desktop")
        if not os.path.isdir(desktop):
            desktop = os.path.join(os.path.expanduser("~"), "Desktop")
        out_path = os.path.join(desktop, f"cast_wifi_{int(time.time())}.jpg")
        with open(out_path, "wb") as f:
            f.write(self._latest_jpeg)
        os.startfile(out_path)
