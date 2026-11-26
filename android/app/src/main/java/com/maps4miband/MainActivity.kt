package com.maps4miband

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.location.Geocoder
import android.os.Build
import android.os.Bundle
import android.text.InputType
import android.widget.Button
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.TextView

class MainActivity : Activity() {
    private lateinit var dest: EditText
    private lateinit var mac: EditText
    private lateinit var status: TextView
    private val prefs by lazy { getSharedPreferences("main", MODE_PRIVATE) }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        dest = EditText(this).apply { hint = "Điểm đến: địa chỉ hoặc vĩ độ,kinh độ" }
        mac = EditText(this).apply {
            hint = "MAC của vòng (Gadgetbridge → chi tiết thiết bị)"
            inputType = InputType.TYPE_TEXT_FLAG_CAP_CHARACTERS
            setText(prefs.getString("mac", ""))
        }
        status = TextView(this)
        val start = Button(this).apply { text = "Bắt đầu dẫn đường"; setOnClickListener { start() } }
        val stop = Button(this).apply {
            text = "Dừng"
            setOnClickListener { startService(Intent(this@MainActivity, NavService::class.java).setAction(NavService.ACTION_STOP)) }
        }
        setContentView(LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(48, 96, 48, 48)
            listOf(dest, mac, start, stop, status).forEach(::addView)
        })
        onNewIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        // geo:21.03,105.83 or geo:0,0?q=21.03,105.83(Label) or geo:0,0?q=some address
        val data = intent.data?.takeIf { it.scheme == "geo" } ?: return
        val q = data.schemeSpecificPart.substringAfter("q=", "")
        dest.setText(if (q.isNotEmpty()) q.substringBefore('(') else data.schemeSpecificPart.substringBefore('?'))
    }

    private fun start() {
        val perms = listOfNotNull(
            Manifest.permission.ACCESS_FINE_LOCATION,
            if (Build.VERSION.SDK_INT >= 33) Manifest.permission.POST_NOTIFICATIONS else null,
        ).filter { checkSelfPermission(it) != PackageManager.PERMISSION_GRANTED }
        if (perms.isNotEmpty()) {
            requestPermissions(perms.toTypedArray(), 1)
            return
        }
        val m = mac.text.toString().trim().uppercase()
        if (!Regex("^([0-9A-F]{2}:){5}[0-9A-F]{2}$").matches(m)) {
            status.text = "MAC không hợp lệ, dạng AA:BB:CC:DD:EE:FF"
            return
        }
        prefs.edit().putString("mac", m).apply()
        val text = dest.text.toString().trim()
        status.text = "Đang tìm điểm đến…"
        Thread {
            val p = resolve(text)
            runOnUiThread {
                if (p == null) {
                    status.text = "Không tìm thấy \"$text\""
                } else {
                    startNav(this, p, m)
                    status.text = "Đang dẫn đường tới ${"%.5f, %.5f".format(p.lat, p.lon)}.\nMở app Dẫn đường trên vòng."
                }
            }
        }.start()
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        if (grantResults.isNotEmpty() && grantResults.all { it == PackageManager.PERMISSION_GRANTED }) start()
        else status.text = "Cần quyền vị trí và thông báo để dẫn đường"
    }

    private fun resolve(text: String): Pt? {
        Regex("""^\s*(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)""").find(text)?.let {
            return Pt(it.groupValues[1].toDouble(), it.groupValues[2].toDouble())
        }
        if (text.isEmpty() || !Geocoder.isPresent()) return null
        @Suppress("DEPRECATION") // the async overload is API 33+
        val a = runCatching { Geocoder(this).getFromLocationName(text, 1)?.firstOrNull() }.getOrNull()
        return a?.let { Pt(it.latitude, it.longitude) }
    }
}
