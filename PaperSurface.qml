import QtQuick
import QtQuick.Effects
import "DocumentModel.js" as DocumentModel
import "Geometry.js" as Geometry

Item {
    id: root

    property color paperColor: "#ded7c5"
    property color graphite: "#423e38"
    property color selectionColor: "#b18d52"
    property color minorGrid: "#7898a8"
    property color majorGrid: "#5f8394"
    property color marginRule: "#c0736a"
    readonly property string paperType: shownDocument && shownDocument.paper ? shownDocument.paper : "graph"
    readonly property var paperLabels: ({ graph: "GRAPH 16", dots: "DOTS 16", ruled: "RULED 24", plain: "PLAIN" })
    property var document: DocumentModel.createDocument(width, height)
    // Uncommitted result of the gesture in progress (erase drag, stroke move, new note),
    // committed as a single undo step when the gesture ends.
    property var draftDocument: null
    readonly property var shownDocument: draftDocument || document
    property string currentTool: "pen"
    property real penWidth: 2.5
    property real eraserRadius: 10
    // Mouse and touchpad strokes are steadied (see Geometry.smoothStroke); tablet pens
    // already report smooth, precise positions and are kept exactly as drawn.
    property real mouseSmoothing: 3.5
    property bool steadyStroke: false
    property string statusText: "READY"
    property var activeStroke: []
    property var gestureOrigin: null
    property string selectedObjectId: ""
    property string editingObjectId: ""
    property int sheetIndex: 0
    property int sheetCount: 1
    signal commitRequested(var nextDocument)
    signal toolRequested(string tool)
    signal editingFinished()
    signal paperRequested()

    function pad2(value) {
        return value < 10 ? "0" + value : String(value)
    }

    function commit(nextDocument) {
        draftDocument = null
        if (!DocumentModel.sameObjects(nextDocument, document))
            commitRequested(nextDocument)
    }

    function deleteSelected() {
        if (selectedObjectId === "" || editingObjectId !== "")
            return false
        var id = selectedObjectId
        selectedObjectId = ""
        commit(DocumentModel.deleteObject(document, id))
        return true
    }

    function clearSelection() {
        if (selectedObjectId === "")
            return false
        selectedObjectId = ""
        return true
    }

    // Moving focus off the active editor commits it (see TextNote).
    function finishEditing() {
        if (editingObjectId !== "")
            editorPointer.forceActiveFocus()
    }

    function beginEditing(id) {
        finishEditing()
        selectedObjectId = id
        editingObjectId = id
    }

    function cancelEditing() {
        if (editingObjectId === "")
            return false
        editingObjectId = ""
        draftDocument = null
        return true
    }

    function commitText(id, text, height) {
        editingObjectId = ""
        selectedObjectId = ""
        var base = draftDocument || document
        var trimmed = String(text).replace(/\s+$/, "")
        commit(trimmed === ""
            ? DocumentModel.deleteObject(base, id)
            : DocumentModel.updateText(base, id, trimmed, height))
    }

    function eraseAt(x, y) {
        var base = shownDocument
        var next = base
        var center = [x, y]
        for (var i = 0; i < base.objects.length; i++) {
            var object = base.objects[i]
            if (object.type === "stroke") {
                var radius = eraserRadius + Number(object.width || 1) / 2
                if (!Geometry.strokeTouches(object.points, center, radius))
                    continue
                var segments = Geometry.splitStroke(object.points, center, radius)
                next = DocumentModel.replaceStrokeSegments(next, object.id, segments)
            } else if (object.type === "text" && Geometry.rectTouches(object, center, eraserRadius)) {
                next = DocumentModel.deleteObject(next, object.id)
            }
        }
        if (next === base)
            return false
        if (selectedObjectId !== "" && !DocumentModel.findObject(next, selectedObjectId))
            selectedObjectId = ""
        draftDocument = next
        return true
    }

    // Fast drags deliver sparse pointer events; sweep the eraser along the gap.
    function eraseAlong(from, to) {
        var steps = Math.max(1, Math.ceil(Geometry.pointDistance(from, to) / (eraserRadius / 2)))
        for (var i = 1; i <= steps; i++)
            eraseAt(from[0] + (to[0] - from[0]) * i / steps, from[1] + (to[1] - from[1]) * i / steps)
    }

    function strokePoints() {
        return steadyStroke ? Geometry.smoothStroke(activeStroke, mouseSmoothing) : activeStroke
    }

    function isSteadyInput(mouse) {
        if (mouse.source !== Qt.MouseEventNotSynthesized)
            return false
        var device = pointerKind.point ? pointerKind.point.device : null
        return !device || device.type === PointerDevice.Mouse || device.type === PointerDevice.TouchPad
    }

    function finishGesture(x, y) {
        if (!gestureOrigin)
            return
        gestureOrigin = null
        if (currentTool === "pen" && activeStroke.length > 0) {
            if (activeStroke.length === 1)
                activeStroke.push([x + 0.1, y + 0.1])
            var points = strokePoints()
            var next = DocumentModel.addStroke(document, Geometry.simplifyStroke(points, 0.35), penWidth)
            if (next === document)
                clearWetInk()
            else
                commit(next) // the wet layer keeps the stroke until the ink layer has painted it
        } else if (draftDocument) {
            commit(draftDocument)
        }
    }

    function cancelGesture() {
        gestureOrigin = null
        clearWetInk()
        if (editingObjectId === "")
            draftDocument = null
    }

    function clearWetInk() {
        if (activeStroke.length === 0)
            return
        activeStroke = []
        wet.requestPaint()
    }

    function gridLines(ctx, width, height, step, lineWidth, color) {
        ctx.lineWidth = lineWidth
        ctx.strokeStyle = color
        ctx.beginPath()
        for (var x = step; x < width; x += step) {
            ctx.moveTo(Math.round(x) + 0.5, 0)
            ctx.lineTo(Math.round(x) + 0.5, height)
        }
        for (var y = step; y < height; y += step) {
            ctx.moveTo(0, Math.round(y) + 0.5)
            ctx.lineTo(width, Math.round(y) + 0.5)
        }
        ctx.stroke()
    }

    function paintGraph(ctx, width, height) {
        gridLines(ctx, width, height, 16, 1, Qt.rgba(minorGrid.r, minorGrid.g, minorGrid.b, 0.20))
        gridLines(ctx, width, height, 80, 1.15, Qt.rgba(majorGrid.r, majorGrid.g, majorGrid.b, 0.31))
    }

    // A dot at every 16 px crossing, slightly stronger every 80 px.
    function paintDots(ctx, width, height) {
        for (var x = 16; x < width; x += 16) {
            for (var y = 16; y < height; y += 16) {
                var major = x % 80 === 0 && y % 80 === 0
                ctx.fillStyle = Qt.rgba(majorGrid.r, majorGrid.g, majorGrid.b, major ? 0.62 : 0.42)
                ctx.beginPath()
                ctx.arc(x, y, major ? 1.5 : 1.1, 0, Math.PI * 2)
                ctx.fill()
            }
        }
    }

    // Notebook ruling: lines every 24 px below the header and a red margin rule.
    function paintRuled(ctx, width, height) {
        ctx.lineWidth = 1
        ctx.strokeStyle = Qt.rgba(minorGrid.r, minorGrid.g, minorGrid.b, 0.45)
        ctx.beginPath()
        for (var y = 46 + 24; y < height - 20; y += 24) {
            ctx.moveTo(0, y + 0.5)
            ctx.lineTo(width, y + 0.5)
        }
        ctx.stroke()
        ctx.strokeStyle = Qt.rgba(marginRule.r, marginRule.g, marginRule.b, 0.5)
        ctx.beginPath()
        ctx.moveTo(64.5, 0)
        ctx.lineTo(64.5, height)
        ctx.stroke()
    }

    function traceStroke(ctx, points, width, color) {
        if (!points || points.length === 0)
            return
        ctx.strokeStyle = color
        ctx.fillStyle = color
        ctx.lineWidth = width
        ctx.lineCap = "round"
        ctx.lineJoin = "round"
        ctx.beginPath()
        if (points.length === 1) {
            ctx.arc(points[0][0], points[0][1], width / 2, 0, Math.PI * 2)
            ctx.fill()
            return
        }
        // Quadratic curves through segment midpoints smooth out pointer sampling.
        ctx.moveTo(points[0][0], points[0][1])
        for (var i = 1; i < points.length - 1; i++) {
            ctx.quadraticCurveTo(points[i][0], points[i][1],
                (points[i][0] + points[i + 1][0]) / 2, (points[i][1] + points[i + 1][1]) / 2)
        }
        ctx.lineTo(points[points.length - 1][0], points[points.length - 1][1])
        ctx.stroke()
    }

    onDocumentChanged: {
        if (editingObjectId === "")
            draftDocument = null
    }
    onShownDocumentChanged: ink.requestPaint()
    onPaperTypeChanged: graph.requestPaint()
    onSelectedObjectIdChanged: ink.requestPaint()
    onCurrentToolChanged: {
        cancelGesture()
        selectedObjectId = ""
    }
    onEditingObjectIdChanged: {
        if (editingObjectId === "")
            editingFinished()
    }

    rotation: 0.8
    transformOrigin: Item.Center

    // With more than one sheet, the next one peeks out from under the page.
    Rectangle {
        anchors.fill: parent
        visible: root.sheetCount > 1
        rotation: -1.5
        radius: 3
        color: "#cdc5b1"
        border.width: 1
        border.color: "#a99e87"
    }

    Rectangle {
        id: sheet

        anchors.fill: parent
        radius: 3
        color: root.paperColor
        border.width: 1
        border.color: "#b8ad96"
        layer.enabled: true
        layer.smooth: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: "#7a000000"
            shadowBlur: 0.72
            shadowHorizontalOffset: 5
            shadowVerticalOffset: 13
            autoPaddingEnabled: true
        }

        Canvas {
            id: graph

            anchors.fill: parent
            anchors.margins: 1
            antialiasing: true

            onPaint: {
                var ctx = getContext("2d")
                ctx.reset()
                ctx.fillStyle = root.paperColor
                ctx.fillRect(0, 0, width, height)

                if (root.paperType === "graph")
                    root.paintGraph(ctx, width, height)
                else if (root.paperType === "dots")
                    root.paintDots(ctx, width, height)
                else if (root.paperType === "ruled")
                    root.paintRuled(ctx, width, height)
            }
        }

        // Committed strokes: repainted only when the shown document or selection changes.
        Canvas {
            id: ink

            anchors.fill: parent
            antialiasing: true
            renderStrategy: Canvas.Threaded

            onPaint: {
                var ctx = getContext("2d")
                ctx.reset()
                var objects = root.shownDocument && root.shownDocument.objects ? root.shownDocument.objects : []
                var halo = Qt.rgba(root.selectionColor.r, root.selectionColor.g, root.selectionColor.b, 0.45)
                for (var i = 0; i < objects.length; i++) {
                    if (objects[i].type !== "stroke")
                        continue
                    if (objects[i].id === root.selectedObjectId)
                        root.traceStroke(ctx, objects[i].points, (objects[i].width || 2.5) + 7, halo)
                    root.traceStroke(ctx, objects[i].points, objects[i].width || 2.5, root.graphite)
                }
            }
            onPainted: {
                if (!editorPointer.pressed)
                    root.clearWetInk()
            }
        }

        // The stroke being drawn, kept separate so each pointer sample repaints only itself.
        Canvas {
            id: wet

            anchors.fill: parent
            antialiasing: true

            onPaint: {
                var ctx = getContext("2d")
                ctx.reset()
                // Smoothed here, once per frame, rather than on every pointer event.
                root.traceStroke(ctx, root.strokePoints(), root.penWidth, root.graphite)
            }
        }

        Repeater {
            model: root.shownDocument && root.shownDocument.objects
                ? root.shownDocument.objects.filter(function(object) { return object.type === "text" })
                : []

            TextNote {
                required property var modelData
                objectData: modelData
                selected: modelData.id === root.selectedObjectId
                editing: modelData.id === root.editingObjectId
                selectable: root.currentTool === "select"
                editable: root.currentTool === "text"
                onSelectedRequested: function(id) {
                    root.finishEditing()
                    root.selectedObjectId = id
                }
                onEditRequested: function(id) {
                    root.beginEditing(id)
                }
                onCommitRequested: function(id, text, height) {
                    root.commitText(id, text, height)
                }
                onCancelRequested: function(id) {
                    root.cancelEditing()
                }
                onMoveRequested: function(id, x, y) {
                    root.commit(DocumentModel.moveText(root.document, id, x, y))
                }
            }
        }

        MouseArea {
            id: editorPointer

            anchors.fill: parent
            z: 15
            acceptedButtons: Qt.LeftButton
            hoverEnabled: true
            cursorShape: root.currentTool === "pen" || root.currentTool === "eraser" ? Qt.CrossCursor
                : root.currentTool === "text" ? Qt.IBeamCursor
                : root.gestureOrigin ? Qt.ClosedHandCursor
                : Qt.ArrowCursor

            onPressed: function(mouse) {
                if (root.editingObjectId !== "") {
                    editorPointer.forceActiveFocus()
                    mouse.accepted = true
                    return
                }
                root.gestureOrigin = [mouse.x, mouse.y]
                if (root.currentTool === "pen") {
                    root.steadyStroke = root.isSteadyInput(mouse)
                    root.activeStroke = [[mouse.x, mouse.y]]
                    wet.requestPaint()
                } else if (root.currentTool === "eraser") {
                    root.eraseAt(mouse.x, mouse.y)
                } else if (root.currentTool === "text") {
                    root.gestureOrigin = null
                    var next = DocumentModel.addText(root.document, mouse.x - 4, mouse.y - 12, "")
                    if (next !== root.document) {
                        root.draftDocument = next
                        root.beginEditing(next.objects[next.objects.length - 1].id)
                    }
                } else if (root.currentTool === "select") {
                    root.selectedObjectId = Geometry.hitTest(root.document.objects, [mouse.x, mouse.y], 6)
                    if (root.selectedObjectId === "")
                        root.gestureOrigin = null
                }
            }

            onPositionChanged: function(mouse) {
                if (!pressed || !root.gestureOrigin)
                    return
                var point = [mouse.x, mouse.y]
                if (root.currentTool === "eraser") {
                    root.eraseAlong(root.gestureOrigin, point)
                    root.gestureOrigin = point
                } else if (root.currentTool === "pen") {
                    var points = root.activeStroke
                    if (points.length > 0 && Geometry.pointDistance(points[points.length - 1], point) >= 1.5) {
                        points.push(point)
                        root.activeStroke = points
                        wet.requestPaint()
                    }
                } else if (root.currentTool === "select") {
                    if (!root.draftDocument && Geometry.pointDistance(root.gestureOrigin, point) < 3)
                        return
                    root.draftDocument = DocumentModel.translateObject(root.document, root.selectedObjectId,
                        mouse.x - root.gestureOrigin[0], mouse.y - root.gestureOrigin[1])
                }
            }

            onReleased: function(mouse) {
                root.finishGesture(mouse.x, mouse.y)
            }

            onCanceled: root.cancelGesture()

            // Passive: only reports which kind of device pressed, before onPressed runs.
            PointHandler {
                id: pointerKind

                target: null
            }
        }

        Rectangle {
            id: eraserRing

            z: 16
            visible: root.currentTool === "eraser" && editorPointer.containsMouse && root.editingObjectId === ""
            x: editorPointer.mouseX - width / 2
            y: editorPointer.mouseY - height / 2
            width: root.eraserRadius * 2
            height: width
            radius: width / 2
            color: "#14423e38"
            border.width: 1
            border.color: "#a0423e38"
        }

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: 46
            color: "#17ffffff"

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: 1
                color: "#375b5349"
            }

            Text {
                anchors.left: parent.left
                anchors.leftMargin: 28
                anchors.verticalCenter: parent.verticalCenter
                text: "FIELD NOTES"
                color: root.graphite
                font.family: "monospace"
                font.pixelSize: 16
                font.bold: true
                font.letterSpacing: 2.6
                textFormat: Text.PlainText
            }
        }

        // Above the drawing surface, so the paper type can be clicked; the rest of the row
        // takes no input, and the header stays drawable around it.
        Row {
            anchors.right: parent.right
            anchors.rightMargin: 19
            y: 23 - height / 2
            z: 21

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "SHEET " + root.pad2(root.sheetIndex + 1) + " OF " + root.pad2(root.sheetCount) + "  /"
                color: "#805b5349"
                font.family: "monospace"
                font.pixelSize: 9
                font.letterSpacing: 1.1
                textFormat: Text.PlainText
            }

            Item {
                id: paperLabel

                width: paperText.implicitWidth + 12
                height: 22

                Accessible.role: Accessible.Button
                Accessible.name: "Paper: " + paperText.text + ". Change paper (G)"
                Accessible.onPressAction: root.paperRequested()

                Rectangle {
                    anchors.fill: parent
                    radius: 4
                    color: paperMouse.pressed ? "#1a5b5349" : "transparent"
                    border.width: 1
                    border.color: paperMouse.containsMouse ? "#705b5349" : "transparent"
                }

                Text {
                    id: paperText

                    anchors.centerIn: parent
                    text: root.paperLabels[root.paperType] || "GRAPH 16"
                    color: paperMouse.containsMouse ? root.graphite : "#805b5349"
                    font.family: "monospace"
                    font.pixelSize: 9
                    font.letterSpacing: 1.1
                    textFormat: Text.PlainText
                }

                MouseArea {
                    id: paperMouse

                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.paperRequested()
                }

                Tooltip {
                    text: "Change paper"
                    shortcut: "G"
                    side: "bottom"
                    hovered: paperMouse.containsMouse
                }
            }
        }

        Rectangle {
            width: Math.max(68, statusLabel.implicitWidth + 16)
            height: 18
            anchors.right: parent.right
            anchors.rightMargin: 24
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 11
            radius: 2
            color: "transparent"
            border.width: 1
            border.color: "#705b5349"

            Text {
                id: statusLabel

                anchors.centerIn: parent
                text: root.statusText
                color: "#955b5349"
                font.family: "monospace"
                font.pixelSize: 8
                font.bold: true
                font.letterSpacing: 1.2
                textFormat: Text.PlainText
            }
        }
    }
}
