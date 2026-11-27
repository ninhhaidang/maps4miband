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

// The label is a LABEL_W × LABEL_H box; the band can't measure text, so the box is what must stay readable.
function assertReadable(box, x, y) {
  for (const [px, py] of [[box.l, box.t], [box.l + LABEL_W, box.t], [box.l, box.t + LABEL_H], [box.l + LABEL_W, box.t + LABEL_H]]) {
    assert.ok(onScreen(px, py), `corner ${px},${py} of the label is cut off`)
  }
  assert.ok(box.t >= MAP_TOP, `under the panel: ${box.t}`)
  assert.ok(box.t + LABEL_H <= y - 6 || box.t >= y + 6, 'does not cover the turn mark')
}

test('labels the turn just above it, centred on it', () => {
  const box = label(106, 300)
  assertReadable(box, 106, 300)
  assert.equal(box.l + LABEL_W / 2, 106)
  assert.ok(box.t < 300)
})

test('a turn near the side keeps its label on screen', () => {
  for (const x of [0, 10, 200, 212]) assertReadable(label(x, 300), x, 300)
  // down where the rounded bottom end narrows the screen
  for (const x of [0, 40, 106, 170, 212]) for (const y of [470, 500, 515]) assertReadable(label(x, y), x, y)
})

test('a turn just below the panel gets its label underneath, one near the bottom above', () => {
  const high = label(106, MAP_TOP + 4)
  assertReadable(high, 106, MAP_TOP + 4)
  const low = label(106, 500)
  assertReadable(low, 106, 500)
})

test('no label for a turn under the panel or off the screen', () => {
  assert.equal(label(106, MAP_TOP - 1), null)
  assert.equal(label(-5, 300), null)
  assert.equal(label(217, 300), null)
  assert.equal(label(106, 521), null)
})

test('the rounded corners cut off what the ruler page showed on the band', () => {
  // px cut off each side of the row 10, 20 … 90 px from the top, read off a photo of the ruler page
  const read = [59, 41, 29, 20, 13, 8, 4, 2, 0]
  read.forEach((px, k) => assert.ok(Math.abs(inset((k + 1) * 10) - px) <= 4, `row ${(k + 1) * 10}: ${inset((k + 1) * 10)} vs ${px}`))
})
