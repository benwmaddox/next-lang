"""Loop-exit stack release and manifest step budgets (ported from selfhost_loop_exit_stack.rs and selfhost_step_budget.rs)."""

import os
import pathlib
import shutil
import subprocess
import unittest

from support import ROOT, compile_package, selfhost, temporary_package

LINK = str(ROOT / "scripts" / "nlc")
PEAK_LIMIT = 1024 * 1024
FIXTURES = [
    "tests/e3/e3a3fix_continue_if",
    "tests/e3/e3a3fix_break_inner",
    "tests/e3/e3a3fix_continue_match",
    "tests/e3/e3a3fix_continue_nested",
    "tests/e3/e3a3fix_expression_exits",
    "tests/e3/e3a3fix_while_exits",
]


def link(directory, level="1"):
    return subprocess.run([LINK, "link-ir", "module.ll", "-o", "program"], cwd=directory,
                          env=dict(os.environ, NLC_OPT_LEVEL=level), stdout=subprocess.PIPE, stderr=subprocess.PIPE)


class LoopExits(unittest.TestCase):
    """`break` and `continue` must release the data-stack space that blocks between the jump and the loop body
    reserved. Each fixture jumps out of an 8 KB region local millions of times, so a leak would reach gigabytes."""

    def test_selfhost_loop_exits_release_nested_block_reservations(self):
        for fixture in FIXTURES:
            source = ROOT / fixture
            for level in ("1", "3"):
                for threshold in (None, "--test-region-threshold=0"):
                    what = f"{fixture} at O{level} {threshold}"
                    with self.subTest(what), temporary_package({}) as directory:
                        for name in ("main.nl", "package.toml"):
                            shutil.copy(source / name, directory / name)
                        built = subprocess.run(
                            [str(selfhost()), "build", ".", "-o", "module.ll", "--test", *([threshold] if threshold else [])],
                            cwd=directory, env=dict(os.environ, NLC_OPT_LEVEL=level), stdout=subprocess.PIPE, stderr=subprocess.PIPE)
                        self.assertEqual(built.returncode, 0, built.stderr.decode(errors="replace"))
                        linked = link(directory, level)
                        self.assertEqual(linked.returncode, 0, linked.stderr.decode(errors="replace"))
                        env = dict(os.environ, NLC_STACK_STATS="1")
                        env.pop("NLC_STACK_PREALLOC", None)
                        env.pop("NLC_TEST_STACK_FORCE_MOVE", None)
                        ran = subprocess.run(["./program"], cwd=directory, env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
                        stderr = ran.stderr.decode(errors="replace")
                        self.assertEqual(ran.returncode, 0, f"{what} failed: {stderr}")
                        self.assertEqual(ran.stdout, (source / "expected.stdout").read_bytes(), f"{what} stdout")
                        stats = next((line for line in stderr.splitlines() if line.startswith("nl offset stack entry ")), None)
                        self.assertIsNotNone(stats, f"no stack stats line in:\n{stderr}")
                        peak = next(int(field[len("peak_used="):]) for field in stats.split() if field.startswith("peak_used="))
                        self.assertLess(peak, PEAK_LIMIT, f"{what} leaked data-stack space across loop exits: peak_used={peak}")


class StepBudget(unittest.TestCase):
    """Manifest budgets are opt-in, shared across calls, and diagnosed before lowering."""

    def compile(self, manifest, source, timeout=60):
        directory = pathlib.Path(self._scratch.name)
        (directory / "package.toml").write_text(manifest)
        (directory / "main.nl").write_text(source)
        (directory / "module.ll").unlink(missing_ok=True)
        return directory, compile_package(directory, output="module.ll", timeout=timeout)

    def setUp(self):
        import tempfile
        self._scratch = tempfile.TemporaryDirectory(prefix="nl-step-budget-")

    def tearDown(self):
        self._scratch.cleanup()

    def test_manifest_step_budgets_are_optional_checked_and_shared(self):
        for value in ["", "-1", "1.5", '"10"', "10 MB", "_1", "1_", "1__0", "9223372036854775808", "18446744073709551616"]:
            directory, result = self.compile(f"step_budget.main = {value}\n", "fn main() {}\n")
            stderr = result.stderr.decode(errors="replace")
            self.assertEqual(result.returncode, 3, f"value {value!r}: {stderr}")
            self.assertIn("step_budget.main", stderr, f"value {value!r}")
            self.assertIn("nonnegative integer", stderr, f"value {value!r}")
            self.assertFalse((directory / "module.ll").exists(), "invalid budget emitted IR")
        for name, manifest, message in [
            ("duplicate", "step_budget.main = 1\nstep_budget.main = 2\n", "listed more than once"),
            ("missing-equals", "step_budget.main 10\n", "expected"),
        ]:
            directory, result = self.compile(manifest, "fn main() {}\n")
            stderr = result.stderr.decode(errors="replace")
            self.assertEqual(result.returncode, 3, f"{name}: {stderr}")
            self.assertTrue("step_budget.main" in stderr and message in stderr, f"{name}: {stderr}")
            self.assertFalse((directory / "module.ll").exists())

        long_loop = "fn main() {\n    var index = 0L\n    while index < 10000001L { index += 1L }\n    print(index)\n}\n"
        shared = "fn burn() {\n    var index = 0L\n    while index < 2L { index += 1L }\n}\nfn main() { burn(); burn(); print(99) }\n"
        cases = [
            ("unlimited", 'capabilities = ["out"]\n', long_loop, 0, "10000001\n"),
            ("zero", "step_budget.main = 0\n", "fn main() { while true { continue } }\n", 1, ""),
            ("shared", "step_budget.main = 3\n", shared, 1, ""),
            ("exact", "step_budget.main = 4\n", shared, 0, "99\n"),
            ("separated", "step_budget.main = 1_000\n", shared, 0, "99\n"),
        ]
        for name, manifest, source, expected_status, expected_stdout in cases:
            with self.subTest(name):
                directory, compiled = self.compile(manifest, source)
                self.assertEqual(compiled.returncode, 0, f"{name}: {compiled.stderr.decode(errors='replace')}")
                ir = (directory / "module.ll").read_text()
                self.assertEqual("call i1 @nl_core_nl_context_step_budget_take(" in ir, name != "unlimited",
                                 f"{name}: budget checks must be emitted only for an explicit budget")
                linked = link(directory, "3")
                self.assertEqual(linked.returncode, 0, linked.stderr.decode(errors="replace"))
                ran = subprocess.run(["timeout", "15", "./program"], cwd=directory, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
                stderr = ran.stderr.decode(errors="replace")
                self.assertEqual(ran.returncode, expected_status, f"{name}: {stderr}")
                self.assertEqual(ran.stdout, expected_stdout.encode(), name)
                if expected_status == 0:
                    self.assertEqual(ran.stderr, b"", f"{name}: {stderr}")
                else:
                    self.assertIn("loop step budget exhausted", stderr, name)
        directory, compiled = self.compile("step_budget.main = 9223372036854775807\n", "fn main() {}\n")
        self.assertEqual(compiled.returncode, 0, f"maximum budget: {compiled.stderr.decode(errors='replace')}")


if __name__ == "__main__":
    unittest.main()
