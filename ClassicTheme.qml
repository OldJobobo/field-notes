import QtQuick

// Field Notes' own warm graphite look, used when "Use Omarchy theme" is off. It defines
// the same properties as OmarchyTheme.qml, so either can be handed to the components.
QtObject {
    readonly property color text: "#e8e1cf"
    readonly property color accent: "#d9c9a3"
    readonly property color danger: "#d98672"

    readonly property color background: "#f02b2925"
    readonly property color border: "#5a6f695d"
    readonly property int borderWidth: 1
    readonly property int radius: 13

    readonly property color icon: "#a9a291"
    readonly property color hoverIcon: "#f0e9d8"
    readonly property color selectedIcon: "#2b2925"
    readonly property color hoverFill: "#14ffffff"
    readonly property color pressedFill: "#26ffffff"
    readonly property color selectedFill: "#e6dfcc"
    readonly property color dangerFill: "#d98672"
    readonly property color hoverBorder: "transparent"
    readonly property int hoverBorderWidth: 0
    readonly property color selectedBorder: "transparent"
    readonly property int selectedBorderWidth: 0
    readonly property color selectedDangerIcon: "#2b2925"
    readonly property color divider: "#4a6f695d"
    readonly property color subtle: "#9a9382"

    readonly property color fieldFill: "#14ffffff"
    readonly property color fieldBorder: "#4d483f"
    readonly property color switchOn: "#d9c9a3"
    readonly property color switchOff: "#3d3a34"
    readonly property color knobOn: "#2b2925"
    readonly property color knobOff: "#a9a291"

    readonly property color tooltipBackground: "#1f1d1a"
    readonly property color tooltipText: "#f4efe4"
    readonly property color tooltipBorder: "#4d483f"
    readonly property color keycapFill: "#38342e"
    readonly property color keycapBorder: "#4d483f"
}
