import QtQuick

Item {
    id: root

    property string text: "TOOL"
    property string glyph: "•"
    property bool selected: false
    property bool dangerous: false
    property bool enabled: true
    signal activated()

    implicitWidth: 58
    implicitHeight: 43
    opacity: enabled ? 1 : 0.38

    Rectangle {
        anchors.fill: parent
        radius: 5
        color: root.selected ? "#d8d0bc" : mouse.containsMouse ? "#3b3933" : "transparent"
        border.width: root.selected ? 1 : 0
        border.color: root.selected ? "#f0e9d8" : "transparent"

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: 5
            text: root.glyph
            color: root.selected ? "#2b2925" : root.dangerous ? "#d98672" : "#e1dac8"
            font.family: "monospace"
            font.pixelSize: 15
            font.bold: true
            textFormat: Text.PlainText
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 5
            text: root.text
            color: root.selected ? "#2b2925" : root.dangerous ? "#d98672" : "#aaa391"
            font.family: "monospace"
            font.pixelSize: 7
            font.bold: true
            font.letterSpacing: 0.6
            textFormat: Text.PlainText
        }
    }

    MouseArea {
        id: mouse

        anchors.fill: parent
        enabled: root.enabled
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.activated()
    }
}
