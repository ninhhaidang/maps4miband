import { test } from 'node:test'
import assert from 'node:assert/strict'
import { segments, rotate, label, inset, LINE, MAP_TOP, LABEL_W, LABEL_H } from '../src/common/render.js'

test('one segment per point pair, placed at its start point and rotated in screen degrees', () => {
  // right, then down (screen y grows downwards)
  const s = segments([0, 0, 10, 0, 10, 20])
  assert.deepEqual(s, [
    { l: -LINE / 2, t: -LINE / 2, w: 10 + LINE, r: '{"rotate":"0deg"}' },
    { l: 10 - LINE / 2, t: -LINE / 2, w: 20 + LINE, r: '{"rotate":"90deg"}' }
  ])
})

test('drops zero-length segments and odd trailing values', () => {
  assert.deepEqual(segments([5, 5, 5, 5, 7]), [])
  assert.deepEqual(segments([]), [])
})

test('rotate gives the JSON transform Vela expects', () => {
  assert.equal(rotate(-90), '{"rotate":"-90deg"}')
  assert.equal(rotate(44.6), '{"rotate":"45deg"}')
})

// The screen as measured with the ruler page (docs/band-screen.md): 212×520 with corners rounded at radius 100.
function onScreen(px, py) {
  const R = 100
  const cx = Math.min(Math.max(px, R), 212 - R)
  const cy = Math.min(Math.max(py, R), 520 - R)
  return (px - cx) ** 2 + (py - cy) ** 2 <= R * R
}

// The label is a w × LABEL_H box; the band can't measure text, so the box is what must stay readable.
function assertReadable(box, x, y) {
  for (const [px, py] of [[box.l, box.t], [box.l + box.w, box.t], [box.l, box.t + LABEL_H], [box.l + box.w, box.t + LABEL_H]]) {
    assert.ok(onScreen(px, py), `corner ${px},${py} of the label is cut off`)
  }
  assert.ok(box.t >= MAP_TOP, `under the panel: ${box.t}`)
  assert.ok(!overlaps(box, { l: x - 14, t: y - 14, w: 28, h: 28 }), 'covers the turn mark')
}

function overlaps(a, b) {
  return a.l < b.l + b.w && b.l < a.l + a.w && a.t < b.t + (b.h ?? LABEL_H) && b.t < a.t + (a.h ?? LABEL_H)
}

// The drawn road along an axis-aligned polyline, as LINE-wide boxes.
function road(p) {
  const out = []
  for (let k = 0; k + 3 < p.length; k += 2) {
    const [x1, y1, x2, y2] = p.slice(k, k + 4)
    out.push({ l: Math.min(x1, x2) - LINE / 2, t: Math.min(y1, y2) - LINE / 2, w: Math.abs(x2 - x1) + LINE, h: Math.abs(y2 - y1) + LINE })
  }
  return out
}

const LONG = 'Đường Nguyễn Văn Linh kéo dài'

test('labels the turn just above it, centred on it, when the road leaves it sideways', () => {
  const p = [106, 460, 106, 300, 0, 300]
  const box = label(106, 300, LONG, p)
  assertReadable(box, 106, 300)
  assert.equal(box.l + box.w / 2, 106)
  assert.ok(box.t < 300)
  assert.ok(!road(p).some((r) => overlaps(box, r)))
})

test('keeps the label off the road when the road goes on straight up past the turn', () => {
  // the photo in #13: "Phan Huy Chú" sat on the road
  const p = [106, 460, 106, 300, 106, 170]
  const box = label(106, 300, 'Phan Huy Chú', p)
  assertReadable(box, 106, 300)
  assert.ok(!road(p).some((r) => overlaps(box, r)), JSON.stringify(box))
})

test('keeps the label off both legs of a right turn', () => {
  const p = [106, 460, 106, 300, 212, 300]
  const box = label(106, 300, 'Phan Huy Chú', p)
  assertReadable(box, 106, 300)
  assert.ok(!road(p).some((r) => overlaps(box, r)), JSON.stringify(box))
})

test('a short street name gets a narrower box, a long one no wider than LABEL_W', () => {
  assert.ok(label(106, 300, 'Ngõ 7').w < label(106, 300, 'Phan Huy Chú').w)
  assert.equal(label(106, 300, LONG).w, LABEL_W)
})

test('a turn near the side keeps its label on screen', () => {
  for (const x of [0, 10, 200, 212]) assertReadable(label(x, 300, LONG), x, 300)
  // down where the rounded bottom end narrows the screen
  for (const x of [0, 40, 106, 170, 212]) for (const y of [470, 500, 515]) assertReadable(label(x, y, LONG), x, y)
})

test('a turn just below the panel gets its label underneath, one near the bottom above', () => {
  assertReadable(label(106, MAP_TOP + 4, LONG), 106, MAP_TOP + 4)
  assertReadable(label(106, 500, LONG), 106, 500)
})

test('no label for a turn under the panel or off the screen', () => {
  assert.equal(label(106, MAP_TOP - 1, LONG), null)
  assert.equal(label(-5, 300, LONG), null)
  assert.equal(label(217, 300, LONG), null)
  assert.equal(label(106, 521, LONG), null)
})

test('the rounded corners cut off what the ruler page showed on the band', () => {
  // px cut off each side of the row 10, 20 … 90 px from the top, read off a photo of the ruler page
  const read = [59, 41, 29, 20, 13, 8, 4, 2, 0]
  read.forEach((px, k) => assert.ok(Math.abs(inset((k + 1) * 10) - px) <= 4, `row ${(k + 1) * 10}: ${inset((k + 1) * 10)} vs ${px}`))
})
