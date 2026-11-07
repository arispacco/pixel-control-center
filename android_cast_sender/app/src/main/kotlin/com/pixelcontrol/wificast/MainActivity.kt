package com.pixelcontrol.wificast

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.text.InputType
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.Button
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.Inet4Address
import java.net.InetAddress
import java.net.NetworkInterface

class MainActivity : Activity() {

    data class DiscoveredPc(
        val hostName: String,
        val ip: String,
        val tcpPort: Int
    )

    companion object {
        private const val REQ_MEDIA_PROJECTION = 9001
        private const val UDP_DISCOVERY_PORT = 5958
    }

    private val uiHandler = Handler(Looper.getMainLooper())
    private var pendingTargetHost: String = ""
    private var pendingTargetPort: Int = 5959

    private lateinit var statusBadgeView: TextView
    private lateinit var phoneWebUrlView: TextView
    private lateinit var discoveredContainer: LinearLayout
    private lateinit var manualIpInput: EditText
    private lateinit var stopButton: Button

    private val statusRefreshRunnable = object : Runnable {
        override fun run() {
            refreshStreamingUi()
            uiHandler.postDelayed(this, 800L)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.statusBarColor = Color.parseColor("#0F766E")

        val scroll = ScrollView(this).apply {
            setBackgroundColor(Color.parseColor("#F8FAFC"))
            isFillViewport = true
        }

        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(20), dp(24), dp(20), dp(32))
        }

        val title = TextView(this).apply {
            text = "Pixel Wi-Fi Cast"
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 24f)
            setTypeface(typeface, Typeface.BOLD)
            setTextColor(Color.parseColor("#0F172A"))
        }
        val subtitle = TextView(this).apply {
            text = "Partagez votre écran en direct par Wi-Fi sans câble ni mode débogage. Le tactile de votre téléphone reste 100 % actif."
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 14f)
            setTextColor(Color.parseColor("#475569"))
            setPadding(0, dp(6), 0, dp(16))
        }

        statusBadgeView = TextView(this).apply {
            setPadding(dp(14), dp(10), dp(14), dp(10))
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
            setTypeface(typeface, Typeface.BOLD)
            background = roundedBg("#E2E8F0", 12)
            setTextColor(Color.parseColor("#334155"))
        }

        stopButton = Button(this).apply {
            text = "Arrêter la diffusion en direct"
            isAllCaps = false
            setTextColor(Color.WHITE)
            background = roundedBg("#DC2626", 12)
            visibility = View.GONE
            val lp = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                dp(48)
            ).apply { topMargin = dp(12) }
            layoutParams = lp
            setOnClickListener {
                val stop = Intent(this@MainActivity, ScreenCastService::class.java).apply {
                    action = ScreenCastService.ACTION_STOP
                }
                startService(stop)
                refreshStreamingUi()
            }
        }

        // Card 1: Auto-discovered PCs running Pixel Control Center
        val pcCard = buildCard().apply {
            addView(sectionTitle("1. Caster vers votre PC (Automatique)"))
            addView(helperText("Ouvrez Pixel Control Center sur votre ordinateur connecté au même Wi-Fi (ou partage de connexion) :"))

            discoveredContainer = LinearLayout(this@MainActivity).apply {
                orientation = LinearLayout.VERTICAL
                setPadding(0, dp(10), 0, dp(6))
            }
            addView(discoveredContainer)

            val rescanBtn = Button(this@MainActivity).apply {
                text = "Rechercher mon ordinateur sur le Wi-Fi"
                isAllCaps = false
                setTextColor(Color.parseColor("#0F766E"))
                background = outlinedBg("#0F766E", 10)
                setOnClickListener { scanForPcsOnLan() }
            }
            addView(rescanBtn)
        }

        // Card 2: Browser / Smart TV zero-install casting
        val webCard = buildCard().apply {
            addView(sectionTitle("2. Caster vers un Navigateur Web ou Smart TV"))
            addView(helperText("Aucun logiciel requis sur l'écran cible : démarrez ci-dessous puis ouvrez cette adresse dans Chrome, Edge ou Safari :"))

            phoneWebUrlView = TextView(this@MainActivity).apply {
                text = "http://${findLocalPhoneIp()}:${ScreenCastService.DEFAULT_HTTP_PORT}"
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)
                setTypeface(Typeface.MONOSPACE, Typeface.BOLD)
                setTextColor(Color.parseColor("#0F766E"))
                gravity = Gravity.CENTER
                setPadding(dp(12), dp(12), dp(12), dp(12))
                background = roundedBg("#F0FDFA", 10)
                val lp = LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    ViewGroup.LayoutParams.WRAP_CONTENT
                ).apply {
                    topMargin = dp(10)
                    bottomMargin = dp(12)
                }
                layoutParams = lp
            }
            addView(phoneWebUrlView)

            val webCastBtn = Button(this@MainActivity).apply {
                text = "Caster en Direct sur le Navigateur Web"
                isAllCaps = false
                setTextColor(Color.WHITE)
                background = roundedBg("#0F766E", 10)
                setOnClickListener {
                    requestScreenCast("", 5959)
                }
            }
            addView(webCastBtn)
        }

        // Card 3: Optional manual PC IP entry
        val manualCard = buildCard().apply {
            addView(sectionTitle("Connexion manuelle par adresse IP (Optionnel)"))
            manualIpInput = EditText(this@MainActivity).apply {
                hint = "Adresse IP du PC (ex: 192.168.100.12)"
                inputType = InputType.TYPE_CLASS_TEXT
                setSingleLine(true)
                setPadding(dp(12), dp(10), dp(12), dp(10))
                background = outlinedBg("#CBD5E1", 10)
                val lp = LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    ViewGroup.LayoutParams.WRAP_CONTENT
                ).apply {
                    topMargin = dp(8)
                    bottomMargin = dp(10)
                }
                layoutParams = lp
            }
            addView(manualIpInput)

            val connectIpBtn = Button(this@MainActivity).apply {
                text = "Caster vers cette IP"
                isAllCaps = false
                setTextColor(Color.WHITE)
                background = roundedBg("#2563EB", 10)
                setOnClickListener {
                    val raw = manualIpInput.text.toString().trim()
                    if (raw.isNotEmpty()) {
                        val parts = raw.split(":")
                        val host = parts[0].trim()
                        val port = parts.getOrNull(1)?.toIntOrNull() ?: 5959
                        requestScreenCast(host, port)
                    }
                }
            }
            addView(connectIpBtn)
        }

        root.addView(title)
        root.addView(subtitle)
        root.addView(statusBadgeView)
        root.addView(stopButton)
        root.addView(pcCard)
        root.addView(webCard)
        root.addView(manualCard)

        scroll.addView(root)
        setContentView(scroll)

        refreshStreamingUi()
        scanForPcsOnLan()
    }

    override fun onResume() {
        super.onResume()
        phoneWebUrlView.text =
            "http://${findLocalPhoneIp()}:${ScreenCastService.DEFAULT_HTTP_PORT}"
        uiHandler.post(statusRefreshRunnable)
    }

    override fun onPause() {
        uiHandler.removeCallbacks(statusRefreshRunnable)
        super.onPause()
    }

    private fun refreshStreamingUi() {
        if (ScreenCastService.isStreaming) {
            statusBadgeView.text = "● EN DIRECT — ${ScreenCastService.statusMessage}"
            statusBadgeView.background = roundedBg("#DCFCE7", 12)
            statusBadgeView.setTextColor(Color.parseColor("#166534"))
            stopButton.visibility = View.VISIBLE
        } else {
            statusBadgeView.text = "Prêt à diffuser • Aucun mode débogage requis"
            statusBadgeView.background = roundedBg("#E2E8F0", 12)
            statusBadgeView.setTextColor(Color.parseColor("#334155"))
            stopButton.visibility = View.GONE
        }
    }

    private fun scanForPcsOnLan() {
        discoveredContainer.removeAllViews()
        discoveredContainer.addView(helperText("Recherche des ordinateurs sur le Wi-Fi..."))

        Thread({
            val found = LinkedHashMap<String, DiscoveredPc>()
            var socket: DatagramSocket? = null
            try {
                socket = DatagramSocket()
                socket.broadcast = true
                socket.soTimeout = 450

                val probe = "PIXEL_CAST_DISCOVER".toByteArray(Charsets.UTF_8)
                val targets = mutableSetOf("255.255.255.255")
                val localIp = findLocalPhoneIp()
                val octets = localIp.split(".")
                if (octets.size == 4) {
                    targets.add("${octets[0]}.${octets[1]}.${octets[2]}.255")
                }

                for (target in targets) {
                    try {
                        val addr = InetAddress.getByName(target)
                        socket.send(DatagramPacket(probe, probe.size, addr, UDP_DISCOVERY_PORT))
                    } catch (_: Throwable) {}
                }

                val buf = ByteArray(512)
                val deadline = System.currentTimeMillis() + 1100L
                while (System.currentTimeMillis() < deadline) {
                    try {
                        val pkt = DatagramPacket(buf, buf.size)
                        socket.receive(pkt)
                        val msg = String(pkt.data, 0, pkt.length, Charsets.UTF_8).trim()
                        if (msg.startsWith("PIXEL_CAST_HERE|")) {
                            val parts = msg.split("|")
                            val hostName = parts.getOrNull(1) ?: "Ordinateur"
                            val tcpPort = parts.getOrNull(2)?.toIntOrNull() ?: 5959
                            val ip = pkt.address.hostAddress ?: continue
                            found[ip] = DiscoveredPc(hostName, ip, tcpPort)
                        }
                    } catch (_: Throwable) {
                        break
                    }
                }
            } catch (_: Throwable) {
            } finally {
                socket?.close()
            }

            uiHandler.post {
                discoveredContainer.removeAllViews()
                if (found.isEmpty()) {
                    discoveredContainer.addView(
                        helperText("Aucun PC détecté automatiquement pour l'instant. Vérifiez que Pixel Control Center est ouvert sur le PC.")
                    )
                } else {
                    for (pc in found.values) {
                        val btn = Button(this@MainActivity).apply {
                            text = "Caster vers ${pc.hostName} (${pc.ip})"
                            isAllCaps = false
                            setTextColor(Color.WHITE)
                            background = roundedBg("#0F766E", 10)
                            val lp = LinearLayout.LayoutParams(
                                ViewGroup.LayoutParams.MATCH_PARENT,
                                ViewGroup.LayoutParams.WRAP_CONTENT
                            ).apply { bottomMargin = dp(8) }
                            layoutParams = lp
                            setOnClickListener {
                                requestScreenCast(pc.ip, pc.tcpPort)
                            }
                        }
                        discoveredContainer.addView(btn)
                    }
                }
            }
        }, "PixelCastUdpScan").start()
    }

    private fun requestScreenCast(targetHost: String, targetPort: Int) {
        pendingTargetHost = targetHost
        pendingTargetPort = targetPort
        val mpm = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
        @Suppress("DEPRECATION")
        startActivityForResult(mpm.createScreenCaptureIntent(), REQ_MEDIA_PROJECTION)
    }

    @Deprecated("Handled directly for zero AndroidX dependency footprint")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQ_MEDIA_PROJECTION && resultCode == RESULT_OK && data != null) {
            val svcIntent = Intent(this, ScreenCastService::class.java).apply {
                action = ScreenCastService.ACTION_START
                putExtra(ScreenCastService.EXTRA_RESULT_CODE, resultCode)
                putExtra(ScreenCastService.EXTRA_RESULT_DATA, data)
                putExtra(ScreenCastService.EXTRA_TARGET_HOST, pendingTargetHost)
                putExtra(ScreenCastService.EXTRA_TARGET_PORT, pendingTargetPort)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(svcIntent)
            } else {
                startService(svcIntent)
            }
            uiHandler.postDelayed({ refreshStreamingUi() }, 300L)
        }
    }

    private fun findLocalPhoneIp(): String {
        try {
            val interfaces = NetworkInterface.getNetworkInterfaces() ?: return "127.0.0.1"
            var fallback = "127.0.0.1"
            while (interfaces.hasMoreElements()) {
                val nif = interfaces.nextElement()
                if (!nif.isUp || nif.isLoopback) continue
                val name = nif.name.lowercase()
                val addrs = nif.inetAddresses
                while (addrs.hasMoreElements()) {
                    val addr = addrs.nextElement()
                    if (addr is Inet4Address && !addr.isLoopbackAddress) {
                        val ip = addr.hostAddress ?: continue
                        if (name.startsWith("wlan") || name.startsWith("ap") || name.startsWith("swlan")) {
                            return ip
                        }
                        fallback = ip
                    }
                }
            }
            return fallback
        } catch (_: Throwable) {
            return "127.0.0.1"
        }
    }

    private fun buildCard(): LinearLayout {
        return LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(16), dp(16), dp(16), dp(16))
            background = roundedBg("#FFFFFF", 14, strokeHex = "#E2E8F0")
            val lp = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            ).apply { topMargin = dp(14) }
            layoutParams = lp
        }
    }

    private fun sectionTitle(label: String): TextView {
        return TextView(this).apply {
            text = label
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)
            setTypeface(typeface, Typeface.BOLD)
            setTextColor(Color.parseColor("#0F172A"))
        }
    }

    private fun helperText(label: String): TextView {
        return TextView(this).apply {
            text = label
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
            setTextColor(Color.parseColor("#64748B"))
            setPadding(0, dp(4), 0, dp(4))
        }
    }

    private fun roundedBg(fillHex: String, radiusDp: Int, strokeHex: String? = null): GradientDrawable {
        return GradientDrawable().apply {
            shape = GradientDrawable.RECTANGLE
            cornerRadius = dp(radiusDp).toFloat()
            setColor(Color.parseColor(fillHex))
            if (strokeHex != null) {
                setStroke(dp(1), Color.parseColor(strokeHex))
            }
        }
    }

    private fun outlinedBg(strokeHex: String, radiusDp: Int): GradientDrawable {
        return roundedBg("#FFFFFF", radiusDp, strokeHex)
    }

    private fun dp(value: Int): Int {
        return TypedValue.applyDimension(
            TypedValue.COMPLEX_UNIT_DIP,
            value.toFloat(),
            resources.displayMetrics
        ).toInt()
    }
}
