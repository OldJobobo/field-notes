// Documents are immutable plain data: every edit returns a new document that shares
// untouched objects with the previous one, and a no-op edit returns the same document.

var MAX_OBJECTS = 4096
var MAX_STROKE_POINTS = 8192
var MAX_TOTAL_POINTS = 250000
var MAX_TEXT = 4096
var MAX_TITLE = 60
var MAX_SHEETS = 32
var TOOLS = ["select", "pen", "eraser", "text"]
var TOOLBAR_SIDES = ["right", "left", "top", "bottom"]
// Ruling printed on a sheet, in the order clicking the paper label cycles through them.
var PAPERS = ["graph", "dots", "ruled", "plain"]
// Sheet sizes, smallest first; all share the medium sheet's proportions.
var SIZES = {
    small: { width: 520, height: 380 },
    medium: { width: 760, height: 560 },
    large: { width: 1040, height: 760 }
}
var SIZE_ORDER = ["small", "medium", "large"]
// User settings and the values each one accepts. The first value is the default, which
// matches how Field Notes behaves with no settings saved.
var SETTING_CHOICES = {
    theme: [true, false],
    tilt: [true, false],
    fadeToolbar: [true, false],
    smoothing: ["medium", "off", "light", "strong"],
    eraser: ["medium", "small", "large"],
    clipboard: ["path", "image"]
}
var MAX_PATH = 512

function createDocument(width, height, paper) {
    return {
        schemaVersion: 1,
        page: { width: width, height: height },
        paper: PAPERS.indexOf(paper) >= 0 ? paper : "graph",
        title: "",
        objects: [],
        ui: { tool: "pen", penWidth: 2.5 }
    }
}

function clamp(value, low, high) {
    return Math.max(low, Math.min(high, Number(value) || 0))
}

function round1(value) {
    return Math.round(value * 10) / 10
}

function withObjects(document, objects) {
    return Object.assign({}, document, { objects: objects })
}

function setPaper(document, paper) {
    if (PAPERS.indexOf(paper) < 0 || paper === document.paper)
        return document
    return Object.assign({}, document, { paper: paper })
}

// One line, trimmed and bounded.
function cleanTitle(title) {
    return String(title || "").replace(/\s+/g, " ").trim().slice(0, MAX_TITLE)
}

function setTitle(document, title) {
    var clean = cleanTitle(title)
    return clean === document.title ? document : Object.assign({}, document, { title: clean })
}

// A sheet with nothing drawn, written or named on it.
function isBlank(document) {
    return document.objects.length === 0 && !document.title
}

// File-name form of a title, e.g. "Meeting notes: Q4!" -> "meeting-notes-q4".
function slug(title) {
    return cleanTitle(title).toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "").slice(0, 40)
}

function createSheet(size, paper) {
    var dimensions = SIZES[size] || SIZES.medium
    return createDocument(dimensions.width, dimensions.height, paper)
}

function sizeName(document) {
    for (var i = 0; i < SIZE_ORDER.length; i++) {
        var dimensions = SIZES[SIZE_ORDER[i]]
        if (document.page.width === dimensions.width && document.page.height === dimensions.height)
            return SIZE_ORDER[i]
    }
    return "medium"
}

// The furthest right and down any ink or note reaches.
function contentExtent(document) {
    var extent = { width: 0, height: 0 }
    for (var i = 0; i < document.objects.length; i++) {
        var object = document.objects[i]
        if (object.type === "text") {
            extent.width = Math.max(extent.width, object.x + object.width)
            extent.height = Math.max(extent.height, object.y + object.height)
        } else if (object.type === "stroke") {
            var pressure = object.points.some(function(point) {
                return point && typeof point[2] === "number" && isFinite(point[2])
            })
            // Keep the firm-press envelope in sync with Geometry.pressureWidth;
            // sizing tests compare both without coupling these standalone modules.
            var half = Number(object.width || 1) * (pressure ? 1.1 : 1) / 2
            for (var j = 0; j < object.points.length; j++) {
                extent.width = Math.max(extent.width, object.points[j][0] + half)
                extent.height = Math.max(extent.height, object.points[j][1] + half)
            }
        }
    }
    return extent
}

function fitsSize(document, size) {
    var dimensions = SIZES[size]
    var extent = contentExtent(document)
    return !!dimensions && extent.width <= dimensions.width && extent.height <= dimensions.height
}

// Resizes the sheet from its top-left corner. Content keeps its place and scale, so a
// size it would not fit on is refused (the same document comes back).
function setSize(document, size) {
    if (!SIZES[size] || size === sizeName(document) || !fitsSize(document, size))
        return document
    return Object.assign({}, document, { page: { width: SIZES[size].width, height: SIZES[size].height } })
}

// The next size in order that the sheet's content fits on, or the current size if none.
function nextSize(document) {
    var current = SIZE_ORDER.indexOf(sizeName(document))
    for (var step = 1; step < SIZE_ORDER.length; step++) {
        var size = SIZE_ORDER[(current + step) % SIZE_ORDER.length]
        if (fitsSize(document, size))
            return size
    }
    return SIZE_ORDER[current]
}

function nextPaper(paper) {
    return PAPERS[(PAPERS.indexOf(paper) + 1) % PAPERS.length]
}

function indexOf(document, id) {
    for (var i = 0; i < document.objects.length; i++) {
        if (document.objects[i].id === id)
            return i
    }
    return -1
}

function findObject(document, id) {
    var index = indexOf(document, id)
    return index < 0 ? null : document.objects[index]
}

function replaceAt(document, index, object) {
    var objects = document.objects.slice()
    objects[index] = object
    return withObjects(document, objects)
}

function sameObjects(a, b) {
    if (a === b)
        return true
    if (!a || !b || a.objects.length !== b.objects.length)
        return false
    for (var i = 0; i < a.objects.length; i++) {
        if (a.objects[i] !== b.objects[i])
            return false
    }
    return true
}

function nextId(document, prefix) {
    var highest = 0
    var head = prefix + "-"
    for (var i = 0; i < document.objects.length; i++) {
        var id = String(document.objects[i].id || "")
        if (id.indexOf(head) === 0)
            highest = Math.max(highest, Number(id.slice(head.length)) || 0)
    }
    return prefix + "-" + (highest + 1)
}

function cleanPoints(document, points) {
    var clean = []
    for (var i = 0; i < points.length && clean.length < MAX_STROKE_POINTS; i++) {
        var x = Number(points[i] && points[i][0])
        var y = Number(points[i] && points[i][1])
        if (isFinite(x) && isFinite(y)) {
            var point = [round1(clamp(x, 0, document.page.width)), round1(clamp(y, 0, document.page.height))]
            // Optional pressure; absent or malformed values retain legacy fixed-width ink.
            var pressure = Array.isArray(points[i]) ? points[i][2] : undefined
            if (typeof pressure === "number" && isFinite(pressure))
                point.push(Math.round(clamp(pressure, 0, 1) * 1000) / 1000)
            clean.push(point)
        }
    }
    return clean
}

function addStroke(document, points, width) {
    if (document.objects.length >= MAX_OBJECTS)
        return document
    var clean = cleanPoints(document, points || [])
    if (clean.length === 0)
        return document
    return withObjects(document, document.objects.concat([{
        id: nextId(document, "stroke"),
        type: "stroke",
        color: "graphite",
        width: clamp(width, 1, 12),
        points: clean
    }]))
}

function deleteObject(document, id) {
    var index = indexOf(document, id)
    if (index < 0)
        return document
    var objects = document.objects.slice()
    objects.splice(index, 1)
    return withObjects(document, objects)
}

function replaceStrokeSegments(document, id, segments) {
    var index = indexOf(document, id)
    if (index < 0 || document.objects[index].type !== "stroke")
        return document

    var source = document.objects[index]
    var next = withObjects(document, document.objects.slice())
    next.objects.splice(index, 1)
    var inserted = 0
    for (var j = 0; j < segments.length; j++) {
        if (!segments[j] || segments[j].length < 2)
            continue
        next.objects.splice(index + inserted, 0, {
            id: inserted === 0 ? source.id : nextId(next, "stroke"),
            type: "stroke",
            color: source.color,
            width: source.width,
            points: cleanPoints(document, segments[j])
        })
        inserted++
    }
    return next
}

function clearDocument(document) {
    return document.objects.length === 0 ? document : withObjects(document, [])
}

function addText(document, x, y, text) {
    if (document.objects.length >= MAX_OBJECTS)
        return document
    var width = 220
    var height = 40
    return withObjects(document, document.objects.concat([{
        id: nextId(document, "text"),
        type: "text",
        x: clamp(x, 0, Math.max(0, document.page.width - width)),
        y: clamp(y, 0, Math.max(0, document.page.height - height)),
        width: width,
        height: height,
        text: String(text || "").slice(0, MAX_TEXT),
        size: 16
    }]))
}

function updateText(document, id, text, height) {
    var index = indexOf(document, id)
    if (index < 0 || document.objects[index].type !== "text")
        return document
    var source = document.objects[index]
    var nextText = String(text || "").slice(0, MAX_TEXT)
    var nextHeight = height === undefined ? source.height : Math.round(clamp(height, 20, document.page.height))
    if (nextText === source.text && nextHeight === source.height)
        return document
    var object = Object.assign({}, source, { text: nextText, height: nextHeight })
    object.y = clamp(object.y, 0, Math.max(0, document.page.height - nextHeight))
    return replaceAt(document, index, object)
}

function moveText(document, id, x, y) {
    var index = indexOf(document, id)
    if (index < 0 || document.objects[index].type !== "text")
        return document
    var source = document.objects[index]
    var nextX = clamp(x, 0, Math.max(0, document.page.width - source.width))
    var nextY = clamp(y, 0, Math.max(0, document.page.height - source.height))
    if (nextX === source.x && nextY === source.y)
        return document
    return replaceAt(document, index, Object.assign({}, source, { x: nextX, y: nextY }))
}

// Moves a stroke or note by an offset, limited so the whole object stays on the page
// without distorting its shape.
function translateObject(document, id, dx, dy) {
    var index = indexOf(document, id)
    if (index < 0)
        return document
    var source = document.objects[index]
    if (source.type === "text")
        return moveText(document, id, source.x + Number(dx), source.y + Number(dy))
    if (source.type !== "stroke" || source.points.length === 0)
        return document

    var minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity
    for (var i = 0; i < source.points.length; i++) {
        minX = Math.min(minX, source.points[i][0])
        maxX = Math.max(maxX, source.points[i][0])
        minY = Math.min(minY, source.points[i][1])
        maxY = Math.max(maxY, source.points[i][1])
    }
    var offsetX = round1(clamp(dx, -minX, document.page.width - maxX))
    var offsetY = round1(clamp(dy, -minY, document.page.height - maxY))
    if (offsetX === 0 && offsetY === 0)
        return document
    var points = source.points.map(function(point) {
        var moved = point.slice(0, 3)
        moved[0] = round1(point[0] + offsetX)
        moved[1] = round1(point[1] + offsetY)
        return moved
    })
    return replaceAt(document, index, Object.assign({}, source, { points: points }))
}

function sanitizeObjects(rawObjects, document, budget) {
    var objects = []
    var seen = {}
    var width = document.page.width
    var height = document.page.height
    for (var i = 0; i < rawObjects.length && objects.length < MAX_OBJECTS; i++) {
        var source = rawObjects[i]
        if (!source || typeof source !== "object")
            continue
        var id = String(source.id || "")
        var object = null
        if (source.type === "stroke" && Array.isArray(source.points)) {
            if (source.points.length > Math.min(budget.points, MAX_STROKE_POINTS))
                budget.trimmed = true
            var points = cleanPoints(document, source.points.slice(0, budget.points))
            if (points.length === 0)
                continue
            budget.points -= points.length
            object = { id: id, type: "stroke", color: "graphite", width: clamp(source.width, 1, 12), points: points }
        } else if (source.type === "text" && typeof source.text === "string" && source.text.trim() !== "") {
            var noteWidth = Math.round(clamp(source.width || 220, 40, width))
            var noteHeight = Math.round(clamp(source.height || 40, 20, height))
            object = {
                id: id,
                type: "text",
                x: clamp(source.x, 0, width - noteWidth),
                y: clamp(source.y, 0, height - noteHeight),
                width: noteWidth,
                height: noteHeight,
                text: source.text.slice(0, MAX_TEXT),
                size: clamp(source.size || 16, 8, 48)
            }
        }
        if (!object)
            continue
        if (!/^(stroke|text)-\d+$/.test(id) || id.indexOf(object.type) !== 0 || seen[id])
            object.id = ""
        else
            seen[id] = true
        objects.push(object)
    }
    if (i < rawObjects.length)
        budget.trimmed = true

    for (var j = 0; j < objects.length; j++) {
        if (objects[j].id === "")
            objects[j].id = nextId({ objects: objects }, objects[j].type)
    }
    return withObjects(document, objects)
}

function defaultSettings() {
    var settings = { exportDir: "" }
    for (var key in SETTING_CHOICES)
        settings[key] = SETTING_CHOICES[key][0]
    return settings
}

// Untrusted saved settings -> a complete, valid settings object. exportDir is a single-line
// path, or "" for the default folder.
function sanitizeSettings(raw) {
    var settings = defaultSettings()
    if (!raw || typeof raw !== "object")
        return settings
    for (var key in SETTING_CHOICES) {
        if (SETTING_CHOICES[key].indexOf(raw[key]) >= 0)
            settings[key] = raw[key]
    }
    if (typeof raw.exportDir === "string")
        settings.exportDir = raw.exportDir.replace(/[\r\n\0]/g, "").trim().slice(0, MAX_PATH)
    return settings
}

// Where the board was left on each screen, keyed by output name ("DP-1"), in that screen's
// pixels. Names must look like output names, which also keeps "__proto__" out.
var MAX_SCREENS = 16
var SCREEN_NAME = /^[A-Za-z][A-Za-z0-9_.:-]{0,127}$/

function sanitizeBoards(raw) {
    var boards = {}
    if (!raw || typeof raw !== "object" || Array.isArray(raw))
        return boards
    var names = Object.keys(raw)
    var count = 0
    for (var i = 0; i < names.length && count < MAX_SCREENS; i++) {
        var position = raw[names[i]]
        if (!SCREEN_NAME.test(names[i]) || !position || typeof position !== "object")
            continue
        if (position.x === null || position.y === null || !isFinite(Number(position.x)) || !isFinite(Number(position.y)))
            continue
        boards[names[i]] = { x: Math.round(Number(position.x)), y: Math.round(Number(position.y)) }
        count++
    }
    return boards
}

function isScreenName(name) {
    return typeof name === "string" && SCREEN_NAME.test(name)
}

function sanitizeUi(raw) {
    var ui = { tool: "pen", penWidth: 2.5, toolbar: "right" }
    if (!raw || typeof raw !== "object")
        return ui
    if (TOOLS.indexOf(raw.tool) >= 0)
        ui.tool = raw.tool
    if (TOOLBAR_SIDES.indexOf(raw.toolbar) >= 0)
        ui.toolbar = raw.toolbar
    if (isFinite(Number(raw.penWidth)) && raw.penWidth !== null)
        ui.penWidth = clamp(raw.penWidth, 1, 12)
    if (isFinite(Number(raw.boardX)) && isFinite(Number(raw.boardY)) && raw.boardX !== null && raw.boardY !== null) {
        ui.boardX = Number(raw.boardX)
        ui.boardY = Number(raw.boardY)
    }
    var boards = sanitizeBoards(raw.boards)
    if (Object.keys(boards).length > 0)
        ui.boards = boards
    return ui
}

// Accepts untrusted saved JSON (a single-sheet version 1 file or a version 2 notebook) and
// returns { documents, current, ui } with every sheet bounded and valid, or null when the
// data is not a Field Notes file at all. Blank sheets are kept only if they are open.
function sanitizeNotebook(raw, width, height) {
    if (!raw || typeof raw !== "object")
        return null
    var rawSheets = null
    var current = 0
    if (raw.schemaVersion === 1 && Array.isArray(raw.objects)) {
        rawSheets = [raw]
    } else if (raw.schemaVersion === 2 && Array.isArray(raw.sheets)) {
        rawSheets = raw.sheets
        current = Math.floor(Number(raw.current)) || 0
    } else {
        return null
    }

    var documents = []
    var open = 0
    var budget = { points: MAX_TOTAL_POINTS }
    for (var i = 0; i < rawSheets.length && documents.length < MAX_SHEETS; i++) {
        var sheet = rawSheets[i]
        if (!sheet || typeof sheet !== "object" || !Array.isArray(sheet.objects))
            continue
        var dimensions = SIZES[sheet.size] || { width: width, height: height }
        var document = sanitizeObjects(sheet.objects, createDocument(dimensions.width, dimensions.height, sheet.paper), budget)
        document.title = cleanTitle(typeof sheet.title === "string" ? sheet.title : "")
        if (isBlank(document) && i !== current)
            continue
        if (i === current)
            open = documents.length
        documents.push(document)
    }
    if (i < rawSheets.length)
        budget.trimmed = true
    if (documents.length === 0)
        documents.push(createDocument(width, height))
    // trimmed: the file held more than these limits allow, so saving now would lose the rest.
    return { documents: documents, current: open, ui: sanitizeUi(raw.ui), settings: sanitizeSettings(raw.settings),
             trimmed: budget.trimmed === true }
}

// How far a notebook goes past what loading keeps (sanitizeNotebook): 0 means it reloads in
// full. It counts every limit loading enforces (sheets, objects per sheet, points per stroke,
// characters per note and points in total), so editing can refuse anything that would be lost.
function overLimits(documents) {
    var over = Math.max(0, documents.length - MAX_SHEETS)
    var points = 0
    for (var i = 0; i < documents.length; i++) {
        var objects = documents[i].objects
        over += Math.max(0, objects.length - MAX_OBJECTS)
        for (var j = 0; j < objects.length; j++) {
            if (objects[j].type === "stroke") {
                points += objects[j].points.length
                over += Math.max(0, objects[j].points.length - MAX_STROKE_POINTS)
            } else if (objects[j].type === "text") {
                over += Math.max(0, String(objects[j].text).length - MAX_TEXT)
            }
        }
    }
    return over + Math.max(0, points - MAX_TOTAL_POINTS)
}

// Stroke points across a set of sheets: what the notebook budget (MAX_TOTAL_POINTS) counts.
function totalPoints(documents) {
    var total = 0
    for (var i = 0; i < documents.length; i++) {
        var objects = documents[i].objects
        for (var j = 0; j < objects.length; j++) {
            if (objects[j].type === "stroke")
                total += objects[j].points.length
        }
    }
    return total
}

function serialize(documents, current, ui, settings) {
    return JSON.stringify({
        schemaVersion: 2,
        page: documents[0].page,
        current: current,
        sheets: documents.map(function(document) {
            return { title: document.title || "", size: sizeName(document), paper: document.paper, objects: document.objects }
        }),
        ui: ui,
        settings: settings || defaultSettings()
    })
}

if (typeof module !== "undefined")
    module.exports = {
        MAX_SHEETS: MAX_SHEETS,
        MAX_TOTAL_POINTS: MAX_TOTAL_POINTS,
        MAX_STROKE_POINTS: MAX_STROKE_POINTS,
        totalPoints: totalPoints,
        overLimits: overLimits,
        MAX_OBJECTS: MAX_OBJECTS,
        PAPERS: PAPERS,
        createDocument: createDocument,
        setPaper: setPaper,
        SIZES: SIZES,
        SETTING_CHOICES: SETTING_CHOICES,
        defaultSettings: defaultSettings,
        sanitizeSettings: sanitizeSettings,
        sanitizeBoards: sanitizeBoards,
        isScreenName: isScreenName,
        MAX_SCREENS: MAX_SCREENS,
        SIZE_ORDER: SIZE_ORDER,
        createSheet: createSheet,
        sizeName: sizeName,
        fitsSize: fitsSize,
        setSize: setSize,
        nextSize: nextSize,
        setTitle: setTitle,
        isBlank: isBlank,
        slug: slug,
        nextPaper: nextPaper,
        findObject: findObject,
        sameObjects: sameObjects,
        addStroke: addStroke,
        deleteObject: deleteObject,
        replaceStrokeSegments: replaceStrokeSegments,
        clearDocument: clearDocument,
        addText: addText,
        updateText: updateText,
        moveText: moveText,
        translateObject: translateObject,
        sanitizeNotebook: sanitizeNotebook,
        serialize: serialize
    }
