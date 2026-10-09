import QtQuick
import Quickshell
import Quickshell.Wayland
import "DocumentModel.js" as DocumentModel
import "History.js" as History

Item {
    id: root

    property var shell: null
    property var manifest: null
    property bool opened: false
    property bool closingFromHost: false
    property bool positionInitialized: false
    property string currentTool: "pen"
    property real penWidth: 2.5
    property var historyState: History.create(DocumentModel.createDocument(760, 560))
    readonly property var currentDocument: historyState.present
    readonly property bool canUndo: historyState.past.length > 0
    readonly property bool canRedo: historyState.future.length > 0

    function commitDocument(nextDocument) {
        historyState = History.commit(historyState, nextDocument)
    }

    function undo() {
        historyState = History.undo(historyState)
    }

    function redo() {
        historyState = History.redo(historyState)
    }

    function clearDocument() {
        if (currentDocument.objects.length > 0)
            commitDocument(DocumentModel.clearDocument(currentDocument))
    }

    function clamp(value, low, high) {
        return Math.max(low, Math.min(high, value))
    }

    function clampBoard() {
        if (!surface || !board)
            return
        board.x = clamp(board.x, 0, Math.max(0, surface.width - board.width))
        board.y = clamp(board.y, 0, Math.max(0, surface.height - board.height))
    }

    function centerBoard() {
        if (!surface || !board || surface.width <= 0 || surface.height <= 0)
            return
        board.x = Math.round(Math.max(0, (surface.width - board.width) / 2))
        board.y = Math.round(Math.max(0, (surface.height - board.height) / 2))
        positionInitialized = true
    }

    function ensureBoardPosition() {
        if (!positionInitialized)
            centerBoard()
        else
            clampBoard()
    }

    function nudgeBoard(dx, dy) {
        board.x = clamp(board.x + dx, 0, Math.max(0, surface.width - board.width))
        board.y = clamp(board.y + dy, 0, Math.max(0, surface.height - board.height))
    }

    function open(payloadJson) {
        closingFromHost = false
        opened = true
        Qt.callLater(function() {
            root.ensureBoardPosition()
            keyboardRoot.forceActiveFocus()
        })
    }

    function close() {
        closingFromHost = true
        opened = false
        closingFromHost = false
    }

    function requestClose() {
        if (shell && typeof shell.hide === "function")
            shell.hide("jobo.field-notes")
        else
            close()
    }

    PanelWindow {
        id: surface

        screen: Quickshell.screens.length > 0 ? Quickshell.screens[0] : null
        visible: root.opened
        color: "transparent"
        surfaceFormat.opaque: false
        exclusionMode: ExclusionMode.Ignore

        WlrLayershell.namespace: "jobo-field-notes"
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }

        mask: Region {
            Region {
                x: board.x + paper.x - 24
                y: board.y + paper.y - 28
                width: paper.width + 48
                height: paper.height + 56
            }
            Region {
                x: board.x + tools.x - 18
                y: board.y + tools.y - 18
                width: tools.width + 36
                height: tools.height + 36
            }
            Region {
                x: board.x + dragClip.x
                y: board.y + dragClip.y
                width: dragClip.width
                height: dragClip.height
            }
        }

        onWidthChanged: root.ensureBoardPosition()
        onHeightChanged: root.ensureBoardPosition()

        FocusScope {
            id: keyboardRoot

            anchors.fill: parent
            focus: true

            Keys.onPressed: function(event) {
                var control = (event.modifiers & Qt.ControlModifier) !== 0
                var shift = (event.modifiers & Qt.ShiftModifier) !== 0
                if (control && event.key === Qt.Key_Z && shift) {
                    root.redo()
                    event.accepted = true
                    return
                } else if (control && event.key === Qt.Key_Z) {
                    root.undo()
                    event.accepted = true
                    return
                } else if (control && event.key === Qt.Key_Y) {
                    root.redo()
                    event.accepted = true
                    return
                } else if (!control && event.key === Qt.Key_P) {
                    root.currentTool = "pen"
                    event.accepted = true
                    return
                } else if (!control && event.key === Qt.Key_E) {
                    root.currentTool = "eraser"
                    event.accepted = true
                    return
                } else if (!control && event.key === Qt.Key_T) {
                    root.currentTool = "text"
                    event.accepted = true
                    return
                } else if (!control && event.key === Qt.Key_V) {
                    root.currentTool = "select"
                    event.accepted = true
                    return
                } else if (event.key === Qt.Key_BracketLeft) {
                    root.penWidth = Math.max(1, root.penWidth - 0.5)
                    event.accepted = true
                    return
                } else if (event.key === Qt.Key_BracketRight) {
                    root.penWidth = Math.min(12, root.penWidth + 0.5)
                    event.accepted = true
                    return
                }
                var step = shift ? 32 : 8
                if (event.key === Qt.Key_Left) {
                    root.nudgeBoard(-step, 0)
                    event.accepted = true
                } else if (event.key === Qt.Key_Right) {
                    root.nudgeBoard(step, 0)
                    event.accepted = true
                } else if (event.key === Qt.Key_Up) {
                    root.nudgeBoard(0, -step)
                    event.accepted = true
                } else if (event.key === Qt.Key_Down) {
                    root.nudgeBoard(0, step)
                    event.accepted = true
                } else if (event.key === Qt.Key_Home) {
                    root.centerBoard()
                    event.accepted = true
                } else if (event.key === Qt.Key_Delete) {
                    event.accepted = paper.deleteSelected()
                } else if (event.key === Qt.Key_Escape) {
                    if (!paper.cancelEditing())
                        root.requestClose()
                    event.accepted = true
                }
            }

            Item {
                id: board

                width: 940
                height: 660

                PaperSurface {
                    id: paper

                    x: 28
                    y: 58
                    width: 760
                    height: 560
                    document: root.currentDocument
                    currentTool: root.currentTool
                    penWidth: root.penWidth
                    onCommitRequested: function(nextDocument) {
                        root.commitDocument(nextDocument)
                        if (paper.editingObjectId === "")
                            keyboardRoot.forceActiveFocus()
                    }
                    onToolRequested: function(tool) {
                        root.currentTool = tool
                    }
                }

                ToolIsland {
                    id: tools

                    x: 830
                    y: 118
                    width: 76
                    height: 424
                    currentTool: root.currentTool
                    canUndo: root.canUndo
                    canRedo: root.canRedo
                    hasContent: root.currentDocument.objects.length > 0
                    penWidth: root.penWidth
                    onToolSelected: function(tool) {
                        root.currentTool = tool
                        keyboardRoot.forceActiveFocus()
                    }
                    onUndoRequested: root.undo()
                    onRedoRequested: root.redo()
                    onClearRequested: root.clearDocument()
                    onPenWidthRequested: function(width) {
                        root.penWidth = width
                    }
                    onCloseRequested: root.requestClose()
                }

                Item {
                    id: dragClip

                    x: paper.x + Math.round((paper.width - width) / 2)
                    y: paper.y - 24
                    width: 190
                    height: 48
                    z: 20

                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.top: parent.top
                        width: 144
                        height: 31
                        radius: 7
                        color: "#b18d52"
                        border.width: 1
                        border.color: "#7a6037"

                        Rectangle {
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.top: parent.top
                            anchors.topMargin: 5
                            width: 88
                            height: 8
                            radius: 3
                            color: "#836a43"
                        }

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 4
                            text: "DRAG  •  ARROWS"
                            color: "#342b20"
                            font.family: "monospace"
                            font.pixelSize: 7
                            font.bold: true
                            font.letterSpacing: 0.8
                            textFormat: Text.PlainText
                        }
                    }

                    HoverHandler {
                        cursorShape: Qt.SizeAllCursor
                    }
                    TapHandler {
                        onTapped: keyboardRoot.forceActiveFocus()
                    }
                    DragHandler {
                        target: board
                        acceptedButtons: Qt.LeftButton
                        xAxis.minimum: 0
                        xAxis.maximum: Math.max(0, surface.width - board.width)
                        yAxis.minimum: 0
                        yAxis.maximum: Math.max(0, surface.height - board.height)
                        onActiveChanged: {
                            if (!active) {
                                root.positionInitialized = true
                                root.clampBoard()
                                keyboardRoot.forceActiveFocus()
                            }
                        }
                    }
                }
            }
        }
    }
}
