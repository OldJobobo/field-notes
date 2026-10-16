import QtQuick
import QtQuick.Effects

// Field Notes settings: a card in the toolbar's style (and theme). It only displays the
// settings it is given and reports changes; the panel applies and saves them.
Item {
    id: root

    property QtObject theme
    property var settings: ({})
    property string toolbarSide: "right"
    property string version: ""
    property string notesPath: ""
    property string defaultExportDir: ""
    property string home: ""
    // Largest the card may be; it uses two columns when there is room, and the body
    // scrolls beyond maxHeight.
    property real maxWidth: 1000
    property real maxHeight: 600
    readonly property bool wide: maxWidth >= 780
    signal settingChanged(string key, var value)
    signal toolbarSideRequested(string side)
    signal openExportFolderRequested()
    signal centerBoardRequested()
    signal resetRequested()
    signal closeRequested()
    signal editingFinished()

    function tilde(path) {
        return home !== "" && path.indexOf(home) === 0 ? "~" + path.slice(home.length) : path
    }

    implicitWidth: wide ? 780 : 460
    implicitHeight: Math.min(maxHeight, header.height + body.contentHeight + 12)

    Accessible.role: Accessible.Dialog
    Accessible.name: "Field Notes settings"

    component SectionHeading: Item {
        property string text: ""

        width: parent ? parent.width : 0
        height: 30

        Text {
            anchors.left: parent.left
            anchors.bottom: rule.top
            anchors.bottomMargin: 6
            text: parent.text
            color: root.theme.subtle
            font.family: "monospace"
            font.pixelSize: 10
            font.bold: true
            font.letterSpacing: 1.6
            font.capitalization: Font.AllUppercase
            textFormat: Text.PlainText
        }

        Rectangle {
            id: rule

            anchors.bottom: parent.bottom
            width: parent.width
            height: 1
            color: root.theme.divider
        }
    }

    component TextButton: Rectangle {
        id: button

        property string text: ""
        signal clicked()

        implicitWidth: buttonLabel.implicitWidth + 24
        height: 28
        radius: Math.min(7, root.theme.radius)
        color: buttonMouse.pressed ? root.theme.pressedFill
            : buttonMouse.containsMouse ? root.theme.hoverFill : root.theme.fieldFill
        border.width: activeFocus ? 2 : 1
        border.color: activeFocus ? root.theme.hoverIcon : root.theme.fieldBorder
        activeFocusOnTab: true

        Accessible.role: Accessible.Button
        Accessible.name: text
        Accessible.onPressAction: button.clicked()
        Keys.onSpacePressed: button.clicked()
        Keys.onReturnPressed: button.clicked()

        Text {
            id: buttonLabel

            anchors.centerIn: parent
            text: button.text
            color: buttonMouse.containsMouse ? root.theme.hoverIcon : root.theme.text
            font.family: "monospace"
            font.pixelSize: 12
            textFormat: Text.PlainText
        }

        MouseArea {
            id: buttonMouse

            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: button.clicked()
        }
    }

    // Card background; a sibling of the content so its shadow layer cannot clip tooltips.
    Rectangle {
        anchors.fill: parent
        radius: root.theme.radius
        color: root.theme.background
        border.width: root.theme.borderWidth
        border.color: root.theme.border
        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: "#80000000"
            shadowBlur: 0.8
            shadowVerticalOffset: 10
            autoPaddingEnabled: true
        }
    }

    // Swallows clicks on the card so they never reach the paper underneath.
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        onWheel: function(wheel) {
            wheel.accepted = false
        }
    }

    Item {
        id: header

        x: 20
        width: parent.width - 32
        height: 64

        Column {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 3

            Text {
                text: "Settings"
                color: root.theme.text
                font.family: "monospace"
                font.pixelSize: 16
                font.bold: true
                textFormat: Text.PlainText
            }

            Text {
                text: root.version === "" ? "Field Notes" : "Field Notes v" + root.version
                color: root.theme.subtle
                font.family: "monospace"
                font.pixelSize: 11
                textFormat: Text.PlainText
            }
        }

        ToolButton {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            theme: root.theme
            text: "Close settings"
            icon: "󰅖"
            shortcut: "Esc"
            tooltipSide: "left"
            onActivated: root.closeRequested()
        }
    }

    // Scroll cue: a fade at the bottom while there is more below.
    Rectangle {
        x: body.x
        y: body.y + body.height - height
        z: 1
        width: body.width
        height: 28
        visible: body.contentY + body.height < body.contentHeight - 1
        gradient: Gradient {
            GradientStop { position: 0; color: "transparent" }
            GradientStop { position: 1; color: root.theme.background }
        }
    }

    Flickable {
        id: body

        x: 20
        y: header.height
        width: parent.width - 40
        height: parent.height - header.height - 12
        contentHeight: column.implicitHeight + 12
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        // Two columns when the board is wide enough, so the card fits without scrolling;
        // one scrolling column on small sheets.
        Grid {
            id: column

            width: parent.width
            columns: root.wide ? 2 : 1
            columnSpacing: 28
            rowSpacing: 12

            Column {
                width: root.wide ? (column.width - column.columnSpacing) / 2 : column.width
                spacing: 12

                SectionHeading {
                    text: "Appearance"
                }

                SettingSwitch {
                    width: parent.width
                    theme: root.theme
                    label: "Use Omarchy theme"
                    description: "Colors follow theme changes live."
                    checked: root.settings.theme === true
                    onToggled: function(checked) {
                        root.settingChanged("theme", checked)
                    }
                }

                SettingChoice {
                    width: parent.width
                    theme: root.theme
                    label: "Toolbar position"
                    description: "Or drag the toolbar by its grip."
                    options: [["left", "Left"], ["top", "Top"], ["bottom", "Bottom"], ["right", "Right"]]
                    value: root.toolbarSide
                    onChosen: function(value) {
                        root.toolbarSideRequested(value)
                    }
                }

                SettingSwitch {
                    width: parent.width
                    theme: root.theme
                    label: "Fade toolbar"
                    description: "Hide it while you work in another window."
                    checked: root.settings.fadeToolbar === true
                    onToggled: function(checked) {
                        root.settingChanged("fadeToolbar", checked)
                    }
                }

                SettingSwitch {
                    width: parent.width
                    theme: root.theme
                    label: "Tilted paper"
                    description: "Rest the sheet at a slight angle."
                    checked: root.settings.tilt === true
                    onToggled: function(checked) {
                        root.settingChanged("tilt", checked)
                    }
                }

                SectionHeading {
                    text: "Drawing"
                }

                SettingChoice {
                    width: parent.width
                    theme: root.theme
                    label: "Mouse smoothing"
                    description: "Steadies mouse strokes; tablets stay exact."
                    options: [["off", "Off"], ["light", "Light"], ["medium", "Medium"], ["strong", "Strong"]]
                    value: root.settings.smoothing
                    onChosen: function(value) {
                        root.settingChanged("smoothing", value)
                    }
                }

                SettingChoice {
                    width: parent.width
                    theme: root.theme
                    label: "Eraser size"
                    options: [["small", "Small"], ["medium", "Medium"], ["large", "Large"]]
                    value: root.settings.eraser
                    onChosen: function(value) {
                        root.settingChanged("eraser", value)
                    }
                }
            }

            Column {
                width: root.wide ? (column.width - column.columnSpacing) / 2 : column.width
                spacing: 12

                SectionHeading {
                    text: "Export"
                }

                SettingChoice {
                    width: parent.width
                    theme: root.theme
                    label: "Ctrl+C copies"
                    description: "Ctrl+Shift+C copies the other. Both save a PNG."
                    options: [["path", "File path"], ["image", "Image"]]
                    value: root.settings.clipboard
                    onChosen: function(value) {
                        root.settingChanged("clipboard", value)
                    }
                }

                Column {
                    width: parent.width
                    spacing: 8

                    Text {
                        text: "Export folder"
                        color: root.theme.text
                        font.family: "monospace"
                        font.pixelSize: 13
                        textFormat: Text.PlainText
                    }

                    Row {
                        width: parent.width
                        spacing: 8

                        Rectangle {
                            width: parent.width - openButton.width - 8
                            height: 28
                            radius: Math.min(7, root.theme.radius)
                            color: root.theme.fieldFill
                            border.width: folderInput.activeFocus ? 2 : 1
                            border.color: folderInput.activeFocus ? root.theme.hoverIcon : root.theme.fieldBorder

                            TextInput {
                                id: folderInput

                                property bool reverting: false

                                function commit() {
                                    if (!reverting && text.trim() !== (root.settings.exportDir || ""))
                                        root.settingChanged("exportDir", text.trim())
                                    reverting = false
                                }

                                anchors.fill: parent
                                anchors.leftMargin: 10
                                anchors.rightMargin: 10
                                verticalAlignment: TextInput.AlignVCenter
                                clip: true
                                text: root.settings.exportDir || ""
                                maximumLength: 512
                                color: root.theme.text
                                selectionColor: root.theme.selectedFill
                                selectedTextColor: root.theme.selectedIcon
                                font.family: "monospace"
                                font.pixelSize: 12

                                Accessible.role: Accessible.EditableText
                                Accessible.name: "Export folder"

                                Keys.onReturnPressed: root.editingFinished()
                                Keys.onEnterPressed: root.editingFinished()
                                // Esc restores the saved folder and keeps the field bound to it.
                                Keys.onEscapePressed: {
                                    reverting = true
                                    text = Qt.binding(function() {
                                        return root.settings.exportDir || ""
                                    })
                                    root.editingFinished()
                                }
                                onActiveFocusChanged: {
                                    if (!activeFocus)
                                        commit()
                                }

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width
                                    visible: folderInput.text === ""
                                    text: root.tilde(root.defaultExportDir)
                                    color: root.theme.subtle
                                    elide: Text.ElideMiddle
                                    font: folderInput.font
                                    textFormat: Text.PlainText
                                }
                            }
                        }

                        TextButton {
                            id: openButton

                            text: "Open"
                            onClicked: root.openExportFolderRequested()
                        }
                    }

                    Text {
                        width: parent.width
                        text: "Empty uses the default. ~ is your home folder."
                        color: root.theme.subtle
                        font.family: "monospace"
                        font.pixelSize: 11
                        wrapMode: Text.WordWrap
                        textFormat: Text.PlainText
                    }
                }

                SectionHeading {
                    text: "About"
                }

                Text {
                    width: parent.width
                    text: "Saved to " + root.tilde(root.notesPath)
                    color: root.theme.subtle
                    font.family: "monospace"
                    font.pixelSize: 11
                    elide: Text.ElideMiddle
                    textFormat: Text.PlainText
                }

                Row {
                    spacing: 8

                    TextButton {
                        text: "Center board"
                        onClicked: root.centerBoardRequested()
                    }

                    TextButton {
                        text: "Reset settings"
                        onClicked: root.resetRequested()
                    }
                }
            }
        }
    }
}
