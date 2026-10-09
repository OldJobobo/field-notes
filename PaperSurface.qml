import QtQuick
import QtQuick.Effects
import "DocumentModel.js" as DocumentModel
import "Geometry.js" as Geometry

Item {
    id: root

    property color paperColor: "#ded7c5"
    property color graphite: "#423e38"
    property color minorGrid: "#7898a8"
    property color majorGrid: "#5f8394"
    property var document: DocumentModel.createDocument(width, height)
    property string currentTool: "pen"
    property real penWidth: 2.5
    property var activeStroke: []
    property string selectedObjectId: ""
    property string editingObjectId: ""
    signal commitRequested(var nextDocument)
    signal toolRequested(string tool)

    function deleteSelected() {
        if (selectedObjectId === "")
            return false
        commitRequested(DocumentModel.deleteObject(document, selectedObjectId))
        selectedObjectId = ""
        editingObjectId = ""
        return true
    }

    function cancelEditing() {
        if (editingObjectId === "")
            return false
        editingObjectId = ""
        return true
    }

    function commitText(id, text) {
        editingObjectId = ""
        selectedObjectId = ""
        commitRequested(DocumentModel.updateText(document, id, text))
    }

    function moveText(id, x, y) {
        commitRequested(DocumentModel.moveText(document, id, x, y))
    }

    function eraseAt(x, y) {
        var erasedId = Geometry.hitTest(document.objects, [x, y], 12)
        if (erasedId === "")
            return false

        var erasedObject = null
        for (var i = 0; i < document.objects.length; i++) {
            if (document.objects[i].id === erasedId) {
                erasedObject = document.objects[i]
                break
            }
        }
        if (!erasedObject)
            return false

        if (selectedObjectId === erasedId)
            selectedObjectId = ""
        if (editingObjectId === erasedId)
            editingObjectId = ""

        if (erasedObject.type === "stroke") {
            var radius = 12 + Number(erasedObject.width || 1) / 2
            var segments = Geometry.splitStroke(erasedObject.points, [x, y], radius)
            commitRequested(DocumentModel.replaceStrokeSegments(document, erasedId, segments))
        } else {
            commitRequested(DocumentModel.deleteObject(document, erasedId))
        }
        return true
    }

    onDocumentChanged: ink.requestPaint()

    rotation: 0.8
    transformOrigin: Item.Center

    Rectangle {
        id: sheet

        anchors.fill: parent
        radius: 3
        color: root.paperColor
        border.width: 1
        border.color: "#b8ad96"
        layer.enabled: true
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

                var minor = 16
                var major = 80
                ctx.lineWidth = 1
                ctx.strokeStyle = Qt.rgba(root.minorGrid.r, root.minorGrid.g, root.minorGrid.b, 0.20)
                ctx.beginPath()
                for (var x = minor; x < width; x += minor) {
                    ctx.moveTo(Math.round(x) + 0.5, 0)
                    ctx.lineTo(Math.round(x) + 0.5, height)
                }
                for (var y = minor; y < height; y += minor) {
                    ctx.moveTo(0, Math.round(y) + 0.5)
                    ctx.lineTo(width, Math.round(y) + 0.5)
                }
                ctx.stroke()

                ctx.lineWidth = 1.15
                ctx.strokeStyle = Qt.rgba(root.majorGrid.r, root.majorGrid.g, root.majorGrid.b, 0.31)
                ctx.beginPath()
                for (var mx = major; mx < width; mx += major) {
                    ctx.moveTo(Math.round(mx) + 0.5, 0)
                    ctx.lineTo(Math.round(mx) + 0.5, height)
                }
                for (var my = major; my < height; my += major) {
                    ctx.moveTo(0, Math.round(my) + 0.5)
                    ctx.lineTo(width, Math.round(my) + 0.5)
                }
                ctx.stroke()
            }
        }

        Canvas {
            id: ink

            anchors.fill: parent
            antialiasing: true
            renderStrategy: Canvas.Threaded

            function drawStroke(ctx, stroke) {
                if (!stroke.points || stroke.points.length === 0)
                    return
                ctx.strokeStyle = root.graphite
                ctx.fillStyle = root.graphite
                ctx.lineWidth = stroke.width || 2.5
                ctx.lineCap = "round"
                ctx.lineJoin = "round"
                if (stroke.points.length === 1) {
                    ctx.beginPath()
                    ctx.arc(stroke.points[0][0], stroke.points[0][1], ctx.lineWidth / 2, 0, Math.PI * 2)
                    ctx.fill()
                    return
                }
                ctx.beginPath()
                ctx.moveTo(stroke.points[0][0], stroke.points[0][1])
                for (var i = 1; i < stroke.points.length; i++)
                    ctx.lineTo(stroke.points[i][0], stroke.points[i][1])
                ctx.stroke()
            }

            onPaint: {
                var ctx = getContext("2d")
                ctx.reset()
                var objects = root.document && root.document.objects ? root.document.objects : []
                for (var i = 0; i < objects.length; i++) {
                    if (objects[i].type === "stroke")
                        drawStroke(ctx, objects[i])
                }
                if (root.activeStroke.length > 0)
                    drawStroke(ctx, { points: root.activeStroke, width: root.penWidth })
            }
        }

        Repeater {
            model: root.document && root.document.objects
                ? root.document.objects.filter(function(object) { return object.type === "text" })
                : []

            TextNote {
                required property var modelData
                objectData: modelData
                selected: modelData.id === root.selectedObjectId
                editing: modelData.id === root.editingObjectId
                selectable: root.currentTool === "select"
                erasable: root.currentTool === "eraser"
                onSelectedRequested: function(id) {
                    root.selectedObjectId = id
                }
                onEditRequested: function(id) {
                    root.selectedObjectId = id
                    root.editingObjectId = id
                }
                onCommitRequested: function(id, text) {
                    root.commitText(id, text)
                }
                onCancelRequested: function(id) {
                    root.editingObjectId = ""
                }
                onEraseRequested: function(id) {
                    root.selectedObjectId = ""
                    root.editingObjectId = ""
                    root.commitRequested(DocumentModel.deleteObject(root.document, id))
                }
                onMoveRequested: function(id, x, y) {
                    root.moveText(id, x, y)
                }
            }
        }

        MouseArea {
            id: editorPointer

            anchors.fill: parent
            z: 15
            acceptedButtons: Qt.LeftButton
            hoverEnabled: true
            cursorShape: root.currentTool === "pen" ? Qt.CrossCursor
                : root.currentTool === "eraser" ? Qt.PointingHandCursor
                : root.currentTool === "text" ? Qt.IBeamCursor
                : Qt.ArrowCursor

            onPressed: function(mouse) {
                if (root.editingObjectId !== "") {
                    editorPointer.forceActiveFocus()
                    mouse.accepted = true
                    return
                }
                if (root.currentTool === "pen") {
                    root.activeStroke = [[mouse.x, mouse.y]]
                    ink.requestPaint()
                } else if (root.currentTool === "eraser") {
                    root.eraseAt(mouse.x, mouse.y)
                } else if (root.currentTool === "text") {
                    var next = DocumentModel.addText(root.document, mouse.x, mouse.y, "New note")
                    root.selectedObjectId = next.objects[next.objects.length - 1].id
                    root.editingObjectId = root.selectedObjectId
                    root.commitRequested(next)
                } else if (root.currentTool === "select") {
                    root.selectedObjectId = Geometry.hitTest(root.document.objects, [mouse.x, mouse.y], 5)
                }
            }

            onPositionChanged: function(mouse) {
                if (!pressed)
                    return
                if (root.currentTool === "eraser") {
                    root.eraseAt(mouse.x, mouse.y)
                    return
                }
                if (root.currentTool !== "pen" || root.activeStroke.length === 0)
                    return
                var point = [mouse.x, mouse.y]
                if (Geometry.pointDistance(root.activeStroke[root.activeStroke.length - 1], point) >= 2.5) {
                    var nextPoints = root.activeStroke.slice()
                    nextPoints.push(point)
                    root.activeStroke = nextPoints
                    ink.requestPaint()
                }
            }

            onReleased: function(mouse) {
                if (root.currentTool !== "pen" || root.activeStroke.length === 0)
                    return
                var points = root.activeStroke
                root.activeStroke = []
                if (points.length === 1)
                    points.push([mouse.x + 0.1, mouse.y + 0.1])
                root.commitRequested(DocumentModel.addStroke(root.document, points, root.penWidth))
                ink.requestPaint()
            }

            onCanceled: {
                root.activeStroke = []
                ink.requestPaint()
            }
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

            Text {
                anchors.right: parent.right
                anchors.rightMargin: 25
                anchors.verticalCenter: parent.verticalCenter
                text: "SHEET 01  /  GRAPH 16"
                color: "#805b5349"
                font.family: "monospace"
                font.pixelSize: 9
                font.letterSpacing: 1.1
                textFormat: Text.PlainText
            }
        }

        Text {
            anchors.left: parent.left
            anchors.leftMargin: 27
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 15
            text: "jobo.field-notes  •  drag the brass clip to move"
            color: "#705b5349"
            font.family: "monospace"
            font.pixelSize: 8
            font.letterSpacing: 0.7
            textFormat: Text.PlainText
        }

        Rectangle {
            width: 68
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
                anchors.centerIn: parent
                text: "READY"
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
