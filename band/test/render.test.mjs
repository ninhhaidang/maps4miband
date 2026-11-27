import { test } from 'node:test'
import assert from 'node:assert/strict'
import { segments, rotate, LINE } from '../src/common/render.js'

test('one segment per point pair, centred on its midpoint and rotated in screen degrees', () => {
  // right, then down (screen y grows downwards)
  const s = segments([0, 0, 10, 0, 10, 20])
  assert.deepEqual(s, [
    { l: 5 - (10 + LINE) / 2, t: -LINE / 2, w: 10 + LINE, r: '{"rotate":"0deg"}' },
    { l: 10 - (20 + LINE) / 2, t: 10 - LINE / 2, w: 20 + LINE, r: '{"rotate":"90deg"}' }
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
