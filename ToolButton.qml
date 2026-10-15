import QtQuick

Item {
    id: root

    // Name shown in the hover tooltip and exposed to accessibility tools.
    property string text: ""
    // Nerd Font glyph.
    property string icon: ""
    property string shortcut: ""
    // When positive, a filled dot of this diameter replaces the icon (pen width preview).
    property real dotSize: 0
    property bool selected: false
    property bool dangerous: false
    // Shows the tooltip immediately, e.g. while a destructive action awaits confirmation.
    property bool forceTooltip: false
    // Edge of the button the tooltip appears beyond: left, right, top or bottom.
    property string tooltipSide: "left"
    readonly property color iconColor: selected ? "#2b2925"
        : dangerous ? "#d98672"
        : mouse.containsMouse ? "#f0e9d8" : "#a9a291"
    signal activated()

    implicitWidth: 40
    implicitHeight: 40
    opacity: enabled ? 1 : 0.3
    // Lifts the open tooltip above the neighbouring buttons.
    z: tooltip.visible ? 1 : 0

    Accessible.role: Accessible.Button
    Accessible.name: shortcut === "" ? text : text + " (" + shortcut + ")"
    Accessible.onPressAction: {
        if (root.enabled)
            root.activated()
    }

    Rectangle {
        anchors.fill: parent
        radius: 9
        color: root.selected ? (root.dangerous ? "#d98672" : "#e6dfcc")
            : mouse.pressed ? "#26ffffff"
            : mouse.containsMouse ? "#14ffffff" : "transparent"
    }

    Text {
        anchors.centerIn: parent
        visible: root.dotSize <= 0
        text: root.icon
        color: root.iconColor
        font.family: "JetBrainsMono Nerd Font"
        font.pixelSize: 18
        textFormat: Text.PlainText
    }

    Rectangle {
        anchors.centerIn: parent
        visible: root.dotSize > 0
        width: root.dotSize
        height: root.dotSize
        radius: root.dotSize / 2
        color: root.iconColor
    }

    Tooltip {
        id: tooltip

        text: root.text
        shortcut: root.shortcut
        side: root.tooltipSide
        hovered: mouse.containsMouse
        force: root.forceTooltip
        alert: root.dangerous && root.selected
    }

    MouseArea {
        id: mouse

        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.activated()
    }
}
