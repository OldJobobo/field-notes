import QtQuick
import qs.Commons

// The active Omarchy theme, mapped onto the toolbar, settings and tooltips the way the shell's own
// controls use it. Everything comes from the shell's theme state (the theme's colors.toml
// and shell.toml, plus the user's ~/.config/omarchy/shell.toml), which the shell updates
// live when the theme changes, so every binding here follows a theme switch.
//
//   toolbar surface   [popups] background / border, unless [field-notes] overrides them
//   button states     [controls] hover-cursor / selected / pressed, as the shell's Button
//   tooltips          [tooltip]
//   danger            the palette's urgent color
//   fields, switches  [controls] normal state; switches use the accent
//   corner radius     Hyprland's window rounding
//
// Optional overrides, in a theme's shell.toml or ~/.config/omarchy/shell.toml:
//
//   [field-notes]
//   background = "#1e4147"     # hex or a palette role: foreground, background, accent, urgent
//   background-alpha = 0.94
//   border = "accent"
//   border-alpha = 0.6
//   border-width = 1
//   text = "foreground"
//   accent = "accent"
//   danger = "urgent"
QtObject {
    function value(key, fallback) {
        return Color.flatColor(Color.pick("field-notes." + key, ""), fallback)
    }

    // [field-notes] key, else the shell key it defaults to, else the fallback number.
    function number(key, shellKey, fallback) {
        var raw = Color.pick("field-notes." + key, Color.pick(shellKey, ""))
        var n = Number(raw)
        return raw !== "" && isFinite(n) ? n : fallback
    }

    readonly property color text: value("text", Color.popups.text)
    readonly property color accent: value("accent", Color.accent)
    readonly property color danger: value("danger", Color.urgent)

    readonly property color background: Color.composed("field-notes.background", "field-notes.background-alpha",
        Color.pick("popups.background", Color.background), Color.pickAlpha("popups.background-alpha", 1.0))
    readonly property color border: Color.composed("field-notes.border", "field-notes.border-alpha",
        Color.pick("popups.border", Color.accent), Color.pickAlpha("popups.border-alpha", 1.0))
    readonly property int borderWidth: Math.max(0, Math.round(number("border-width", "popups.border-width", 1)))
    readonly property int radius: Style.cornerRadius

    readonly property color icon: text
    readonly property color hoverIcon: Style.hoverStateColor(text, accent)
    readonly property color selectedIcon: Style.selectedStateColor(text, accent)
    readonly property color hoverFill: Style.hoverFillFor(text, accent)
    readonly property color pressedFill: Style.pressedFillFor(text, accent)
    readonly property color selectedFill: Style.selectedFillFor(text, accent)
    readonly property color dangerFill: Util.alpha(danger, Style.selectedFillAlpha)
    readonly property color hoverBorder: Style.hoverBorderFor(text, accent)
    readonly property int hoverBorderWidth: Style.hoverBorderWidth
    readonly property color selectedBorder: Style.selectedBorderFor(text, accent)
    readonly property int selectedBorderWidth: Style.selectedBorderWidth
    readonly property color selectedDangerIcon: danger
    readonly property color divider: Util.alpha(text, 0.22)
    readonly property color subtle: Util.alpha(text, 0.6)

    readonly property color fieldFill: Style.normalFillFor(text, accent)
    readonly property color fieldBorder: Style.normalBorderFor(text, accent)
    readonly property color switchOn: accent
    readonly property color switchOff: Util.alpha(text, 0.2)
    readonly property color knobOn: Color.background
    readonly property color knobOff: text

    readonly property color tooltipBackground: Color.tooltip.background
    readonly property color tooltipText: Color.tooltip.text
    readonly property color tooltipBorder: Color.tooltip.border
    readonly property color keycapFill: Util.alpha(Color.tooltip.text, 0.12)
    readonly property color keycapBorder: Util.alpha(Color.tooltip.text, 0.28)
}
