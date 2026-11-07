package com.pixelcontrol.wificast

import android.app.Activity
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.Bitmap
import android.graphics.PixelFormat
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.ImageReader
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.IBinder
import java.io.BufferedReader
import java.io.ByteArrayOutputStream
import java.io.DataOutputStream
import java.io.InputStreamReader
import java.net.InetSocketAddress
import java.net.ServerSocket
import java.net.Socket
import java.util.concurrent.atomic.AtomicBoolean

class ScreenCastService : Service() {

    data class FrameSnapshot(
        val jpegBytes: ByteArray,
        val width: Int,
        val height: Int,
        val sequence: Long
    )

    companion object {
        const val ACTION_START = "com.pixelcontrol.wificast.START"
        const val ACTION_STOP = "com.pixelcontrol.wificast.STOP"
        const val EXTRA_RESULT_CODE = "extra_result_code"
        const val EXTRA_RESULT_DATA = "extra_result_data"
        const val EXTRA_TARGET_HOST = "extra_target_host"
        const val EXTRA_TARGET_PORT = "extra_target_port"

        const val DEFAULT_HTTP_PORT = 8080
        private const val CHANNEL_ID = "pixel_wifi_cast_channel"
        private const val NOTIF_ID = 4201

        @Volatile
        var isStreaming: Boolean = false
            private set

        @Volatile
        var statusMessage: String = "Inactif"
            private set
    }

    private val running = AtomicBoolean(false)
    private val frameLock = Object()

    @Volatile
    private var latestFrame: FrameSnapshot? = null
    private var frameCounter: Long = 0L

    private var mediaProjection: MediaProjection? = null
    private var virtualDisplay: VirtualDisplay? = null
    private var imageReader: ImageReader? = null
    private var captureThread: HandlerThread? = null
    private var captureHandler: Handler? = null

    private var tcpSenderThread: Thread? = null
    private var httpServerSocket: ServerSocket? = null
    private var httpAcceptThread: Thread? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopStreamingInternal()
            stopSelf()
            return START_NOT_STICKY
        }

        if (intent?.action == ACTION_START) {
            val resultCode = intent.getIntExtra(EXTRA_RESULT_CODE, Activity.RESULT_CANCELED)
            val resultData: Intent? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                intent.getParcelableExtra(EXTRA_RESULT_DATA, Intent::class.java)
            } else {
                @Suppress("DEPRECATION")
                intent.getParcelableExtra(EXTRA_RESULT_DATA)
            }
            val targetHost = intent.getStringExtra(EXTRA_TARGET_HOST).orEmpty().trim()
            val targetPort = intent.getIntExtra(EXTRA_TARGET_PORT, 5959)

            if (resultCode != Activity.RESULT_OK || resultData == null) {
                stopSelf()
                return START_NOT_STICKY
            }

            // Android 10..15+ requirement: promote to mediaProjection foreground service FIRST.
            promoteToForeground()
            startCapturePipeline(resultCode, resultData, targetHost, targetPort)
        }

        return START_NOT_STICKY
    }

    private fun promoteToForeground() {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Diffusion Écran Wi-Fi",
                NotificationManager.IMPORTANCE_LOW
            )
            nm.createNotificationChannel(channel)
        }

        val stopIntent = Intent(this, ScreenCastService::class.java).apply {
            action = ACTION_STOP
        }
        val stopPending = PendingIntent.getService(
            this,
            1,
            stopIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }

        val notification = builder
            .setContentTitle("Pixel Wi-Fi Cast en direct")
            .setContentText("Diffusion de l'écran par Wi-Fi active (sans mode débogage)")
            .setSmallIcon(android.R.drawable.ic_menu_share)
            .addAction(
                Notification.Action.Builder(
                    null,
                    "Arrêter",
                    stopPending
                ).build()
            )
            .setOngoing(true)
            .build()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIF_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION
            )
        } else {
            startForeground(NOTIF_ID, notification)
        }
    }

    private fun startCapturePipeline(
        resultCode: Int,
        resultData: Intent,
        targetHost: String,
        targetPort: Int
    ) {
        stopStreamingInternal()
        running.set(true)
        isStreaming = true

        val thread = HandlerThread("PixelCastCaptureThread").apply { start() }
        val handler = Handler(thread.looper)
        captureThread = thread
        captureHandler = handler

        val mpm = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
        val projection = mpm.getMediaProjection(resultCode, resultData) ?: run {
            statusMessage = "Autorisation de capture refusée"
            stopStreamingInternal()
            stopSelf()
            return
        }
        mediaProjection = projection

        // Required on Android 14+ (API 34+) BEFORE createVirtualDisplay().
        projection.registerCallback(object : MediaProjection.Callback() {
            override fun onStop() {
                stopStreamingInternal()
                stopSelf()
            }
        }, handler)

        val dm = resources.displayMetrics
        val rawW = dm.widthPixels.coerceAtLeast(360)
        val rawH = dm.heightPixels.coerceAtLeast(640)
        val scale = if (rawW > 720) 720f / rawW.toFloat() else 1f
        val capW = ((rawW * scale).toInt() and 0xFFFE).coerceAtLeast(320)
        val capH = ((rawH * scale).toInt() and 0xFFFE).coerceAtLeast(480)
        val density = dm.densityDpi

        val reader = ImageReader.newInstance(capW, capH, PixelFormat.RGBA_8888, 2)
        imageReader = reader

        val jpegOut = ByteArrayOutputStream(160 * 1024)
        var lastCaptureMs = 0L

        reader.setOnImageAvailableListener({ ir ->
            val img = try {
                ir.acquireLatestImage()
            } catch (_: Throwable) {
                null
            } ?: return@setOnImageAvailableListener

            try {
                val now = System.currentTimeMillis()
                // Cap at ~30 FPS to keep phone cool and Wi-Fi latency ultra-low.
                if (now - lastCaptureMs < 32L) {
                    return@setOnImageAvailableListener
                }
                lastCaptureMs = now

                val plane = img.planes[0]
                val buffer = plane.buffer
                val pixelStride = plane.pixelStride
                val rowStride = plane.rowStride
                val rowPadding = rowStride - pixelStride * capW
                val paddedWidth = capW + (rowPadding / pixelStride)

                val fullBitmap = Bitmap.createBitmap(
                    paddedWidth,
                    capH,
                    Bitmap.Config.ARGB_8888
                )
                buffer.rewind()
                fullBitmap.copyPixelsFromBuffer(buffer)

                val cleanBitmap = if (rowPadding > 0) {
                    Bitmap.createBitmap(fullBitmap, 0, 0, capW, capH).also {
                        fullBitmap.recycle()
                    }
                } else {
                    fullBitmap
                }

                jpegOut.reset()
                cleanBitmap.compress(Bitmap.CompressFormat.JPEG, 72, jpegOut)
                cleanBitmap.recycle()

                val bytes = jpegOut.toByteArray()
                synchronized(frameLock) {
                    frameCounter++
                    latestFrame = FrameSnapshot(bytes, capW, capH, frameCounter)
                    frameLock.notifyAll()
                }
            } catch (_: Throwable) {
                // Ignore transient surface resize frames.
            } finally {
                img.close()
            }
        }, handler)

        virtualDisplay = projection.createVirtualDisplay(
            "PixelWifiCastDisplay",
            capW,
            capH,
            density,
            DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
            reader.surface,
            null,
            handler
        )

        startHttpMjpegServer()
        if (targetHost.isNotEmpty()) {
            startTcpPushLoop(targetHost, targetPort)
        } else {
            statusMessage = "Serveur Web actif sur le port $DEFAULT_HTTP_PORT"
        }
    }

    private fun startTcpPushLoop(host: String, port: Int) {
        val worker = Thread({
            while (running.get()) {
                var socket: Socket? = null
                try {
                    statusMessage = "Connexion au PC $host:$port..."
                    socket = Socket()
                    socket.tcpNoDelay = true
                    socket.connect(InetSocketAddress(host, port), 3000)
                    val out = DataOutputStream(socket.getOutputStream())
                    statusMessage = "En direct vers $host:$port"

                    var lastSentSeq = -1L
                    while (running.get() && !socket.isClosed) {
                        val snap: FrameSnapshot?
                        synchronized(frameLock) {
                            if (latestFrame == null || latestFrame!!.sequence == lastSentSeq) {
                                frameLock.wait(250L)
                            }
                            snap = latestFrame
                        }
                        if (snap == null || snap.sequence == lastSentSeq) continue
                        lastSentSeq = snap.sequence

                        // 16-byte PCST header: 'P','C','S','T' + width + height + length
                        out.writeByte(0x50)
                        out.writeByte(0x43)
                        out.writeByte(0x53)
                        out.writeByte(0x54)
                        out.writeInt(snap.width)
                        out.writeInt(snap.height)
                        out.writeInt(snap.jpegBytes.size)
                        out.write(snap.jpegBytes)
                        out.flush()
                    }
                } catch (_: Throwable) {
                    if (running.get()) {
                        statusMessage = "Attente du PC $host:$port (Web :$DEFAULT_HTTP_PORT actif)..."
                        try {
                            Thread.sleep(1500L)
                        } catch (_: InterruptedException) {
                            break
                        }
                    }
                } finally {
                    try {
                        socket?.close()
                    } catch (_: Throwable) {}
                }
            }
        }, "PixelCastTcpPush")
        worker.isDaemon = true
        worker.start()
        tcpSenderThread = worker
    }

    private fun startHttpMjpegServer() {
        val serverThread = Thread({
            try {
                val server = ServerSocket()
                server.reuseAddress = true
                server.bind(InetSocketAddress(DEFAULT_HTTP_PORT))
                httpServerSocket = server

                while (running.get() && !server.isClosed) {
                    val client = try {
                        server.accept()
                    } catch (_: Throwable) {
                        break
                    }
                    Thread({ handleHttpClient(client) }, "PixelCastHttpClient").apply {
                        isDaemon = true
                        start()
                    }
                }
            } catch (_: Throwable) {}
        }, "PixelCastHttpServer")
        serverThread.isDaemon = true
        serverThread.start()
        httpAcceptThread = serverThread
    }

    private fun handleHttpClient(client: Socket) {
        client.use { sock ->
            sock.tcpNoDelay = true
            val reader = BufferedReader(InputStreamReader(sock.getInputStream()))
            val requestLine = reader.readLine() ?: return
            while (true) {
                val hdr = reader.readLine()
                if (hdr == null || hdr.isEmpty()) break
            }

            val out = sock.getOutputStream()
            if (requestLine.contains("GET /stream")) {
                val headers = (
                    "HTTP/1.1 200 OK\r\n" +
                    "Content-Type: multipart/x-mixed-replace; boundary=frame\r\n" +
                    "Cache-Control: no-cache, no-store, must-revalidate\r\n" +
                    "Connection: close\r\n\r\n"
                ).toByteArray(Charsets.UTF_8)
                out.write(headers)
                out.flush()

                var lastSeq = -1L
                while (running.get() && !sock.isClosed) {
                    val snap: FrameSnapshot?
                    synchronized(frameLock) {
                        if (latestFrame == null || latestFrame!!.sequence == lastSeq) {
                            frameLock.wait(250L)
                        }
                        snap = latestFrame
                    }
                    if (snap == null || snap.sequence == lastSeq) continue
                    lastSeq = snap.sequence

                    val partHeader = (
                        "--frame\r\n" +
                        "Content-Type: image/jpeg\r\n" +
                        "Content-Length: ${snap.jpegBytes.size}\r\n\r\n"
                    ).toByteArray(Charsets.UTF_8)
                    out.write(partHeader)
                    out.write(snap.jpegBytes)
                    out.write("\r\n".toByteArray(Charsets.UTF_8))
                    out.flush()
                }
            } else {
                val html = """
                    <!DOCTYPE html>
                    <html lang="fr">
                    <head>
                      <meta charset="utf-8"/>
                      <meta name="viewport" content="width=device-width,initial-scale=1"/>
                      <title>Pixel Wi-Fi Cast — En Direct</title>
                      <style>
                        body { margin:0; background:#111315; color:#fff; font-family:system-ui,sans-serif; display:flex; flex-direction:column; height:100vh; }
                        header { padding:10px 18px; background:#1e2126; display:flex; justify-content:space-between; align-items:center; }
                        .badge { color:#4ade80; font-weight:600; font-size:14px; }
                        button { background:#0f766e; color:#fff; border:none; padding:7px 14px; border-radius:8px; cursor:pointer; font-weight:600; }
                        main { flex:1; display:flex; justify-content:center; align-items:center; overflow:hidden; padding:8px; }
                        img { max-width:100%; max-height:100%; object-fit:contain; border-radius:8px; box-shadow:0 8px 30px rgba(0,0,0,.6); }
                      </style>
                    </head>
                    <body>
                      <header>
                        <span class="badge">● Pixel Wi-Fi Cast — Diffusion en direct (Sans Mode Débogage)</span>
                        <button onclick="document.documentElement.requestFullscreen()">Plein Écran</button>
                      </header>
                      <main><img src="/stream" alt="Écran en direct"/></main>
                    </body>
                    </html>
                """.trimIndent().toByteArray(Charsets.UTF_8)

                val resp = (
                    "HTTP/1.1 200 OK\r\n" +
                    "Content-Type: text/html; charset=utf-8\r\n" +
                    "Content-Length: ${html.size}\r\n" +
                    "Connection: close\r\n\r\n"
                ).toByteArray(Charsets.UTF_8)
                out.write(resp)
                out.write(html)
                out.flush()
            }
        }
    }

    private fun stopStreamingInternal() {
        if (!running.getAndSet(false) && !isStreaming) return
        isStreaming = false
        statusMessage = "Inactif"

        synchronized(frameLock) {
            frameLock.notifyAll()
        }

        try {
            httpServerSocket?.close()
        } catch (_: Throwable) {}
        httpServerSocket = null

        tcpSenderThread?.interrupt()
        tcpSenderThread = null

        captureHandler?.post {
            try {
                virtualDisplay?.release()
            } catch (_: Throwable) {}
            virtualDisplay = null

            try {
                imageReader?.close()
            } catch (_: Throwable) {}
            imageReader = null

            try {
                mediaProjection?.stop()
            } catch (_: Throwable) {}
            mediaProjection = null

            captureThread?.quitSafely()
        }
        captureHandler = null
        captureThread = null
    }

    override fun onDestroy() {
        stopStreamingInternal()
        super.onDestroy()
    }
}
