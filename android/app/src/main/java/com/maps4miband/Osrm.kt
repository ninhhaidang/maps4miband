package com.maps4miband

import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL

// shortcut: OSRM's public demo server, car profile only, fair-use limits; self-host OSRM/Valhalla for real use or bike/foot.
fun fetchRoute(from: Pt, to: Pt): Route {
    val url = URL(
        "https://router.project-osrm.org/route/v1/driving/" +
            "${from.lon},${from.lat};${to.lon},${to.lat}?overview=false&steps=true&geometries=geojson"
    )
    val conn = url.openConnection() as HttpURLConnection
    conn.setRequestProperty("User-Agent", "maps4miband")
    conn.connectTimeout = 10_000
    conn.readTimeout = 15_000
    try {
        val body = (if (conn.responseCode < 400) conn.inputStream else conn.errorStream).bufferedReader().readText()
        return parseOsrm(body)
    } finally {
        conn.disconnect()
    }
}

fun parseOsrm(json: String): Route {
    val root = JSONObject(json)
    require(root.optString("code") == "Ok") { "OSRM: ${root.optString("message", root.optString("code"))}" }
    val steps = root.getJSONArray("routes").getJSONObject(0)
        .getJSONArray("legs").getJSONObject(0).getJSONArray("steps")
    val pts = ArrayList<Pt>()
    val mans = ArrayList<Maneuver>()
    for (s in 0 until steps.length()) {
        val step = steps.getJSONObject(s)
        val coords = step.getJSONObject("geometry").getJSONArray("coordinates")
        // Each step starts (at its maneuver) where the previous one ended; drop that repeat.
        val at = maxOf(pts.size - 1, 0)
        for (c in 0 until coords.length()) {
            val xy = coords.getJSONArray(c)
            val p = Pt(xy.getDouble(1), xy.getDouble(0))
            if (pts.lastOrNull() != p) pts += p
        }
        val m = step.getJSONObject("maneuver")
        mans += Maneuver(at, instruction(m, step.optString("name")), angleOf(m))
    }
    require(pts.size >= 2) { "OSRM: route too short" }
    return Route(pts, mans)
}

// OSRM's modifier, not bearing_before/after: those come from a few metres of geometry and can say +4° for a left turn.
private val MODIFIER = mapOf(
    "uturn" to ("Quay đầu" to 180),
    "sharp right" to ("Rẽ gắt phải" to 135),
    "right" to ("Rẽ phải" to 90),
    "slight right" to ("Chếch phải" to 45),
    "straight" to ("Đi thẳng" to 0),
    "slight left" to ("Chếch trái" to -45),
    "left" to ("Rẽ trái" to -90),
    "sharp left" to ("Rẽ gắt trái" to -135),
)

private fun angleOf(m: JSONObject): Int? =
    if (m.getString("type") in setOf("depart", "arrive")) null else MODIFIER[m.optString("modifier")]?.second

fun instruction(m: JSONObject, road: String): String {
    val base = when (m.getString("type")) {
        "arrive" -> return "Đến nơi"
        "depart" -> "Xuất phát"
        "roundabout", "rotary" -> "Vòng xuyến, lối ra thứ ${m.optInt("exit", 1)}"
        else -> MODIFIER[m.optString("modifier")]?.first ?: "Đi tiếp"
    }
    return if (road.isBlank()) base else "$base vào $road"
}
