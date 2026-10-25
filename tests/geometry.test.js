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

test("pressure width is gentle, monotonic, bounded, and distinguishes zero from missing", () => {
  assert.equal(Geometry.hasPressure([[1, 2], [3, 4, null]]), false)
  assert.equal(Geometry.hasPressure([[1, 2, 0]]), true)
  assert.equal(Geometry.pointPressure([1, 2]), 1)
  assert.equal(Geometry.pointPressure([1, 2, 0]), 0)
  assert.equal(Geometry.pointPressure([1, 2, NaN]), 1)
  assert.equal(Geometry.pressureWidth(4, 0), 1.2)
  assert.equal(Geometry.pressureWidth(4, 1), 4.4)
  assert.equal(Geometry.pressureWidth(4, undefined), 4)
  assert.equal(Geometry.pressureWidth(4, NaN), 4)
  assert.equal(Geometry.pressureWidth(4, -5), 1.2)
  assert.equal(Geometry.pressureWidth(4, 5), 4.4)
  let previous = 0
  for (let i = 0; i <= 100; i++) {
    const width = Geometry.pressureWidth(4, i / 100)
    assert.ok(width >= 1.2 && width <= 4.4 && width > previous)
    previous = width
  }
  assert.ok(Geometry.pressureWidth(4, 0.5) < 2.5, "mid pressure should not already look firm")
})

test("pressure range widens slightly while preserving the middle and fixed-width input", () => {
  const previous = pressure => 4 * (0.35 + 0.65 * Math.pow(pressure, 1.8))
  for (const pressure of [0.1, 0.25])
    assert.ok(Geometry.pressureWidth(4, pressure) < previous(pressure), "lighter contact should be finer")
  for (const pressure of [0.75, 1])
    assert.ok(Geometry.pressureWidth(4, pressure) > previous(pressure), "firm contact should be broader")
  assert.ok(Math.abs(Geometry.pressureWidth(4, 0.5) / previous(0.5) - 1) < 0.02,
    "keep the familiar mid-pressure feel within two percent")
  assert.equal(Geometry.pressureWidth(4, 0), 1.2)
  assert.equal(Geometry.pressureWidth(4, 1), 4.4)
  assert.equal(Geometry.pressureWidth(4, undefined), 4, "fixed-width input is unchanged")
})

test("selection envelopes include the boosted pressure width but not legacy strokes", () => {
  const pressure = { id: "stroke-1", type: "stroke", width: 10, points: [[20, 20, 1], [120, 20, 1]] }
  const legacy = { ...pressure, points: [[20, 20], [120, 20]] }
  assert.equal(Geometry.strokeMaxWidth(pressure), 11)
  assert.equal(Geometry.strokeMaxWidth(legacy), 10)
  assert.equal(Geometry.strokeMaxWidth({ ...pressure, points: [[20, 20, 0]] }), 11,
    "even zero-pressure samples use the conservative pressure envelope")
  assert.equal(Geometry.hitTest([pressure], [60, 25.4], 0), "stroke-1", "the visible outer edge remains selectable")
  assert.equal(Geometry.hitTest([legacy], [60, 25.4], 0), "")
})

test("eraser cuts interpolate pressure and preserve pressure dots", () => {
  const points = [[0, 0, 0], [100, 0, 1]]
  assert.deepEqual(Geometry.splitStroke(points, [50, 0], 10), [
    [[0, 0, 0], [40, 0, 0.4]], [[60, 0, 0.6], [100, 0, 1]]
  ])
  assert.deepEqual(Geometry.splitStroke([[1, 1, 0.2]], [30, 30], 2), [[[1, 1, 0.2]]])
  assert.deepEqual(Geometry.splitStroke([[1, 1, 0.2]], [1, 1], 2), [])
  assert.deepEqual(points, [[0, 0, 0], [100, 0, 1]])
  const mixed = Geometry.lerp([0, 0, 0], [100, 0], 0.5)
  assert.deepEqual(mixed, [50, 0, 0.5], "missing pressure interpolates from full width")
  assert.deepEqual(Geometry.lerp([0, 0], [100, 0], 0.5), [50, 0])
})

test("simplification preserves straight-line pressure extrema and stationary changes", () => {
  const ramp = [[0, 0, 0.1], [10, 0, 0.5], [20, 0, 0.9], [30, 0, 0.5], [40, 0, 0.1]]
  assert.deepEqual(Geometry.simplifyStroke(ramp, 0.35), [ramp[0], ramp[2], ramp[4]])
  const stationary = [[10, 10, 0.1], [10, 10, 0.9], [10, 10, 0.1]]
  assert.deepEqual(Geometry.simplifyStroke(stationary, 0.35), stationary)
  const constant = [[0, 0, 0.5], [10, 0.05, 0.5], [20, 0, 0.5]]
  assert.deepEqual(Geometry.simplifyStroke(constant, 0.35), [constant[0], constant[2]])
  assert.deepEqual(Geometry.simplifyStroke([[0, 0], [10, 0, 0], [20, 0]], 0.35),
    [[0, 0], [10, 0, 0], [20, 0]], "missing values must not be confused with light contact")
})

test("simplification falls back without data loss on adversarial pressure samples", () => {
  const points = Array.from({ length: 8192 }, (_, i) => [i / 20, 200, i % 2])
  const simplified = Geometry.simplifyStroke(points, 0.35)
  assert.notEqual(simplified, points)
  assert.deepEqual(simplified, points, "a linear work budget must not flatten pressure detail")
})

test("pressure paths keep endpoints, follow midpoint curves, and bound subdivision", () => {
  assert.deepEqual(Geometry.pressurePath([]), [])
  assert.deepEqual(Geometry.pressurePath([[1, 2, 0]]), [[1, 2, 0]])
  const held = [[10, 10, 0.1], [10, 10, 0.9], [10, 10, 0.2]]
  assert.deepEqual(Geometry.pressurePath(held), held, "easing off must not shrink a held dot")
  const points = [[0, 0, 0.1], [500, 700, 1], [1000, 0, 0.2]]
  const path = Geometry.pressurePath(points)
  assert.deepEqual(path[0], points[0])
  assert.deepEqual(path.at(-1), points.at(-1))
  assert.ok(path.length > 3 && path.length <= 66)
  assert.deepEqual(path.at(-2), Geometry.lerp(points[1], points[2], 0.5))
  for (const point of path) {
    assert.ok(point.every(Number.isFinite))
    assert.ok(point[2] >= 0.1 && point[2] <= 1)
  }
  assert.deepEqual(points, [[0, 0, 0.1], [500, 700, 1], [1000, 0, 0.2]])
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
