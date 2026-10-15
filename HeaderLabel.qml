import QtQuick

// A small printed setting in the paper header (paper type, size) that changes when
// clicked. It looks like print until hovered; flash() briefly explains a refused change.
Item {
    id: root

    property string text: ""
    property string action: ""
    property string shortcut: ""
    property color ink: "#423e38"
    // While exporting, hover outlines and tooltips stay off the image.
    property bool quiet: false
    property string notice: ""
    property QtObject theme
    signal activated()

    function flash(message) {
        notice = message
        noticeTimer.restart()
    }

    width: label.implicitWidth + 12
    height: 22

    Accessible.role: Accessible.Button
    Accessible.name: text + ". " + action + (shortcut === "" ? "" : " (" + shortcut + ")")
    Accessible.onPressAction: root.activated()

    Timer {
        id: noticeTimer

        interval: 1800
        onTriggered: root.notice = ""
    }

    Rectangle {
        anchors.fill: parent
        radius: 4
        color: mouse.pressed ? "#1a5b5349" : "transparent"
        border.width: 1
        border.color: mouse.containsMouse && !root.quiet ? "#705b5349" : "transparent"
    }

    Text {
        id: label

        anchors.centerIn: parent
        text: root.text
        color: mouse.containsMouse && !root.quiet ? root.ink : "#805b5349"
        font.family: "monospace"
        font.pixelSize: 9
        font.letterSpacing: 1.1
        textFormat: Text.PlainText
    }

    MouseArea {
        id: mouse

        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.activated()
    }

    // Right-aligned: these labels sit at the paper's right edge, so the tooltip opens over
    // the paper rather than out toward the toolbar.
    Tooltip {
        x: root.width - width
        theme: root.theme
        text: root.notice || root.action
        shortcut: root.notice === "" ? root.shortcut : ""
        side: "bottom"
        hovered: mouse.containsMouse && !root.quiet
        force: root.notice !== "" && !root.quiet
        alert: root.notice !== ""
    }
}
