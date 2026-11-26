package com.maps4miband

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject

/** Follows GPS, snaps to the route and pushes one screen to the band through Gadgetbridge every few seconds. */
class NavService : Service(), LocationListener {
    companion object {
        const val EXTRA_LAT = "lat"
        const val EXTRA_LON = "lon"
        const val EXTRA_MAC = "mac"
        const val ACTION_STOP = "com.maps4miband.STOP"
        // Must match "package" in band/src/manifest.json.
        const val BAND_APP = "com.maps4miband.band"
        private const val GB_SEND = "nodomain.freeyourgadget.gadgetbridge.command.SEND_WATCH_APP_MESSAGE"
        private const val SEND_EVERY_MS = 3_000L
        private const val REROUTE_EVERY_MS = 10_000L
        private const val OFF_ROUTE_M = 40.0
        private const val OFF_ROUTE_FIXES = 3
        private const val BUZZ_BEFORE_M = 60.0
        private const val ARRIVED_M = 20.0
        private const val NOTIF_ID = 1
    }

    private val main = Handler(Looper.getMainLooper())
    private lateinit var dest: Pt
    private lateinit var mac: String
    private var route: Route? = null
    private var seg = 0
    private var offFixes = 0
    private var routing = false
    private var lastRouteAt = 0L
    private var lastSendAt = 0L
    private var buzzed: Maneuver? = null

    override fun onBind(intent: Intent?) = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent == null || intent.action == ACTION_STOP) {
            if (::mac.isInitialized) send(JSONObject().put("i", "Đã dừng dẫn đường"))
            stopSelf()
            return START_NOT_STICKY
        }
        dest = Pt(intent.getDoubleExtra(EXTRA_LAT, 0.0), intent.getDoubleExtra(EXTRA_LON, 0.0))
        mac = intent.getStringExtra(EXTRA_MAC)!!
        route = null
        seg = 0
        val n = notification("Đang chờ GPS…")
        if (Build.VERSION.SDK_INT >= 29) startForeground(NOTIF_ID, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION)
        else startForeground(NOTIF_ID, n)
        val lm = getSystemService(LocationManager::class.java)
        lm.removeUpdates(this)
        try {
            lm.requestLocationUpdates(LocationManager.GPS_PROVIDER, 2_000L, 0f, this, Looper.getMainLooper())
        } catch (e: SecurityException) {
            Log.w("nav", "no location permission", e)
            stopSelf()
        }
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        getSystemService(LocationManager::class.java).removeUpdates(this)
        super.onDestroy()
    }

    override fun onLocationChanged(loc: Location) {
        val here = Pt(loc.latitude, loc.longitude)
        val r = route ?: return reroute(here)
        val f = frame(r, here, seg)
        seg = f.seg
        offFixes = if (f.offRouteM > OFF_ROUTE_M) offFixes + 1 else 0
        if (offFixes >= OFF_ROUTE_FIXES) return reroute(here)

        if (f.remainingM < ARRIVED_M) {
            send(JSONObject().put("p", JSONArray(f.poly)).put("d", "").put("i", "Đã đến nơi").put("v", 1))
            stopSelf()
            return
        }
        val buzz = f.toTurnM < BUZZ_BEFORE_M && buzzed !== f.turn
        if (!buzz && SystemClock.elapsedRealtime() - lastSendAt < SEND_EVERY_MS) return
        if (buzz) buzzed = f.turn
        send(
            JSONObject()
                .put("p", JSONArray(f.poly))
                .put("a", f.turn.angle ?: JSONObject.NULL)
                .put("d", fmtDist(f.toTurnM))
                .put("i", f.turn.text)
                .put("r", "Còn ${fmtDist(f.remainingM)}")
                .put("v", if (buzz) 1 else 0)
        )
    }

    private fun reroute(here: Pt) {
        val now = SystemClock.elapsedRealtime()
        if (routing || now - lastRouteAt < REROUTE_EVERY_MS) return
        routing = true
        lastRouteAt = now
        send(JSONObject().put("i", if (route == null) "Đang tìm đường…" else "Đang tìm đường lại…"))
        Thread {
            val result = runCatching { fetchRoute(here, dest) }
            main.post {
                routing = false
                result.onSuccess {
                    route = it
                    seg = 0
                    offFixes = 0
                    buzzed = null
                }.onFailure {
                    Log.w("nav", "routing failed", it)
                    send(JSONObject().put("i", "Lỗi tìm đường: ${it.message}"))
                }
            }
        }.start()
    }

    private fun send(msg: JSONObject) {
        lastSendAt = SystemClock.elapsedRealtime()
        sendBroadcast(
            Intent(GB_SEND)
                .putExtra("device", mac)
                .putExtra("appId", BAND_APP)
                .putExtra("payload", msg.toString())
        )
        getSystemService(NotificationManager::class.java)
            .notify(NOTIF_ID, notification(listOf(msg.optString("d"), msg.optString("i")).filter { it.isNotEmpty() }.joinToString(" · ")))
    }

    private fun notification(text: String): Notification {
        val nm = getSystemService(NotificationManager::class.java)
        nm.createNotificationChannel(NotificationChannel("nav", "Dẫn đường", NotificationManager.IMPORTANCE_LOW))
        val stop = PendingIntent.getService(
            this, 0, Intent(this, NavService::class.java).setAction(ACTION_STOP), PendingIntent.FLAG_IMMUTABLE
        )
        return Notification.Builder(this, "nav")
            .setSmallIcon(android.R.drawable.ic_menu_directions)
            .setContentTitle("Dẫn đường trên Mi Band")
            .setContentText(text)
            .setOngoing(true)
            .addAction(Notification.Action.Builder(null, "Dừng", stop).build())
            .build()
    }
}

fun startNav(ctx: Context, dest: Pt, mac: String) {
    ctx.startForegroundService(
        Intent(ctx, NavService::class.java)
            .putExtra(NavService.EXTRA_LAT, dest.lat)
            .putExtra(NavService.EXTRA_LON, dest.lon)
            .putExtra(NavService.EXTRA_MAC, mac)
    )
}
