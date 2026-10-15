// A notebook is an ordered list of sheets, each with its own undo history (History.js),
// plus the index of the open sheet. Only the open sheet may be blank (nothing drawn,
// written or named on it): a blank sheet is dropped when the user leaves it, so new
// sheets never pile up as empty pages.
var MAX_SHEETS = 32

function create(histories, current) {
    return { sheets: histories, current: Math.max(0, Math.min(histories.length - 1, Math.floor(current) || 0)) }
}

function isBlank(history) {
    return history.present.objects.length === 0 && !history.present.title
}

function replaceCurrent(notebook, history) {
    if (history === notebook.sheets[notebook.current])
        return notebook
    var sheets = notebook.sheets.slice()
    sheets[notebook.current] = history
    return { sheets: sheets, current: notebook.current }
}

function select(notebook, index) {
    if (index < 0 || index >= notebook.sheets.length || index === notebook.current)
        return notebook
    var sheets = notebook.sheets
    if (isBlank(sheets[notebook.current])) {
        sheets = sheets.slice()
        sheets.splice(notebook.current, 1)
        if (index > notebook.current)
            index--
    }
    return { sheets: sheets, current: index }
}

function canAdd(notebook) {
    return notebook.sheets.length < MAX_SHEETS && !isBlank(notebook.sheets[notebook.current])
}

function add(notebook, history) {
    if (!canAdd(notebook))
        return notebook
    return { sheets: notebook.sheets.concat([history]), current: notebook.sheets.length }
}

if (typeof module !== "undefined")
    module.exports = {
        MAX_SHEETS: MAX_SHEETS,
        create: create,
        isBlank: isBlank,
        replaceCurrent: replaceCurrent,
        select: select,
        canAdd: canAdd,
        add: add
    }
