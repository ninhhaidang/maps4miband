package com.maps4miband

import kotlin.math.PI
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.hypot
import kotlin.math.roundToInt
import kotlin.math.sin

data class Pt(val lat: Double, val lon: Double)

/** A turn at route point [at]; [angle] is the turn in degrees (+ = right), null = no arrow. */
data class Maneuver(val at: Int, val text: String, val angle: Int?)

class Route(val pts: List<Pt>, val maneuvers: List<Maneuver>) {
    /** Metres from the start to each point. */
    val cum: DoubleArray = DoubleArray(pts.size).also {
        for (i in 1 until pts.size) it[i] = it[i - 1] + dist(pts[i - 1], pts[i])
    }
}

/** What the band shows for one position fix. [seg] is the route segment we are on; feed it back as the next hint. */
class Frame(
    val poly: List<Int>,
    val turn: Maneuver,
    val toTurnM: Double,
    val remainingM: Double,
    val offRouteM: Double,
    val seg: Int,
)

// Must match the rider marker in band/src/pages/index/index.ux.
const val ME_X = 106
const val ME_Y = 280
const val M_PER_PX = 2.0
private const val AHEAD_M = 700.0
private const val BEHIND_M = 100.0
private const val SEARCH_M = 500.0
private const val MIN_STEP_PX = 3.0
private const val R = 6371000.0

private fun rad(d: Double) = d * PI / 180

/** Equirectangular metres (east, north) of [p] relative to [o]; exact enough over a few km. */
fun local(o: Pt, p: Pt): Pair<Double, Double> =
    rad(p.lon - o.lon) * cos(rad(o.lat)) * R to rad(p.lat - o.lat) * R

fun dist(a: Pt, b: Pt): Double = local(a, b).let { (e, n) -> hypot(e, n) }

/**
 * Snaps [here] to the route and builds the heading-up screen polyline.
 * Only searches forward from [hint] (the last segment) so an out-and-back route can't snap to the return leg.
 */
fun frame(route: Route, here: Pt, hint: Int): Frame {
    val pts = route.pts
    var best = hint
    var bestT = 0.0
    var bestD = Double.MAX_VALUE
    var i = hint
    while (i < pts.size - 1 && route.cum[i] - route.cum[hint] <= SEARCH_M) {
        val (ax, ay) = local(here, pts[i])
        val (bx, by) = local(here, pts[i + 1])
        val dx = bx - ax
        val dy = by - ay
        val len2 = dx * dx + dy * dy
        val t = if (len2 == 0.0) 0.0 else ((-ax * dx - ay * dy) / len2).coerceIn(0.0, 1.0)
        val d = hypot(ax + t * dx, ay + t * dy)
        if (d < bestD) { best = i; bestT = t; bestD = d }
        i++
    }
    val segLen = route.cum[best + 1] - route.cum[best]
    val along = route.cum[best] + bestT * segLen
    val a = pts[best]
    val b = pts[best + 1]
    val snap = Pt(a.lat + bestT * (b.lat - a.lat), a.lon + bestT * (b.lon - a.lon))

    // Heading from the route rather than GPS: GPS bearing is noise at walking speed.
    val (he, hn) = local(a, b)
    val h = atan2(he, hn)
    val poly = ArrayList<Int>()
    var lastX = Double.NaN
    var lastY = Double.NaN
    fun add(p: Pt, force: Boolean = false) {
        val (e, n) = local(snap, p)
        val x = ME_X + (e * cos(h) - n * sin(h)) / M_PER_PX
        val y = ME_Y - (e * sin(h) + n * cos(h)) / M_PER_PX
        if (!force && hypot(x - lastX, y - lastY) < MIN_STEP_PX) return
        poly += x.roundToInt(); poly += y.roundToInt()
        lastX = x; lastY = y
    }
    var j = best
    while (j > 0 && along - route.cum[j] < BEHIND_M) j--
    for (k in j..best) add(pts[k])
    add(snap)
    for (k in best + 1 until pts.size) {
        add(pts[k], force = route.cum[k] - along >= AHEAD_M)
        if (route.cum[k] - along >= AHEAD_M) break
    }

    val turn = route.maneuvers.firstOrNull { it.at > best } ?: route.maneuvers.last()
    return Frame(
        poly = poly,
        turn = turn,
        toTurnM = (route.cum[turn.at] - along).coerceAtLeast(0.0),
        remainingM = route.cum.last() - along,
        offRouteM = bestD,
        seg = best,
    )
}

fun fmtDist(m: Double): String =
    if (m < 1000) "${(m / 10).roundToInt() * 10} m" else "%.1f km".format(java.util.Locale.US, m / 1000)
