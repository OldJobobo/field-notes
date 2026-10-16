import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

Item {
    id: root

    property var bar: null

    implicitWidth: button.implicitWidth
    implicitHeight: button.implicitHeight

    // Opens the notes on the monitor this icon's bar is on. Prefers the bar's in-process shell
    // facade, falling back to the omarchy-shell CLI on hosts without it.
    function summon(extra) {
        var window = button.QsWindow.window
        var screen = window && window.screen ? String(window.screen.name || "") : ""
        var payload = Object.assign({}, extra)
        if (/^[A-Za-z][A-Za-z0-9_.:-]{0,127}$/.test(screen))
            payload.screen = screen
        var json = JSON.stringify(payload)
        var api = root.bar ? root.bar.shell : null
        if (api && typeof api.summon === "function" && api.summon("jobo.field-notes", json) === true)
            return
        if (root.bar)
            root.bar.run("omarchy-shell shell summon jobo.field-notes '" + json + "'")
    }

    BarIconButton {
        id: button

        anchors.fill: parent
        bar: root.bar
        text: "󰈙"
        fontFamily: "JetBrainsMono Nerd Font"
        tooltipText: "Field Notes (right-click for settings)"
        slotSize: Style.bar.iconSlot

        // Left click toggles the notes here (or brings them over from another monitor);
        // right click opens them at the settings, never closing them.
        onPressed: function(mouseButton) {
            if (mouseButton === Qt.LeftButton)
                root.summon({ toggle: true })
            else if (mouseButton === Qt.RightButton)
                root.summon({ settings: true })
        }
    }
}
