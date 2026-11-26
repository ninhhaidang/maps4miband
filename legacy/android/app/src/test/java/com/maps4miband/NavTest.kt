package com.maps4miband

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class NavTest {
    // Real OSRM answer: Cát Linh -> Lê Duẩn, Hà Nội, 1634 m, starts with a U-turn on Phố Cát Linh.
    private val route = parseOsrm(javaClass.getResource("/osrm_hanoi.json")!!.readText())

    @Test fun parsesStepsIntoOnePolyline() {
        assertEquals(8, route.maneuvers.size)
        assertEquals(0, route.maneuvers.first().at)
        assertEquals(route.pts.size - 1, route.maneuvers.last().at)
        assertEquals("Quay đầu vào Phố Cát Linh", route.maneuvers[1].text)
        assertEquals("Rẽ trái vào Phố Tôn Đức Thắng", route.maneuvers[2].text)
        assertEquals("Đến nơi", route.maneuvers.last().text)
        assertNull(route.maneuvers.first().angle)
        assertTrue(route.maneuvers[2].angle!! < -45) // left
        assertEquals(1634.0, route.cum.last(), 20.0)
    }

    @Test fun atStartTheNextTurnIsTheUturn() {
        val f = frame(route, route.pts[0], 0)
        assertEquals(route.maneuvers[1], f.turn)
        assertEquals(86.0, f.toTurnM, 5.0)
        assertEquals(1634.0, f.remainingM, 20.0)
        assertEquals(0.0, f.offRouteM, 1.0)
        assertEquals(listOf(ME_X, ME_Y), f.poly.take(2)) // rider is drawn at the marker
    }

    @Test fun headingUpWithTheTurnDrawnToTheRight() {
        // 100 m east, then 100 m south: a right turn whatever the compass says.
        val o = Pt(21.0, 105.8)
        val east = Pt(21.0, 105.8 + 100 / (111_320 * Math.cos(Math.toRadians(21.0))))
        val south = Pt(east.lat - 100 / 111_320.0, east.lon)
        val r = Route(listOf(o, east, south), listOf(Maneuver(0, "", null), Maneuver(1, "", 90), Maneuver(2, "", null)))
        val f = frame(r, o, 0)
        assertEquals(listOf(ME_X, ME_Y, ME_X, ME_Y - 50, ME_X + 50, ME_Y - 50), f.poly)
        assertEquals(100.0, f.toTurnM, 1.0)
    }

    @Test fun afterTheUturnItDoesNotSnapBackToTheOutboundLeg() {
        val back = route.maneuvers[1].at
        // Halfway down the outbound leg, which the return leg retraces.
        val p = route.pts[back / 2]
        val f = frame(route, p, back)
        assertTrue("snapped to ${f.seg}, before $back", f.seg >= back)
        assertEquals(route.maneuvers[2], f.turn)
    }

    @Test fun reportsOffRouteDistance() {
        val p = route.pts[0]
        val f = frame(route, Pt(p.lat + 0.002, p.lon), 0) // ~220 m north
        assertTrue(f.offRouteM > 100)
    }

    @Test fun formatsDistances() {
        assertEquals("80 m", fmtDist(83.0))
        assertEquals("1.6 km", fmtDist(1634.0))
    }
}
