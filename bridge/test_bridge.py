"""Runs the bridge against a fake omarchy-shell, never the real one: python3 -m unittest discover -s bridge"""
import importlib.machinery
import importlib.util
import json
import os
import socket
import stat
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from pathlib import Path

sys.dont_write_bytecode = True  # no __pycache__ in the repository

HERE = Path(__file__).parent
TESTDATA = HERE / "testdata"
STATUS = {"open": True, "saved": "SAVED", "drawing": 0}

# status as the plugin answers it; every call is appended to calls.
FAKE_SHELL = """#!/bin/sh
echo "$@" >> "$FAKE/calls"
case "$2" in
  status) cat "$FAKE/status.json" ;;
  *) echo ok ;;
esac
"""


def load_bridge():
    loader = importlib.machinery.SourceFileLoader("fieldnotes_bridge", str(HERE / "fieldnotes-bridge"))
    module = importlib.util.module_from_spec(importlib.util.spec_from_loader("fieldnotes_bridge", loader))
    loader.exec_module(module)
    return module


class BridgeTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.dir = Path(self.tmp.name)
        os.environ["XDG_STATE_HOME"] = str(self.dir / "state")
        os.environ["FAKE"] = str(self.dir)
        self.module = load_bridge()
        self.module.print = lambda *args, **kwargs: None  # the bridge narrates for Field Notes; tests need not hear it
        (self.dir / "status.json").write_text(json.dumps(STATUS))
        self.shell = self.dir / "omarchy-shell"
        self.shell.write_text(FAKE_SHELL)
        self.shell.chmod(self.shell.stat().st_mode | stat.S_IXUSR)
        self.module.NOTES.parent.mkdir(parents=True)
        self.module.NOTES.write_text((TESTDATA / "notes.json").read_text())

        self.bridge = self.module.Bridge("adb", str(self.shell), 0)
        server = socket.socket()
        server.bind(("127.0.0.1", 0))
        server.listen()
        self.addCleanup(server.close)
        self.port = server.getsockname()[1]
        for target in (self.bridge.sync, self.bridge.ink_loop):
            threading.Thread(target=target, daemon=True).start()
        threading.Thread(target=self.accept_forever, args=(server,), daemon=True).start()

    def accept_forever(self, server):
        while True:
            try:
                conn, _ = server.accept()
            except OSError:
                return
            threading.Thread(target=self.bridge.serve, args=(conn,), daemon=True).start()

    def connect(self, token):
        conn = socket.create_connection(("127.0.0.1", self.port), timeout=5)
        self.addCleanup(conn.close)
        reader = conn.makefile("r", encoding="utf-8")
        conn.sendall((json.dumps({"t": "hello", "v": 1, "token": token}) + "\n").encode())
        return conn, reader

    def read_until(self, reader, kind):
        while True:
            message = json.loads(reader.readline())
            if message["t"] == kind:
                return message

    def calls(self):
        path = self.dir / "calls"
        return path.read_text().splitlines() if path.exists() else []

    def wait_for_call(self, call):
        for _ in range(100):
            if call in self.calls():
                return
            time.sleep(0.03)
        self.fail(f"the plugin was never called with {call!r}; it got {self.calls()}")

    def test_wrong_token_is_turned_away(self):
        _, reader = self.connect("wrong")
        self.assertEqual(json.loads(reader.readline()), {"t": "unpaired"})
        self.assertEqual(reader.readline(), "")

    def test_paired_phone_gets_desk_and_the_open_sheet(self):
        _, reader = self.connect(self.bridge.token)
        self.assertEqual(self.read_until(reader, "desk")["saved"], "SAVED")
        self.assertEqual(self.read_until(reader, "sheet"), json.loads((TESTDATA / "sheet.json").read_text()))

    def test_stroke_reaches_the_shell_and_is_settled(self):
        conn, reader = self.connect(self.bridge.token)
        self.read_until(reader, "sheet")
        conn.sendall((TESTDATA / "stroke.json").read_bytes())
        self.assertEqual(self.read_until(reader, "sheet")["settled"], 7)
        self.assertIn(" ".join(json.loads((TESTDATA / "stroke-argv.json").read_text())), self.calls())

    def test_every_command_becomes_its_plugin_call(self):
        conn, reader = self.connect(self.bridge.token)
        self.read_until(reader, "sheet")
        for command in json.loads((TESTDATA / "commands.json").read_text()):
            with self.subTest(command["name"]):
                conn.sendall((command["line"] + "\n").encode())
                self.wait_for_call(" ".join(command["argv"]))

    def test_nonsense_is_refused_and_never_reaches_the_shell(self):
        conn, reader = self.connect(self.bridge.token)
        self.read_until(reader, "sheet")
        for line in ({"t": "stroke", "id": 3, "points": ["x", 1, 2, 3]}, {"t": "select", "id": 4, "sheet": 0},
                     {"t": "width", "id": 5, "value": 99}, {"t": "note", "id": 6, "x": 1, "y": 2, "text": "  "},
                     {"t": "bogus", "id": 7}):
            conn.sendall((json.dumps(line) + "\n").encode())
            self.assertEqual(self.read_until(reader, "error")["id"], line["id"])
        self.assertEqual([c for c in self.calls() if not c.endswith(" status")], [])

    def test_text_keeps_its_backslashes_and_loses_its_nulls(self):
        conn, reader = self.connect(self.bridge.token)
        self.read_until(reader, "sheet")
        conn.sendall((json.dumps({"t": "note", "id": 1, "x": 1, "y": 2, "text": "C:\\new\nline\0"}) + "\n").encode())
        self.wait_for_call("jobo.field-notes addNote 1.0 2.0 C:\\\\new\\nline")

    def test_points_out_of_reach_are_refused(self):
        conn, reader = self.connect(self.bridge.token)
        self.read_until(reader, "sheet")
        for points in ([0, 0, 1e9, 1e9], [0, 0, 10 ** 400, 5]):
            conn.sendall((json.dumps({"t": "stroke", "id": 2, "points": points}) + "\n").encode())
            self.assertEqual(self.read_until(reader, "error")["id"], 2)

    def test_a_line_that_never_ends_closes_the_connection(self):
        conn, reader = self.connect(self.bridge.token)
        self.read_until(reader, "sheet")
        conn.sendall(b"x" * (self.module.MAX_LINE + 1))
        conn.shutdown(socket.SHUT_WR)
        self.assertEqual(reader.read(), "")

    def test_a_vanishing_phone_takes_its_ink_away(self):
        conn, reader = self.connect(self.bridge.token)
        self.read_until(reader, "sheet")
        conn.sendall(b'{"t":"ink","points":[1.0,2.0,3.0,4.0]}\n')
        self.wait_for_call("jobo.field-notes ink 1.0 2.0 3.0 4.0")
        conn.shutdown(socket.SHUT_RDWR)  # close() alone leaves the reader's copy of the socket open
        self.wait_for_call("jobo.field-notes ink ")

    def test_link_prefers_usb_and_stays_put(self):
        pick = self.module.pick_carrier
        both = ["192.168.0.193:37143", "R52R107DV2J"]
        self.assertEqual(pick(None, both), "R52R107DV2J")
        self.assertEqual(pick("192.168.0.193:37143", both), "192.168.0.193:37143")  # no flip-flopping
        self.assertEqual(pick("R52R107DV2J", both[:1]), "192.168.0.193:37143")  # the cable came out
        self.assertEqual(pick(None, ["adb-R52R107DV2J-MrDmpF._adb-tls-connect._tcp", "R52R107DV2J"]), "R52R107DV2J")

    def test_pairing_hands_the_token_to_each_phone(self):
        adb = self.dir / "adb"
        adb.write_text('#!/bin/sh\n[ "$1" = devices ] && printf "List of devices attached\\nR52R107DV2J\\tdevice\\nXYZ\\toffline\\n" && exit 0\necho "$@" >> "$FAKE/adb-calls"\n')
        adb.chmod(0o755)
        self.module.pair(str(adb))
        self.assertEqual((self.dir / "adb-calls").read_text().splitlines(),
                         [f"-s R52R107DV2J shell am start -n com.wonderingsolutions.fieldnotes/.MainActivity --es token {self.bridge.token}"])

    def test_a_stalled_status_is_a_blip_until_it_lasts(self):
        self.assertTrue(self.bridge.reachable(None))
        self.bridge.failing_since -= 6
        self.assertFalse(self.bridge.reachable(None))
        self.assertTrue(self.bridge.reachable({}))

    def test_token_is_made_once_and_private(self):
        self.assertEqual(self.module.get_token(), self.module.get_token())
        self.assertEqual(stat.S_IMODE(self.module.TOKEN.stat().st_mode), 0o600)

    def test_an_empty_token_is_replaced(self):
        self.module.TOKEN.write_text("")
        self.assertNotEqual(self.module.get_token(), "")


class ProcessTest(unittest.TestCase):
    """The bridge as Field Notes runs it."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.dir = Path(self.tmp.name)
        shell = self.dir / "omarchy-shell"
        shell.write_text("#!/bin/sh\necho '{\"open\":true,\"saved\":\"SAVED\",\"drawing\":0}'\n")
        shell.chmod(0o755)
        self.env = {**os.environ, "XDG_STATE_HOME": str(self.dir / "state")}
        self.args = [sys.executable, str(HERE / "fieldnotes-bridge"), "--adb", "/bin/true", "--shell", str(shell)]

    def start(self, port):
        proc = subprocess.Popen([*self.args, "--port", str(port), "--exit-with-stdin"], env=self.env,
                                stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        self.addCleanup(lambda: (proc.kill(), proc.wait(), [f.close() for f in (proc.stdout, proc.stderr) if not f.closed]))
        return proc

    def test_reports_its_status_and_ends_with_its_parent(self):
        proc = self.start(0)
        lines = []
        while "status: Waiting for a phone" not in lines:
            line = proc.stdout.readline().strip()
            if line == "":
                self.fail(f"the bridge ended early: {lines} {proc.stderr.read()}")
            lines.append(line)
        proc.stdin.close()  # the shell went away
        self.assertEqual(proc.wait(timeout=5), 0)

    def test_a_taken_port_is_exit_2(self):
        with socket.socket() as taken:
            taken.bind(("127.0.0.1", 0))
            taken.listen()
            proc = self.start(taken.getsockname()[1])
            self.assertEqual(proc.wait(timeout=5), 2)


if __name__ == "__main__":
    unittest.main()
