// Documents are immutable (see DocumentModel.js), so history keeps references
// instead of deep copies.
var LIMIT = 100

function create(document) {
    return { past: [], present: document, future: [] }
}

function commit(history, document) {
    if (document === history.present)
        return history
    var past = history.past.concat([history.present])
    if (past.length > LIMIT)
        past = past.slice(past.length - LIMIT)
    return { past: past, present: document, future: [] }
}

function undo(history) {
    if (!history.past.length)
        return history
    return {
        past: history.past.slice(0, -1),
        present: history.past[history.past.length - 1],
        future: [history.present].concat(history.future)
    }
}

function redo(history) {
    if (!history.future.length)
        return history
    return {
        past: history.past.concat([history.present]),
        present: history.future[0],
        future: history.future.slice(1)
    }
}

if (typeof module !== "undefined")
    module.exports = { create: create, commit: commit, undo: undo, redo: redo }
