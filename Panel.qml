import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "DocumentModel.js" as DocumentModel
import "History.js" as History
import "Layout.js" as Layout
import "Notebook.js" as Notebook

Item {
    id: root

    property var shell: null
    property var manifest: null
    property bool opened: false
    property bool closingFromHost: false
    property bool positionInitialized: false
    property string currentTool: "pen"
    property real penWidth: 2.5
    property string toolbarSide: "right"
    // The toolbar has the same length in either orientation (see ToolIsland).
    readonly property var dockLayout: Layout.dock(toolbarSide, 760, 560,
        Math.max(tools.implicitWidth, tools.implicitHeight), Math.min(tools.implicitWidth, tools.implicitHeight))
    property var notebook: Notebook.create([History.create(DocumentModel.createDocument(760, 560))], 0)
    readonly property var historyState: notebook.sheets[notebook.current]
    readonly property var currentDocument: historyState.present
    readonly property bool canUndo: historyState.past.length > 0
    readonly property bool canRedo: historyState.future.length > 0
    readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/field-notes"
    // Nothing is written until the saved sheet has been read, so a slow or failed load
    // can never overwrite it with an empty page.
    property bool stateReady: false
    property string saveStatus: "LOADING"

    function focusKeys() {
        // Taking focus away from an open note editor also commits it.
        keySink.forceActiveFocus()
    }

    function commitDocument(nextDocument) {
        notebook = Notebook.replaceCurrent(notebook, History.commit(historyState, nextDocument))
    }

    // Commits an open note and drops any gesture or selection, whose object ids belong
    // to the sheet being left.
    function leaveSheet() {
        focusKeys()
        paper.cancelGesture()
        paper.clearSelection()
    }

    function selectSheet(index) {
        leaveSheet()
        notebook = Notebook.select(notebook, index)
    }

    function addSheet() {
        leaveSheet()
        // A new sheet starts with the paper of the sheet being left.
        notebook = Notebook.add(notebook, History.create(DocumentModel.createDocument(760, 560, currentDocument.paper)))
    }

    function selectTool(tool) {
        focusKeys()
        currentTool = tool
    }

    function undo() {
        focusKeys()
        notebook = Notebook.replaceCurrent(notebook, History.undo(historyState))
    }

    function redo() {
        focusKeys()
        notebook = Notebook.replaceCurrent(notebook, History.redo(historyState))
    }

    function cyclePaper() {
        focusKeys()
        commitDocument(DocumentModel.setPaper(currentDocument, DocumentModel.nextPaper(currentDocument.paper)))
    }

    function clearDocument() {
        focusKeys()
        commitDocument(DocumentModel.clearDocument(currentDocument))
    }

    // Docks the toolbar to another side of the paper while keeping the paper where it is
    // on screen.
    function setToolbarSide(side) {
        if (side === toolbarSide || Layout.TOOLBAR_SIDES.indexOf(side) < 0)
            return
        var paperX = board.x + paper.x * board.scale
        var paperY = board.y + paper.y * board.scale
        toolbarSide = side
        board.x = paperX - paper.x * board.scale
        board.y = paperY - paper.y * board.scale
        positionInitialized = true
        clampBoard()
        scheduleSave()
    }

    function dragToolbar(sceneX, sceneY) {
        var point = board.mapFromItem(null, sceneX, sceneY)
        setToolbarSide(Layout.nearestSide(point.x, point.y, paper, toolbarSide))
    }

    function setPenWidth(width) {
        penWidth = Math.max(1, Math.min(12, width))
    }

    function scheduleSave() {
        if (!stateReady)
            return
        saveStatus = "EDITED"
        saveTimer.restart()
    }

    function saveNow() {
        saveTimer.stop()
        if (!stateReady)
            return
        var documents = notebook.sheets.map(function(sheet) {
            return sheet.present
        })
        stateFile.setText(DocumentModel.serialize(documents, notebook.current, {
            tool: currentTool,
            penWidth: penWidth,
            toolbar: toolbarSide,
            boardX: positionInitialized ? Math.round(board.x) : null,
            boardY: positionInitialized ? Math.round(board.y) : null
        }))
    }

    function flushSave() {
        if (saveTimer.running)
            saveNow()
    }

    function restoreState(text) {
        if (stateReady)
            return
        var raw = null
        try {
            raw = JSON.parse(text)
        } catch (error) {
            raw = null
        }
        var restored = DocumentModel.sanitizeNotebook(raw, 760, 560)
        if (restored) {
            notebook = Notebook.create(restored.documents.map(function(document) {
                return History.create(document)
            }), restored.current)
            currentTool = restored.ui.tool
            penWidth = restored.ui.penWidth
            toolbarSide = restored.ui.toolbar
            if (restored.ui.boardX !== undefined) {
                board.x = restored.ui.boardX
                board.y = restored.ui.boardY
                positionInitialized = true
            }
            saveStatus = "SAVED"
        } else if (String(text).trim() !== "") {
            // Keep a copy of the unreadable file before the next save replaces it.
            backupCorrupt.running = true
            saveStatus = "RECOVERED"
        } else {
            saveStatus = "READY"
        }
        stateReady = true
    }

    function clampBoard() {
        if (!surface || !board || surface.width <= 0 || surface.height <= 0)
            return
        var edge = Layout.margin(surface.width, surface.height)
        board.x = Layout.clampPosition(board.x, surface.width, board.width, board.scale, edge)
        board.y = Layout.clampPosition(board.y, surface.height, board.height, board.scale, edge)
    }

    // Until the user places the board, it stays centered as the surface settles its size.
    function centerBoard(remember) {
        if (!surface || !board || surface.width <= 0 || surface.height <= 0)
            return
        board.x = Math.round((surface.width - board.width * board.scale) / 2)
        board.y = Math.round((surface.height - board.height * board.scale) / 2)
        if (remember) {
            positionInitialized = true
            scheduleSave()
        }
    }

    function ensureBoardPosition() {
        if (!positionInitialized)
            centerBoard()
        else
            clampBoard()
    }

    function nudgeBoard(dx, dy) {
        board.x += dx
        board.y += dy
        positionInitialized = true
        clampBoard()
        scheduleSave()
    }

    function open(payloadJson) {
        closingFromHost = false
        opened = true
        Qt.callLater(function() {
            root.ensureBoardPosition()
            root.focusKeys()
        })
    }

    function close() {
        closingFromHost = true
        focusKeys()
        opened = false
        flushSave()
        closingFromHost = false
    }

    function requestClose() {
        if (shell && typeof shell.hide === "function")
            shell.hide("jobo.field-notes")
        else
            close()
    }

    onNotebookChanged: scheduleSave()
    onCurrentToolChanged: scheduleSave()
    onPenWidthChanged: scheduleSave()
    Component.onCompleted: prepareStateDir.running = true
    Component.onDestruction: flushSave()

    Timer {
        id: saveTimer

        interval: 500
        onTriggered: root.saveNow()
    }

    Process {
        id: prepareStateDir

        command: ["mkdir", "-p", "-m", "700", root.stateDir]
    }

    Process {
        id: backupCorrupt

        command: ["cp", "-f", "--", stateFile.path, stateFile.path + ".corrupt"]
    }

    FileView {
        id: stateFile

        path: root.stateDir + "/notes.json"
        atomicWrites: true
        blockWrites: true
        printErrors: false

        onLoaded: root.restoreState(text())
        onLoadFailed: function(error) {
            if (error === FileViewError.FileNotFound) {
                root.saveStatus = "READY"
                root.stateReady = true
            } else {
                root.saveStatus = "NOT SAVED"
            }
        }
        onSaved: {
            if (!saveTimer.running)
                root.saveStatus = "SAVED"
        }
        onSaveFailed: function(error) {
            root.saveStatus = "NOT SAVED"
        }
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
                x: board.x + (paper.x - 24) * board.scale
                y: board.y + (paper.y - 28) * board.scale
                width: (paper.width + 48) * board.scale
                height: (paper.height + 56) * board.scale
            }
            Region {
                x: board.x + (tools.x - 18) * board.scale
                y: board.y + (tools.y - 18) * board.scale
                width: (tools.width + 36) * board.scale
                height: (tools.height + 36) * board.scale
            }
            Region {
                x: board.x + dragClip.x * board.scale
                y: board.y + dragClip.y * board.scale
                width: dragClip.width * board.scale
                height: dragClip.height * board.scale
            }
        }

        onWidthChanged: root.ensureBoardPosition()
        onHeightChanged: root.ensureBoardPosition()

        FocusScope {
            id: keyboardRoot

            anchors.fill: parent
            focus: true

            // Plain focus target: unlike the FocusScope itself, focusing it pulls active
            // focus out of a note editor. Unhandled keys bubble up to keyboardRoot.
            Item {
                id: keySink

                focus: true
            }

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
                } else if (!control && (event.key === Qt.Key_P || event.key === Qt.Key_B)) {
                    root.selectTool("pen")
                    event.accepted = true
                    return
                } else if (!control && event.key === Qt.Key_E) {
                    root.selectTool("eraser")
                    event.accepted = true
                    return
                } else if (!control && event.key === Qt.Key_T) {
                    root.selectTool("text")
                    event.accepted = true
                    return
                } else if (!control && event.key === Qt.Key_V) {
                    root.selectTool("select")
                    event.accepted = true
                    return
                } else if (!control && event.key === Qt.Key_G) {
                    root.cyclePaper()
                    event.accepted = true
                    return
                } else if (!control && event.key === Qt.Key_N) {
                    root.addSheet()
                    event.accepted = true
                    return
                } else if (event.key === Qt.Key_PageUp) {
                    root.selectSheet(root.notebook.current - 1)
                    event.accepted = true
                    return
                } else if (event.key === Qt.Key_PageDown) {
                    root.selectSheet(root.notebook.current + 1)
                    event.accepted = true
                    return
                } else if (event.key === Qt.Key_BracketLeft) {
                    root.setPenWidth(root.penWidth - 0.5)
                    event.accepted = true
                    return
                } else if (event.key === Qt.Key_BracketRight) {
                    root.setPenWidth(root.penWidth + 0.5)
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
                    root.centerBoard(true)
                    event.accepted = true
                } else if (event.key === Qt.Key_Delete || event.key === Qt.Key_Backspace) {
                    event.accepted = paper.deleteSelected()
                } else if (event.key === Qt.Key_Escape) {
                    if (!paper.cancelEditing() && !paper.clearSelection())
                        root.requestClose()
                    event.accepted = true
                }
            }

            Item {
                id: board

                width: root.dockLayout.width
                height: root.dockLayout.height
                // Shrinks the whole board on small displays; stored geometry stays in paper space.
                scale: Layout.fitScale(surface.width, surface.height, width, height)
                transformOrigin: Item.TopLeft
                onScaleChanged: Qt.callLater(root.ensureBoardPosition)

                PaperSurface {
                    id: paper

                    x: root.dockLayout.paperX
                    y: root.dockLayout.paperY
                    width: 760
                    height: 560
                    document: root.currentDocument
                    currentTool: root.currentTool
                    penWidth: root.penWidth
                    statusText: root.saveStatus
                    sheetIndex: root.notebook.current
                    sheetCount: root.notebook.sheets.length
                    onCommitRequested: function(nextDocument) {
                        root.commitDocument(nextDocument)
                    }
                    onEditingFinished: root.focusKeys()
                    onPaperRequested: root.cyclePaper()
                    onToolRequested: function(tool) {
                        root.selectTool(tool)
                    }
                }

                ToolIsland {
                    id: tools

                    x: root.dockLayout.toolX
                    y: root.dockLayout.toolY
                    // Topmost on the board, so its tooltips draw over the paper and the clip.
                    z: 30
                    width: implicitWidth
                    height: implicitHeight
                    side: root.toolbarSide
                    sheetIndex: root.notebook.current
                    sheetCount: root.notebook.sheets.length
                    canAddSheet: Notebook.canAdd(root.notebook)
                    currentTool: root.currentTool
                    canUndo: root.canUndo
                    canRedo: root.canRedo
                    hasContent: root.currentDocument.objects.length > 0
                    penWidth: root.penWidth
                    onToolSelected: function(tool) {
                        root.selectTool(tool)
                    }
                    onUndoRequested: root.undo()
                    onRedoRequested: root.redo()
                    onClearRequested: root.clearDocument()
                    onPenWidthRequested: function(width) {
                        root.setPenWidth(width)
                    }
                    onSheetRequested: function(index) {
                        root.selectSheet(index)
                    }
                    onNewSheetRequested: root.addSheet()
                    onCloseRequested: root.requestClose()
                    onGripMoved: function(sceneX, sceneY) {
                        root.dragToolbar(sceneX, sceneY)
                    }
                    onGripReleased: root.focusKeys()
                }

                Item {
                    id: dragClip

                    // Centred on the paper's top edge, following its tilt.
                    x: paper.x + Math.round((paper.width - width) / 2 + paper.height / 2 * Math.sin(paper.rotation * Math.PI / 180))
                    y: paper.y - 26
                    width: 140
                    height: 50
                    z: 20

                    Accessible.role: Accessible.Grip
                    Accessible.name: "Move the board (arrow keys nudge it, Home centres it)"

                    BinderClip {
                        x: Math.round((parent.width - width) / 2)
                        width: implicitWidth
                        height: implicitHeight
                        tilt: paper.rotation
                        hovered: clipHover.hovered
                        lifted: clipDrag.active
                    }

                    Tooltip {
                        text: "Drag to move"
                        shortcut: "Arrows"
                        side: "bottom"
                        hovered: clipHover.hovered && !clipDrag.active
                    }

                    HoverHandler {
                        id: clipHover

                        cursorShape: clipDrag.active ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                    }
                    TapHandler {
                        onTapped: root.focusKeys()
                    }
                    DragHandler {
                        id: clipDrag

                        target: board
                        acceptedButtons: Qt.LeftButton
                        xAxis.minimum: Layout.margin(surface.width, surface.height)
                        xAxis.maximum: Math.max(xAxis.minimum, surface.width - board.width * board.scale - xAxis.minimum)
                        yAxis.minimum: Layout.margin(surface.width, surface.height)
                        yAxis.maximum: Math.max(yAxis.minimum, surface.height - board.height * board.scale - yAxis.minimum)
                        onActiveChanged: {
                            if (!active) {
                                root.positionInitialized = true
                                root.clampBoard()
                                root.focusKeys()
                                root.scheduleSave()
                            }
                        }
                    }
                }
            }
        }
    }
}
