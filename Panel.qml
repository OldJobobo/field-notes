import QtQuick
import Quickshell
import Quickshell.Hyprland
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
    // Whether the board has a place on the screen it is shown on (else it is centred there).
    property bool positionInitialized: false
    // The screen the notes are shown on, chosen each time they open (see showOn).
    property var targetScreen: null
    // Where the board was left on each screen, by output name, in that screen's pixels.
    property var boardPositions: ({})
    // A position saved before boards were kept per screen, used once on the first screen opened.
    property var legacyBoard: null
    property string currentTool: "pen"
    property real penWidth: 2.5
    property string toolbarSide: "right"
    // The toolbar has the same length in either orientation (see ToolIsland).
    readonly property var dockLayout: Layout.dock(toolbarSide, currentDocument.page.width, currentDocument.page.height,
        Math.max(tools.implicitWidth, tools.implicitHeight), Math.min(tools.implicitWidth, tools.implicitHeight))
    property var notebook: Notebook.create([History.create(DocumentModel.createSheet("medium"))], 0)
    readonly property var historyState: notebook.sheets[notebook.current]
    readonly property var currentDocument: historyState.present
    readonly property bool canUndo: historyState.past.length > 0
    readonly property bool canRedo: historyState.future.length > 0
    readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/field-notes"
    // Nothing is written until the saved sheet has been read, so a slow or failed load
    // can never overwrite it with an empty page.
    property bool stateReady: false
    // The notes file is only opened once stateCheck has confirmed it is safe to read.
    property bool stateChecked: false
    readonly property int maxStateBytes: 16 * 1024 * 1024
    property string saveStatus: "LOADING"
    readonly property string home: Quickshell.env("HOME")
    readonly property string defaultExportDir: (Quickshell.env("XDG_PICTURES_DIR") || home + "/Pictures") + "/field-notes"
    // User settings (DocumentModel.defaultSettings), saved with the notes.
    property var settings: DocumentModel.defaultSettings()
    property bool settingsOpen: false
    readonly property QtObject theme: settings.theme ? omarchyTheme : classicTheme
    readonly property string exportDir: settings.exportDir ? expandHome(settings.exportDir) : defaultExportDir
    readonly property var smoothingStrength: ({ off: 0, light: 2, medium: 3.5, strong: 5 })
    readonly property var eraserRadii: ({ small: 6, medium: 10, large: 16 })
    // The part of the board beside the toolbar, where the settings card may go, so it
    // never covers the toolbar (or the gear that closes it).
    readonly property var settingsArea: {
        var edge = 12
        var area = { x: edge, y: edge, width: board.width - 2 * edge, height: board.height - 2 * edge }
        if (toolbarSide === "bottom")
            area.height = tools.y - 2 * edge
        else if (toolbarSide === "top") {
            area.y = tools.y + tools.height + edge
            area.height = board.height - area.y - edge
        } else if (toolbarSide === "left") {
            area.x = tools.x + tools.width + edge
            area.width = board.width - area.x - edge
        } else {
            area.width = tools.x - 2 * edge
        }
        return area
    }
    property string pendingExport: ""
    // What the export in progress puts on the clipboard: "path" or "image".
    property string pendingMode: "path"
    // The copy of the notes file made before saving over it: "", "copying", "done" or "failed".
    property string backupState: ""
    // The last export to finish, for the scripting interface.
    property string lastExport: ""
    property bool lastExportOk: false
    property string appVersion: ""

    function focusKeys() {
        // Taking focus away from an open note editor also commits it.
        keySink.forceActiveFocus()
    }

    // Every notebook change goes through here. When the open sheet changes size
    // (switching sheets, resizing, undo), the paper stays centred where it was on screen.
    function setNotebook(next) {
        var before = currentDocument.page
        var centerX = board.x + (paper.x + paper.width / 2) * board.scale
        var centerY = board.y + (paper.y + paper.height / 2) * board.scale
        notebook = next
        var after = currentDocument.page
        if (after.width === before.width && after.height === before.height)
            return
        if (!positionInitialized) {
            centerBoard()
            return
        }
        board.x = Math.round(centerX - (paper.x + paper.width / 2) * board.scale)
        board.y = Math.round(centerY - (paper.y + paper.height / 2) * board.scale)
        clampBoard()
    }

    // Loading keeps only what fits its limits (DocumentModel.overLimits: points in total, objects
    // per sheet, and the rest), so no change may take the notebook past them: the excess would
    // be lost on the next load and the save after it. Erasing can add objects as well as points,
    // by splitting strokes. A change that leaves an already over-full notebook no worse is allowed.
    function fitsLimits(nextNotebook) {
        var present = function(sheet) { return sheet.present }
        var after = DocumentModel.overLimits(nextNotebook.sheets.map(present))
        return after === 0 || after <= DocumentModel.overLimits(notebook.sheets.map(present))
    }

    function refuseFull() {
        paper.discardUncommitted()
        paper.refuse("The notebook is full")
    }

    function commitDocument(nextDocument) {
        var next = Notebook.replaceCurrent(notebook, History.commit(historyState, nextDocument))
        if (!fitsLimits(next)) {
            refuseFull()
            return false
        }
        setNotebook(next)
        return true
    }

    // Commits an open note and drops any gesture or selection, whose object ids belong
    // to the sheet being left.
    function leaveSheet() {
        focusKeys()
        paper.cancelScriptStrokes()
        paper.cancelGesture()
        paper.clearSelection()
    }

    function selectSheet(index) {
        leaveSheet()
        setNotebook(Notebook.select(notebook, index))
    }

    function addSheet() {
        leaveSheet()
        // A new sheet starts with the size and paper of the sheet being left.
        setNotebook(Notebook.add(notebook, History.create(
            DocumentModel.createSheet(DocumentModel.sizeName(currentDocument), currentDocument.paper))))
    }

    function selectTool(tool) {
        focusKeys()
        currentTool = tool
    }

    // Undo and redo can bring back strokes too (undoing a Clear restores a whole sheet).
    function undo() {
        focusKeys()
        var next = Notebook.replaceCurrent(notebook, History.undo(historyState))
        if (fitsLimits(next))
            setNotebook(next)
        else
            refuseFull()
        return notebook === next
    }

    function redo() {
        focusKeys()
        var next = Notebook.replaceCurrent(notebook, History.redo(historyState))
        if (fitsLimits(next))
            setNotebook(next)
        else
            refuseFull()
        return notebook === next
    }

    function cyclePaper() {
        focusKeys()
        commitDocument(DocumentModel.setPaper(currentDocument, DocumentModel.nextPaper(currentDocument.paper)))
    }

    function cycleSize() {
        focusKeys()
        var size = DocumentModel.nextSize(currentDocument)
        if (size === DocumentModel.sizeName(currentDocument))
            paper.refuseSize("The ink doesn't fit a smaller size")
        else
            commitDocument(DocumentModel.setSize(currentDocument, size))
    }

    function renameSheet(title) {
        commitDocument(DocumentModel.setTitle(currentDocument, title))
    }

    // Saves the open sheet as a PNG and copies its path or the image itself, for pasting
    // into other tools: the "Ctrl+C copies" setting, or the other one when alternate is
    // true (Ctrl+Shift+C). Every export is a new file, so a path pasted earlier keeps
    // showing that version.
    function copyImagePath(alternate) {
        focusKeys()
        if (pendingExport !== "")
            return
        var preferred = settings.clipboard
        pendingMode = alternate ? (preferred === "image" ? "path" : "image") : preferred
        var name = DocumentModel.slug(currentDocument.title) || "sheet-" + paper.pad2(notebook.current + 1)
        pendingExport = exportDir + "/" + name + "-" + Qt.formatDateTime(new Date(), "yyyyMMdd-HHmmss") + ".png"
        prepareExportDir.running = true
    }

    function finishExport(ok) {
        lastExport = pendingExport
        lastExportOk = ok
        pendingExport = ""
        tools.exportFinished(ok, pendingMode)
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

    // "~" and relative paths are taken from the home folder.
    function expandHome(path) {
        if (path === "~")
            return home
        if (path.indexOf("~/") === 0)
            return home + path.slice(1)
        return path.charAt(0) === "/" ? path : home + "/" + path
    }

    function setSetting(key, value) {
        var next = Object.assign({}, settings)
        next[key] = value
        settings = DocumentModel.sanitizeSettings(next)
    }

    function resetSettings() {
        settings = DocumentModel.defaultSettings()
        setToolbarSide("right")
    }

    function openSettings() {
        focusKeys()
        paper.cancelGesture()
        settingsOpen = true
    }

    function closeSettings() {
        if (!settingsOpen)
            return false
        settingsOpen = false
        focusKeys()
        return true
    }

    function toggleSettings() {
        if (!closeSettings())
            openSettings()
    }

    // Opens the export folder in the file manager. Launched detached through a login shell,
    // as Omarchy's own Util.execArgv does, so the file manager is not tied to the shell and
    // gets the full session environment; the folder is only ever an argument. Prefers gio,
    // which reads desktop entries correctly: outside a full desktop environment xdg-open
    // keeps the quotes of a quoted Exec program path, and the folder never opens.
    function openExportFolder() {
        console.info("Field Notes: opening export folder " + exportDir)
        Quickshell.execDetached(["bash", "-lc", "exec \"$@\"", "bash", "sh", "-c",
            "mkdir -p -- \"$1\" || exit 1; command -v gio >/dev/null && exec gio open \"$1\"; exec xdg-open \"$1\"",
            "field-notes", exportDir])
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
        // The file must be safely copied before anything is saved over it. Wait while the copy
        // runs; if it failed, keep the file exactly as it is.
        if (backupState === "copying") {
            saveTimer.restart()
            return
        }
        if (backupState === "failed") {
            saveStatus = "NOT SAVED"
            return
        }
        var documents = notebook.sheets.map(function(sheet) {
            return sheet.present
        })
        rememberBoard()
        stateFile.setText(DocumentModel.serialize(documents, notebook.current, {
            tool: currentTool,
            penWidth: penWidth,
            toolbar: toolbarSide,
            // boardX/boardY keep the open screen's place readable by older versions.
            boardX: positionInitialized ? Math.round(board.x) : null,
            boardY: positionInitialized ? Math.round(board.y) : null,
            boards: boardPositions
        }, settings))
    }

    // Copies the notes file aside (backupCorrupt or backupTrimmed) before anything is saved over
    // it. Saving waits for the copy and only goes ahead once cp has succeeded (see saveNow).
    function startBackup(process) {
        backupState = "copying"
        backupWatchdog.restart()
        process.running = true
    }

    function finishBackup(exitCode, name) {
        if (backupState !== "copying")
            return
        backupWatchdog.stop()
        backupState = exitCode === 0 ? "done" : "failed"
        if (backupState === "failed") {
            console.warn("Field Notes: could not copy " + stateFile.path + " to " + name + "; it will not be saved over")
            saveStatus = "NOT SAVED"
        }
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
            settings = restored.settings
            // Places are applied per screen as the notes open there (showOn).
            boardPositions = restored.ui.boards || {}
            if (!restored.ui.boards && restored.ui.boardX !== undefined)
                legacyBoard = { x: restored.ui.boardX, y: restored.ui.boardY }
            if (targetScreen && boardPositions[targetScreen.name]) {
                board.x = boardPositions[targetScreen.name].x
                board.y = boardPositions[targetScreen.name].y
                positionInitialized = true
                clampBoard()
            }
            if (restored.trimmed) {
                // The file held more than loading keeps (written by an older version, or by
                // hand): keep the whole of it before the next save replaces it.
                console.warn("Field Notes: " + stateFile.path + " holds more than a notebook can keep; the full file is saved as notes.json.trimmed")
                startBackup(backupTrimmed)
                saveStatus = "RECOVERED"
            } else {
                saveStatus = "SAVED"
            }
        } else if (String(text).trim() !== "") {
            // Keep a copy of the unreadable file before the next save replaces it.
            startBackup(backupCorrupt)
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

    function screenNamed(name) {
        for (var i = 0; i < Quickshell.screens.length; i++) {
            if (Quickshell.screens[i].name === name)
                return Quickshell.screens[i]
        }
        return null
    }

    // The monitor Hyprland has focused: where a keyboard-summoned panel belongs.
    function focusedScreen() {
        var monitor = Hyprland.focusedMonitor
        return screenNamed(monitor ? String(monitor.name || "") : "")
            || (Quickshell.screens.length > 0 ? Quickshell.screens[0] : null)
    }

    function rememberBoard() {
        if (!targetScreen || !positionInitialized || !DocumentModel.isScreenName(targetScreen.name))
            return
        var next = Object.assign({}, boardPositions)
        next[targetScreen.name] = { x: Math.round(board.x), y: Math.round(board.y) }
        boardPositions = next
    }

    // Shows the notes on screen, with the board where it was last left there (or centred).
    function showOn(screen) {
        if (!screen || screen === targetScreen)
            return
        rememberBoard()
        targetScreen = screen
        var saved = boardPositions[screen.name] || legacyBoard
        legacyBoard = null
        if (saved) {
            board.x = saved.x
            board.y = saved.y
        }
        positionInitialized = !!saved
        Qt.callLater(ensureBoardPosition)
    }

    // payloadJson may hold "screen" (an output name: the bar icon passes the monitor it sits
    // on; otherwise the focused monitor is used), "settings": true to open straight to
    // settings (the bar icon's right-click), and "toggle": true to put the notes away if they
    // are already open on that screen. A summon while open applies the payload, moving the
    // notes if it names another screen.
    function open(payloadJson) {
        var payload = {}
        try {
            payload = JSON.parse(payloadJson || "{}") || {}
        } catch (error) {
            payload = {}
        }
        var screen = (DocumentModel.isScreenName(payload.screen) ? screenNamed(payload.screen) : null) || focusedScreen()
        if (opened && payload.toggle === true && screen === targetScreen) {
            // Not from inside the shell's summon: let it finish first.
            Qt.callLater(requestClose)
            return
        }
        showOn(screen)
        closingFromHost = false
        opened = true
        Qt.callLater(function() {
            root.ensureBoardPosition()
            if (payload.settings === true)
                root.openSettings()
            else
                root.focusKeys()
        })
    }

    function close() {
        closingFromHost = true
        settingsOpen = false
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

    // The open sheet and its place on screen, for scripts (see the IpcHandler below).
    function scriptStatus() {
        var corners = [[0, 0], [paper.width, 0], [paper.width, paper.height], [0, paper.height]].map(function(point) {
            var mapped = paper.mapToItem(null, point[0], point[1])
            return [Math.round(mapped.x * 10) / 10, Math.round(mapped.y * 10) / 10]
        })
        return {
            open: opened,
            screen: targetScreen ? targetScreen.name : "",
            screens: Quickshell.screens.map(function(screen) { return screen.name }),
            sheet: notebook.current + 1,
            sheets: notebook.sheets.length,
            title: currentDocument.title,
            paper: currentDocument.paper,
            size: DocumentModel.sizeName(currentDocument),
            page: { width: currentDocument.page.width, height: currentDocument.page.height },
            objects: currentDocument.objects.length,
            tool: currentTool,
            penWidth: penWidth,
            toolbar: toolbarSide,
            settingsOpen: settingsOpen,
            // Script strokes still to be drawn, including the one being drawn.
            drawing: paper.scriptPending,
            saved: saveStatus,
            lastExport: lastExport,
            lastExportOk: lastExportOk,
            // The sheet's corners in the screen's pixels, clockwise from top-left, after the
            // board's scale and the paper's tilt: sheet point (x, y) lands at
            // corners[0] + (corners[1] - corners[0]) * x / page.width + (corners[3] - corners[0]) * y / page.height.
            corners: opened ? corners : null
        }
    }

    function scriptSetSize(size) {
        if (!DocumentModel.SIZES[size])
            return "error: size is small, medium or large"
        if (size === DocumentModel.sizeName(currentDocument))
            return "ok"
        if (!DocumentModel.fitsSize(currentDocument, size))
            return "error: the ink doesn't fit a " + size + " sheet"
        focusKeys()
        commitDocument(DocumentModel.setSize(currentDocument, size))
        return "ok"
    }

    // pointsText is "x y x y ..." in sheet coordinates (commas between numbers are fine; a
    // bracketed list is not, because the qs command line splits "[a,b]" into arguments).
    // The stroke is drawn live over durationMs with the current pen width, after any strokes
    // still being drawn; with the notes put away it is added at once.
    function scriptDraw(pointsText, durationMs) {
        var numbers = String(pointsText).trim().split(/[\s,;]+/).map(Number)
        if (numbers.length % 2 !== 0 || numbers.some(function(value) { return !isFinite(value) }))
            return "error: points are numbers in x y pairs, like \"10 20 30 40\""
        if (numbers.length < 4)
            return "error: a stroke needs at least two points"
        if (numbers.length > 2 * 8192)
            return "error: a stroke has at most 8192 points"
        var points = []
        for (var i = 0; i < numbers.length; i += 2)
            points.push([numbers[i], numbers[i + 1]])
        var present = notebook.sheets.map(function(sheet) { return sheet.present })
        if (DocumentModel.totalPoints(present) + points.length > DocumentModel.MAX_TOTAL_POINTS)
            return "error: the notebook is full"
        if (currentDocument.objects.length >= DocumentModel.MAX_OBJECTS)
            return "error: the sheet is full"
        paper.drawScriptStroke(points, penWidth, opened ? Math.max(0, Math.min(60000, durationMs)) : 0)
        return "ok"
    }

    // A typed note with its top-left at (x, y) in sheet coordinates; "\n" starts a new line.
    function scriptNote(x, y, text) {
        var clean = String(text || "").replace(/\\n/g, "\n")
        if (clean.trim() === "")
            return "error: a note needs some text"
        var next = DocumentModel.addText(currentDocument, x, y, clean)
        if (next === currentDocument)
            return "error: the sheet is full"
        var added = next.objects[next.objects.length - 1]
        commitDocument(DocumentModel.updateText(next, added.id, clean, clean.split("\n").length * 21 + 8))
        return "ok"
    }

    // mode is "path", "image", or "" for whatever Ctrl+C copies. Returns the PNG's path;
    // status() reports lastExport and lastExportOk once it is written and copied.
    function scriptCopy(mode) {
        if (mode !== "" && mode !== "path" && mode !== "image")
            return "error: mode is path, image or empty"
        if (pendingExport !== "")
            return "error: an export is already running"
        copyImagePath(mode !== "" && mode !== settings.clipboard)
        return pendingExport
    }

    onNotebookChanged: scheduleSave()
    onCurrentToolChanged: scheduleSave()
    onPenWidthChanged: scheduleSave()
    onSettingsChanged: scheduleSave()
    Component.onCompleted: prepareStateDir.running = true

    // Colors for the toolbar, settings and tooltips: the active Omarchy theme (following
    // theme switches), or Field Notes' own look when "Use Omarchy theme" is off.
    OmarchyTheme {
        id: omarchyTheme
    }

    ClassicTheme {
        id: classicTheme
    }

    // A monitor unplugged under the notes: show them on the focused one instead. Wait a turn so
    // the removed output finishes closing its surface before another is mapped.
    Connections {
        target: Quickshell

        function onScreensChanged() {
            if (!root.targetScreen || Quickshell.screens.indexOf(root.targetScreen) >= 0)
                return
            root.targetScreen = null
            root.positionInitialized = false
            Qt.callLater(function() {
                if (root.opened && !root.targetScreen)
                    root.showOn(root.focusedScreen())
            })
        }
    }

    // Scripting: `omarchy-shell jobo.field-notes <method> [args]`, for demos, tests and
    // automation. Showing and hiding go through the shell so the bar icon stays in step.
    // Actions answer "ok" or "error: <reason>"; sheets are numbered from 1 as on the paper.
    IpcHandler {
        target: "jobo.field-notes"

        function status(): string { return JSON.stringify(root.scriptStatus()) }

        function open(): string {
            return root.shell && typeof root.shell.summon === "function" && root.shell.summon("jobo.field-notes", "{}") ? "ok" : "error: the shell did not open the panel"
        }

        function openOn(screen: string): string {
            if (!DocumentModel.isScreenName(screen) || !root.screenNamed(screen))
                return "error: no screen named " + screen
            return root.shell && typeof root.shell.summon === "function" && root.shell.summon("jobo.field-notes", JSON.stringify({ screen: screen })) ? "ok" : "error: the shell did not open the panel"
        }

        function close(): string {
            if (root.opened)
                root.requestClose()
            return "ok"
        }

        function toggle(): string { return root.opened ? close() : open() }

        function newSheet(): string {
            if (root.notebook.sheets.length >= DocumentModel.MAX_SHEETS)
                return "error: the notebook is full"
            root.addSheet()
            return "ok"
        }

        function selectSheet(number: int): string {
            if (number < 1 || number > root.notebook.sheets.length)
                return "error: there is no sheet " + number
            root.selectSheet(number - 1)
            return "ok"
        }

        function setTitle(title: string): string {
            root.renameSheet(title)
            return "ok"
        }

        function setPaper(name: string): string {
            if (DocumentModel.PAPERS.indexOf(name) < 0)
                return "error: paper is graph, dots, ruled or plain"
            root.focusKeys()
            root.commitDocument(DocumentModel.setPaper(root.currentDocument, name))
            return "ok"
        }

        function setSize(name: string): string { return root.scriptSetSize(name) }

        function setTool(name: string): string {
            if (DocumentModel.TOOLS.indexOf(name) < 0)
                return "error: tool is select, pen, eraser or text"
            root.selectTool(name)
            return "ok"
        }

        function setPenWidth(width: real): string {
            root.setPenWidth(width)
            return "ok"
        }

        function clear(): string {
            root.clearDocument()
            return "ok"
        }

        function center(): string {
            root.centerBoard(true)
            return "ok"
        }

        function undo(): string {
            if (!root.canUndo)
                return "error: nothing to undo"
            return root.undo() ? "ok" : "error: the notebook is full"
        }

        function redo(): string {
            if (!root.canRedo)
                return "error: nothing to redo"
            return root.redo() ? "ok" : "error: the notebook is full"
        }

        function draw(points: string, durationMs: int): string { return root.scriptDraw(points, durationMs) }

        function stopDrawing(): string {
            paper.cancelScriptStrokes()
            return "ok"
        }

        function addNote(x: real, y: real, text: string): string { return root.scriptNote(x, y, text) }

        function copy(mode: string): string { return root.scriptCopy(mode) }
    }
    Component.onDestruction: flushSave()

    Timer {
        id: saveTimer

        interval: 500
        onTriggered: root.saveNow()
    }

    Process {
        id: prepareStateDir

        command: ["mkdir", "-p", "-m", "700", root.stateDir]
        onExited: function(exitCode) {
            if (exitCode === 0) {
                stateCheck.running = true
            } else {
                console.warn("Field Notes: cannot create " + root.stateDir + "; notes will not be saved")
                root.saveStatus = "NOT SAVED"
            }
        }
    }

    // Reads of the notes file fail closed: only a regular file (not a symlink, pipe or
    // folder) of at most maxStateBytes is opened. Otherwise nothing is read and nothing is
    // ever written over it. Exit codes: 0 safe, 3 missing (start fresh), 4 not a regular
    // file, 5 unreadable, 6 too large.
    Process {
        id: stateCheck

        command: ["sh", "-c",
            "if [ -L \"$1\" ]; then exit 4; fi; [ -e \"$1\" ] || exit 3; [ -f \"$1\" ] || exit 4; size=$(stat -c %s -- \"$1\") || exit 5; [ \"$size\" -le \"$2\" ] || exit 6",
            "field-notes", root.stateDir + "/notes.json", String(root.maxStateBytes)]
        onExited: function(exitCode) {
            if (exitCode === 0 || exitCode === 3) {
                root.stateChecked = true
                return
            }
            var reasons = { 4: "is not a regular file", 5: "cannot be read", 6: "is larger than 16 MiB" }
            console.warn("Field Notes: " + root.stateDir + "/notes.json " + (reasons[exitCode] || "failed its safety check")
                + "; it was not opened and notes will not be saved over it")
            root.saveStatus = "NOT SAVED"
        }
    }

    Process {
        id: prepareExportDir

        command: ["mkdir", "-p", "--", root.exportDir]
        onExited: function(exitCode) {
            if (exitCode !== 0) {
                root.finishExport(false)
                return
            }
            paper.exportImage(root.pendingExport, function(ok) {
                if (!ok) {
                    root.finishExport(false)
                    return
                }
                copyPath.command = root.pendingMode === "image"
                    ? ["sh", "-c", "exec wl-copy --type image/png < \"$1\"", "field-notes", root.pendingExport]
                    : ["wl-copy", root.pendingExport]
                copyPath.running = true
            })
        }
    }

    Process {
        id: copyPath

        onExited: function(exitCode) {
            root.finishExport(exitCode === 0)
        }
    }

    // The version shown on the paper comes from the plugin's own manifest.
    FileView {
        path: decodeURIComponent(Qt.resolvedUrl("manifest.json").toString().replace(/^file:\/\//, ""))
        printErrors: false
        onLoaded: {
            try {
                root.appVersion = String(JSON.parse(text()).version || "")
            } catch (error) {
                root.appVersion = ""
            }
        }
    }

    Process {
        id: backupCorrupt

        // Never follows symlinks: replaces any existing backup rather than writing through it.
        command: ["cp", "--no-dereference", "--remove-destination", "--", stateFile.path, stateFile.path + ".corrupt"]
        onExited: function(exitCode) {
            root.finishBackup(exitCode, "notes.json.corrupt")
        }
    }

    Process {
        id: backupTrimmed

        // The same rules as backupCorrupt, for a file that loading had to trim.
        command: ["cp", "--no-dereference", "--remove-destination", "--", stateFile.path, stateFile.path + ".trimmed"]
        onExited: function(exitCode) {
            root.finishBackup(exitCode, "notes.json.trimmed")
        }
    }

    // A copy that never reports back (cp could not start) counts as failed, not as done.
    Timer {
        id: backupWatchdog

        interval: 10000
        onTriggered: root.finishBackup(-1, "a backup")
    }

    FileView {
        id: stateFile

        path: root.stateChecked ? root.stateDir + "/notes.json" : ""
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

        screen: root.targetScreen
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
                x: board.x + settingsCard.x * board.scale
                y: board.y + settingsCard.y * board.scale
                width: root.settingsOpen ? settingsCard.width * board.scale : 0
                height: root.settingsOpen ? settingsCard.height * board.scale : 0
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
                if (control && event.key === Qt.Key_Comma) {
                    root.toggleSettings()
                    event.accepted = true
                    return
                }
                if (root.settingsOpen) {
                    if (event.key === Qt.Key_Escape)
                        root.closeSettings()
                    event.accepted = true
                    return
                }
                if (control && event.key === Qt.Key_Z && shift) {
                    root.redo()
                    event.accepted = true
                    return
                } else if (control && event.key === Qt.Key_Z) {
                    root.undo()
                    event.accepted = true
                    return
                } else if (control && event.key === Qt.Key_C) {
                    root.copyImagePath(shift)
                    event.accepted = true
                    return
                } else if (event.key === Qt.Key_F2) {
                    paper.editTitle()
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
                } else if (!control && event.key === Qt.Key_S) {
                    root.cycleSize()
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
                    width: root.currentDocument.page.width
                    height: root.currentDocument.page.height
                    document: root.currentDocument
                    currentTool: root.currentTool
                    penWidth: root.penWidth
                    statusText: root.saveStatus
                    tilted: root.settings.tilt
                    mouseSmoothing: root.smoothingStrength[root.settings.smoothing]
                    eraserRadius: root.eraserRadii[root.settings.eraser]
                    dimmed: root.settingsOpen
                    onDimClicked: root.closeSettings()
                    sheetIndex: root.notebook.current
                    sheetCount: root.notebook.sheets.length
                    onCommitRequested: function(nextDocument) {
                        root.commitDocument(nextDocument)
                    }
                    onEditingFinished: root.focusKeys()
                    onPaperRequested: root.cyclePaper()
                    onSizeRequested: root.cycleSize()
                    onTitleCommitted: function(title) {
                        root.renameSheet(title)
                    }
                    version: root.appVersion
                    theme: root.theme
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
                    theme: root.theme
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
                    onCopyImageRequested: root.copyImagePath()
                    onSettingsRequested: root.toggleSettings()
                    copyMode: root.settings.clipboard
                    settingsOpen: root.settingsOpen
                    // The notes' surface holds keyboard focus while you work in them.
                    faded: root.settings.fadeToolbar && !Window.active && !root.settingsOpen
                    onCloseRequested: root.requestClose()
                    onGripMoved: function(sceneX, sceneY) {
                        root.dragToolbar(sceneX, sceneY)
                    }
                    onGripReleased: root.focusKeys()
                }

                SettingsPanel {
                    id: settingsCard

                    // Centred on the paper, within the area beside the toolbar.
                    x: Math.max(root.settingsArea.x, Math.min(root.settingsArea.x + root.settingsArea.width - width,
                        Math.round(paper.x + (paper.width - width) / 2)))
                    y: Math.max(root.settingsArea.y, Math.min(root.settingsArea.y + root.settingsArea.height - height,
                        Math.round(paper.y + (paper.height - height) / 2)))
                    z: 40
                    width: implicitWidth
                    height: implicitHeight
                    maxWidth: root.settingsArea.width
                    maxHeight: root.settingsArea.height
                    opacity: root.settingsOpen ? 1 : 0
                    scale: root.settingsOpen ? 1 : 0.97
                    visible: opacity > 0
                    theme: root.theme
                    settings: root.settings
                    toolbarSide: root.toolbarSide
                    version: root.appVersion
                    notesPath: stateFile.path
                    defaultExportDir: root.defaultExportDir
                    home: root.home
                    onSettingChanged: function(key, value) {
                        root.setSetting(key, value)
                    }
                    onToolbarSideRequested: function(side) {
                        root.setToolbarSide(side)
                    }
                    onOpenExportFolderRequested: root.openExportFolder()
                    onCenterBoardRequested: root.centerBoard(true)
                    onResetRequested: root.resetSettings()
                    onCloseRequested: root.closeSettings()
                    onEditingFinished: root.focusKeys()

                    Behavior on opacity {
                        NumberAnimation {
                            duration: 140
                        }
                    }

                    Behavior on scale {
                        NumberAnimation {
                            duration: 160
                            easing.type: Easing.OutCubic
                        }
                    }
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
                        theme: root.theme
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
