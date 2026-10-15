import QtQuick

// A settings row: a label, an optional description, and a segmented control below them.
// options is a list of [value, label] pairs. With keyboard focus, Left and Right move the
// choice.
Item {
    id: root

    property QtObject theme
    property string label: ""
    property string description: ""
    property var options: []
    property var value
    signal chosen(var value)

    function indexOfValue() {
        for (var i = 0; i < options.length; i++) {
            if (options[i][0] === value)
                return i
        }
        return -1
    }

    function step(delta) {
        var next = Math.max(0, Math.min(options.length - 1, indexOfValue() + delta))
        if (next !== indexOfValue())
            chosen(options[next][0])
    }

    implicitHeight: heading.implicitHeight + 8 + segments.height
    activeFocusOnTab: true

    Accessible.role: Accessible.PageTabList
    Accessible.name: label

    Keys.onLeftPressed: step(-1)
    Keys.onRightPressed: step(1)

    Column {
        id: heading

        width: parent.width
        spacing: 2

        Text {
            width: parent.width
            text: root.label
            color: root.theme.text
            font.family: "monospace"
            font.pixelSize: 13
            textFormat: Text.PlainText
        }

        Text {
            width: parent.width
            visible: root.description !== ""
            text: root.description
            color: root.theme.subtle
            font.family: "monospace"
            font.pixelSize: 11
            wrapMode: Text.WordWrap
            textFormat: Text.PlainText
        }
    }

    Rectangle {
        id: segments

        y: heading.implicitHeight + 8
        width: parent.width
        height: 30
        radius: Math.min(8, root.theme.radius)
        color: root.theme.fieldFill
        border.width: root.activeFocus ? 2 : 1
        border.color: root.activeFocus ? root.theme.hoverIcon : root.theme.fieldBorder

        Row {
            anchors.fill: parent
            anchors.margins: 3
            spacing: 2

            Repeater {
                model: root.options

                Rectangle {
                    id: segment

                    required property var modelData
                    readonly property bool selected: modelData[0] === root.value

                    width: (parent.width - (root.options.length - 1) * 2) / root.options.length
                    height: parent.height
                    radius: Math.max(0, Math.min(6, root.theme.radius - 3))
                    color: selected ? root.theme.selectedFill
                        : choiceMouse.pressed ? root.theme.pressedFill
                        : choiceMouse.containsMouse ? root.theme.hoverFill : "transparent"

                    Accessible.role: Accessible.PageTab
                    Accessible.name: modelData[1]
                    Accessible.selected: selected
                    Accessible.onPressAction: root.chosen(modelData[0])

                    Behavior on color {
                        ColorAnimation {
                            duration: 100
                        }
                    }

                    Text {
                        anchors.centerIn: parent
                        text: segment.modelData[1]
                        color: segment.selected ? root.theme.selectedIcon
                            : choiceMouse.containsMouse ? root.theme.hoverIcon : root.theme.icon
                        font.family: "monospace"
                        font.pixelSize: 12
                        font.bold: segment.selected
                        textFormat: Text.PlainText
                    }

                    MouseArea {
                        id: choiceMouse

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.forceActiveFocus()
                            root.chosen(segment.modelData[0])
                        }
                    }
                }
            }
        }
    }
}
