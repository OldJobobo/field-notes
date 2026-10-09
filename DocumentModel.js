function createDocument(width, height) {
    return {
        schemaVersion: 1,
        page: { width: width, height: height },
        objects: [],
        ui: { tool: "pen", penWidth: 2.5 }
    }
}

function clamp(value, low, high) {
    return Math.max(low, Math.min(high, Number(value) || 0))
}

function nextId(document, prefix) {
    var highest = 0
    for (var i = 0; i < document.objects.length; i++) {
        var match = String(document.objects[i].id || "").match(new RegExp("^" + prefix + "-(\\d+)$"))
        if (match)
            highest = Math.max(highest, Number(match[1]))
    }
    return prefix + "-" + (highest + 1)
}

function addStroke(document, points, width) {
    var next = JSON.parse(JSON.stringify(document))
    var cleanPoints = []
    for (var i = 0; i < points.length && i < 8192; i++)
        cleanPoints.push([
            clamp(points[i][0], 0, next.page.width),
            clamp(points[i][1], 0, next.page.height)
        ])
    next.objects.push({
        id: nextId(next, "stroke"),
        type: "stroke",
        color: "graphite",
        width: clamp(width, 1, 12),
        points: cleanPoints
    })
    return next
}

function deleteObject(document, id) {
    var next = JSON.parse(JSON.stringify(document))
    next.objects = next.objects.filter(function(object) { return object.id !== id })
    return next
}

function replaceStrokeSegments(document, id, segments) {
    var next = JSON.parse(JSON.stringify(document))
    var index = -1
    for (var i = 0; i < next.objects.length; i++) {
        if (next.objects[i].id === id && next.objects[i].type === "stroke") {
            index = i
            break
        }
    }
    if (index < 0)
        return next

    var source = next.objects[index]
    next.objects.splice(index, 1)
    var inserted = 0
    for (var j = 0; j < segments.length; j++) {
        if (!segments[j] || segments[j].length < 2)
            continue
        var replacement = JSON.parse(JSON.stringify(source))
        replacement.id = inserted === 0 ? source.id : nextId(next, "stroke")
        replacement.points = JSON.parse(JSON.stringify(segments[j]))
        next.objects.splice(index + inserted, 0, replacement)
        inserted++
    }
    return next
}

function clearDocument(document) {
    var next = JSON.parse(JSON.stringify(document))
    next.objects = []
    return next
}

function addText(document, x, y, text) {
    var next = JSON.parse(JSON.stringify(document))
    var width = 220
    var height = 40
    next.objects.push({
        id: nextId(next, "text"),
        type: "text",
        x: clamp(x, 0, Math.max(0, next.page.width - width)),
        y: clamp(y, 0, Math.max(0, next.page.height - height)),
        width: width,
        height: height,
        text: String(text || "").slice(0, 4096),
        size: 16
    })
    return next
}

function updateText(document, id, text) {
    var next = JSON.parse(JSON.stringify(document))
    for (var i = 0; i < next.objects.length; i++) {
        if (next.objects[i].id === id && next.objects[i].type === "text")
            next.objects[i].text = String(text || "").slice(0, 4096)
    }
    return next
}

function moveText(document, id, x, y) {
    var next = JSON.parse(JSON.stringify(document))
    for (var i = 0; i < next.objects.length; i++) {
        var object = next.objects[i]
        if (object.id === id && object.type === "text") {
            object.x = clamp(x, 0, Math.max(0, next.page.width - object.width))
            object.y = clamp(y, 0, Math.max(0, next.page.height - object.height))
        }
    }
    return next
}

if (typeof module !== "undefined")
    module.exports = {
        createDocument: createDocument,
        addStroke: addStroke,
        deleteObject: deleteObject,
        replaceStrokeSegments: replaceStrokeSegments,
        clearDocument: clearDocument,
        addText: addText,
        updateText: updateText,
        moveText: moveText
    }
