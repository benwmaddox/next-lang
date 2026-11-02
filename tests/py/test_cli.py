"""CLI basics: Env.stdin_read and Env.getenv, in a small grep (tests/py/programs/cli_grep)."""

import os
import subprocess
import unittest

from support import ROOT, selfhost


class Cli(unittest.TestCase):
    @unittest.skipIf(os.name == "nt", "driver is Linux-only for now")
    def test_a_grep_reading_standard_input(self):
        env = dict(os.environ, NLC_SELFHOST=str(selfhost()))
        built = subprocess.run([str(ROOT / "scripts" / "nlc"), "build", "tests/py/programs/cli_grep", "-o", ".cli-grep-test"],
                               cwd=ROOT, env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        self.assertEqual(built.returncode, 0, built.stderr.decode(errors="replace"))
        binary = str(ROOT / ".cli-grep-test")
        try:
            def run(arguments, data, extra_env=None):
                return subprocess.run([binary] + arguments, input=data, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                      env=dict(os.environ, **(extra_env or {})))

            text = b"alpha\nbeta\ngamma delta\nepsilon\nlast line without a newline"
            ran = run(["a"], text)
            self.assertEqual((ran.returncode, ran.stdout), (0, b"alpha\nbeta\ngamma delta\nlast line without a newline\n"))
            self.assertEqual(run(["delta"], text).stdout, b"gamma delta\n")
            self.assertEqual(run(["newline"], text).stdout, b"last line without a newline\n")   # the last line has no line break
            self.assertEqual(run(["zzz"], text).returncode, 1)                                    # nothing matched
            self.assertEqual(run([], text).returncode, 2)                                         # usage error
            self.assertEqual(run(["beta"], text, {"NL_PREFIX": "> "}).stdout, b"> beta\n")        # an environment variable
            self.assertEqual(run(["beta"], b"").returncode, 1)                                    # empty input
            big = b"".join(b"line %d xyz\n" % n for n in range(5000))                           # more than one chunk of input
            ran = run(["xyz"], big)
            self.assertEqual(ran.stdout.count(b"\n"), 5000)
            self.assertEqual(run(["line 4999 "], big).stdout, b"line 4999 xyz\n")
        finally:
            try:
                os.remove(ROOT / ".cli-grep-test")
            except OSError:
                pass


if __name__ == "__main__":
    unittest.main()
