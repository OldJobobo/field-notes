const test = require("node:test")
const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")

const root = path.resolve(__dirname, "..")

function read(relativePath) {
  return fs.readFileSync(path.join(root, relativePath), "utf8")
}

test("declares an independent Field Notes panel and bar widget", () => {
  const manifest = JSON.parse(read("manifest.json"))

  assert.equal(manifest.schemaVersion, 1)
  assert.equal(manifest.id, "jobo.field-notes")
  assert.equal(manifest.name, "Field Notes")
  assert.equal(manifest.version, "0.1.0")
  assert.deepEqual(manifest.kinds, ["panel", "bar-widget"])
  assert.equal(manifest.keepLoaded, true)
  assert.equal(manifest.entryPoints.panel, "Panel.qml")
  assert.equal(manifest.entryPoints.barWidget, "BarWidget.qml")
  assert.equal(manifest.barWidget.allowMultiple, false)
  assert.equal(manifest.barWidget.defaultSection, "right")

  for (const entryPoint of Object.values(manifest.entryPoints)) {
    assert.equal(fs.existsSync(path.join(root, entryPoint)), true, `${entryPoint} must exist`)
  }
})

test("entry points expose a movable frameless layer-shell lifecycle", () => {
  const panel = read("Panel.qml")
  const widget = read("BarWidget.qml")

  assert.match(panel, /function open\s*\(/)
  assert.match(panel, /function close\s*\(/)
  assert.match(panel, /import Quickshell\.Wayland/)
  assert.match(panel, /PanelWindow\s*\{/)
  assert.doesNotMatch(panel, /FloatingWindow\s*\{/)
  assert.match(panel, /visible:\s*root\.opened\b/)
  assert.doesNotMatch(panel, /visible:\s*root\.opened\s*&&/, "PanelWindow visibility must not depend on its backing screen")
  assert.doesNotMatch(panel, /onVisibleChanged/, "transient layer-surface remaps must not hide the host panel")
  assert.match(panel, /WlrLayershell\.namespace:\s*"jobo-field-notes"/)
  assert.match(panel, /WlrLayershell\.layer:\s*WlrLayer\.(Top|Overlay)/)
  assert.match(panel, /exclusionMode:\s*ExclusionMode\.Ignore/)
  assert.doesNotMatch(panel, /startSystemMove\s*\(/, "layer surfaces move their scene, not a compositor window")
  assert.match(widget, /shell toggle jobo\.field-notes/)
  assert.match(widget, /BarIconButton\s*\{/)
  assert.match(widget, /fontFamily:\s*"JetBrainsMono Nerd Font"/, "the icon must use the installed Nerd Font rather than the text-only bar font")
  assert.doesNotMatch(widget, /labelVisible:\s*false/, "the bar glyph must actually be rendered")
})

test("base layer composes masked graph paper and a detached tool island", () => {
  const panel = read("Panel.qml")
  const paper = read("PaperSurface.qml")
  const tools = read("ToolIsland.qml")

  assert.match(panel, /mask:\s*Region\s*\{/)
  assert.match(panel, /PaperSurface\s*\{/)
  assert.match(panel, /ToolIsland\s*\{/)
  assert.match(panel, /DragHandler\s*\{/)
  assert.match(panel, /target:\s*board/)
  assert.match(panel, /Keys\.onPressed/)
  assert.match(panel, /Qt\.Key_(Left|Right|Up|Down)/)

  assert.match(paper, /Canvas\s*\{/)
  assert.match(paper, /minorGrid/)
  assert.match(paper, /majorGrid/)
  assert.match(paper, /FIELD NOTES/)

  for (const label of ["Select", "Pen", "Erase", "Text", "Undo", "Redo", "Close"])
    assert.match(tools, new RegExp(`text:\\s*"${label}"`))
  assert.match(tools, /"Clear sheet"/)
})

test("paper and toolbar expose working editing actions", () => {
  const panel = read("Panel.qml")
  const paper = read("PaperSurface.qml")
  const tools = read("ToolIsland.qml")

  assert.match(panel, /import "DocumentModel\.js" as DocumentModel/)
  assert.match(panel, /import "History\.js" as History/)
  assert.match(panel, /onCommitRequested/)
  assert.match(paper, /import "Geometry\.js" as Geometry/)
  assert.match(paper, /signal commitRequested/)
  assert.match(paper, /activeStroke/)
  assert.match(paper, /requestPaint\s*\(/)
  assert.match(paper, /currentTool === "eraser"/)
  assert.match(paper, /function eraseAt\(x, y\)/)
  assert.match(
    paper,
    /function eraseAt\(x, y\)[\s\S]*?Geometry\.splitStroke[\s\S]*?DocumentModel\.replaceStrokeSegments/,
    "drawing erase must cut a local gap and preserve editable stroke segments"
  )
  assert.match(
    paper,
    /onPositionChanged:[\s\S]*?root\.currentTool === "eraser"[\s\S]*?root\.eraseAlong\(/,
    "dragging the eraser must sweep the whole path, not just sparse pointer samples"
  )
  assert.match(paper, /function eraseAlong\(from, to\)[\s\S]*?eraseAt\(/)
  assert.match(
    paper,
    /function finishGesture\([\s\S]*?commit\(draftDocument\)/,
    "an erase or move gesture must land in history as a single undo step"
  )
  assert.match(tools, /signal undoRequested/)
  assert.match(tools, /signal redoRequested/)
  assert.match(tools, /signal clearRequested/)
  assert.match(tools, /clearArmed/)
})

test("keyboard focus returns to the sheet only when note editing ends", () => {
  const panel = read("Panel.qml")
  const paper = read("PaperSurface.qml")
  assert.match(
    panel,
    /onCommitRequested: function\(nextDocument\) \{\s*root\.commitDocument\(nextDocument\)\s*\}/,
    "document commits must not steal focus from an active TextEdit"
  )
  assert.match(panel, /onEditingFinished: root\.focusKeys\(\)/)
  assert.match(
    panel,
    /function focusKeys\(\)\s*\{[\s\S]*?keySink\.forceActiveFocus\(\)/,
    "focusing the FocusScope itself would leave active focus inside a note editor"
  )
  assert.match(paper, /onEditingObjectIdChanged:[\s\S]*?editingFinished\(\)/)
  for (const action of ["selectTool", "undo", "redo", "clearDocument"])
    assert.match(panel, new RegExp(`function ${action}\\([^)]*\\) \\{\\s*focusKeys\\(\\)`),
      `${action} must commit an open note edit first`)
})

test("board scale, input masks and drag bounds use the same coordinate transform", () => {
  const panel = read("Panel.qml")
  assert.match(panel, /scale: Layout\.fitScale\(surface\.width, surface\.height, width, height\)/)
  assert.match(panel, /transformOrigin: Item\.TopLeft/)
  for (const name of ["paper", "tools", "dragClip"]) {
    assert.match(panel, new RegExp(`width: \\(?${name}\\.width[^\\n]*\\* board\\.scale`))
    assert.match(panel, new RegExp(`height: \\(?${name}\\.height[^\\n]*\\* board\\.scale`))
  }
  assert.match(panel, /xAxis\.maximum:[^\n]*board\.width \* board\.scale/)
  assert.match(panel, /yAxis\.maximum:[^\n]*board\.height \* board\.scale/)
})

test("toolbar reflects tool state without breaking the panel binding", () => {
  const tools = read("ToolIsland.qml")
  assert.doesNotMatch(tools, /root\.currentTool\s*=[^=]/, "assigning currentTool would break the binding from Panel")
  assert.match(tools, /"Width "/)
  assert.match(tools, /penWidthRequested\(root\.nextPenWidth\(\)\)/)
})

test("sheet persists atomically and never overwrites unread state", () => {
  const panel = read("Panel.qml")
  assert.match(panel, /import Quickshell\.Io/)
  assert.match(panel, /FileView\s*\{/)
  assert.match(panel, /atomicWrites:\s*true/)
  assert.match(panel, /XDG_STATE_HOME/)
  assert.match(panel, /function scheduleSave\(\)\s*\{\s*if \(!stateReady\)\s*return/)
  assert.match(panel, /function saveNow\(\)\s*\{[\s\S]*?if \(!stateReady\)\s*return/)
  assert.match(panel, /function restoreState\(text\)\s*\{\s*if \(stateReady\)\s*return/)
  assert.match(panel, /DocumentModel\.sanitizeNotebook\(/)
  assert.match(panel, /function close\(\)[\s\S]*?flushSave\(\)/)
  assert.match(panel, /Component\.onDestruction:\s*flushSave\(\)/)
})

test("text notes can edit, select, move, and delete", () => {
  const panel = read("Panel.qml")
  const paper = read("PaperSurface.qml")
  const note = read("TextNote.qml")

  assert.match(paper, /TextNote\s*\{/)
  assert.match(paper, /editingObjectId/)
  assert.match(paper, /moveText\s*\(/)
  assert.match(paper, /updateText\s*\(/)
  assert.match(paper, /deleteSelected\s*\(/)
  assert.match(note, /TextEdit\s*\{/)
  assert.match(note, /DragHandler\s*\{/)
  assert.match(note, /Qt\.Key_(Escape|Return|Enter)/)
  assert.match(
    paper,
    /function commitText\(id, text, height\)[\s\S]*?editingObjectId = ""[\s\S]*?selectedObjectId = ""[\s\S]*?DocumentModel\.updateText/,
    "committing text must leave a clean final note with no input-style selection box"
  )
  assert.match(
    note,
    /onActiveFocusChanged:[\s\S]*?root\.editing[\s\S]*?root\.commitRequested\(root\.objectData\.id, text, root\.height\)/,
    "clicking away must commit the active text draft"
  )
  assert.match(
    paper,
    /onPressed:[\s\S]*?root\.editingObjectId !== ""[\s\S]*?forceActiveFocus\(\)[\s\S]*?return/,
    "the first paper click while editing must commit rather than create another note"
  )
  assert.match(
    note,
    /onEditingChanged:[\s\S]*?if \(editing\)[\s\S]*?else[\s\S]*?editor\.text = objectData\.text/,
    "leaving edit mode must discard an uncommitted draft"
  )
  assert.match(panel, /Qt\.Key_Delete/)
})

test("sheets switch through the notebook with per-sheet history", () => {
  const panel = read("Panel.qml")
  const paper = read("PaperSurface.qml")
  assert.match(panel, /import "Notebook\.js" as Notebook/)
  assert.match(panel, /readonly property var historyState: notebook\.sheets\[notebook\.current\]/)
  assert.match(panel, /onNotebookChanged: scheduleSave\(\)/)
  assert.match(
    panel,
    /function leaveSheet\(\) \{\s*focusKeys\(\)[\s\S]*?cancelGesture\(\)[\s\S]*?clearSelection\(\)/,
    "an open note must be committed to the sheet it belongs to before switching"
  )
  for (const action of ["selectSheet", "addSheet"])
    assert.match(panel, new RegExp(`function ${action}\\([^)]*\\) \\{\\s*leaveSheet\\(\\)`))
  assert.match(panel, /Qt\.Key_PageUp/)
  assert.match(panel, /Qt\.Key_PageDown/)
  assert.match(panel, /Qt\.Key_N/)
  assert.match(paper, /root\.sheetIndex \+ 1/)
  const tools = read("ToolIsland.qml")
  assert.match(tools, /"Previous sheet"/)
  assert.match(tools, /root\.lastSheet \? "New sheet" : "Next sheet"/)
})

test("toolbar docks to any paper side and is laid out from the dock geometry", () => {
  const panel = read("Panel.qml")
  const tools = read("ToolIsland.qml")
  assert.match(panel, /width: root\.dockLayout\.width/)
  assert.match(panel, /x: root\.dockLayout\.paperX/)
  assert.match(panel, /x: root\.dockLayout\.toolX/)
  assert.match(panel, /Layout\.nearestSide\(/)
  assert.match(panel, /toolbar: toolbarSide/)
  assert.match(tools, /DragHandler\s*\{[\s\S]*?target: null/)
  assert.match(tools, /columns: root\.horizontal \? children\.length : 1/)
  assert.match(tools, /tooltipSide: root\.tooltipSide/)
})

test("only mouse and touchpad strokes are smoothed, live and on commit alike", () => {
  const paper = read("PaperSurface.qml")
  assert.match(paper, /PointHandler\s*\{\s*id: pointerKind/)
  assert.match(paper, /device\.type === PointerDevice\.Mouse/)
  assert.match(paper, /root\.steadyStroke = root\.isSteadyInput\(mouse\)/)
  assert.match(paper, /function finishGesture\([\s\S]*?var points = strokePoints\(\)/)
  assert.match(paper, /root\.traceStroke\(ctx, root\.strokePoints\(\)/)
  assert.doesNotMatch(paper, /jobo\.field-notes/)
})

test("tooltips follow the docked side without switching anchors at runtime", () => {
  const tooltip = read("Tooltip.qml")
  assert.doesNotMatch(tooltip, /anchors\.(left|right|top|bottom|horizontalCenter|verticalCenter):[^\n]*\?/,
    "conditional anchors conflict while the toolbar re-docks and leave the tooltip misplaced")
  assert.match(tooltip, /x: side === "left"/)
  assert.match(tooltip, /y: side === "top"/)
  assert.match(read("ToolButton.qml"), /Tooltip\s*\{[\s\S]*?side: root\.tooltipSide/)
})

test("toolbar tooltips draw above every other part of the board", () => {
  const panel = read("Panel.qml")
  const board = panel.slice(panel.indexOf("id: board"))
  const zOf = id => {
    const block = board.slice(board.indexOf(`id: ${id}`))
    const match = /\n {20}z: (\d+)/.exec(block.slice(0, block.indexOf("\n                }")))
    return match ? Number(match[1]) : 0
  }
  for (const id of ["paper", "dragClip"])
    assert.ok(zOf("tools") > zOf(id), `the toolbar (z ${zOf("tools")}) must stack above ${id} (z ${zOf(id)})`)
})

test("the board is moved by a drawn binder clip with a shared tooltip, not a text label", () => {
  const panel = read("Panel.qml")
  const clip = read("BinderClip.qml")
  const dragClip = panel.slice(panel.indexOf("id: dragClip"))
  assert.match(dragClip, /BinderClip\s*\{[\s\S]*?tilt: paper\.rotation[\s\S]*?lifted: clipDrag\.active/)
  assert.match(dragClip, /Tooltip\s*\{[\s\S]*?text: "Drag to move"/)
  assert.match(dragClip, /DragHandler\s*\{\s*id: clipDrag\s*target: board/)
  assert.doesNotMatch(panel, /DRAG {2}• {2}ARROWS/)
  assert.match(clip, /import QtQuick\.Shapes/)
  assert.match(clip, /preferredRendererType: Shape\.CurveRenderer/)
})

test("clicking the paper label or pressing G changes the sheet's paper", () => {
  const panel = read("Panel.qml")
  const paper = read("PaperSurface.qml")
  assert.match(panel, /function cyclePaper\(\) \{\s*focusKeys\(\)[\s\S]*?DocumentModel\.setPaper\(currentDocument, DocumentModel\.nextPaper\(/)
  assert.match(panel, /Qt\.Key_G\) \{\s*root\.cyclePaper\(\)/)
  assert.match(panel, /onPaperRequested: root\.cyclePaper\(\)/)
  assert.match(panel, /createSheet\(DocumentModel\.sizeName\(currentDocument\), currentDocument\.paper\)/,
    "new sheets start with the current size and paper")
  assert.match(paper, /onPaperTypeChanged: graph\.requestPaint\(\)/)
  for (const type of ["graph", "dots", "ruled", "plain"])
    assert.match(paper, new RegExp(`${type}: "`))
  const label = paper.slice(paper.indexOf("// Above the drawing surface"))
  const z = Number(/\n {12}z: (\d+)/.exec(label)[1])
  const pointerZ = Number(/id: editorPointer[\s\S]*?z: (\d+)/.exec(paper)[1])
  assert.ok(z > pointerZ, "the paper label must sit above the drawing surface to receive clicks")
  assert.match(label, /HeaderLabel\s*\{\s*id: paperLabel[\s\S]*?action: "Change paper"\s*shortcut: "G"[\s\S]*?onActivated: root\.paperRequested\(\)/)
  const header = read("HeaderLabel.qml")
  assert.match(header, /Tooltip\s*\{[\s\S]*?text: root\.notice \|\| root\.action/)
})

test("Ctrl+C saves the sheet as a PNG and copies its path", () => {
  const panel = read("Panel.qml")
  const paper = read("PaperSurface.qml")
  const tools = read("ToolIsland.qml")
  assert.match(panel, /control && event\.key === Qt\.Key_C\) \{\s*root\.copyImagePath\(shift\)/)
  assert.match(panel, /function copyImagePath\(alternate\) \{\s*focusKeys\(\)/, "an open note is committed before export")
  assert.match(panel, /XDG_PICTURES_DIR[\s\S]*?\/Pictures"\) \+ "\/field-notes"/)
  assert.match(panel, /DocumentModel\.slug\(currentDocument\.title\)/)
  assert.match(panel, /Qt\.formatDateTime\(new Date\(\), "yyyyMMdd-HHmmss"\) \+ "\.png"/, "every export is a new file")
  assert.match(panel, /command: \["mkdir", "-p", "--", root\.exportDir\]/)
  assert.match(panel, /: \["wl-copy", root\.pendingExport\]/, "by default the path is copied")
  assert.match(paper, /function exportImage\(path, done\)[\s\S]*?selectedObjectId = ""[\s\S]*?exporting = true/)
  assert.match(paper, /sheet\.grabToImage\(/, "the unrotated sheet is captured, not the tilted board")
  assert.match(paper, /visible: !root\.exporting\s*width: Math\.max\(68, statusLabel/, "the save chip stays off exports")
  assert.match(tools, /"Copy image path"/)
  assert.match(tools, /function exportFinished\(ok, mode\)/)
})

test("sheets are renamed in place from the header and the version prints in the footer", () => {
  const panel = read("Panel.qml")
  const paper = read("PaperSurface.qml")
  const title = read("TitleField.qml")
  assert.match(paper, /TitleField\s*\{[\s\S]*?text: root\.sheetTitle[\s\S]*?onFinished: root\.editingFinished\(\)/)
  assert.match(paper, /root\.editingObjectId !== "" \|\| titleField\.editing/, "a paper click commits the title first")
  assert.match(panel, /Qt\.Key_F2\) \{\s*paper\.editTitle\(\)/)
  assert.match(panel, /DocumentModel\.setTitle\(currentDocument, title\)/)
  assert.match(title, /Keys\.onEscapePressed: root\.finish\(false\)/)
  assert.match(title, /onActiveFocusChanged:[\s\S]*?root\.finish\(true\)/, "clicking away keeps the edit")
  assert.match(panel, /Qt\.resolvedUrl\("manifest\.json"\)/, "the version comes from the manifest, not a copy")
  assert.match(paper, /"v" \+ root\.version/)
})

test("sheets come in three sizes, changed from the header or S, without moving the paper", () => {
  const panel = read("Panel.qml")
  const paper = read("PaperSurface.qml")
  assert.match(paper, /HeaderLabel\s*\{\s*id: sizeLabel[\s\S]*?action: "Change size"\s*shortcut: "S"[\s\S]*?onActivated: root\.sizeRequested\(\)/)
  assert.match(panel, /Qt\.Key_S\) \{\s*root\.cycleSize\(\)/)
  assert.match(panel, /onSizeRequested: root\.cycleSize\(\)/)
  assert.match(panel, /function cycleSize\(\) \{\s*focusKeys\(\)[\s\S]*?paper\.refuseSize\([\s\S]*?DocumentModel\.setSize\(/)
  assert.match(panel, /width: root\.currentDocument\.page\.width\s*height: root\.currentDocument\.page\.height/)
  assert.match(panel, /Layout\.dock\(toolbarSide, currentDocument\.page\.width, currentDocument\.page\.height,/)
  assert.doesNotMatch(panel, /^\s*notebook = Notebook\.(replaceCurrent|select|add)/m, "every notebook change keeps the paper in place")
  assert.match(panel, /function setNotebook\(next\)[\s\S]*?centerX - \(paper\.x \+ paper\.width \/ 2\) \* board\.scale/)
  assert.match(paper, /onWidthChanged: root\.repaintAll\(\)/, "canvases repaint at the new size")
  assert.match(read("HeaderLabel.qml"), /Tooltip\s*\{\s*x: root\.width - width/, "header tooltips open over the paper, not under the toolbar")
})

test("the toolbar and tooltips take every color from the active Omarchy theme", () => {
  const theme = read("OmarchyTheme.qml")
  const panel = read("Panel.qml")
  assert.match(theme, /import qs\.Commons/)
  assert.match(theme, /Color\.composed\("field-notes\.background", "field-notes\.background-alpha",\s*Color\.pick\("popups\.background"/)
  assert.match(theme, /Style\.hoverFillFor\(text, accent\)/, "button states follow [controls] like the shell's Button")
  assert.match(theme, /tooltipBackground: Color\.tooltip\.background/)
  assert.match(theme, /radius: Style\.cornerRadius/)
  assert.match(panel, /OmarchyTheme\s*\{\s*id: omarchyTheme\s*\}/)
  assert.doesNotMatch(panel, /\btheme: theme\b/, "binding theme to itself would loop")
  for (const file of ["ToolIsland.qml", "ToolButton.qml", "Tooltip.qml"]) {
    const source = read(file).replace(/shadowColor: "#[0-9a-fA-F]+"/, "")
    assert.doesNotMatch(source, /"#[0-9a-fA-F]{3,8}"/, `${file} must not hard-code colors`)
    assert.match(source, /property QtObject theme/)
  }
  assert.match(read("ToolButton.qml"), /color: mouse\.pressed \? root\.theme\.pressedFill\s*: root\.hot \? root\.theme\.hoverFill\s*: root\.selected/,
    "pressed, hover, selected: the shell's state precedence")
})

test("the Omarchy and classic themes are interchangeable", () => {
  const names = file => [...read(file).matchAll(/readonly property \w+ (\w+)/g)].map(match => match[1]).sort()
  assert.deepEqual(names("ClassicTheme.qml"), names("OmarchyTheme.qml"), "both themes must define the same properties")
  assert.doesNotMatch(read("ClassicTheme.qml"), /qs\.Commons/, "the classic look must not depend on the shell theme")
  assert.match(read("Panel.qml"), /readonly property QtObject theme: settings\.theme \? omarchyTheme : classicTheme/)
})

test("a settings panel opens from the toolbar or Ctrl+, and every setting does something", () => {
  const panel = read("Panel.qml")
  const card = read("SettingsPanel.qml")
  const tools = read("ToolIsland.qml")
  const paper = read("PaperSurface.qml")
  assert.match(tools, /text: "Settings"[\s\S]*?shortcut: "Ctrl\+,"[\s\S]*?onActivated: root\.settingsRequested\(\)/)
  assert.match(panel, /control && event\.key === Qt\.Key_Comma\) \{\s*root\.toggleSettings\(\)/)
  assert.match(panel, /if \(root\.settingsOpen\) \{\s*if \(event\.key === Qt\.Key_Escape\)\s*root\.closeSettings\(\)/,
    "while settings are open, Esc closes them and tool shortcuts do nothing")
  assert.match(panel, /width: root\.settingsOpen \? settingsCard\.width \* board\.scale : 0/, "the card receives clicks")
  assert.match(panel, /onDimClicked: root\.closeSettings\(\)/)
  assert.match(panel, /function close\(\) \{[\s\S]*?settingsOpen = false/)
  assert.match(panel, /DocumentModel\.serialize\([\s\S]*?\}, settings\)\)/, "settings are saved with the notes")
  assert.match(panel, /settings = restored\.settings/)
  assert.match(panel, /onSettingsChanged: scheduleSave\(\)/)

  for (const key of ["theme", "tilt", "smoothing", "eraser", "clipboard", "exportDir"])
    assert.match(card, new RegExp(`settingChanged\\("${key}"`), `the card offers ${key}`)
  assert.match(card, /toolbarSideRequested\(value\)/)
  assert.match(panel, /tilted: root\.settings\.tilt/)
  assert.match(paper, /rotation: tilted \? 0\.8 : 0/)
  assert.match(panel, /mouseSmoothing: root\.smoothingStrength\[root\.settings\.smoothing\]/)
  assert.match(paper, /steadyStroke && mouseSmoothing > 0/, "smoothing off must not divide by zero")
  assert.match(panel, /eraserRadius: root\.eraserRadii\[root\.settings\.eraser\]/)
  assert.match(panel, /pendingMode === "image"\s*\? \["sh", "-c", "exec wl-copy --type image\/png < \\"\$1\\"", "field-notes", root\.pendingExport\]/,
    "the file path is passed as an argument, never spliced into the shell command")
  assert.match(panel, /exportDir: settings\.exportDir \? expandHome\(settings\.exportDir\) : defaultExportDir/)
  assert.match(card, /Keys\.onEscapePressed: \{[\s\S]*?Qt\.binding\(/, "Esc in the folder field keeps it bound to the saved value")
})

test("right-clicking the bar icon opens Field Notes at its settings", () => {
  const widget = read("BarWidget.qml")
  const panel = read("Panel.qml")
  assert.match(widget, /mouseButton === Qt\.RightButton\)\s*root\.bar\.run\("omarchy-shell shell summon jobo\.field-notes '\{\\"settings\\":true\}'"\)/,
    "summon, not toggle, so a right-click never closes an open panel")
  assert.match(panel, /function open\(payloadJson\) \{[\s\S]*?JSON\.parse\(payloadJson \|\| "\{\}"\)[\s\S]*?catch[\s\S]*?payload\.settings === true\)\s*root\.openSettings\(\)/,
    "a malformed payload must not stop the panel from opening")
})

test("Ctrl+Shift+C copies whichever of path or image Ctrl+C does not", () => {
  const panel = read("Panel.qml")
  assert.match(panel, /control && event\.key === Qt\.Key_C\) \{\s*root\.copyImagePath\(shift\)/)
  assert.match(panel, /pendingMode = alternate \? \(preferred === "image" \? "path" : "image"\) : preferred/)
  assert.match(panel, /copyPath\.command = root\.pendingMode === "image"/, "the copy follows the key used, not just the setting")
  assert.match(panel, /tools\.exportFinished\(ok, pendingMode\)/)
  assert.match(read("ToolIsland.qml"), /root\.exportedMode === "image" \? "Image copied" : "Image path copied"/,
    "the confirmation names what was actually copied")
})
