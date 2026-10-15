import QtQuick

// Hover tooltip: a dark chip with the action's name and its shortcut as a keycap, shown
// beyond one side of its parent after a short hover.
Rectangle {
    id: root

    property string text: ""
    property string shortcut: ""
    // Side of the parent the tooltip appears beyond: left, right, top or bottom.
    property string side: "left"
    property bool hovered: false
    // Shows the tooltip immediately, e.g. while a destructive action awaits confirmation.
    property bool force: false
    property bool alert: false
    property bool ready: false

    // Positioned arithmetically: switching anchors at runtime, when the toolbar docks
    // elsewhere, can leave stale conflicting anchors and a misplaced tooltip.
    x: side === "left" ? -width - 10
        : side === "right" ? parent.width + 10
        : Math.round((parent.width - width) / 2)
    y: side === "top" ? -height - 10
        : side === "bottom" ? parent.height + 10
        : Math.round((parent.height - height) / 2)
    width: row.implicitWidth + 20
    height: 30
    radius: 7
    color: "#1f1d1a"
    border.width: 1
    border.color: alert ? "#d98672" : "#4d483f"
    opacity: force || (hovered && ready) ? 1 : 0
    visible: opacity > 0

    onHoveredChanged: {
        if (!hovered)
            ready = false
    }

    Behavior on opacity {
        NumberAnimation {
            duration: 90
        }
    }

    Timer {
        interval: 450
        running: root.hovered && !root.ready
        onTriggered: root.ready = true
    }

    Row {
        id: row

        anchors.centerIn: parent
        spacing: 8

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.text
            color: "#f4efe4"
            font.family: "monospace"
            font.pixelSize: 13
            textFormat: Text.PlainText
        }

        // The shortcut as a keycap.
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.shortcut !== ""
            width: Math.max(height, keyLabel.implicitWidth + 10)
            height: 19
            radius: 4
            color: "#38342e"
            border.width: 1
            border.color: "#4d483f"

            Text {
                id: keyLabel

                anchors.centerIn: parent
                text: root.shortcut
                color: "#d6cfbd"
                font.family: "monospace"
                font.pixelSize: 11
                font.bold: true
                textFormat: Text.PlainText
            }
        }
    }
}
