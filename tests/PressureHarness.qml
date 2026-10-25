import QtQuick
import ".." as FieldNotes
import "../DocumentModel.js" as DocumentModel

// Isolated fixture: no shell, state file, clipboard, or live desktop changes.
Item {
    id: harness
    width: 760
    height: 560
    property int commits: 0
    property bool exportDone: false
    property bool exportOk: false

    function reset() {
        paper.cancelGesture()
        paper.currentTool = "pen"
        paper.document = DocumentModel.createDocument(width, height, "plain")
        commits = 0
    }

    function exportPng(path) {
        exportDone = false
        exportOk = false
        paper.exportImage(path, function(ok) {
            exportOk = ok
            exportDone = true
        })
    }

    function fillStroke() {
        var points = []
        for (var i = 0; i < DocumentModel.MAX_STROKE_POINTS; i++)
            points.push([80 + i % 500, 150, 0.5])
        paper.activeStroke = points
        paper.appendPenPoint([600, 150, 1])
        paper.appendPenPoint([620, 150, 1])
    }

    function snapshot() {
        return JSON.stringify({ commits: commits, objects: paper.document.objects,
            active: paper.activeStroke, pressure: paper.pressureStroke,
            steady: paper.steadyStroke, gesture: paper.gestureOrigin,
            full: paper.strokeFull })
    }

    FieldNotes.PaperSurface {
        id: paper
        objectName: "paper"
        anchors.fill: parent
        tilted: false
        penWidth: 12
        theme: FieldNotes.ClassicTheme {}
        document: DocumentModel.createDocument(width, height, "plain")
        onCommitRequested: function(next) {
            harness.commits++
            document = next
        }
    }

    Component.onCompleted: {
        // MultiEffect shadows are unavailable with Qt's offscreen software renderer.
        for (var i = 0; i < paper.children.length; i++)
            paper.children[i].layer.enabled = false
    }
}
