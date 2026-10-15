const test = require("node:test")
const assert = require("node:assert/strict")
const Model = require("../DocumentModel.js")

test("creates a bounded empty document", () => {
  assert.deepEqual(Model.createDocument(760, 560), {
    schemaVersion: 1,
    page: { width: 760, height: 560 },
    paper: "graph",
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

test("edits share untouched objects and no-op edits return the same document", () => {
  const base = Model.addText(Model.addStroke(Model.createDocument(760, 560), [[1, 1], [9, 9]], 2), 10, 10, "a")
  const edited = Model.updateText(base, "text-1", "b", 28)

  assert.equal(edited.objects[0], base.objects[0])
  assert.equal(base.objects[1].text, "a")
  assert.equal(edited.objects[1].height, 28)
  assert.equal(Model.updateText(edited, "text-1", "b", 28), edited)
  assert.equal(Model.moveText(edited, "text-1", 10, 10), edited)
  assert.equal(Model.deleteObject(edited, "missing"), edited)
  assert.equal(Model.addStroke(edited, [], 2), edited)
  assert.equal(Model.sameObjects(Model.deleteObject(Model.addText(base, 0, 0, ""), "text-2"), base), true)
})

test("translates a stroke as a rigid shape that stays on the page", () => {
  const document = Model.addStroke(Model.createDocument(100, 100), [[10, 10], [30, 20]], 2)
  const moved = Model.translateObject(document, "stroke-1", 5, -3)
  assert.deepEqual(moved.objects[0].points, [[15, 7], [35, 17]])

  const pinned = Model.translateObject(document, "stroke-1", 500, -500)
  assert.deepEqual(pinned.objects[0].points, [[80, 0], [100, 10]])
  assert.equal(Model.translateObject(document, "stroke-1", 0, 0), document)

  const note = Model.addText(Model.createDocument(760, 560), 100, 100, "n")
  assert.deepEqual([Model.translateObject(note, "text-1", 20, 30).objects[0].x, Model.translateObject(note, "text-1", 20, 30).objects[0].y], [120, 130])
})

test("sanitizes untrusted saved state into a bounded notebook", () => {
  assert.equal(Model.sanitizeNotebook(null, 760, 560), null)
  assert.equal(Model.sanitizeNotebook({ schemaVersion: 3, sheets: [] }, 760, 560), null)
  assert.equal(Model.sanitizeNotebook({ schemaVersion: 2, objects: [] }, 760, 560), null)

  const clean = Model.sanitizeNotebook({
    schemaVersion: 1,
    objects: [
      { id: "stroke-1", type: "stroke", width: 99, points: [[1, 2], [NaN, 4], [900, -5]] },
      { id: "stroke-1", type: "stroke", width: 2, points: [[5, 5], [6, 6]] },
      { id: "<b>x</b>", type: "text", x: 9999, y: 10, width: 220, height: 40, text: "hi", size: 16 },
      { id: "text-4", type: "text", x: 0, y: 0, width: 220, height: 40, text: "   " },
      { id: "image-1", type: "image" },
      "junk"
    ],
    ui: { tool: "eraser", penWidth: 0.1, toolbar: "middle", boardX: 40, boardY: 60 }
  }, 760, 560)

  assert.equal(clean.documents.length, 1, "a version 1 file loads as a single sheet")
  assert.equal(clean.current, 0)
  const objects = clean.documents[0].objects
  assert.deepEqual(objects.map(object => object.id), ["stroke-1", "stroke-2", "text-1"])
  assert.equal(objects[0].width, 12)
  assert.deepEqual(objects[0].points, [[1, 2], [760, 0]])
  assert.equal(objects[2].x, 540)
  assert.deepEqual(clean.ui, { tool: "eraser", penWidth: 1, toolbar: "right", boardX: 40, boardY: 60 })
})

test("keeps only valid sheets and points at the open one", () => {
  const stroke = { id: "stroke-1", type: "stroke", width: 2, points: [[1, 1], [2, 2]] }
  const restored = Model.sanitizeNotebook({
    schemaVersion: 2,
    current: 3,
    sheets: [{ objects: [stroke] }, { objects: [] }, "junk", { objects: [] }, { objects: [stroke] }]
  }, 760, 560)
  assert.equal(restored.documents.length, 3, "blank sheets survive only when open")
  assert.equal(restored.current, 1)
  assert.deepEqual(restored.documents[1].objects, [])
  assert.deepEqual(restored.ui, { tool: "pen", penWidth: 2.5, toolbar: "right" })

  const empty = Model.sanitizeNotebook({ schemaVersion: 2, current: 7, sheets: [] }, 760, 560)
  assert.equal(empty.documents.length, 1)
  assert.equal(empty.current, 0)

  const many = Model.sanitizeNotebook({ schemaVersion: 2, sheets: Array(50).fill({ objects: [stroke] }) }, 760, 560)
  assert.equal(many.documents.length, Model.MAX_SHEETS)
})

test("round-trips a notebook through serialize and sanitize", () => {
  const first = Model.addText(Model.addStroke(Model.createDocument(760, 560), [[1, 1], [9, 9]], 3), 50, 60, "note")
  const second = Model.addStroke(Model.createDocument(760, 560), [[5, 5], [7, 8]], 2)
  const ui = { tool: "text", penWidth: 4, toolbar: "bottom", boardX: 12, boardY: 34 }
  const ruled = Model.setPaper(second, "ruled")
  const restored = Model.sanitizeNotebook(JSON.parse(Model.serialize([first, ruled], 1, ui)), 760, 560)
  assert.deepEqual(restored.documents.map(document => document.objects), [first.objects, second.objects])
  assert.deepEqual(restored.documents.map(document => document.paper), ["graph", "ruled"])
  assert.equal(restored.current, 1)
  assert.deepEqual(restored.ui, ui)
})

test("each sheet has a paper type that cycles and survives edits", () => {
  assert.deepEqual(Model.PAPERS, ["graph", "dots", "ruled", "plain"])
  assert.equal(Model.createDocument(760, 560, "dots").paper, "dots")
  assert.equal(Model.createDocument(760, 560, "napkin").paper, "graph")
  assert.deepEqual(Model.PAPERS.map(Model.nextPaper), ["dots", "ruled", "plain", "graph"])

  const ruled = Model.setPaper(Model.createDocument(760, 560), "ruled")
  assert.equal(Model.setPaper(ruled, "ruled"), ruled, "setting the same paper is a no-op")
  assert.equal(Model.setPaper(ruled, "napkin"), ruled)
  const edited = Model.clearDocument(Model.addText(Model.addStroke(ruled, [[1, 1], [5, 5]], 2), 10, 10, "x"))
  assert.equal(edited.paper, "ruled", "drawing and clearing keep the sheet's paper")

  const loaded = Model.sanitizeNotebook({ schemaVersion: 2, sheets: [{ paper: "napkin", objects: [] }] }, 760, 560)
  assert.equal(loaded.documents[0].paper, "graph")
  const legacy = Model.sanitizeNotebook({ schemaVersion: 1, objects: [] }, 760, 560)
  assert.equal(legacy.documents[0].paper, "graph", "older single-sheet files load as graph paper")
})
