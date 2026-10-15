const test = require("node:test")
const assert = require("node:assert/strict")
const History = require("../History.js")
const Model = require("../DocumentModel.js")

test("undoes, redoes, and invalidates redo after a new edit", () => {
  const empty = Model.createDocument(760, 560)
  const first = Model.addStroke(empty, [[0, 0], [10, 10]], 2)
  const second = Model.addStroke(first, [[20, 20], [30, 30]], 2)
  let history = History.create(empty)
  history = History.commit(history, first)
  history = History.commit(history, second)

  history = History.undo(history)
  assert.equal(history.present.objects.length, 1)
  history = History.redo(history)
  assert.equal(history.present.objects.length, 2)
  history = History.undo(history)
  history = History.commit(history, Model.clearDocument(history.present))
  assert.equal(history.future.length, 0)
})

test("ignores no-op commits so they do not consume undo steps", () => {
  const empty = Model.createDocument(760, 560)
  const history = History.create(empty)
  assert.equal(History.commit(history, Model.clearDocument(empty)), history)
  assert.equal(History.commit(history, Model.deleteObject(empty, "stroke-9")), history)
})

test("caps history depth at 100 steps", () => {
  let document = Model.createDocument(760, 560)
  let history = History.create(document)
  for (let i = 0; i < 130; i++) {
    document = Model.addStroke(document, [[i, i], [i + 1, i + 1]], 2)
    history = History.commit(history, document)
  }
  assert.equal(history.past.length, 100)
  assert.equal(history.past[0].objects.length, 30)
})
