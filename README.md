# Field Notes

A sheet of paper that floats above your Omarchy desktop. Sketch with the mouse or a pen
tablet, type notes, keep several sheets, and copy any sheet as an image with one key —
ready to paste into a chat, an issue or an AI agent.

- **Draw and write** — smooth pencil strokes (mouse wobble is steadied, tablets stay exact),
  a precise eraser, typed notes, and move-anything selection with full undo.
- **A small notebook** — up to 32 sheets, each with its own title, paper (graph, dots,
  ruled or plain) and size.
- **Share in one key** — `Ctrl+C` saves the sheet as a PNG and copies its path;
  `Ctrl+Shift+C` copies the image itself.
- **Fits your desktop** — follows your Omarchy theme live, docks its toolbar to any side,
  and stays out of the way: everything around the paper is click-through.
- **Never loses your notes** — saved automatically to a local file a moment after every change.

## Requirements

- Omarchy with the Quattro shell (`omarchy-shell`)
- `wl-clipboard` for copying, and GLib's `gio` (or `xdg-utils`) for **Open** in settings — all ship with Omarchy
- A Nerd Font for the toolbar icons — Omarchy ships JetBrainsMono Nerd Font

## Install

```sh
omarchy plugin add https://github.com/OldJobobo/field-notes.git
omarchy plugin enable jobo.field-notes
```

Omarchy adds plugins disabled so you can read the code first; enabling puts the Field Notes
icon on the right of your bar.

To open it from the keyboard, add a binding to `~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER + SHIFT + N", "Field Notes", { panel = "jobo.field-notes" })
```

<details>
<summary>Installing from a local checkout</summary>

```sh
git clone https://github.com/OldJobobo/field-notes.git ~/.config/omarchy/plugins/jobo.field-notes
omarchy-shell shell rescanPlugins
omarchy plugin enable jobo.field-notes
```

</details>

## Getting started

Click the bar icon (or your keybinding) to open your notes; press it again, or `Esc`, to put
them away. Right-click the icon to open straight to settings.

The pen is ready as soon as the paper opens — just draw. Press `T` and click the paper to
type a note, `E` to erase, and `Ctrl+Z` if you change your mind. Everything you do is saved
automatically.

## The sheet

```text
         ┌──── binder clip: drag to move the board
 ┌───────┴──────────────────────────────────────────────────┐
 │ MEETING NOTES        SHEET 02 OF 03 / GRAPH 16 / MEDIUM  │ ← title · sheet · paper · size
 │                                                          │
 │                your drawings and notes                   │
 │                                                          │
 │ FIELD NOTES v0.1.0                                 SAVED │ ← version · save status
 └──────────────────────────────────────────────────────────┘
```

Everything printed in the header is also a control:

- **Title** — click it (or press `F2`) to name the sheet. `Enter` keeps the name, `Esc`
  cancels. Untitled sheets show `UNTITLED`.
- **Paper** — click to cycle **GRAPH 16 → DOTS 16 → RULED 24 → PLAIN** (or press `G`).
- **Size** — click to cycle **SMALL → MEDIUM → LARGE** (or press `S`). Your drawing keeps its
  place and size, so a sheet never shrinks below what's on it; the label tells you when no
  smaller size fits.

The status in the corner reads `SAVED` once your latest change is on disk.

## The toolbar

| Button | What it does | Key |
| --- | --- | --- |
| Grip (two lines) | Drag toward any side of the paper to dock the toolbar there | |
| Select | Pick up a stroke or note to move or delete it | `V` |
| Pen | Draw | `P` or `B` |
| Erase | Cut through strokes; removes notes it touches | `E` |
| Text | Click the paper to type a note | `T` |
| Undo / Redo | Step back and forward through your changes | `Ctrl+Z` / `Ctrl+Y` |
| ‹ 2/3 › | Previous and next sheet; on the last sheet, › becomes **+** for a new one | `PgUp` / `PgDn`, `N` |
| Width (dot) | Cycle four pen widths | `[` `]` for finer steps |
| Copy | Save the sheet as a PNG and copy its path (or the image — see Settings) | `Ctrl+C` |
| Clear | Clear the sheet — click twice to confirm; undoable | |
| Settings | Open settings | `Ctrl+,` |
| Close | Put the notes away | `Esc` |

Hover any button for its name and shortcut. Dimmed buttons have nothing to do right now.

## Drawing and writing

- **Pen** — strokes from a mouse or touchpad are steadied as you draw: pixel stair-steps
  and hand wobble are smoothed away while sharp corners and the stroke's ends stay exactly
  where you put them. Pen tablets are left exactly as drawn. The strength is adjustable in
  settings.
- **Eraser** — cuts strokes cleanly at the edge of the eraser ring, however fast you move,
  and removes any note it touches. One drag is one undo step.
- **Notes** — with Text, click empty paper and type. `Enter` starts a new line,
  `Ctrl+Enter` or clicking elsewhere finishes, and `Esc` cancels the edit. Click an existing
  note to edit it; an emptied note disappears.
- **Select** — click a stroke or note to select it, drag to move it, double-click a note to
  edit it, and press `Delete` or `Backspace` to remove it.
- **Undo** — `Ctrl+Z` undoes and `Ctrl+Y` (or `Ctrl+Shift+Z`) redoes, separately for each
  sheet. Undo history lasts until the shell restarts.

## Sheets

- **New sheet** — **+** at the end of the sheet buttons, or `N`. It starts with the same paper
  and size as the sheet you were on.
- **Switch** — **‹ ›** or `PgUp` / `PgDn`. A second sheet peeks out from under the page once
  you have more than one.
- **Delete** — clear a sheet and switch away: a sheet with nothing drawn, written or named
  on it is removed when you leave it. (The same rule stops blank sheets piling up.)

## Sharing a sheet

Press `Ctrl+C` (or the copy button). Field Notes saves the sheet as a PNG and puts its path
on the clipboard, ready to paste into a terminal, an editor or an AI agent:

```text
~/Pictures/field-notes/meeting-notes-20261015-091500.png
```

`Ctrl+Shift+C` copies the **image itself** instead, for pasting straight into a chat. In
settings you can swap which key does which.

The image is the sheet as it would print — straight, with its title, paper and notes, but
without the save status or any selection. Every copy is a new file named after the sheet's
title (or `sheet-02-…` if untitled), so a path you pasted earlier always shows the sheet as
it was then. Files go to `~/Pictures/field-notes/` unless you choose another folder in
settings.

## Moving things around

- **Move the board** — drag the binder clip, or use the arrow keys (hold `Shift` for bigger
  steps). `Home` centres it.
- **Dock the toolbar** — drag its grip toward any side of the paper; it snaps there as you
  drag and lies flat along the top and bottom. Or pick a side in settings.

Field Notes remembers where you left the board and toolbar. On small screens the whole
board scales down to fit.

## Settings

Open settings with the gear button, `Ctrl+,`, or by right-clicking the bar icon. Changes
apply immediately; `Esc` or clicking the dimmed paper closes them.

| Setting | Options | Default |
| --- | --- | --- |
| **Use Omarchy theme** | On: follow your Omarchy theme · Off: Field Notes' own warm graphite look | On |
| **Toolbar position** | Left · Top · Bottom · Right | Right |
| **Tilted paper** | A slight angle, like a sheet resting on a desk | On |
| **Mouse smoothing** | Off · Light · Medium · Strong | Medium |
| **Eraser size** | Small · Medium · Large | Medium |
| **Ctrl+C copies** | File path · Image (`Ctrl+Shift+C` does the other) | File path |
| **Export folder** | Any folder; `~` works; empty uses `~/Pictures/field-notes` | Empty |

**About** shows where your notes are saved, with buttons to **Center board** and
**Reset settings**.

## Theming

With **Use Omarchy theme** on, the toolbar, settings and tooltips take their colours from
your current Omarchy theme and change the moment you switch themes. They match the rest of
your shell: the toolbar uses the theme's popup surface, buttons use its hover, selected and
pressed states, tooltips use its tooltip colours, and corners follow your window rounding.
The paper always stays paper-coloured.

To fine-tune the toolbar for one theme — or for every theme, in
`~/.config/omarchy/shell.toml` — add a `[field-notes]` section. Colours can be hex values or
palette roles (`foreground`, `background`, `accent`, `urgent`):

```toml
[field-notes]
background = "#1e4147"
background-alpha = 0.94
border = "accent"
border-alpha = 0.6
border-width = 1
text = "foreground"
accent = "accent"
danger = "urgent"
```

Every key is optional; anything you leave out comes from the theme.

## Your notes

Your sheets, settings and layout are saved to a single file on your computer — nothing is
sent anywhere:

```text
~/.local/state/field-notes/notes.json      ($XDG_STATE_HOME/field-notes/ if set)
```

- Saving happens about half a second after each change, and again when the notes close.
  Each save replaces the file in one step, so a crash can't leave it half-written.
- To back up your notes, copy that file. To start over, close Field Notes and move it aside.
- If the file is ever unreadable, Field Notes keeps a copy as `notes.json.corrupt` before
  saving a fresh one, and loads whatever it safely can.

## Troubleshooting

**The bar icon or panel doesn't appear.** Check `omarchy plugin list` shows
`jobo.field-notes` as enabled, then run `omarchy plugin enable jobo.field-notes`.

**Nothing is copied.** Copying needs `wl-copy` (from `wl-clipboard`). If an image paste
does nothing, the app you're pasting into may not accept images — paste the path instead.

**The status says `NOT SAVED`.** Field Notes can't write to its notes folder. Check that
`~/.local/state/field-notes/` exists and is yours.

**My tablet strokes look smoothed.** Your tablet is reporting itself as a mouse. Set
**Mouse smoothing** to **Off** in settings.

**A sheet won't get smaller.** Something on it reaches past the smaller size. Move or erase
it first.

**Open in settings does nothing.** Field Notes opens the folder with your default file manager
(`xdg-mime query default inode/directory`). Check that app opens folders on its own.

**A sheet disappeared.** Sheets with nothing drawn, written or named on them are removed when
you switch away. Give a sheet a title to keep it while it's empty.

## Uninstall

```sh
omarchy plugin remove jobo.field-notes
```

Your notes stay in `~/.local/state/field-notes/` and your exports in
`~/Pictures/field-notes/`; delete those folders if you don't want them.

## Development

See [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) for how Field Notes is built, the saved-file
format, and how to test and try changes.

## License

MIT — see [LICENSE](LICENSE).
