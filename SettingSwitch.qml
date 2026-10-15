import QtQuick

// A settings row: a label, an optional one-line description, and an on/off switch.
// Click anywhere on the row, or press Space or Enter when it has keyboard focus.
Item {
    id: root

    property QtObject theme
    property string label: ""
    property string description: ""
    property bool checked: false
    signal toggled(bool checked)

    implicitHeight: Math.max(30, text.implicitHeight)
    activeFocusOnTab: true

    Accessible.role: Accessible.CheckBox
    Accessible.name: label
    Accessible.description: description
    Accessible.checkable: true
    Accessible.checked: checked
    Accessible.onToggleAction: root.toggled(!root.checked)
    Accessible.onPressAction: root.toggled(!root.checked)

    Keys.onSpacePressed: root.toggled(!root.checked)
    Keys.onReturnPressed: root.toggled(!root.checked)
    Keys.onEnterPressed: root.toggled(!root.checked)

    Column {
        id: text

        anchors.left: parent.left
        anchors.right: track.left
        anchors.rightMargin: 16
        anchors.verticalCenter: parent.verticalCenter
        spacing: 2

        Text {
            width: parent.width
            text: root.label
            color: root.theme.text
            font.family: "monospace"
            font.pixelSize: 13
            elide: Text.ElideRight
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
        id: track

        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: 36
        height: 20
        radius: height / 2
        color: root.checked ? root.theme.switchOn : root.theme.switchOff
        border.width: root.activeFocus ? 2 : 0
        border.color: root.theme.hoverIcon

        Behavior on color {
            ColorAnimation {
                duration: 120
            }
        }

        Rectangle {
            x: root.checked ? parent.width - width - 3 : 3
            anchors.verticalCenter: parent.verticalCenter
            width: 14
            height: 14
            radius: 7
            color: root.checked ? root.theme.knobOn : root.theme.knobOff

            Behavior on x {
                NumberAnimation {
                    duration: 140
                    easing.type: Easing.OutCubic
                }
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            root.forceActiveFocus()
            root.toggled(!root.checked)
        }
    }
}
