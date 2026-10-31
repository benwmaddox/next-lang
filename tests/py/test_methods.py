"""Method syntax for user structs: x.m(args) calls Type_m(x, args)."""

import os
import unittest

from support import selfhost
from test_jobs import run_program


class Methods(unittest.TestCase):
    def test_struct_methods(self):
        os.environ.setdefault("NLC_SELFHOST", str(selfhost()))
        ran = run_program("methods")
        self.assertEqual(ran.returncode, 0, ran.stderr.decode(errors="replace"))
        # 7; (9 + 12); 3*10 + 4*20; (6*20 + 8*40); 42; 7 * (0 + 1 + 2 + 3 + 4)
        self.assertEqual(ran.stdout.decode().split(), ["7", "21", "110", "440", "42", "70"])


class MethodErrors(unittest.TestCase):
    def build(self, body):
        import pathlib, shutil, subprocess
        from support import ROOT
        package = ROOT / ".methods-test"
        package.mkdir(exist_ok=True)
        (package / "package.toml").write_text('capabilities = ["env", "out"]\n')
        (package / "main.nl").write_text(
            "struct Point {\n    x: long\n    y: long\n}\n\nfn Point_sum(p: Point) -> long {\n    p.x + p.y\n}\n\n"
            "fn Point_scale(p: Point, k: long) -> long {\n    p.x * k\n}\n\n"
            "fn main() {\n    let p = Point { x: 1L, y: 2L }\n" + body + "\n}\n")
        try:
            return subprocess.run([str(ROOT / "scripts" / "nlc"), "run", ".methods-test"], cwd=ROOT,
                                  env=dict(os.environ, NLC_SELFHOST=str(selfhost())), stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        finally:
            shutil.rmtree(package, ignore_errors=True)

    def test_a_missing_method_is_an_error(self):
        self.assertNotEqual(self.build("    print(p.missing())").returncode, 0)

    def test_wrong_argument_count_and_type_are_errors(self):
        self.assertNotEqual(self.build("    print(p.sum(1L))").returncode, 0)
        self.assertNotEqual(self.build("    print(p.scale())").returncode, 0)
        self.assertNotEqual(self.build("    print(p.scale(true))").returncode, 0)

    def test_the_good_call_still_runs(self):
        ran = self.build("    print(p.scale(5L))")
        self.assertEqual(ran.returncode, 0, ran.stderr.decode(errors="replace"))
        self.assertEqual(ran.stdout.decode().split(), ["5"])


if __name__ == "__main__":
    unittest.main()
