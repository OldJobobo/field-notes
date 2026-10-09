function copy(value) {
    return JSON.parse(JSON.stringify(value))
}

function create(document) {
    return { past: [], present: copy(document), future: [] }
}

function commit(history, document) {
    var past = history.past.concat([copy(history.present)])
    if (past.length > 100)
        past = past.slice(past.length - 100)
    return { past: past, present: copy(document), future: [] }
}

function undo(history) {
    if (!history.past.length)
        return history
    return {
        past: history.past.slice(0, -1),
        present: copy(history.past[history.past.length - 1]),
        future: [copy(history.present)].concat(history.future)
    }
}

function redo(history) {
    if (!history.future.length)
        return history
    return {
        past: history.past.concat([copy(history.present)]),
        present: copy(history.future[0]),
        future: history.future.slice(1)
    }
}

if (typeof module !== "undefined")
    module.exports = { create: create, commit: commit, undo: undo, redo: redo }
