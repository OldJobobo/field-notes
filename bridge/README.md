# Phone bridge

`fieldnotes-bridge` links Android devices to Field Notes. Field Notes starts it while
**Settings › Draw from a phone** is on (`phoneBridge` in `Panel.qml`); you can also run it by hand
(`python3 bridge/fieldnotes-bridge`, Ctrl+C stops it) as long as the setting is off.
Standard library only. The Android app it talks to is in `../android`.

```text
 phone                                  desktop
┌────────────────────┐  adb reverse   ┌─────────────────────┐
│ Field Notes app    │ ─────────────▶ │ fieldnotes-bridge   │──▶ omarchy-shell jobo.field-notes draw, ink, erase …
│ @fieldnotes-bridge │                │ 127.0.0.1:7741      │◀── ~/.local/state/field-notes/notes.json
└────────────────────┘ ◀─ the sheet ─ └─────────────────────┘
```

- Every 3 s it lists the devices adb knows, reconnects the Wi-Fi ones it has seen (addresses are kept in
  `~/.local/state/fieldnotes-bridge/wireless`), and keeps one `adb reverse localabstract:fieldnotes-bridge tcp:7741`
  per physical device: USB first, Wi-Fi when the cable comes out, never flip-flopping.
- A device must open with the pairing token (`~/.local/state/fieldnotes-bridge/token`, made on first use;
  `--token` prints it, `--pair` hands it to the app on each device, which opens it).
- It sends the open sheet back from the saved notes file, once the plugin reports `SAVED` with nothing
  left to draw, so the device sees every command reflected.
- Options: `--adb PATH` (default: `adb` on `PATH`, `$ANDROID_HOME`, `~/Android/Sdk`), `--shell`, `--port`,
  `--exit-with-stdin` (exit when stdin closes; Field Notes uses it so the bridge never outlives the shell).
- It prints `status: <text>` whenever its state changes, which Field Notes shows under the switch. Exit code 2
  means the port is taken.

## Protocol

One JSON object per line. Phone to bridge:

| `t` | Fields | Effect |
| --- | --- | --- |
| `hello` | `v: 1`, `token` | must come first; a wrong token gets `unpaired` |
| `stroke` | `id`, `points: [x0, y0, x1, y1, …]` in sheet units, on a 0.1 grid | `draw "<points>" 0` |
| `ink` | `points`, the points added since the last `ink` (none clears it) | `ink "<all points so far>"`; no `id` |
| `erase` | `points`, `end`; `id` when `end` is true | `erase "<points>" 0`, and `… 1` to finish; each call starts from the last point of the one before |
| `width` | `id`, `value` (1 to 12) | `setPenWidth` |
| `clear`, `new` | `id` | `clear`, `newSheet` |
| `select` | `id`, `sheet` (from 1) | `selectSheet` |
| `title` | `id`, `text` (at most 60 characters) | `setTitle` |
| `note` | `id`, `x`, `y`, `text` | `addNote` (a newline becomes `\n`) |
| `undo`, `redo`, `show` | `id` | `undo`, `redo`, `open` |

A line the bridge cannot use gets an `error` if it has an `id`, and is ignored if not.

Bridge to phone:

| `t` | Fields |
| --- | --- |
| `sheet` | `settled` (every command up to this id is reflected), `sheet`, `sheets`, `title`, `paper`, `width`, `height`, `penWidth`, `objects` (strokes and typed notes) |
| `desk` | `ok`, `open`, `saved`, `message`; every 2 s, so it doubles as a heartbeat |
| `error` | `id` (or null), `message` |
| `unpaired` | sent before the bridge closes a connection with the wrong token |

`testdata/` holds the fixtures its tests check, and the Android app's tests check the same files.

## Tests

```sh
python3 -m unittest discover -s bridge
```

They run the bridge against a fake `omarchy-shell` and a fake `adb`, never the real ones.
