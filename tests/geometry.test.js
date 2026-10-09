const test = require("node:test")
const assert = require("node:assert/strict")
const Geometry = require("../Geometry.js")

test("computes point and segment distances", () => {
  assert.equal(Geometry.pointDistance([0, 0], [3, 4]), 5)
  assert.equal(Geometry.segmentDistance([5, 4], [0, 0], [10, 0]), 4)
  assert.equal(Geometry.segmentDistance([-3, 4], [0, 0], [10, 0]), 5)
})

test("splits a stroke around an eraser footprint", () => {
  const points = [[0, 0], [5, 0], [10, 0], [15, 0], [20, 0], [25, 0], [30, 0], [35, 0], [40, 0]]

  assert.deepEqual(Geometry.splitStroke(points, [20, 0], 6), [
    [[0, 0], [5, 0], [10, 0]],
    [[30, 0], [35, 0], [40, 0]]
  ])
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
