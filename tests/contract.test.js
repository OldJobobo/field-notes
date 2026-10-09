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

  for (const label of ["SELECT", "PEN", "ERASE", "TEXT", "UNDO", "REDO", "CLOSE"])
    assert.match(tools, new RegExp(`text:\\s*"${label}"`))
  assert.match(tools, /"CLEAR"/)
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
    /onPositionChanged:[\s\S]*?root\.currentTool === "eraser"[\s\S]*?root\.eraseAt\(mouse\.x, mouse\.y\)/,
    "dragging the eraser across an object must remove it"
  )
  assert.match(
    paper,
    /onEraseRequested:[\s\S]*?selectedObjectId = ""[\s\S]*?editingObjectId = ""[\s\S]*?DocumentModel\.deleteObject/,
    "text-note erase must clear delegate state before the commit destroys its delegate"
  )
  assert.match(tools, /signal undoRequested/)
  assert.match(tools, /signal redoRequested/)
  assert.match(tools, /signal clearRequested/)
  assert.match(tools, /clearArmed/)
})

test("text editor keeps focus while a newly inserted note is being edited", () => {
  const panel = read("Panel.qml")
  assert.match(
    panel,
    /onCommitRequested:[\s\S]*?root\.commitDocument\(nextDocument\)[\s\S]*?if \(paper\.editingObjectId === ""\)[\s\S]*?keyboardRoot\.forceActiveFocus\(\)/,
    "document commits must not steal focus from an active TextEdit"
  )
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
    /function commitText\(id, text\)[\s\S]*?editingObjectId = ""[\s\S]*?selectedObjectId = ""[\s\S]*?DocumentModel\.updateText/,
    "committing text must leave a clean final note with no input-style selection box"
  )
  assert.match(
    note,
    /onActiveFocusChanged:[\s\S]*?root\.editing[\s\S]*?root\.commitRequested\(root\.objectData\.id, text\)/,
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
