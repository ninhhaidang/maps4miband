export const LINE = 8

// shortcut: safe area is a guess until the ruler page is read on a real band (docs/band-screen.md); then set it here
// and in index.ux. `side`: px the bezel hides along the long edges; `corner`: rows at top and bottom the rounded
// corners cut into, so text there must stay narrow and centred.
export const SAFE = { side: 8, corner: 40 }
// The instruction panel covers y < MAP_TOP; the map shows below it (index.ux .panel height).
export const MAP_TOP = 160
// Street-name box beside a turn mark (index.ux .label).
export const LABEL_W = 150
export const LABEL_H = 26
const W = 212
const H = 520
const GAP = 12

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
// panel; kept inside the safe area. null when the mark itself is not on the map.
export function label(x, y) {
  if (x < 0 || x > W || y < MAP_TOP || y > H) return null
  const l = Math.min(Math.max(Math.round(x - LABEL_W / 2), SAFE.side), W - SAFE.side - LABEL_W)
  const above = y - GAP - LABEL_H
  return { l, t: Math.min(above < MAP_TOP ? y + GAP : above, H - SAFE.corner - LABEL_H) }
}
