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
    // OmarchyTheme.qml or ClassicTheme.qml, chosen in settings.
    property QtObject theme
    readonly property bool hot: mouse.containsMouse
    readonly property color iconColor: dangerous ? (selected ? theme.selectedDangerIcon : theme.danger)
        : selected ? theme.selectedIcon
        : hot ? theme.hoverIcon : theme.icon
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

    // Same state precedence as the shell's own Button: pressed, hover, selected, rest.
    Rectangle {
        anchors.fill: parent
        radius: Math.max(0, root.theme.radius - 4)
        color: mouse.pressed ? root.theme.pressedFill
            : root.hot ? root.theme.hoverFill
            : root.selected ? (root.dangerous ? root.theme.dangerFill : root.theme.selectedFill)
            : "transparent"
        border.width: root.hot ? root.theme.hoverBorderWidth
            : root.selected ? root.theme.selectedBorderWidth : 0
        border.color: root.hot ? root.theme.hoverBorder : root.theme.selectedBorder
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

        theme: root.theme
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
