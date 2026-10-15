const test = require("node:test")
const assert = require("node:assert/strict")
const Notebook = require("../Notebook.js")
const History = require("../History.js")
const Model = require("../DocumentModel.js")

const blank = () => History.create(Model.createDocument(760, 560))
const inked = () => History.create(Model.addStroke(Model.createDocument(760, 560), [[1, 1], [2, 2]], 2))

test("shares its sheet limit with the saved-file sanitizer", () => {
  assert.equal(Notebook.MAX_SHEETS, Model.MAX_SHEETS)
})

test("creates with a clamped open sheet", () => {
  assert.equal(Notebook.create([blank()], 5).current, 0)
  assert.equal(Notebook.create([inked(), inked()], 1).current, 1)
  assert.equal(Notebook.create([inked()], NaN).current, 0)
})

test("adds a sheet only when the open one has something on it", () => {
  const start = Notebook.create([blank()], 0)
  assert.equal(Notebook.canAdd(start), false)
  assert.equal(Notebook.add(start, blank()), start)

  const written = Notebook.create([inked()], 0)
  const added = Notebook.add(written, blank())
  assert.equal(added.sheets.length, 2)
  assert.equal(added.current, 1)
  assert.equal(Notebook.add(added, blank()), added, "a second blank sheet is never created")

  let full = Notebook.create(Array.from({ length: Notebook.MAX_SHEETS }, inked), 0)
  assert.equal(Notebook.canAdd(full), false)
})

test("drops a blank sheet when it is left, and keeps written ones", () => {
  const notebook = Notebook.create([inked(), inked(), blank(), inked()], 2)
  const left = Notebook.select(notebook, 3)
  assert.equal(left.sheets.length, 3)
  assert.equal(left.current, 2)
  assert.equal(left.sheets[2], notebook.sheets[3])

  const back = Notebook.select(notebook, 0)
  assert.equal(back.sheets.length, 3)
  assert.equal(back.current, 0)

  const kept = Notebook.select(Notebook.create([inked(), inked()], 1), 0)
  assert.equal(kept.sheets.length, 2)
  assert.equal(Notebook.select(notebook, 2), notebook)
  assert.equal(Notebook.select(notebook, -1), notebook)
  assert.equal(Notebook.select(notebook, 9), notebook)
})

test("keeps an independent undo history per sheet", () => {
  let notebook = Notebook.create([inked()], 0)
  notebook = Notebook.add(notebook, blank())
  const drawn = Model.addStroke(notebook.sheets[1].present, [[5, 5], [6, 6]], 2)
  notebook = Notebook.replaceCurrent(notebook, History.commit(notebook.sheets[1], drawn))
  notebook = Notebook.select(notebook, 0)
  assert.equal(notebook.sheets[0].past.length, 0)
  assert.equal(notebook.sheets[1].past.length, 1)
  assert.equal(Notebook.replaceCurrent(notebook, notebook.sheets[0]), notebook)
})
