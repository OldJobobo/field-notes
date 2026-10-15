const test = require("node:test")
const assert = require("node:assert/strict")
const Geometry = require("../Geometry.js")

function rounded(segments) {
  return segments.map(segment => segment.map(([x, y]) => [Math.round(x * 100) / 100, Math.round(y * 100) / 100]))
}

test("computes point and segment distances", () => {
  assert.equal(Geometry.pointDistance([0, 0], [3, 4]), 5)
  assert.equal(Geometry.segmentDistance([5, 4], [0, 0], [10, 0]), 4)
  assert.equal(Geometry.segmentDistance([-3, 4], [0, 0], [10, 0]), 5)
})

test("splits a stroke exactly at the eraser footprint edge", () => {
  const points = [[0, 0], [5, 0], [10, 0], [15, 0], [20, 0], [25, 0], [30, 0], [35, 0], [40, 0]]

  assert.deepEqual(rounded(Geometry.splitStroke(points, [20, 0], 6)), [
    [[0, 0], [5, 0], [10, 0], [14, 0]],
    [[26, 0], [30, 0], [35, 0], [40, 0]]
  ])
})

test("cuts sparse segments whose endpoints both lie outside the eraser", () => {
  assert.deepEqual(rounded(Geometry.splitStroke([[0, 0], [100, 0]], [50, 0], 10)), [
    [[0, 0], [40, 0]],
    [[60, 0], [100, 0]]
  ])
  assert.deepEqual(Geometry.splitStroke([[0, 0], [100, 0]], [50, 30], 10), [[[0, 0], [100, 0]]])
})

test("erasing a stroke end removes it without leaving slivers", () => {
  assert.deepEqual(rounded(Geometry.splitStroke([[0, 0], [50, 0]], [50, 0], 10)), [[[0, 0], [40, 0]]])
  assert.deepEqual(Geometry.splitStroke([[0, 0], [10.5, 0]], [0, 0], 10), [])
  assert.deepEqual(Geometry.splitStroke([[0, 0], [4, 0]], [2, 0], 10), [])
})

test("detects eraser contact with strokes and notes", () => {
  assert.equal(Geometry.strokeTouches([[0, 0], [100, 0]], [50, 9], 10), true)
  assert.equal(Geometry.strokeTouches([[0, 0], [100, 0]], [50, 11], 10), false)
  const note = { x: 10, y: 10, width: 50, height: 20 }
  assert.equal(Geometry.rectTouches(note, [5, 15], 6), true)
  assert.equal(Geometry.rectTouches(note, [0, 0], 6), false)
})

test("hit tests the topmost stroke or text object", () => {
  const objects = [
    { id: "stroke-1", type: "stroke", width: 2, points: [[0, 10], [100, 10]] },
    { id: "text-1", type: "text", x: 20, y: 0, width: 50, height: 30, text: "top" }
  ]

  assert.equal(Geometry.hitTest(objects, [30, 10], 5), "text-1")
  assert.equal(Geometry.hitTest(objects, [80, 12], 5), "stroke-1")
  assert.equal(Geometry.hitTest(objects, [80, 30], 5), "")
})

test("simplifies nearly straight runs but keeps corners", () => {
  const line = [[0, 0], [1, 0.05], [2, -0.05], [3, 0], [4, 0.02], [5, 0]]
  assert.deepEqual(Geometry.simplifyStroke(line, 0.35), [[0, 0], [5, 0]])

  const corner = [[0, 0], [5, 0], [10, 0], [10, 5], [10, 10]]
  assert.deepEqual(Geometry.simplifyStroke(corner, 0.35), [[0, 0], [10, 0], [10, 10]])
  assert.deepEqual(Geometry.simplifyStroke([[1, 1]], 0.35), [[1, 1]])
})

test("steadies jagged mouse strokes without moving ends or rounding corners", () => {
  // A circle as a mouse reports it: whole pixels plus a slow wobble.
  const circle = []
  let wobble = 0
  for (let t = 0; t <= 2 * Math.PI; t += 0.004) {
    wobble = 0.9 * wobble + 0.3 * Math.sin(t * 97)
    const point = [Math.round(200 + 60 * Math.cos(t) + wobble), Math.round(200 + 60 * Math.sin(t) - wobble)]
    if (!circle.length || Geometry.pointDistance(circle[circle.length - 1], point) >= 1.5)
      circle.push(point)
  }
  const turning = points => {
    const s = Geometry.simplifyStroke(points, 0.35)
    let total = 0
    for (let i = 1; i + 1 < s.length; i++) {
      let d = Math.abs(Math.atan2(s[i + 1][1] - s[i][1], s[i + 1][0] - s[i][0]) - Math.atan2(s[i][1] - s[i - 1][1], s[i][0] - s[i - 1][0]))
      total += d > Math.PI ? 2 * Math.PI - d : d
    }
    return total / (2 * Math.PI)
  }
  const smooth = Geometry.smoothStroke(circle, 3.5)
  assert.ok(turning(circle) > 4, "the raw stroke zig-zags")
  assert.ok(turning(smooth) < 1.3, `a smoothed circle turns about once, got ${turning(smooth)}`)
  assert.deepEqual(smooth[0], circle[0])
  assert.deepEqual(smooth[smooth.length - 1], circle[circle.length - 1])

  const square = []
  for (let u = 0; u <= 100; u += 2) square.push([u, 0])
  for (let u = 2; u <= 100; u += 2) square.push([100, u])
  const corner = Geometry.smoothStroke(square, 3.5)
  assert.ok(Math.min(...corner.map(p => Geometry.pointDistance(p, [100, 0]))) < 1, "corners stay sharp")
})

test("leaves short strokes and dots untouched", () => {
  assert.deepEqual(Geometry.smoothStroke([[1, 1], [2, 2]], 3.5), [[1, 1], [2, 2]])
  assert.deepEqual(Geometry.smoothStroke([[1, 1], [2, 1], [3, 2]], 3.5), [[1, 1], [2, 1], [3, 2]])
})
