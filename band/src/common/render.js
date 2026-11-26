export const LINE = 8

// Vela JS has no <canvas>: each polyline segment becomes an absolutely placed div rotated around
// its start point. The div runs LINE/2 past both ends so rounded caps hide the joints.
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
      r: Math.round((Math.atan2(dy, dx) * 180) / Math.PI)
    })
  }
  return out
}
