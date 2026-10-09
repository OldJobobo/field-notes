import QtQuick
import QtQuick.Effects

Item {
    id: root

    property string currentTool: "pen"
    property bool canUndo: false
    property bool canRedo: false
    property bool hasContent: false
    property bool clearArmed: false
    property real penWidth: 2.5
    signal toolSelected(string tool)
    signal undoRequested()
    signal redoRequested()
    signal clearRequested()
    signal penWidthRequested(real width)
    signal closeRequested()

    Timer {
        id: clearTimer
        interval: 2500
        onTriggered: root.clearArmed = false
    }

    Rectangle {
        id: island

        anchors.fill: parent
        radius: 18
        color: "#ed2b2925"
        border.width: 1
        border.color: "#806f695d"
        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: "#72000000"
            shadowBlur: 0.68
            shadowHorizontalOffset: 4
            shadowVerticalOffset: 10
            autoPaddingEnabled: true
        }

        Column {
            anchors.fill: parent
            anchors.margins: 9
            spacing: 2

            Item {
                width: parent.width
                height: 22

                Row {
                    anchors.centerIn: parent
                    spacing: 3
                    Repeater {
                        model: 3
                        Rectangle {
                            width: 4
                            height: 4
                            radius: 2
                            color: "#746f6557"
                        }
                    }
                }
            }

            ToolButton {
                width: parent.width
                text: "SELECT"
                glyph: "◇"
                selected: root.currentTool === "select"
                onActivated: {
                    root.currentTool = "select"
                    root.toolSelected("select")
                }
            }
            ToolButton {
                width: parent.width
                text: "PEN"
                glyph: "╱"
                selected: root.currentTool === "pen"
                onActivated: {
                    root.currentTool = "pen"
                    root.toolSelected("pen")
                }
            }
            ToolButton {
                width: parent.width
                text: "ERASE"
                glyph: "▱"
                selected: root.currentTool === "eraser"
                onActivated: {
                    root.currentTool = "eraser"
                    root.toolSelected("eraser")
                }
            }
            ToolButton {
                width: parent.width
                text: "TEXT"
                glyph: "T"
                selected: root.currentTool === "text"
                onActivated: {
                    root.currentTool = "text"
                    root.toolSelected("text")
                }
            }

            Rectangle {
                width: parent.width
                height: 1
                color: "#4f6f695d"
            }

            ToolButton {
                width: parent.width
                text: "UNDO"
                glyph: "↶"
                enabled: root.canUndo
                onActivated: root.undoRequested()
            }
            ToolButton {
                width: parent.width
                text: "REDO"
                glyph: "↷"
                enabled: root.canRedo
                onActivated: root.redoRequested()
            }

            Rectangle {
                width: parent.width
                height: 1
                color: "#4f6f695d"
            }

            ToolButton {
                width: parent.width
                text: root.clearArmed ? "AGAIN" : "CLEAR"
                glyph: root.clearArmed ? "!" : "×"
                dangerous: true
                enabled: root.hasContent
                onActivated: {
                    if (root.clearArmed) {
                        root.clearArmed = false
                        clearTimer.stop()
                        root.clearRequested()
                    } else {
                        root.clearArmed = true
                        clearTimer.restart()
                    }
                }
            }
            ToolButton {
                width: parent.width
                text: "CLOSE"
                glyph: "—"
                onActivated: root.closeRequested()
            }
        }
    }
}
