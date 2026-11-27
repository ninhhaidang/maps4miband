export const LINE = 8

// Measured with the ruler page (docs/band-screen.md): the long edges show every px, the corners are rounded at
// radius 100, so both ends are close to half circles.
export const SAFE = { side: 0, radius: 100 }
// The instruction panel covers y < MAP_TOP; the map shows below it (index.ux .panel height).
export const MAP_TOP = 170
// Street-name box beside a turn mark (index.ux .label): at most LABEL_W wide, longer names end in "…".
export const LABEL_W = 150
export const LABEL_H = 26
// shortcut: Vela can't measure text, so the box is sized from the name's length at ~7.5 px a character of the 14 px
// bold font (from a photo of the band); if names get cut off with "…" while there is room, raise it.
const CHAR_W = 7.5
const PAD = 8
const W = 212
const H = 520
// From the mark's centre to the label: the 16 px mark plus a gap.
const GAP = 16

// px the rounded corners cut off each side of the row `d` px from the top or bottom edge.
export function inset(d) {
  const r = SAFE.radius
  if (d >= r) return SAFE.side
  return Math.max(SAFE.side, Math.ceil(r - Math.sqrt(r * r - (r - d) * (r - d))))
}

// Vela applies transform only as JSON ('{"rotate":"45deg"}'). The compiler converts class CSS to that form,
// but inline {{}} styles reach the band as written, so build the JSON here.
export function rotate(deg) {
  return JSON.stringify({ rotate: Math.round(deg) + 'deg' })
}

// Vela JS has no <canvas>: each polyline segment becomes an absolutely placed div rotated around its start
// point (transform-origin 4px 4px in index.ux). It runs LINE/2 past both ends so rounded caps hide the joints.
export function segments(p) {
  const out = []
  for (let i = 0; i + 3 < p.length; i += 2) {
    const dx = p[i + 2] - p[i]
    const dy = p[i + 3] - p[i + 1]
    const len = Math.sqrt(dx * dx + dy * dy)
    if (len < 1) continue
    out.push({
      l: p[i] - LINE / 2,
      t: p[i + 1] - LINE / 2,
      w: Math.round(len + LINE),
      r: rotate((Math.atan2(dy, dx) * 180) / Math.PI)
    })
  }
  return out
}

// Where the street-name box for `name` goes beside a turn mark at (x, y), given the drawn polyline `p`: above or below
// the mark, centred or to one side, whichever covers the least road (the first in that order on a tie), kept on the
// map and clear of the rounded bottom end. null when the mark itself is not on the map.
export function label(x, y, name, p = []) {
  if (x < 0 || x > W || y < MAP_TOP || y > H) return null
  const w = Math.min(LABEL_W, Math.ceil(PAD + CHAR_W * name.length))
  let floor = 0 // rows from the bottom edge a w-wide box must keep clear of
  while (inset(floor) > (W - w) / 2) floor++
  let best = null
  for (const above of [true, false]) {
    const t = Math.min(Math.max(above ? y - GAP - LABEL_H : y + GAP, MAP_TOP), H - floor - LABEL_H)
    const side = inset(H - t - LABEL_H)
    for (const want of [x - w / 2, x + GAP, x - GAP - w]) {
      const l = Math.round(Math.min(Math.max(want, side), W - side - w))
      const onMark = l < x + GAP && x - GAP < l + w && t < y + GAP && y - GAP < t + LABEL_H
      const cost = (onMark ? 1e6 : 0) + roadUnder(p, l, t, w)
      if (!best || cost < best.cost) best = { l, t, w, cost }
    }
  }
  return { l: best.l, t: best.t, w: best.w }
}

// How many px of the polyline's LINE-wide stroke fall in the box (sampled every px along each segment).
function roadUnder(p, l, t, w) {
  let n = 0
  for (let k = 0; k + 3 < p.length; k += 2) {
    const steps = Math.ceil(Math.hypot(p[k + 2] - p[k], p[k + 3] - p[k + 1]))
    for (let s = 0; s <= steps; s++) {
      const px = p[k] + ((p[k + 2] - p[k]) * s) / Math.max(steps, 1)
      const py = p[k + 1] + ((p[k + 3] - p[k + 1]) * s) / Math.max(steps, 1)
      if (px > l - LINE / 2 && px < l + w + LINE / 2 && py > t - LINE / 2 && py < t + LABEL_H + LINE / 2) n++
    }
  }
  return n
}
