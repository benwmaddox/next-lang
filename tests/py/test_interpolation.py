"""Interpolated strings: $"text {hole} text" with number and text holes, {{ and }} for braces, and the errors."""

import os
import shutil
import subprocess
import unittest

from support import ROOT, selfhost
from test_jobs import run_program


class Interpolation(unittest.TestCase):
    def test_a_program_using_interpolated_strings(self):
        os.environ.setdefault("NLC_SELFHOST", str(selfhost()))
        ran = run_program("interpolation")
        self.assertEqual(ran.returncode, 0, ran.stderr.decode(errors="replace"))
        self.assertEqual(ran.stdout.decode().split("\n"), [
            "42", "id=42!", "user 7: ada scored -3", "{braces} and 4242", "43 84", 'tab\there "quoted" 42', "", "plain",
            "[x][x]", "20", "row 0: 0", "row 1: 0", "row 2: 1", ""])

    def build(self, body):
        package = ROOT / ".interp-test"
        package.mkdir(exist_ok=True)
        (package / "package.toml").write_text('capabilities = ["env", "out"]\n')
        (package / "main.nl").write_text("fn main(env: Env) {\n    let id = 1L\n    let flag = true\n    var name: Bytes max 8 = Bytes.empty()\n" + body + "\n}\n")
        try:
            return subprocess.run([str(ROOT / "scripts" / "nlc"), "build", ".interp-test", "-o", ".interp-bin"], cwd=ROOT,
                                  env=dict(os.environ, NLC_SELFHOST=str(selfhost())), stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        finally:
            shutil.rmtree(package, ignore_errors=True)
            try:
                os.remove(ROOT / ".interp-bin")
            except OSError:
                pass

    def test_errors(self):
        for body, message in [
            ('print($"a {flag} b")', "takes int, long, byte, Ascii or Text; found bool"),
            ('print($"a {name} b")', "takes int, long, byte, Ascii or Text; found"),
            ('print($"a {id")', "string literals cannot contain a newline"),
            ('print($"a } b")', "unexpected character '}'"),
            ('print($"a {} b")', "expected a value"),
            ('print($"a\nb")', "string literals cannot contain a newline"),
        ]:
            built = self.build(body)
            self.assertNotEqual(built.returncode, 0, body)
            self.assertIn(message, built.stderr.decode(), body)


if __name__ == "__main__":
    unittest.main()
