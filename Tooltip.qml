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
    // OmarchyTheme.qml or ClassicTheme.qml, chosen in settings.
    property QtObject theme

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
    radius: theme.radius
    color: theme.tooltipBackground
    border.width: 1
    border.color: alert ? theme.danger : theme.tooltipBorder
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
            color: root.theme.tooltipText
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
            radius: Math.min(4, root.theme.radius)
            color: root.theme.keycapFill
            border.width: 1
            border.color: root.theme.keycapBorder

            Text {
                id: keyLabel

                anchors.centerIn: parent
                text: root.shortcut
                color: root.theme.tooltipText
                font.family: "monospace"
                font.pixelSize: 11
                font.bold: true
                textFormat: Text.PlainText
            }
        }
    }
}
