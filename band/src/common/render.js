export const LINE = 8

// Measured with the ruler page (docs/band-screen.md): the long edges show every px, the corners are rounded at
// radius 100, so both ends are close to half circles.
export const SAFE = { side: 0, radius: 100 }
// The instruction panel covers y < MAP_TOP; the map shows below it (index.ux .panel height).
export const MAP_TOP = 170
// Street-name box beside a turn mark (index.ux .label).
export const LABEL_W = 150
export const LABEL_H = 26
const W = 212
const H = 520
const GAP = 12

// px the rounded corners cut off each side of the row `d` px from the top or bottom edge.
export function inset(d) {
  const r = SAFE.radius
  if (d >= r) return SAFE.side
  return Math.max(SAFE.side, Math.ceil(r - Math.sqrt(r * r - (r - d) * (r - d))))
}

// Rows from the bottom edge a centred label must keep clear of to fit its full width.
let labelFloor = 0
while (inset(labelFloor) > (W - LABEL_W) / 2) labelFloor++

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

// Where the street-name box goes for a turn mark at (x, y): just above it, or below if that would reach under the
// panel; kept clear of the rounded bottom end. null when the mark itself is not on the map.
export function label(x, y) {
  if (x < 0 || x > W || y < MAP_TOP || y > H) return null
  const above = y - GAP - LABEL_H
  const t = Math.min(above < MAP_TOP ? y + GAP : above, H - labelFloor - LABEL_H)
  const side = inset(H - t - LABEL_H)
  return { l: Math.min(Math.max(Math.round(x - LABEL_W / 2), side), W - side - LABEL_W), t }
}
