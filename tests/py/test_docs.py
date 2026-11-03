"""The language tour in docs/examples/tour (the examples docs/LANGUAGE.md explains) builds, runs and passes its tests, and
`nlc check` reports a build error without linking."""

import os
import subprocess
import unittest

from support import ROOT, selfhost


def nlc(*arguments, cwd=ROOT):
    script = ["pwsh", "-NoProfile", "-File", str(ROOT / "scripts" / "nlc.ps1")] if os.name == "nt" else [str(ROOT / "scripts" / "nlc")]
    env = dict(os.environ, NLC_SELFHOST=str(selfhost()))
    return subprocess.run(script + list(arguments), cwd=cwd, env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=300)


class Docs(unittest.TestCase):
    def test_the_tour_runs(self):
        ran = nlc("run", "docs/examples/tour")
        self.assertEqual(ran.returncode, 0, ran.stderr.decode(errors="replace"))
        self.assertEqual(ran.stdout.decode().split("\n")[:3], ["bob: 7 hp", "10", "9"])

    @unittest.skipIf(os.name == "nt", "nlc test is Linux-only for now")
    def test_the_tours_tests_pass(self):
        ran = nlc("test", "docs/examples/tour")
        self.assertEqual(ran.returncode, 0, ran.stdout.decode(errors="replace"))
        self.assertIn("2 passed, 0 failed", ran.stdout.decode())
        only = nlc("test", "--filter", "hurt", "docs/examples/tour")
        self.assertIn("1 passed, 0 failed", only.stdout.decode())
        self.assertNotIn("a bad input", only.stdout.decode())

    def test_check_accepts_a_good_package_and_rejects_a_bad_one(self):
        good = nlc("check", "docs/examples/tour")
        self.assertEqual(good.returncode, 0, good.stderr.decode(errors="replace"))
        self.assertIn("ok", good.stdout.decode())
        bad_dir = ROOT / ".docs-check-bad"
        bad_dir.mkdir(exist_ok=True)
        try:
            (bad_dir / "main.nl").write_text("fn main() { let x: int = true }\n")
            bad = nlc("check", ".docs-check-bad")
            self.assertNotEqual(bad.returncode, 0)
            self.assertIn("expected int, found bool", bad.stderr.decode())
            self.assertFalse(list(ROOT.glob(".nlc-check.*")), "check leaves no temporary files")
            if os.name != "nt":
                # the driver adds the source line and a caret under the column; --json gives one object per error
                lines = bad.stderr.decode().splitlines()
                self.assertTrue(lines[1].endswith("| fn main() { let x: int = true }"), lines)
                self.assertEqual(lines[2].index("^"), lines[1].index("| ") + 2 + 25, lines)
                as_json = nlc("check", "--json", ".docs-check-bad")
                self.assertIn('"line":1,"col":26,"severity":"error"', as_json.stderr.decode())
        finally:
            (bad_dir / "main.nl").unlink()
            bad_dir.rmdir()


if __name__ == "__main__":
    unittest.main()
