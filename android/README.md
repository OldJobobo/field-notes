# Field Notes for Android

The companion app for [Field Notes](../README.md#drawing-from-a-phone). Run the commands below in this folder (`android/`).

Draw on an Android phone or tablet, and each stroke lands on the Field Notes
sheet on your Omarchy desktop. The phone shows the sheet that is open on the desktop (its paper, title, ink and
typed notes), so you always draw in context. Undo and Redo on the phone act on the desktop sheet.

This is the first, lean iteration: a debug build you install over adb on your own devices.

## How it works

```text
 phone                                        desktop
┌──────────────────────┐   adb (USB or      ┌──────────────────────────┐
│ Field Notes app      │   Wireless         │ Field Notes' phone bridge│──▶ omarchy-shell jobo.field-notes draw …
│ LocalSocket          │──▶ debugging) ────▶│ 127.0.0.1:7741           │
│ @fieldnotes-bridge   │◀── the open sheet ─│                          │◀── ~/.local/state/field-notes/notes.json
└──────────────────────┘                    └──────────────────────────┘
```

- The **bridge** (`../bridge`, Python, standard library only) ships with the Field Notes plugin and runs on the desktop while
  **Settings › Draw from a phone** is on. It links every phone adb can see with
  `adb reverse localabstract:fieldnotes-bridge tcp:7741`. That puts the phone's end on a local socket, not on the
  phone's Wi-Fi.
- While the pen moves, the app streams the stroke and the bridge shows it on the desktop paper; when you lift the
  pen it hands the whole stroke to Field Notes' own scripting interface (`omarchy-shell jobo.field-notes draw`). It
  becomes an ordinary stroke: saved, undoable and exported like any other.
- The bridge watches Field Notes' saved file and sends the open sheet back to the phone. Field Notes saves about
  half a second after a change, so desktop edits reach the phone in under a second.

Field Notes must be installed and enabled (`omarchy plugin enable jobo.field-notes`). `../bridge/README.md` has the details.

> **Build from a clone, not from the installed plugin folder.** Omarchy watches an installed plugin and
> reloads it on every file change, and a Gradle build writes thousands of files. Clone the repository
> somewhere else (such as `~/Projects/field-notes`) to work on the app; the bridge it pairs with runs from
> whichever copy of the plugin is installed.

## Requirements

- Omarchy with this version of Field Notes (it has **Draw from a phone** in its settings), and Python 3 (Omarchy has it).
- The Android SDK in `~/Android/Sdk` (platform 37 and platform-tools), and JDK 17. `mise.toml` pins
  `java = "temurin-17"` for this folder.
- An Android phone or tablet running Android 8.0 or newer, with developer options turned on. Wireless debugging
  needs Android 11 or newer.

The bridge and the make targets find `adb` in `~/Android/Sdk/platform-tools`. For commands you type yourself, put it
on your PATH:

```sh
export PATH="$HOME/Android/Sdk/platform-tools:$PATH"
```

## First run (USB)

1. On the phone, turn on developer options: **Settings › About phone**, tap **Build number** seven times (on
   Samsung it is under **Software information**). Then turn on **Developer options › USB debugging**.
2. Plug the phone in and unlock it. Accept **Allow USB debugging?**, ticking **Always allow from this computer**.
   `adb devices` should now list the phone as `device`. If it says `unauthorized`, the prompt is still waiting on
   the phone.
3. In Field Notes' settings (the gear button, or `Ctrl+,`), switch on **Draw from a phone**. The line under the switch
   should say `Waiting for a phone`, then `Linked: <your phone>`.
4. Build, install and open the app:

   ```sh
   make run
   ```

   Watch the phone during the first install. Some phones ask to scan the app (Play Protect), and Xiaomi phones need
   **Install via USB** turned on in developer options.
5. The phone shows your open sheet, and the footer says **LIVE**. Open Field Notes on the desktop (its bar icon, or
   your keybinding) to watch your strokes arrive, or tap **Show on desktop** on the phone.

`make run` also pairs the app with this desktop: it gives the app the bridge's token (`fieldnotes-bridge --pair`), which the app keeps. After that you
can open the app from the launcher.

## Wireless debugging

Pair once, with the phone and the desktop on the same Wi-Fi:

1. On the phone: **Developer options › Wireless debugging** on, then **Pair device with pairing code**.
2. On the desktop: `adb pair <ip>:<pairing port>` and type the six-digit code.
3. Run `adb connect <ip>:<port>` once. Use the port shown on the Wireless debugging screen itself, not the pairing
   port.

From then on the bridge keeps that connection up by itself and links the phone over Wi-Fi exactly as over USB. Pull
the USB cable out and the link moves to Wi-Fi within a few seconds; the app reconnects on its own. The port changes
when Wireless debugging is switched off and on, or the phone restarts: run `adb connect` again then. If the phone
shows up twice in `adb devices` (USB and Wi-Fi), that's fine; `make run` asks for `ANDROID_SERIAL=<serial>` only if
you want just one of them.

## Using it

- **Draw** with a finger or a stylus. Strokes start only on the page, so a swipe from the screen edge (to bring
  back the system bars) never draws. Once a stylus touches the screen, fingers stop drawing until the app is
  reopened, so a resting palm leaves no marks.
  The desktop shows the stroke as you draw it, a moment behind the pen, and saves it when you lift.
- **The toolbar** (right of the page on a wide screen, below it on a tall one; it scrolls on a small screen) names
  every button:

  | Button | What it does |
  | --- | --- |
  | **Pen**, **Eraser**, **Text** | What a touch on the page does. The eraser works like the desktop's: drag across ink to cut it away (the sheet shows the result a moment after you lift). With **Text**, tap the page, type in the box that opens, and the note lands where you tapped. |
  | **Width** | Steps the pen width through 1.5, 2.5, 4 and 7. The width belongs to the desktop sheet's pen. |
  | **Undo** / **Redo** | Step through the desktop sheet's history, the same one `Ctrl+Z` / `Ctrl+Y` use there. |
  | **Clear sheet** | After a confirmation, empties the sheet. Undo on the desktop brings it back. |
  | **Previous** / **Next**, **New sheet** | Switch sheets (the counter shows where you are) or add one after the last. |
  | **Show on desktop** | Opens the notes on the desktop, so you can see the sheet there. Strokes land whether the notes are open or put away. |

- **Title**: tap the underlined title in the sheet's header, type a name in the box that opens and press OK. A tap on
  the title never draws.
- **Footer status** (bottom right of the sheet):

  | Status | Meaning |
  | --- | --- |
  | `LIVE` | linked; your strokes go to the desktop |
  | `LIVE · NOTES PUT AWAY` | linked; the desktop notes are closed, but strokes still land |
  | `OFFLINE` | no bridge reachable: is **Draw from a phone** on in Field Notes' settings, and is the phone listed by `adb devices`? |
  | `NOT PAIRED` | the app doesn't have this desktop's token: run `make run` once |
  | `FIELD NOTES NOT RUNNING` | the bridge can't reach Field Notes (is the plugin enabled? did the shell restart?) |
  | `DESKTOP LOADING` / `DESKTOP NOT SAVING` | Field Notes is starting, or can't save its file; drawing waits |

- For a long session at the phone, keep the desktop from locking: `omarchy toggle idle stay-awake`, and
  `omarchy toggle idle allow-idle` afterwards. Strokes from the phone don't count as activity on the desktop.

## Commands

| Command | What it does |
| --- | --- |
| `make bridge` | Run the bridge by hand, in the foreground, instead of the setting (switch the setting off first); Ctrl+C stops it |
| `make run` | Build, install on every connected phone (or `ANDROID_SERIAL`), pair and open the app |
| `make logs` | Follow the app's log (`adb logcat -s FieldNotes`) |
| `make test` | The bridge's tests, the app's JVM tests and lint |

## Limits of this version

- The phone can't change the paper or the size of a sheet, move or edit notes, or choose a pen colour (there is only
  one). Do those on the desktop.
- Erasing shows on the phone after you lift, not while you drag (the desktop shows it live).
- A stroke or an erase from the phone commits a note being typed on the desktop first, so the note is kept.
- Any app on the phone can open the bridge's socket while the bridge runs. Without the pairing token it is turned
  away before it can read or change anything.

## Reporting back

When something looks wrong, send:

- what you did and what you saw (a screenshot helps: `adb exec-out screencap -p > shot.png`);
- the status line under **Draw from a phone** in Field Notes' settings (or the terminal output of `make bridge`);
- `make logs` around the moment, or after a crash `adb logcat -b crash -d`;
- the phone's model and Android version: `adb shell getprop ro.product.model` and
  `adb shell getprop ro.build.version.release`;
- if the desktop side misbehaved: `journalctl --user -t omarchy-shell --since -10min`.

## Protocol

The app and the bridge exchange one JSON object per line; `../bridge/README.md` documents every message.
`../bridge/testdata/` holds the fixtures that this app's tests and the bridge's tests both check, so the two sides
can't drift apart.

## Development

- The bridge is `../bridge/fieldnotes-bridge`, with its tests.
- `app/`: the Android app, in Kotlin on platform APIs only (no AndroidX). `Sheet.kt` holds the protocol and the
  stroke geometry (tested on the JVM); `SheetView.kt` draws and takes touch; `Link.kt` is the socket;
  `MainActivity.kt` is the window and the toolbar.
- The toolbar icons are Material Symbols and Material Icons (Apache License 2.0), except the eraser and the width
  icons, which are drawn for this app (see the comment in each `res/drawable` file).
