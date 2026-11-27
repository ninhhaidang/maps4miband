export const LINE = 8

// Measured with the ruler page (docs/band-screen.md): the long edges show every px, the corners are rounded at
// radius 100, so both ends are close to half circles.
export const SAFE = { side: 0, radius: 100 }
// The instruction panel covers y < MAP_TOP; the map shows below it (index.ux .panel height).
export const MAP_TOP = 170
// Street-name box beside a turn mark (index.ux .label): at most LABEL_W wide, LABEL_H high on one line and
// LABEL_H2 on two; longer names end in "…".
export const LABEL_W = 150
export const LABEL_H = 26
const LABEL_H2 = 42
// shortcut: Vela can't measure text, so the box is sized from the name's length at ~9 px a character of the 14 px
// bold font ("Phan Huy Chú" got "…" in 98 px on the band); if names still get cut off while there is room, raise it.
const CHAR_W = 9
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

// Vela JS has no <canvas>: each polyline segment becomes an absolutely placed div `line` px thick, rotated around
// its start point (transform-origin line/2 in index.ux). It runs line/2 past both ends so rounded caps hide the joints.
export function segments(p, line = LINE) {
  const out = []
  for (let i = 0; i + 3 < p.length; i += 2) {
    const dx = p[i + 2] - p[i]
    const dy = p[i + 3] - p[i + 1]
    const len = Math.sqrt(dx * dx + dy * dy)
    if (len < 1) continue
    out.push({
      l: p[i] - line / 2,
      t: p[i + 1] - line / 2,
      w: Math.round(len + line),
      r: rotate((Math.atan2(dy, dx) * 180) / Math.PI)
    })
  }
  return out
}

// Where the street-name box for `name` goes beside a turn mark at (x, y), given the drawn polyline `p`: on one line or
// two, above or below the mark, centred or to one side, whichever covers the least road (the first in that order on
// a tie), kept on the map and clear of the rounded bottom end. null when the mark itself is not on the map.
export function label(x, y, name, p = []) {
  if (x < 0 || x > W || y < MAP_TOP || y > H) return null
  const width = (chars) => Math.min(LABEL_W, Math.ceil(PAD + CHAR_W * chars))
  const shapes = [{ lines: 1, w: width(name.length), h: LABEL_H }]
  // Two lines split at the space that leaves the longer line shortest; the band wraps greedily, which then fits too.
  const words = name.split(' ')
  let longest = name.length
  for (let k = 1; k < words.length; k++) {
    longest = Math.min(longest, Math.max(words.slice(0, k).join(' ').length, words.slice(k).join(' ').length))
  }
  if (words.length > 1) shapes.push({ lines: 2, w: width(longest), h: LABEL_H2 })

  let best = null
  for (const { lines, w, h } of shapes) {
    let floor = 0 // rows from the bottom edge a w-wide box must keep clear of
    while (inset(floor) > (W - w) / 2) floor++
    for (const above of [true, false]) {
      const t = Math.min(Math.max(above ? y - GAP - h : y + GAP, MAP_TOP), H - floor - h)
      const side = inset(H - t - h)
      for (const want of [x - w / 2, x + GAP, x - GAP - w]) {
        const l = Math.round(Math.min(Math.max(want, side), W - side - w))
        const onMark = l < x + GAP && x - GAP < l + w && t < y + GAP && y - GAP < t + h
        const cost = (onMark ? 1e6 : 0) + roadUnder(p, l, t, w, h)
        if (!best || cost < best.cost) best = { l, t, w, h, lines, cost }
      }
    }
  }
  return { l: best.l, t: best.t, w: best.w, h: best.h, lines: best.lines }
}

// How many px of the polyline's LINE-wide stroke fall in the box (sampled every px along each segment).
function roadUnder(p, l, t, w, h) {
  let n = 0
  for (let k = 0; k + 3 < p.length; k += 2) {
    const steps = Math.ceil(Math.hypot(p[k + 2] - p[k], p[k + 3] - p[k + 1]))
    for (let s = 0; s <= steps; s++) {
      const px = p[k] + ((p[k + 2] - p[k]) * s) / Math.max(steps, 1)
      const py = p[k + 1] + ((p[k + 3] - p[k + 1]) * s) / Math.max(steps, 1)
      if (px > l - LINE / 2 && px < l + w + LINE / 2 && py > t - LINE / 2 && py < t + h + LINE / 2) n++
    }
  }
  return n
}

const B64 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
const B64_VALUE = new Uint8Array(128)
for (let i = 0; i < 64; i++) B64_VALUE[B64.charCodeAt(i)] = i

// Bytes of a padded base64 string, for the grey-street picture the phone sends as text (interconnect carries strings
// only); the band may have no atob. Four characters to three bytes at a time: a character at a time took 0.6 s for
// 11 KB on the band.
export function fromBase64(s) {
  const pad = s.endsWith('==') ? 2 : s.endsWith('=') ? 1 : 0
  const out = new Uint8Array((s.length / 4) * 3 - pad)
  let k = 0
  for (let i = 0; i < s.length; i += 4) {
    const n = (B64_VALUE[s.charCodeAt(i)] << 18) | (B64_VALUE[s.charCodeAt(i + 1)] << 12) |
      (B64_VALUE[s.charCodeAt(i + 2)] << 6) | B64_VALUE[s.charCodeAt(i + 3)]
    out[k++] = n >> 16
    if (k < out.length) out[k++] = n >> 8
    if (k < out.length) out[k++] = n
  }
  return out
}
