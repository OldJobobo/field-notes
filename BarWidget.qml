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
        tooltipText: "Field Notes"
        slotSize: Style.bar.iconSlot

        onPressed: function(mouseButton) {
            if (mouseButton === Qt.LeftButton)
                root.bar.run("omarchy-shell shell toggle jobo.field-notes '{}'")
        }
    }
}
