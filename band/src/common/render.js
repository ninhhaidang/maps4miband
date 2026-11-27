export const LINE = 8

// Vela applies transform only as JSON ('{"rotate":"45deg"}'). The compiler converts class CSS to that form,
// but inline {{}} styles reach the band as written, so build the JSON here.
export function rotate(deg) {
  return JSON.stringify({ rotate: Math.round(deg) + 'deg' })
}

// Vela JS has no <canvas>: each polyline segment becomes an absolutely placed div centred on the segment's
// midpoint and rotated about its centre (the default origin). It runs LINE/2 past both ends so rounded caps
// hide the joints.
export function segments(p) {
  const out = []
  for (let i = 0; i + 3 < p.length; i += 2) {
    const dx = p[i + 2] - p[i]
    const dy = p[i + 3] - p[i + 1]
    const len = Math.sqrt(dx * dx + dy * dy)
    if (len < 1) continue
    const w = Math.round(len + LINE)
    out.push({
      l: Math.round(p[i] + dx / 2 - w / 2),
      t: Math.round(p[i + 1] + dy / 2 - LINE / 2),
      w,
      r: rotate((Math.atan2(dy, dx) * 180) / Math.PI)
    })
  }
  return out
}
