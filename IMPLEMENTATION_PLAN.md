# Field Notes Graph-Paper Plugin Implementation Plan

> **For Hermes:** Use subagent-driven-development skill to implement this plan task-by-task.

**Goal:** Build a standalone Omarchy Quattro plugin that opens a movable physical-looking sheet of graph paper with a detached floating tool island, allowing freehand drawing and typed notes with safe local persistence.

**Architecture:** Use one transparent `FloatingWindow` containing two visually separate surfaces: the paper and the nearby toolbar island. Keep them in one native window so opening, movement, scaling, focus, and persistence stay synchronized; use a `Region` input mask so the transparent gap does not block desktop clicks. Store editable objects—not a flattened bitmap—as bounded JSON: freehand strokes plus text-note records. Render strokes with QML `Canvas`, render/edit text with QML delegates, and persist through a small audited helper under XDG state.

**Tech Stack:** Omarchy Quattro panel and bar-widget plugin APIs, Qt 6 / QML / Quickshell, plain JavaScript modules testable with Node, small dependency-free C state helper, Node test runner, `qmlformat`, `omarchy plugin validate`.

---

## 1. Grounded context

The live Lantern checkout inspected on Wintermute is:

```text
/home/oldjobobo/.config/omarchy/plugins/jobo.lantern
```

Relevant patterns already proven there:

- `manifest.json` declares `panel` and `bar-widget` entry points and `keepLoaded: true`.
- `Panel.qml` owns a lazily rebuilt `FloatingWindow`, implements `open()` / `close()`, and delegates host hide behavior through `shell.hide()`.
- `MapOverlay.qml` proves the physical graph-paper treatment, `MultiEffect` shadow, modal focus, pointer blocking, viewport state, and non-CRT rendering.
- `MapCanvas.qml` proves threaded QML `Canvas`, deterministic drawing, pointer drag, wheel handling, and bounded plain-data rendering.
- Quickshell `Region` masks are already used elsewhere in the installed shell and can keep transparent surfaces click-through.

Do not import Lantern files at runtime or make this plugin depend on Lantern being installed. Lantern's graph-paper map is the visual/interaction reference only. The new plugin must own its assets, model, state path, tests, and release lifecycle.

### Working identity

Use these working names unless the user renames the plugin before implementation:

```text
Display name: Field Notes
Plugin id:   jobo.field-notes
Repo:        /home/oldjobobo/Projects/field-notes
Live path:   /home/oldjobobo/.config/omarchy/plugins/jobo.field-notes
State root:  ${XDG_STATE_HOME:-~/.local/state}/field-notes
```

The exact title and icon can be changed without changing the architecture.

## 2. Product scope

### MVP behavior

- Clicking the bar widget toggles one floating graph-paper workspace.
- The paper looks physical: warm neutral sheet, faded blue grid, slight rotation, lifted drop shadow, subtle paper texture.
- A compact toolbar island floats beside the paper with its own shadow and does not visually connect to the sheet.
- Tools: Select, Pen, Eraser, Text, Undo, Redo, and Clear.
- Pen creates freehand strokes.
- Text tool click creates a text note at that location and immediately focuses editing.
- Select tool selects, drags, and deletes a text note; selecting whole strokes is not required for MVP.
- Eraser removes a complete stroke or text object hit under the pointer. Pixel-level stroke splitting is deferred.
- Changes autosave after a short debounce and flush on close.
- Reopening restores page content, window placement, selected tool, pen width, and paper scale.
- The transparent gap around/between the sheet and toolbar is click-through.
- Keyboard and pointer operation are both supported.

### Explicit non-goals for v0.1

- Multiple notebooks/pages.
- Infinite canvas.
- Collaboration or sync.
- Rich-text formatting or Markdown rendering.
- Images, pasted files, or clipboard attachments.
- Shape recognition, arrows, connectors, or handwriting recognition.
- Pressure-sensitive brush simulation.
- PNG/PDF export.
- Cross-plugin embedding inside Lantern.

These can be added only after the single-sheet interaction is stable.

## 3. Interaction and visual specification

### Window composition

Use a transparent logical surface around `1120 × 780`:

- Paper: approximately `850 × 640`, slightly rotated (`0.6–1.2°`).
- Toolbar island: approximately `54 × 360` on the right by default.
- Gap: `16–24 px` between paper shadow and toolbar shadow.
- Input mask: union of the paper rectangle, toolbar rectangle, and explicit drag handle; do not mask the entire transparent window.
- Window movement: a small paper tab/clip at the top edge starts `window.startSystemMove()`.
- Scale control: optional 1× / 1.25× / 1.5× cycle, applied to the complete composition.

Keep the paper neutral and independent from the current Omarchy theme. The toolbar may use restrained theme-aware foreground/accent values, but should still read as an object near the paper rather than a generic shell card.

### Paper stack

From back to front:

1. soft broad black shadow at roughly 30–40% opacity;
2. warm paper base;
3. faded blue square grid at roughly 18–24% opacity;
4. very subtle bundled paper texture/noise;
5. freehand stroke canvas;
6. text-note delegates;
7. selection and insertion affordances.

Do not reuse the Lantern CRT shader or phosphor colors. Do not animate paper grain.

### Toolbar island

Vertical default order:

```text
MOVE/SELECT
PEN
ERASER
TEXT
────────
UNDO
REDO
────────
WIDTH
CLEAR
CLOSE
```

Requirements:

- Current tool is unmistakable through shape/border/pressed state, not color alone.
- Every icon has a tooltip and accessible name.
- Minimum pointer target: 40 × 40 logical pixels.
- Clear requires a two-step confirmation state that times out.
- Toolbar may be dragged to the left or right side of the paper and snaps to either side; arbitrary free placement is deferred.

### Keyboard map

- `V`: Select.
- `P` or `B`: Pen.
- `E`: Eraser.
- `T`: Text.
- `Ctrl+Z`: Undo.
- `Ctrl+Shift+Z` and `Ctrl+Y`: Redo.
- `Delete`: delete selected text object.
- `Escape`: finish/cancel text editing first; otherwise close the plugin.
- `Ctrl+Enter`: commit the active text edit.
- `[` / `]`: decrease/increase pen width.

Shortcuts must be active only while the Field Notes window is visible and focused.

## 4. Editable document model

Use one versioned JSON document:

```json
{
  "schemaVersion": 1,
  "page": {
    "width": 850,
    "height": 640
  },
  "objects": [
    {
      "id": "stroke-1",
      "type": "stroke",
      "color": "graphite",
      "width": 2.5,
      "points": [[120.5, 84.0], [122.0, 85.5]]
    },
    {
      "id": "text-2",
      "type": "text",
      "x": 180,
      "y": 140,
      "width": 220,
      "text": "Call the supplier",
      "size": 16
    }
  ],
  "ui": {
    "tool": "pen",
    "penWidth": 2.5,
    "windowScale": 1.0,
    "toolbarSide": "right"
  }
}
```

Bounds:

- maximum document: 2 MiB;
- maximum objects: 4,096;
- maximum points per stroke: 8,192;
- maximum aggregate points: 250,000;
- maximum text length per object: 4,096 characters;
- finite numeric coordinates clamped to the page;
- supported schema versions only;
- generated IDs are opaque and unique; display text never becomes an ID.

Record coordinates in unscaled paper-local logical pixels. UI scaling must not alter stored geometry.

## 5. File layout

Create the new repository with this initial structure:

```text
/home/oldjobobo/Projects/field-notes/
├── manifest.json
├── Panel.qml
├── BarWidget.qml
├── PaperSurface.qml
├── ToolIsland.qml
├── ToolButton.qml
├── TextNote.qml
├── DocumentModel.js
├── Geometry.js
├── assets/
│   ├── field-notes.svg
│   └── paper-texture.png
├── bin/
│   ├── field-notes-state
│   └── field-notes-state.c
├── scripts/
│   └── build-state-helper
├── tests/
│   ├── contract.test.js
│   ├── document-model.test.js
│   ├── geometry.test.js
│   ├── state-helper.test.js
│   └── run
├── README.md
└── LICENSE
```

## 6. Implementation tasks

### Task 1: Scaffold and validate the standalone plugin contract

**Objective:** Establish a minimal independent Quattro plugin that can be validated before any drawing code exists.

**Files:**

- Create: `manifest.json`
- Create: `Panel.qml`
- Create: `BarWidget.qml`
- Create: `assets/field-notes.svg`
- Create: `tests/contract.test.js`
- Create: `tests/run`

**Steps:**

1. Write contract tests asserting the manifest id, kinds, entry points, `keepLoaded`, folder/id agreement, and existence of all entry-point files.
2. Run `node --test tests/contract.test.js`; expect failure because files are absent/incomplete.
3. Add a minimal `panel` + `bar-widget` manifest modeled on Lantern's verified contract.
4. Add a minimal `Panel.qml` with `open(payloadJson)`, `close()`, host-aware hide behavior, and lazy `FloatingWindow` lifecycle.
5. Add a bar button that calls `omarchy-shell shell toggle jobo.field-notes '{}'`.
6. Run `node --test tests/contract.test.js`; expect pass.
7. Run `omarchy plugin validate .`; expect successful validation.
8. Commit: `Scaffold Field Notes plugin`.

### Task 2: Build the transparent floating composition and input mask

**Objective:** Prove the sheet and detached tool island can look separate without transparent areas blocking desktop input.

**Files:**

- Modify: `Panel.qml`
- Create: `PaperSurface.qml`
- Create: `ToolIsland.qml`
- Create: `ToolButton.qml`

**Steps:**

1. Write static contract assertions for a transparent window, explicit `Region` mask, paper region, toolbar region, and system-move handle.
2. Run the contract test; expect failure.
3. Implement a fixed logical root with paper and toolbar island geometry.
4. Add `MultiEffect` shadows to both surfaces.
5. Make the input mask the union of paper, toolbar, and drag handle regions only.
6. Implement paper/window movement using `startSystemMove()` and preserve the draggable area even when a text editor has focus.
7. Implement right/left toolbar snap and window-scale state.
8. Run tests, `qmlformat` checks, and `omarchy plugin validate .`.
9. Live-check on Wintermute that clicks in the transparent gap reach the desktop beneath.
10. Commit: `Add floating paper and tool island`.

### Task 3: Implement the bounded pure document model with TDD

**Objective:** Make document mutation, validation, IDs, and serialization deterministic and testable outside QML.

**Files:**

- Create: `DocumentModel.js`
- Create: `tests/document-model.test.js`

**Steps:**

1. Write failing tests for empty-document creation, unique IDs, stroke insertion, text insertion/update/move/delete, clear, schema rejection, coordinate clamping, length bounds, and deterministic serialization.
2. Run `node --test tests/document-model.test.js`; expect failure.
3. Implement only the pure functions required by those tests.
4. Ensure functions return new plain-data objects or explicit mutation results; do not retain QML object references.
5. Run the focused test; expect pass.
6. Commit: `Add bounded document model`.

### Task 4: Implement freehand pen capture and rendering

**Objective:** Draw smooth freehand strokes while preserving editable vector data.

**Files:**

- Modify: `PaperSurface.qml`
- Create: `Geometry.js`
- Create: `tests/geometry.test.js`

**Steps:**

1. Write failing geometry tests for point distance, minimum sampling distance, line-segment distance, stroke bounds, and hit testing.
2. Implement the pure geometry helpers and make tests pass.
3. Add a threaded QML `Canvas` that redraws all committed strokes.
4. Capture a temporary active stroke with mouse, touchpad, or stylus pointer events.
5. Sample only when movement exceeds a small logical-distance threshold to avoid huge point arrays.
6. Draw the active stroke immediately; commit it to the document on release.
7. Scale the canvas backing store for the active window scale so strokes remain crisp.
8. Verify pointer coordinates remain correct at 1×, 1.25×, and 1.5×.
9. Commit: `Add freehand pen tool`.

### Task 5: Implement text-note creation and editing

**Objective:** Let the user place, type, select, move, edit, and delete plain-text notes on the paper.

**Files:**

- Create: `TextNote.qml`
- Modify: `PaperSurface.qml`
- Modify: `DocumentModel.js`
- Modify: `tests/document-model.test.js`

**Steps:**

1. Add failing model tests for text creation, bounded update, movement, and deletion.
2. Implement and pass those tests.
3. In Text mode, clicking the paper creates a bounded-width note at the pointer and focuses a plain-text editor.
4. Commit edits on focus loss or `Ctrl+Enter`; `Escape` restores the pre-edit value or removes a newly created empty note.
5. In Select mode, click selects one note, drag moves it, double-click edits it, and `Delete` removes it.
6. Clamp the note rectangle to paper bounds.
7. Ensure notes use `Text.PlainText` semantics and never interpret rich text, HTML, or QML.
8. Verify IME input, multiline text, and keyboard focus do not accidentally trigger global tool shortcuts.
9. Commit: `Add editable text notes`.

### Task 6: Add object erasing and undo/redo

**Objective:** Make edits recoverable and erasing understandable without implementing pixel-level stroke surgery.

**Files:**

- Modify: `DocumentModel.js`
- Modify: `Geometry.js`
- Modify: `PaperSurface.qml`
- Modify: `ToolIsland.qml`
- Modify: corresponding tests

**Steps:**

1. Write failing tests for topmost-object hit testing, whole-stroke deletion, text deletion, undo, redo, redo invalidation after a new edit, and bounded history depth.
2. Implement an operation history with a default cap of 100 entries.
3. Eraser click/drag removes each hit object once per gesture; do not repeatedly create history entries for the same object.
4. Record one completed pen stroke as one undo step and one completed text edit/drag as one undo step.
5. Wire toolbar and keyboard undo/redo controls with disabled states.
6. Pass focused and full model tests.
7. Commit: `Add eraser and edit history`.

### Task 7: Implement safe, debounced persistence

**Objective:** Restore the editable document and UI state without unbounded QML file access or unsafe writes.

**Files:**

- Create: `bin/field-notes-state.c`
- Create: `scripts/build-state-helper`
- Create: `tests/state-helper.test.js`
- Modify: `Panel.qml`

**Helper contract:**

```text
field-notes-state read
field-notes-state write     # JSON arrives on stdin
field-notes-state reset
```

**Steps:**

1. Write failing helper tests using an isolated temporary `XDG_STATE_HOME`.
2. Implement checks for ownership, regular files, symlink rejection, size limits, schema version, object/point/text bounds, `0700` directory, `0600` file, temp-file write, `fsync`, and atomic rename.
3. Build the helper and run tests; expect pass.
4. In QML, load state once when the panel initializes.
5. Debounce writes for about 400–600 ms after committed changes; do not write for every pointer sample.
6. Flush on plugin close and native-window close.
7. Treat missing/corrupt/future state as recoverable: open an empty sheet and show a non-blocking status indicator.
8. Verify state survives shell reload and full logout/login.
9. Commit: `Persist Field Notes safely`.

### Task 8: Finish tool island, accessibility, and destructive-action safety

**Objective:** Turn the functional controls into a polished, keyboard-accessible detached toolbar.

**Files:**

- Modify: `ToolIsland.qml`
- Modify: `ToolButton.qml`
- Modify: `Panel.qml`
- Modify: `PaperSurface.qml`

**Steps:**

1. Add tools and actions in the specified order with accessible names and tooltips.
2. Add visible selected, hover, pressed, focus, and disabled states that do not rely on color alone.
3. Add pen-width control with numeric/visual feedback.
4. Make Clear enter `CLEAR? AGAIN` state for a short timeout; second activation clears as one undoable action.
5. Ensure `Escape` resolves text editing before closing the panel.
6. Add focus traversal between toolbar actions and active text note.
7. Honor reduced-motion settings by disabling open/close flourish and toolbar snap animation.
8. Commit: `Polish Field Notes controls`.

### Task 9: Window placement and lifecycle reliability

**Objective:** Make the standalone panel behave reliably across close/reopen and compositor-driven native close.

**Files:**

- Modify: `Panel.qml`
- Reuse or adapt with attribution: a narrowly scoped window-state helper pattern proven in Lantern
- Create tests for the adapted helper behavior

**Steps:**

1. Persist monitor-relative window position and window scale under the Field Notes state root.
2. Prepare temporary Hyprland initial-placement before mapping, then remove the temporary rule.
3. Rebuild the `FloatingWindow` after native compositor close rather than retaining a dead surface.
4. Ensure drawing content remains loaded because the panel module is `keepLoaded`.
5. Verify bar toggle, shell toggle, Escape close, native close, and reopen paths.
6. Commit: `Persist Field Notes window placement`.

### Task 10: Documentation, full validation, and live acceptance pass

**Objective:** Produce an installable v0.1 candidate backed by automated and live evidence.

**Files:**

- Create: `README.md`
- Create: `LICENSE`
- Update: all tests and `tests/run`

**Automated validation:**

```bash
cd /home/oldjobobo/Projects/field-notes
./tests/run
omarchy plugin validate .
qmlformat Panel.qml >/dev/null
qmlformat BarWidget.qml >/dev/null
qmlformat PaperSurface.qml >/dev/null
qmlformat ToolIsland.qml >/dev/null
qmlformat ToolButton.qml >/dev/null
qmlformat TextNote.qml >/dev/null
```

If a helper binary is committed, also rebuild it to `/tmp`, compare byte-for-byte where reproducibility permits, and verify its checksum/source provenance.

**Live acceptance checklist on Wintermute:**

1. Bar icon opens and hides the panel.
2. Paper and toolbar appear as distinct floating physical objects.
3. Transparent gap is click-through.
4. Window drag does not draw or move a note.
5. Pen drawing tracks accurately at all supported scales.
6. Text creation, multiline editing, drag, commit, cancel, and delete work.
7. Eraser deletes the intended topmost object.
8. Undo/redo spans pen, text, drag, erase, and clear.
9. Clear requires confirmation and can be undone.
10. State survives hide/show, shell reload, and logout/login.
11. Native window close can reopen cleanly.
12. No QML/plugin error appears in shell logs.
13. The plugin remains usable with reduced motion enabled.

Commit: `Document and validate Field Notes`.

## 7. Risks and tradeoffs

- **One window versus two native windows:** one masked window is the recommended default because two Wayland windows complicate focus, movement, monitor placement, and synchronized close. The mask must be proven live; if `FloatingWindow` does not honor a compound mask, fallback to two windows only after a focused spike.
- **QML Canvas performance:** redraw committed strokes only on document/view changes, not on every unrelated frame. Draw the active stroke incrementally or as a small overlay. Enforce point/object limits.
- **Text over Canvas:** use QML text delegates above Canvas, not text baked into pixels. This keeps notes editable and accessible.
- **Eraser expectations:** whole-object erasure is intentionally simpler and more predictable for v0.1. Partial stroke splitting can be a separate feature.
- **Persistence helper cost:** the helper adds build/release work but provides safe atomic writes and avoids unbounded shell-string/file access.
- **Lantern coupling:** copying reusable code is acceptable only as source-level adaptation with review; runtime paths must never point into `jobo.lantern`.
- **Dirty Lantern checkout:** the inspected Lantern implementation is currently a large uncommitted worktree. Do not alter it while building this plugin, and do not treat those files as a stable dependency.

## 8. Open decisions that do not block the first prototype

- Final public name and plugin id; `Field Notes` / `jobo.field-notes` is the working choice.
- Whether the toolbar starts on the right or remembers the last snapped side; the plan recommends remembered side.
- Whether pen ink defaults to graphite only or offers one restrained accent color; start graphite-only.
- Whether a later release adds multiple sheets, export, shapes/arrows, or partial-stroke erasing.

## 9. Recommended first checkpoint

Before building the complete model, implement Tasks 1–2 as a visual/input spike and stop for review. The checkpoint should show a live graph-paper sheet and detached toolbar island on Wintermute, prove click-through in the transparent gap, and confirm the window can be moved and reopened. That is the highest-risk shell/compositor behavior; the drawing model should follow only after it is proven.
