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
  "ui": { "tool": "pen", "penWidth": 2.5, "toolbar": "right", "boardX": 840, "boardY": 390 },
  "settings": { "theme": true, "tilt": true, "smoothing": "medium", "eraser": "medium",
                "clipboard": "path", "exportDir": "" }
}
```

- Coordinates are in the sheet's own space: small 520×380, medium 760×560, large 1040×760.
- Loading treats the file as untrusted (`DocumentModel.sanitizeNotebook`): unknown values
  fall back to defaults, coordinates are clamped to the sheet, IDs are made unique, and
  limits apply — 32 sheets, 4096 objects per sheet, 8192 points per stroke, 250,000 points
  in total, 4096 characters per note, 60 per title, 512 per export folder.
- Blank sheets are dropped unless they are the open one.
- Version 1 files (a single sheet with `objects` at the top level) load as one sheet; files
  without `settings` get the defaults. Older versions of Field Notes cannot read version 2.
- Nothing is written until the existing file has been read (`stateReady`), so a slow or
  failed load can never overwrite notes with an empty page. Writes are atomic. A file that
  is not a Field Notes file at all is copied to `notes.json.corrupt` first.

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

Link your checkout into the plugin folder once:

```sh
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
```

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
