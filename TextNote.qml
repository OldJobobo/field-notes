import QtQuick

Item {
    id: root

    required property var objectData
    property bool selected: false
    property bool editing: false
    property bool selectable: false
    property bool erasable: false
    property bool dragStarted: false

    signal selectedRequested(string id)
    signal editRequested(string id)
    signal commitRequested(string id, string text)
    signal cancelRequested(string id)
    signal eraseRequested(string id)
    signal moveRequested(string id, real x, real y)

    x: objectData.x
    y: objectData.y
    width: objectData.width
    height: Math.max(objectData.height || 40, editor.contentHeight + 8)
    z: 20

    onEditingChanged: {
        if (editing) {
            editor.text = objectData.text
            Qt.callLater(function() {
                editor.forceActiveFocus()
                editor.selectAll()
            })
        } else {
            editor.text = objectData.text
        }
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

        anchors.fill: parent
        anchors.margins: 4
        text: root.objectData.text
        color: "#423e38"
        font.family: "monospace"
        font.pixelSize: root.objectData.size || 16
        wrapMode: TextEdit.Wrap
        textFormat: TextEdit.PlainText
        readOnly: !root.editing
        selectByMouse: root.editing
        cursorVisible: root.editing && activeFocus
        property bool editingFocusEstablished: false

        onActiveFocusChanged: {
            if (activeFocus && root.editing) {
                editingFocusEstablished = true
            } else if (!activeFocus && root.editing && editingFocusEstablished) {
                editingFocusEstablished = false
                root.commitRequested(root.objectData.id, text)
            }
        }

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
            var control = (event.modifiers & Qt.ControlModifier) !== 0
            if (event.key === Qt.Key_Escape) {
                root.cancelRequested(root.objectData.id)
                event.accepted = true
            } else if (control && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)) {
                root.commitRequested(root.objectData.id, text)
                event.accepted = true
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        enabled: !root.editing
        acceptedButtons: Qt.LeftButton
        cursorShape: root.erasable ? Qt.PointingHandCursor : (root.selectable ? Qt.SizeAllCursor : Qt.IBeamCursor)
        onClicked: {
            if (root.erasable)
                root.eraseRequested(root.objectData.id)
            else
                root.selectedRequested(root.objectData.id)
        }
        onDoubleClicked: {
            if (!root.erasable)
                root.editRequested(root.objectData.id)
        }
    }

    DragHandler {
        enabled: root.selectable && !root.editing
        target: root
        acceptedButtons: Qt.LeftButton
        onActiveChanged: {
            if (active) {
                root.dragStarted = true
                root.selectedRequested(root.objectData.id)
            } else if (root.dragStarted) {
                root.dragStarted = false
                root.moveRequested(root.objectData.id, root.x, root.y)
            }
        }
    }
}
