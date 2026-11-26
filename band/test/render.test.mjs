import { test } from 'node:test'
import assert from 'node:assert/strict'
import { segments, LINE } from '../src/common/render.js'

test('one segment per point pair, angle in screen degrees', () => {
  // right, then down (screen y grows downwards)
  const s = segments([0, 0, 10, 0, 10, 20])
  assert.deepEqual(s, [
    { l: -LINE / 2, t: -LINE / 2, w: 10 + LINE, r: 0 },
    { l: 10 - LINE / 2, t: -LINE / 2, w: 20 + LINE, r: 90 }
  ])
})

test('drops zero-length segments and odd trailing values', () => {
  assert.deepEqual(segments([5, 5, 5, 5, 7]), [])
  assert.deepEqual(segments([]), [])
})
