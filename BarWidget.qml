import QtQuick
import qs.Commons
import qs.Ui

Item {
    id: root

    property var bar: null

    implicitWidth: button.implicitWidth
    implicitHeight: button.implicitHeight

    BarIconButton {
        id: button

        anchors.fill: parent
        bar: root.bar
        text: "󰈙"
        fontFamily: "JetBrainsMono Nerd Font"
        tooltipText: "Field Notes (right-click for settings)"
        slotSize: Style.bar.iconSlot

        // Left click toggles the notes; right click opens them at the settings.
        onPressed: function(mouseButton) {
            if (mouseButton === Qt.LeftButton)
                root.bar.run("omarchy-shell shell toggle jobo.field-notes '{}'")
            else if (mouseButton === Qt.RightButton)
                root.bar.run("omarchy-shell shell summon jobo.field-notes '{\"settings\":true}'")
        }
    }
}
