const test = require("node:test")
const assert = require("node:assert/strict")
const fs = require("node:fs")
const os = require("node:os")
const path = require("node:path")
const { spawnSync } = require("node:child_process")

const panel = fs.readFileSync(path.resolve(__dirname, "../Panel.qml"), "utf8")

// The exact commands Panel.qml runs, taken from the QML source so the tests cannot drift.
function qmlString(literal) {
  return JSON.parse(`"${literal}"`)
}
const checkScript = qmlString(/id: stateCheck[\s\S]*?command: \["sh", "-c",\s*"((?:[^"\\]|\\.)*)"/.exec(panel)[1])
const backupArgs = /id: backupCorrupt[\s\S]*?command: \[([^\]]*)\]/.exec(panel)[1]
  .split(",").map(part => part.trim()).filter(part => part.startsWith('"')).map(part => JSON.parse(part))

function workspace() {
  return fs.mkdtempSync(path.join(os.tmpdir(), "field-notes-state-"))
}

function check(file, limit = 1024) {
  return spawnSync("sh", ["-c", checkScript, "field-notes", file, String(limit)]).status
}

test("the notes file is opened only when it is a regular file within the size limit", () => {
  const dir = workspace()
  const notes = path.join(dir, "notes.json")

  assert.equal(check(notes), 3, "a missing file means starting fresh")

  fs.writeFileSync(notes, '{"schemaVersion":2,"sheets":[]}')
  assert.equal(check(notes), 0, "a small regular file is safe to read")
  assert.equal(check(notes, 10), 6, "a file over the limit is refused")

  const target = path.join(dir, "elsewhere.json")
  fs.writeFileSync(target, "{}")
  const link = path.join(dir, "linked.json")
  fs.symlinkSync(target, link)
  assert.equal(check(link), 4, "a symlink is refused even when it points at a regular file")
  const dangling = path.join(dir, "dangling.json")
  fs.symlinkSync(path.join(dir, "missing"), dangling)
  assert.equal(check(dangling), 4, "a broken symlink is refused, not treated as missing")

  const folder = path.join(dir, "folder.json")
  fs.mkdirSync(folder)
  assert.equal(check(folder), 4, "a directory is refused")

  const fifo = path.join(dir, "pipe.json")
  if (spawnSync("mkfifo", [fifo]).status === 0)
    assert.equal(check(fifo), 4, "a named pipe is refused without blocking")

  fs.rmSync(dir, { recursive: true, force: true })
})

test("the panel reads and saves notes only after the check passes", () => {
  assert.match(panel, /path: root\.stateChecked \? root\.stateDir \+ "\/notes\.json" : ""/,
    "the file view must not open the path before the check")
  assert.match(panel, /id: prepareStateDir[\s\S]*?onExited: function\(exitCode\) \{\s*if \(exitCode === 0\) \{\s*stateCheck\.running = true/)
  assert.match(panel, /id: stateCheck[\s\S]*?if \(exitCode === 0 \|\| exitCode === 3\) \{\s*root\.stateChecked = true\s*return\s*\}[\s\S]*?root\.saveStatus = "NOT SAVED"/,
    "a refused file leaves notes unsaved rather than overwriting it")
  assert.match(panel, /readonly property int maxStateBytes: 16 \* 1024 \* 1024/)
})

test("the corrupt-file backup never writes through a symlink", () => {
  assert.deepEqual(backupArgs.slice(0, 4), ["cp", "--no-dereference", "--remove-destination", "--"])
  const trimmedArgs = /id: backupTrimmed[\s\S]*?command: \[([^\]]*)\]/.exec(panel)[1]
  assert.equal(trimmedArgs.replace(".trimmed", ".corrupt"), /id: backupCorrupt[\s\S]*?command: \[([^\]]*)\]/.exec(panel)[1],
    "the trimmed-file backup copies with exactly the same safe command")
  const dir = workspace()
  const notes = path.join(dir, "notes.json")
  const backup = notes + ".corrupt"
  const victim = path.join(dir, "victim.txt")
  fs.writeFileSync(notes, "not json")
  fs.writeFileSync(victim, "precious")
  fs.symlinkSync(victim, backup)

  const result = spawnSync(backupArgs[0], [...backupArgs.slice(1), notes, backup])
  assert.equal(result.status, 0, String(result.stderr))
  assert.equal(fs.readFileSync(victim, "utf8"), "precious", "the symlink target is untouched")
  assert.equal(fs.lstatSync(backup).isSymbolicLink(), false, "the symlink was replaced by a real backup")
  assert.equal(fs.readFileSync(backup, "utf8"), "not json")
  fs.rmSync(dir, { recursive: true, force: true })
})
