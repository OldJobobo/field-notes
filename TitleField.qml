import QtQuick

// The sheet title in the paper header. It reads as printed text and edits in place when
// clicked (or on F2): Enter or clicking away keeps the edit, Escape restores the title.
Item {
    id: root

    property string text: ""
    property string placeholder: "UNTITLED"
    property color ink: "#423e38"
    property bool editing: false
    // While exporting, hover outlines and tooltips stay off the image.
    property bool quiet: false
    property QtObject theme
    signal committed(string text)
    signal finished()

    function startEditing() {
        if (editing)
            return
        input.text = root.text
        editing = true
        input.forceActiveFocus()
        input.selectAll()
    }

    function finish(keep) {
        if (!editing)
            return
        editing = false
        if (keep)
            committed(input.text)
        finished()
    }

    implicitHeight: 30

    Accessible.role: Accessible.EditableText
    Accessible.name: "Sheet title: " + (root.text || "untitled") + ". Rename (F2)"

    Rectangle {
        x: -6
        width: parent.width + 12
        height: parent.height
        radius: 4
        color: root.editing ? "#24ffffff" : "transparent"
        border.width: 1
        border.color: root.editing ? "#a05b5349" : mouse.containsMouse && !root.quiet ? "#705b5349" : "transparent"
    }

    Text {
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        visible: !root.editing
        text: root.text || root.placeholder
        color: root.text ? root.ink : Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.35)
        elide: Text.ElideRight
        font.family: "monospace"
        font.pixelSize: 16
        font.bold: true
        font.letterSpacing: 2.6
        font.capitalization: Font.AllUppercase
        textFormat: Text.PlainText
    }

    TextInput {
        id: input

        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        visible: root.editing
        clip: true
        maximumLength: 60
        color: root.ink
        selectionColor: "#b18d52"
        selectedTextColor: "#f4efe4"
        font.family: "monospace"
        font.pixelSize: 16
        font.bold: true
        font.letterSpacing: 2.6
        font.capitalization: Font.AllUppercase

        Keys.onReturnPressed: root.finish(true)
        Keys.onEnterPressed: root.finish(true)
        Keys.onEscapePressed: root.finish(false)
        onActiveFocusChanged: {
            if (!activeFocus)
                root.finish(true)
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: input.text === ""
            text: root.placeholder
            color: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.3)
            font: input.font
            textFormat: Text.PlainText
        }
    }

    MouseArea {
        id: mouse

        anchors.fill: parent
        enabled: !root.editing
        hoverEnabled: true
        cursorShape: Qt.IBeamCursor
        onClicked: root.startEditing()
    }

    Tooltip {
        theme: root.theme
        text: "Rename sheet"
        shortcut: "F2"
        side: "bottom"
        x: 0
        hovered: mouse.containsMouse && !root.editing && !root.quiet
    }
}
