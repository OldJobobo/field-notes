# Developing Field Notes

Field Notes is an Omarchy shell plugin (`jobo.field-notes`) written in QML for Quickshell,
with its logic in plain JavaScript modules that run both in QML and in Node for tests. It has
no build step and no dependencies beyond the shell.

## Files

| File | Role |
| --- | --- |
| `manifest.json` | Plugin identity, entry points (`panel`, `barWidget`), version shown on the paper |
| `Panel.qml` | The panel entry point: owns the notebook, settings and layout; keyboard, saving, export |
| `BarWidget.qml` | Bar icon: left click toggles the panel, right click summons it at settings |
| `PaperSurface.qml` | One sheet: paper ruling, ink and wet-ink canvases, notes, pointer tools, header, export capture |
| `TextNote.qml` | A typed note: display, in-place editing, dragging |
| `TitleField.qml` | The sheet title in the header, edited in place |
| `HeaderLabel.qml` | Clickable header settings (paper type, size) with refusal notices |
| `BinderClip.qml` | The drawn binder clip handle (vector Shapes) |
| `ToolIsland.qml` | The toolbar: layout in either orientation, grip, buttons, export feedback |
| `ToolButton.qml` | Toolbar icon button with themed states |
| `Tooltip.qml` | The shared tooltip (chip plus keycap) used everywhere |
| `SettingsPanel.qml` | The settings card; `SettingSwitch.qml` and `SettingChoice.qml` are its controls |
| `OmarchyTheme.qml` | Maps the active Omarchy theme onto the toolbar, settings and tooltips |
| `ClassicTheme.qml` | Field Notes' own look; same properties as `OmarchyTheme.qml` |
| `DocumentModel.js` | Sheets, objects, papers, sizes, titles, settings; sanitizing and serializing |
| `History.js` | Per-sheet undo/redo |
| `Notebook.js` | The list of sheets and the open one; adding, switching, dropping blank sheets |
| `Geometry.js` | Eraser cuts, hit testing, stroke simplification and mouse smoothing |
| `Layout.js` | Board scaling, toolbar docking geometry, nearest-side snapping |
| `tests/` | Node tests: unit tests for the JS modules and contract tests for the QML |

## How it fits together

**State lives in `Panel.qml`.** It holds the notebook (one undo history per sheet), the
current tool, pen width, toolbar side, board position and settings. Components below it only
display what they are given and report what the user did; the panel applies the change.

**Documents are immutable.** Every edit in `DocumentModel.js` returns a new document that
shares untouched objects with the old one, and an edit that changes nothing returns the same
document. That makes undo cheap (history stores references, not copies) and lets the
panel skip saves and undo steps for no-op edits. All notebook changes go through
`Panel.setNotebook()`, which also keeps the paper in place on screen when the open sheet's
size changes.

**Gestures are one undo step.** `PaperSurface` keeps an uncommitted `draftDocument` while
an erase drag, a move or a new note is in progress, and commits it once when the gesture
ends. Pen strokes draw on a separate "wet" canvas and are committed on release, after mouse
input is smoothed (`Geometry.smoothStroke`) and simplified (`Geometry.simplifyStroke`).
The same smoothing runs for the live stroke, once per frame, so nothing moves on release.

**Basic pressure.** `MouseArea` owns mouse drawing and the existing editing tools; the passive
`PointHandler` owns native pen drawing, including pens without pressure. Synthetic mouse
events from that pen cannot start a second stroke. `acceptedButtons: Qt.NoButton` prevents
those synthetic events from resetting the authentic handler point. Only devices advertising
Qt's `Pressure` capability (excluding mice and touchpads) supply pressure samples. Hover
never starts ink; a release finishes at the last contact sample, not its often-zero pressure
or displaced coordinates. Pressure changes of at least 0.02 are captured even without
movement. Live capture is bounded to 8,192 samples; a full stroke asks the user to lift.

Pressure affects width only: `selectedWidth * (0.30 + 0.80 * Math.pow(pressure, 1.8))`.
The range is 30–110% of the nominal selected width: finer light contact and a modest
firm-press boost, while retaining the gentle 1.8 response. Strokes without pressure
metadata stay at the nominal width. Sheet bounds and selection/eraser envelopes include
the boosted maximum; sizing regressions keep the model and renderer consistent. There
is no opacity accumulation, tilt, or brush engine.
Pressure-aware simplification preserves width changes along straight lines and uses a
linear work budget, retaining the original bounded samples if RDP would become quadratic.
The renderer
flattens the existing midpoint quadratics with bounded subdivision and fills tapered
segments with round caps as one path (consistent winding avoids holes at overlapping caps).
Wet ink, committed ink, selection, and PNG capture use the same renderer. Stationary
pressure changes retain their caps so easing off cannot shrink an already-drawn dot.

**Keyboard focus.** Shortcuts are handled on the panel's focus scope. Focus is handed back
with `Panel.focusKeys()`, which focuses a plain `keySink` item; that also commits any note
or title being edited (they commit when they lose focus).

**Layout.** The board (paper, toolbar, clip, settings card) is one item that scales down
on small screens. `Layout.dock()` gives the board size and the paper and toolbar positions
for each sheet size and toolbar side. Only the paper, toolbar, clip and open settings card
take input; the window's input mask makes everything else click-through. Stacking on the
board: paper, then clip (`z: 20`), toolbar (`z: 30`, so tooltips draw over everything), and
settings card (`z: 40`).

**Theming.** Components take a `theme` object and never hard-code colours.
`OmarchyTheme.qml` reads the shell's own theme state (`qs.Commons` `Color` and `Style`),
which the shell updates on every theme switch, so bindings follow it live. It mirrors the
shell's `Button` state order (pressed, hover, selected) and accepts a `[field-notes]`
override section. `ClassicTheme.qml` has the same properties with fixed values; the panel
hands components one or the other depending on the **Use Omarchy theme** setting. A test
keeps the two property lists identical.

**Export.** `PaperSurface.exportImage()` hides screen-only chrome (save status, selection,
hover outlines), waits a frame, captures the unrotated sheet with `grabToImage`, and saves a
PNG. The panel then runs `wl-copy` with either the path or the image; file paths are
always passed as arguments, never spliced into a shell command.

## Saved file

`$XDG_STATE_HOME/field-notes/notes.json` (default `~/.local/state/field-notes/notes.json`):

```json
{
  "schemaVersion": 2,
  "current": 0,
  "sheets": [
    {
      "title": "Meeting notes",
      "size": "medium",
      "paper": "graph",
      "objects": [
        { "id": "stroke-1", "type": "stroke", "color": "graphite", "width": 2.5,
          "points": [[90, 140], [200, 110]] },
        { "id": "text-1", "type": "text", "x": 90, "y": 200, "width": 220, "height": 40,
          "text": "Call back", "size": 16 }
      ]
    }
  ],
  "ui": { "tool": "pen", "penWidth": 2.5, "toolbar": "right", "boardX": 840, "boardY": 390,
          "boards": { "DP-1": { "x": 840, "y": 390 }, "HDMI-A-1": { "x": 300, "y": 120 } } },
  "settings": { "theme": true, "tilt": true, "smoothing": "medium", "eraser": "medium",
                "clipboard": "path", "exportDir": "" }
}
```

- Coordinates are in the sheet's own space: small 520×380, medium 760×560, large 1040×760.
- A stroke point is `[x, y]` for fixed width, or `[x, y, pressure]` for pressure input.
  Pressure is a finite number clamped to 0–1 and rounded to three decimal places. Missing
  or malformed pressure keeps legacy strokes fixed-width; within a mixed pressure stroke,
  missing samples represent firm contact. A valid zero means light contact, not missing
  data. Moving preserves pressure; eraser cut points interpolate it. This is an
  additive extension to schema 2 (and the schema 1 reader), not a schema bump. Old notes
  remain unchanged. Versions predating pressure support display these strokes at constant
  width and **discard pressure if they save the notebook again**.
- `ui.boards` is where the board was left on each monitor, by output name, in that monitor's
  pixels (at most 16; anything else is dropped). `boardX`/`boardY` repeat the open monitor's
  place for older versions, and a file with only those uses them for the first monitor opened.
- Loading treats the file as untrusted (`DocumentModel.sanitizeNotebook`): unknown values
  fall back to defaults, coordinates are clamped to the sheet, IDs are made unique, and
  limits apply — 32 sheets, 4096 objects per sheet, 8192 points per stroke, 250,000 points
  in total, 4096 characters per note, 60 per title, 512 per export folder.
- Editing is held to every one of those limits (`DocumentModel.overLimits`, checked by
  `fitsLimits` in `Panel.qml`): a stroke, eraser cut (which can add objects), undo, redo or
  scripted stroke that would go past one is refused, so a saved file always loads in full. A
  test drives random edits, eraser splits included, and checks that any notebook within the
  limits reloads unchanged.
- When loading does have to trim (`trimmed` from `sanitizeNotebook`), or the file is
  unreadable, it is copied aside first (`notes.json.trimmed` or `.corrupt`). Saving waits
  for the copy and goes ahead only once `cp` exits 0; a failed copy, or one that never
  reports back within 10 seconds, leaves the file untouched and the status at `NOT SAVED`.
- Blank sheets are dropped unless they are the open one.
- Version 1 files (a single sheet with `objects` at the top level) load as one sheet; files
  without `settings` get the defaults. Older versions of Field Notes cannot read version 2.
- Nothing is written until the existing file has been read (`stateReady`), so a slow or
  failed load can never overwrite notes with an empty page. Writes are atomic. A file that
  is not a Field Notes file at all is copied to `notes.json.corrupt` first.
- Reads fail closed. Before the file is opened, a check (`stateCheck` in `Panel.qml`) requires a
  regular file of at most 16 MiB: a symlink, pipe, folder or oversized file is never read,
  nothing is written over it, and the status shows `NOT SAVED` with the reason in the shell
  log. The check runs just before the read, so a same-user process could still swap the file
  in between; anything with that access can already change the user's files.
- The `.corrupt` backup is copied without following symlinks and replaces any existing
  backup instead of writing through it. `tests/state-safety.test.js` runs both commands
  against real files.

## Testing

```sh
node --test tests/*.test.js     # unit and contract tests (Node 18+)
qmlformat *.qml > /dev/null     # QML syntax check
omarchy plugin validate .       # manifest check
```

- **Unit tests** cover the JavaScript modules: geometry, the document model (including
  sanitizing hostile input), history, the notebook and layout.
- **Contract tests** (`tests/contract.test.js`) read the QML source and pin down behaviour
  that is easy to break silently: wiring between components, focus handling, input masks,
  stacking order, theme coverage. Each assertion's message says what it protects.

### Optional pressure input/render smoke test

With Qt 6 Quick/Test development packages, `pkg-config`, and a C++ compiler available:

```sh
c++ -std=c++17 -fPIC tests/pressure-input.cpp -o /tmp/field-notes-pressure-input \
  $(pkg-config --cflags --libs Qt6Quick Qt6Test)
QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software \
  /tmp/field-notes-pressure-input "$PWD/tests/PressureHarness.qml"
```

This runs the real `PaperSurface.qml` in an isolated window with synthetic native tablet
and mouse events. It checks pressure capture, duplicate mouse suppression, live/committed
pixels, connected tapered segments, PNG export, stationary pressure, zero versus absent
pressure, pen fallback, transformed coordinates, cancellation, point limits, and ordinary
mouse drawing. The fixture disables shadows for Qt's software renderer; it does not load
Quickshell, read/write notes, or change the running desktop. This optional C++ test is not
an application build step or a runtime dependency. Physical tablet feel and compositor
input delivery still need a hands-on check on the target desktop.

### Rendering components without the shell

Most components render outside Quickshell with `qml6` and an offscreen platform, which is
the quickest way to check a visual change:

```sh
QT_QPA_PLATFORM=offscreen qml6 Harness.qml
```

A harness is a small `Window` that instantiates the component and saves
`contentItem.grabToImage(...)` to a PNG. Two limits apply offscreen:

- `MultiEffect` layers (the paper, toolbar and settings shadows) do not render — use copies
  of the files with `layer.enabled: false`.
- `qs.Commons` is not available, so `OmarchyTheme.qml` cannot load; pass `ClassicTheme`, or
  a stand-in object with the same properties.

`PanelWindow` needs the real shell, so the full panel is checked live.

### Trying changes live

Clone the repository and link it into the plugin folder once:

```sh
git clone https://github.com/OldJobobo/field-notes.git ~/Projects/field-notes
ln -s ~/Projects/field-notes ~/.config/omarchy/plugins/jobo.field-notes
omarchy-shell shell rescanPlugins
omarchy plugin enable jobo.field-notes
```

After changing QML, restart the shell with `omarchy-restart-shell`. A rescan reloads the
entry points, but QML files they use can stay cached, so changes there may not appear
until a restart. Then:

```sh
omarchy-shell shell toggle jobo.field-notes '{}'                    # open or close
omarchy-shell shell summon jobo.field-notes '{"settings":true}'     # open at settings
journalctl --user -t omarchy-shell -f                               # shell log
omarchy-shell jobo.field-notes status | jq                          # the open sheet, as scripts see it
```

The scripting interface (the `IpcHandler` at the end of `Panel.qml`, documented in the
README) is the quickest way to set up a sheet for a live check. Strokes from `draw` play
through their own wet layer in `PaperSurface.qml` (`scriptWet`), driven by a
`FrameAnimation`, and are committed exactly as given.

Live checks worth doing after larger changes: draw a fast stroke and erase across it; type,
move and delete a note; switch sheets, papers and sizes; dock the toolbar on each side and
hover its buttons; copy a sheet both ways and paste it; switch Omarchy themes with settings
open; and restart the shell to confirm everything comes back.

## Releasing

1. Run the three checks above and the live checks.
2. Bump `version` in `manifest.json`. It is the only copy: the paper footer and settings read
   it at runtime. Update the version in the README's sheet diagram to match (a test checks).
3. Update `README.md` for anything users will notice.
4. Commit, push, then tag that commit `v<version>` and publish a GitHub release.
