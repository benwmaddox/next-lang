"""Services (tools/svc.py): state, handlers, typed senders, replies; and a package that builds and runs one."""

import pathlib
import sys
import tempfile
import unittest
import os

from support import ROOT, selfhost
from test_jobs import run_program

sys.path.insert(0, str(ROOT / "tools"))
import svc  # noqa: E402


def generate(source):
    with tempfile.TemporaryDirectory(prefix="nl-svc-") as directory:
        (pathlib.Path(directory) / "s.svc").write_text(source)
        svc.compile_package(directory)
        return (pathlib.Path(directory) / "services.gen.nl").read_text()


class Generator(unittest.TestCase):
    def test_the_generated_names(self):
        text = generate("service Box\nstate n: long = 0L\nmailbox 8\non Put(v: long) {\n    state.n = v\n}\non Take() -> long {\n    reply(state.n)\n}\n")
        for expected in ["struct Box {", "enum BoxMessage {", "fn Box_start(", "fn Box_put(service: Box, v: long) -> bool", "fn Box_take(service: Box) -> Option<long>", "fn Box_stop(", "mailbox<BoxMessage, 8>"]:
            self.assertIn(expected, text)

    def test_errors(self):
        for source in ["service A\n", "service A\non X() {\n", "service A\non X() {\n}\non X() {\n}\n", "nothing\n", "service A\non Stop() {\n}\n"]:
            with self.assertRaises(svc.ServiceError, msg=source):
                generate(source)


class Program(unittest.TestCase):
    def test_a_task_uses_a_service(self):
        os.environ.setdefault("NLC_SELFHOST", str(selfhost()))
        ran = run_program("services")
        self.assertEqual(ran.returncode, 0, ran.stderr.decode(errors="replace"))
        # 100 + 3 * (0 + 1 + ... + 9) = 235; ten Adds and the Get make 11 calls before Calls is handled
        self.assertEqual(ran.stdout.decode().split(), ["235", "11", "true"])


if __name__ == "__main__":
    unittest.main()
