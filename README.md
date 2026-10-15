# Field Notes

A Quickshell/Omarchy shell plugin with a floating sheet of graph paper for freehand drawing and typed notes. The panel and bar-widget entry points are declared in `manifest.json`.

## Controls

- `V`: select; `P` / `B`: pen; `E`: eraser; `T`: text. Toolbar buttons show their shortcut.
- Pen: mouse and touchpad strokes are steadied as you draw (pixel stair-steps and hand wobble are averaged out, while sharp corners and the stroke ends stay exactly where you put them); tablet pens are kept exactly as drawn. Strokes are simplified when committed. The width button cycles four widths; `[` / `]` fine-tune.
- Eraser: cuts the stroke exactly at the ring's edge; a note it touches is removed. One drag is one undo step.
- Text: click empty paper to start a note, or click an existing note to edit it. Empty notes are discarded; `Escape` cancels (removing a note that was never committed); `Ctrl+Enter` or clicking away commits.
- Select: click a stroke or note to select it, drag to move it, double-click a note to edit, `Delete` / `Backspace` to remove. `Escape` deselects.
- `Ctrl+Z`: undo; `Ctrl+Shift+Z` / `Ctrl+Y`: redo. `Escape` with nothing to cancel closes the panel.
- Drag the binder clip or use arrow keys to move the board. Hold Shift for larger steps; Home centers it.
- Click Clear twice within 2.5 seconds to clear the sheet (undoable).
- Sheets: the toolbar's ‹ › buttons (or `Page Up` / `Page Down`) switch sheets; on the last sheet › becomes + (or press `N`) for a new one. The paper header shows which sheet is open. Each sheet keeps its own undo history. A sheet left blank is removed when you switch away, so to delete a sheet, clear it and switch away. Up to 32 sheets.
- Toolbar: drag its grip (the two lines at its end) toward any side of the paper to dock it there; it lies horizontally on the top and bottom. Tooltips open toward the paper.
- Paper: click the paper name in the sheet header (GRAPH 16, DOTS 16, RULED 24, PLAIN) or press `G` to switch the open sheet to the next paper. Each sheet keeps its own paper, new sheets start with the paper of the sheet you were on, and a paper change can be undone.

The complete board scales down to fit smaller screens. Drawing coordinates remain in the original 760×560 paper space, and transparent gaps remain click-through.

## Saved notes

All sheets with their paper types, the open sheet, selected tool, pen width, toolbar side and board position autosave atomically 500 ms after a change, and are flushed when the panel closes or the shell shuts down. Undo history is session-only. The status label on the paper shows `EDITED`, `SAVED` or `NOT SAVED`.

State is stored at:

```text
${XDG_STATE_HOME:-$HOME/.local/state}/field-notes/notes.json
```

Nothing is written until the existing file has been read. Single-sheet files from earlier versions load as the first sheet. Loaded data is sanitized (schema version, finite clamped coordinates, unique IDs, object/point/text limits); invalid objects are dropped. A file that is not a Field Notes document at all is copied to `notes.json.corrupt` before the next save replaces it. If the file exists but cannot be read, the sheet works but is not saved.

## Development checks

```sh
node --test tests/*.test.js
qmlformat *.qml >/dev/null
omarchy plugin validate .
```

The tests require only Node.js. Desktop-level verification still requires loading the plugin in a compatible Omarchy shell: draw a long fast stroke and erase its midpoint, restart the shell to check restoration, then use a small display to check toolbar access, dragging, text editing and click-through regions.
