const test = require("node:test")
const assert = require("node:assert/strict")
const Model = require("../DocumentModel.js")

test("creates a bounded empty document", () => {
  assert.deepEqual(Model.createDocument(760, 560), {
    schemaVersion: 1,
    page: { width: 760, height: 560 },
    paper: "graph",
    title: "",
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

test("sheets carry a one-line title that is saved, undoable and used for file names", () => {
  const sheet = Model.createDocument(760, 560)
  const titled = Model.setTitle(sheet, "  Meeting\n notes:   Q4!  ")
  assert.equal(titled.title, "Meeting notes: Q4!")
  assert.equal(Model.setTitle(titled, "Meeting notes: Q4!"), titled, "an unchanged title is a no-op")
  assert.equal(Model.setTitle(sheet, "x".repeat(100)).title.length, 60)
  assert.equal(Model.addStroke(titled, [[1, 1], [2, 2]], 2).title, titled.title, "edits keep the title")

  assert.equal(Model.slug("Meeting notes: Q4!"), "meeting-notes-q4")
  assert.equal(Model.slug("   "), "")
  assert.equal(Model.slug("Ünïcode ✓"), "n-code", "file names stay plain ASCII")

  assert.equal(Model.isBlank(sheet), true)
  assert.equal(Model.isBlank(titled), false, "a named sheet is not blank")

  const restored = Model.sanitizeNotebook(JSON.parse(Model.serialize([titled, sheet], 1, {})), 760, 560)
  assert.deepEqual(restored.documents.map(document => document.title), ["Meeting notes: Q4!", ""])
  const hostile = Model.sanitizeNotebook({ schemaVersion: 2, current: 1, sheets: [
    { title: { evil: true }, objects: [] }, { title: "a\nb", objects: [] }] }, 760, 560)
  assert.deepEqual(hostile.documents.map(document => document.title), ["a b"], "an untitled, empty, unopened sheet is dropped")
})

test("sheets resize between three sizes without cutting off or rescaling content", () => {
  assert.deepEqual(Model.SIZE_ORDER, ["small", "medium", "large"])
  const medium = Model.createSheet("medium", "dots")
  assert.deepEqual([medium.page, medium.paper], [{ width: 760, height: 560 }, "dots"])
  assert.equal(Model.sizeName(Model.createSheet("small")), "small")
  assert.equal(Model.sizeName(Model.createSheet("bogus")), "medium")

  const large = Model.setSize(medium, "large")
  assert.deepEqual(large.page, { width: 1040, height: 760 })
  assert.equal(Model.setSize(large, "large"), large, "same size is a no-op")
  assert.equal(Model.nextSize(medium), "large")
  assert.equal(Model.nextSize(large), "small")

  const inked = Model.addStroke(large, [[10, 10], [900, 700]], 4)
  assert.equal(Model.setSize(inked, "small"), inked, "ink beyond the smaller sheet refuses the shrink")
  assert.equal(Model.nextSize(inked), "large", "no smaller size fits, so the size stays")
  const corner = Model.addText(medium, 320, 300, "note") // reaches x = 540, past the small sheet
  assert.equal(Model.nextSize(Model.setSize(corner, "large")), "medium", "from large, the small sheet is skipped")
  assert.equal(Model.setSize(corner, "small"), corner)
  assert.deepEqual(Model.setSize(corner, "large").objects, corner.objects, "content keeps its place and scale")

  const restored = Model.sanitizeNotebook(JSON.parse(Model.serialize([inked, Model.createSheet("small")], 1, {})), 760, 560)
  assert.deepEqual(restored.documents.map(Model.sizeName), ["large", "small"])
  assert.deepEqual(restored.documents[0].objects, inked.objects, "large-sheet ink is not clamped to the default size")
  const legacy = Model.sanitizeNotebook({ schemaVersion: 2, sheets: [{ objects: [] }] }, 760, 560)
  assert.equal(Model.sizeName(legacy.documents[0]), "medium", "sheets saved before sizes load as medium")
})

test("settings load with safe defaults and keep only valid values", () => {
  assert.deepEqual(Model.defaultSettings(), {
    exportDir: "", theme: true, tilt: true, smoothing: "medium", eraser: "medium", clipboard: "path"
  }, "defaults match how Field Notes behaves with nothing saved")
  assert.deepEqual(Model.sanitizeSettings(null), Model.defaultSettings())
  assert.deepEqual(Model.sanitizeSettings({
    theme: false, tilt: "yes", smoothing: "strong", eraser: "huge", clipboard: "image",
    exportDir: "  ~/Notes/out\nrm -rf /  ", extra: 1
  }), { exportDir: "~/Notes/outrm -rf /", theme: false, tilt: true, smoothing: "strong", eraser: "medium", clipboard: "image" })
  assert.equal(Model.sanitizeSettings({ exportDir: "x".repeat(900) }).exportDir.length, 512)
  assert.equal(Model.sanitizeSettings({ exportDir: 42 }).exportDir, "")

  const settings = Object.assign(Model.defaultSettings(), { theme: false, smoothing: "off" })
  const restored = Model.sanitizeNotebook(JSON.parse(Model.serialize([Model.createSheet("medium")], 0, {}, settings)), 760, 560)
  assert.deepEqual(restored.settings, settings)
  const older = Model.sanitizeNotebook({ schemaVersion: 2, sheets: [{ objects: [] }] }, 760, 560)
  assert.deepEqual(older.settings, Model.defaultSettings(), "files saved before settings existed get the defaults")
})

test("keeps a board place per screen, dropping anything that is not one", () => {
  const boards = Model.sanitizeBoards({
    "DP-1": { x: 840.4, y: 390 },
    "HDMI-A-1": { x: "12", y: -40 },
    "__proto__": { x: 1, y: 1 },
    "bad name": { x: 1, y: 1 },
    "DP-2": { x: null, y: 5 },
    "DP-3": { x: Infinity, y: 5 },
    "eDP-1": "junk",
  })
  assert.deepEqual(boards, { "DP-1": { x: 840, y: 390 }, "HDMI-A-1": { x: 12, y: -40 } })
  assert.equal(Object.getPrototypeOf(boards), Object.prototype)
  assert.deepEqual(Model.sanitizeBoards([{ x: 1, y: 2 }]), {})
  assert.deepEqual(Model.sanitizeBoards(null), {})

  const many = {}
  for (let i = 0; i < 40; i++) many["DP-" + i] = { x: i, y: i }
  assert.equal(Object.keys(Model.sanitizeBoards(many)).length, Model.MAX_SCREENS)

  assert.equal(Model.isScreenName("DP-1"), true)
  assert.equal(Model.isScreenName("'; rm -rf ~"), false)
  assert.equal(Model.isScreenName(""), false)
})

test("round-trips per-screen board places and omits them when there are none", () => {
  const doc = Model.addStroke(Model.createDocument(760, 560), [[1, 1], [9, 9]], 3)
  const ui = { tool: "pen", penWidth: 2.5, toolbar: "right", boardX: 5, boardY: 6, boards: { "DP-1": { x: 5, y: 6 }, "DP-3": { x: 900, y: 120 } } }
  const restored = Model.sanitizeNotebook(JSON.parse(Model.serialize([doc], 0, ui)), 760, 560)
  assert.deepEqual(restored.ui, ui)
  const none = Model.sanitizeNotebook(JSON.parse(Model.serialize([doc], 0, { tool: "pen", boards: {} })), 760, 560)
  assert.equal("boards" in none.ui, false)
})
