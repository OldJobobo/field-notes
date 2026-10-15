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
  assert.match(panel, /createDocument\(760, 560, currentDocument\.paper\)/, "new sheets start on the current paper")
  assert.match(paper, /onPaperTypeChanged: graph\.requestPaint\(\)/)
  for (const type of ["graph", "dots", "ruled", "plain"])
    assert.match(paper, new RegExp(`${type}: "`))
  const label = paper.slice(paper.indexOf("// Above the drawing surface"))
  const z = Number(/\n {12}z: (\d+)/.exec(label)[1])
  const pointerZ = Number(/id: editorPointer[\s\S]*?z: (\d+)/.exec(paper)[1])
  assert.ok(z > pointerZ, "the paper label must sit above the drawing surface to receive clicks")
  assert.match(label, /onClicked: root\.paperRequested\(\)/)
  assert.match(label, /Tooltip\s*\{[\s\S]*?text: "Change paper"[\s\S]*?shortcut: "G"/)
})
