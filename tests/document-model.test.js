const test = require("node:test")
const assert = require("node:assert/strict")
const Model = require("../DocumentModel.js")

test("creates a bounded empty document", () => {
  assert.deepEqual(Model.createDocument(760, 560), {
    schemaVersion: 1,
    page: { width: 760, height: 560 },
    objects: [],
    ui: { tool: "pen", penWidth: 2.5 }
  })
})

test("adds an immutable clamped stroke with a unique id", () => {
  const before = Model.createDocument(760, 560)
  const first = Model.addStroke(before, [[-10, 20], [800, 600]], 3)
  const second = Model.addStroke(first, [[30, 40], [31, 41]], 2)

  assert.equal(before.objects.length, 0)
  assert.deepEqual(first.objects[0], {
    id: "stroke-1",
    type: "stroke",
    color: "graphite",
    width: 3,
    points: [[0, 20], [760, 560]]
  })
  assert.equal(second.objects[1].id, "stroke-2")
})

test("deletes one object immutably and clears the document", () => {
  const withStroke = Model.addStroke(Model.createDocument(760, 560), [[1, 1], [2, 2]], 2)
  const deleted = Model.deleteObject(withStroke, "stroke-1")
  const cleared = Model.clearDocument(withStroke)

  assert.equal(withStroke.objects.length, 1)
  assert.deepEqual(deleted.objects, [])
  assert.deepEqual(cleared.objects, [])
})

test("replaces an erased stroke with editable remaining segments", () => {
  const original = Model.addStroke(
    Model.createDocument(760, 560),
    [[0, 10], [10, 10], [20, 10], [30, 10], [40, 10]],
    4
  )
  const next = Model.replaceStrokeSegments(original, "stroke-1", [
    [[0, 10], [10, 10]],
    [[30, 10], [40, 10]]
  ])

  assert.equal(original.objects.length, 1)
  assert.deepEqual(next.objects.map(object => object.id), ["stroke-1", "stroke-2"])
  assert.deepEqual(next.objects.map(object => object.points), [
    [[0, 10], [10, 10]],
    [[30, 10], [40, 10]]
  ])
  assert.deepEqual(next.objects.map(object => object.width), [4, 4])
})

test("creates, edits, and moves a bounded text note", () => {
  const empty = Model.createDocument(760, 560)
  const added = Model.addText(empty, 740, 550, "Draft")
  const edited = Model.updateText(added, "text-1", "x".repeat(5000))
  const moved = Model.moveText(edited, "text-1", -20, 900)

  assert.deepEqual(added.objects[0], {
    id: "text-1", type: "text", x: 540, y: 520, width: 220, height: 40, text: "Draft", size: 16
  })
  assert.equal(edited.objects[0].text.length, 4096)
  assert.equal(moved.objects[0].x, 0)
  assert.equal(moved.objects[0].y, 520)
})
