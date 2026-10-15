import QtQuick

Item {
    id: root

    required property var objectData
    property bool selected: false
    property bool editing: false
    property bool selectable: false
    property bool editable: false
    property bool dragStarted: false

    signal selectedRequested(string id)
    signal editRequested(string id)
    signal commitRequested(string id, string text, real height)
    signal cancelRequested(string id)
    signal moveRequested(string id, real x, real y)

    function startEditing() {
        editor.text = objectData.text
        editor.editingFocusEstablished = false
        Qt.callLater(function() {
            if (!root.editing)
                return
            editor.forceActiveFocus()
            editor.cursorPosition = editor.length
        })
    }

    x: objectData.x
    y: objectData.y
    width: objectData.width
    height: Math.max(28, editor.contentHeight + 8)
    z: 20

    onEditingChanged: {
        if (editing)
            startEditing()
        else
            editor.text = objectData.text
    }
    Component.onCompleted: {
        if (editing)
            startEditing()
    }

    Rectangle {
        anchors.fill: parent
        color: root.editing ? "#e8ded3bd" : (root.selected ? "#35b18d52" : "transparent")
        border.width: root.editing || root.selected ? 1 : 0
        border.color: root.editing ? "#7a6037" : "#8a6f4a"
        radius: 2
    }

    TextEdit {
        id: editor

        property bool editingFocusEstablished: false

        anchors.fill: parent
        anchors.margins: 4
        // Disabled outside edit mode so presses reach the note and paper handlers below.
        enabled: root.editing
        text: root.objectData.text
        color: "#423e38"
        font.family: "monospace"
        font.pixelSize: root.objectData.size || 16
        wrapMode: TextEdit.Wrap
        textFormat: TextEdit.PlainText
        readOnly: !root.editing
        selectByMouse: root.editing
        cursorVisible: root.editing && activeFocus

        onActiveFocusChanged: {
            if (activeFocus && root.editing) {
                editingFocusEstablished = true
            } else if (!activeFocus && root.editing && editingFocusEstablished) {
                editingFocusEstablished = false
                root.commitRequested(root.objectData.id, text, root.height)
            }
        }

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
            var control = (event.modifiers & Qt.ControlModifier) !== 0
            if (event.key === Qt.Key_Escape) {
                root.cancelRequested(root.objectData.id)
                event.accepted = true
            } else if (control && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)) {
                editingFocusEstablished = false
                root.commitRequested(root.objectData.id, text, root.height)
                event.accepted = true
            }
        }
    }

    Text {
        anchors.fill: editor
        visible: root.editing && editor.length === 0 && editor.preeditText === ""
        text: "Type a note…"
        color: "#80423e38"
        font: editor.font
        textFormat: Text.PlainText
    }

    MouseArea {
        anchors.fill: parent
        enabled: !root.editing && (root.selectable || root.editable)
        acceptedButtons: Qt.LeftButton
        cursorShape: root.editable ? Qt.IBeamCursor : Qt.SizeAllCursor
        onClicked: {
            if (root.editable)
                root.editRequested(root.objectData.id)
            else
                root.selectedRequested(root.objectData.id)
        }
        onDoubleClicked: root.editRequested(root.objectData.id)
    }

    DragHandler {
        enabled: root.selectable && !root.editing
        target: root
        acceptedButtons: Qt.LeftButton
        xAxis.minimum: 0
        xAxis.maximum: root.parent ? Math.max(0, root.parent.width - root.width) : 0
        yAxis.minimum: 0
        yAxis.maximum: root.parent ? Math.max(0, root.parent.height - root.height) : 0
        onActiveChanged: {
            if (active) {
                root.dragStarted = true
                root.selectedRequested(root.objectData.id)
            } else if (root.dragStarted) {
                root.dragStarted = false
                root.moveRequested(root.objectData.id, root.x, root.y)
                root.x = Qt.binding(function() { return root.objectData.x })
                root.y = Qt.binding(function() { return root.objectData.y })
            }
        }
    }
}
