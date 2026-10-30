"""Source-input policy and cache behaviour (ported from selfhost.rs). The expected results are the ones the
Rust reference produced; the Rust side is no longer run."""

import os
import pathlib
import shutil
import subprocess
import sys
import tempfile
import unittest

from support import ROOT, selfhost


def run_compiler(cwd, *args, timeout=120):
    return subprocess.run([str(selfhost()), *args], cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=timeout)


class SourcePolicy(unittest.TestCase):
    def setUp(self):
        self.temp = pathlib.Path(tempfile.mkdtemp(prefix="nl-policy-"))
        self.addCleanup(shutil.rmtree, self.temp, ignore_errors=True)
        self.package = self.temp / "package"
        self.package.mkdir()

    @unittest.skipIf(os.name == "nt", "symlinks")
    def test_rooted_source_symlink_policy(self):
        (self.package / "helper.txt").write_text("fn helper() -> long { 1L }\n")
        (self.temp / "outside.nl").write_text("fn outside() -> long { 2L }\n")
        (self.temp.parent / f"{self.temp.name}-outside2.nl").write_text("fn beyond() -> long { 3L }\n")
        self.addCleanup((self.temp.parent / f"{self.temp.name}-outside2.nl").unlink, missing_ok=True)
        os.symlink("helper.txt", self.package / "linked.nl")
        os.symlink("../outside.nl", self.package / "escape.nl")  # still within the rooted parent
        os.symlink(f"../../{self.temp.name}-outside2.nl", self.package / "beyond.nl")  # escapes the rooted parent
        # A link inside the root and one that stays within the rooted parent are read as sources...
        (self.package / "main.nl").write_text("fn main() { print(helper() + outside()) }\n")
        result = run_compiler(self.temp, "build", "package", "-o", "ok.ll", "--runtime=core")
        self.assertEqual(result.returncode, 0, result.stderr.decode(errors="replace"))
        # ...but one that escapes the rooted parent is not, so a name defined only there is unknown.
        (self.package / "main.nl").write_text("fn main() { print(beyond()) }\n")
        result = run_compiler(self.temp, "build", "package", "-o", "escaped.ll", "--runtime=core")
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.temp / "escaped.ll").exists())

    def test_invalid_utf8_is_a_syntax_diagnostic(self):
        (self.package / "main.nl").write_bytes(b"fn main() {}\n\xff")
        result = run_compiler(self.temp, "build", "package", "-o", "output.ll", "--runtime=core")
        self.assertEqual(result.returncode, 2)
        self.assertEqual(result.stdout, b"")
        self.assertEqual(result.stderr, b"main.nl:2:1: error: source is not valid UTF-8; save the file as UTF-8\n")

    def test_over_parse_source_limits_are_rejected(self):
        file_limit = 16 * 1024 * 1024
        package_limit = 64 * 1024 * 1024
        main = b"fn main() {}\n"
        (self.package / "main.nl").write_bytes(b" " * (file_limit + 1 - len(main)) + main)
        result = run_compiler(self.temp, "build", "package", "-o", "file-output.ll", "--runtime=core")
        self.assertEqual(result.returncode, 2)
        self.assertEqual(result.stdout, b"")
        self.assertIn("source byte limit of 16777216 per file exceeded", result.stderr.decode(errors="replace"))
        (self.package / "main.nl").unlink()
        (self.package / "a.nl").write_bytes(b" " * (file_limit - len(main)) + main)
        for name in ("b.nl", "c.nl", "d.nl"):
            (self.package / name).write_bytes(b" " * file_limit)
        (self.package / "e.nl").write_bytes(b" ")
        total = sum(path.stat().st_size for path in self.package.iterdir())
        self.assertEqual(total, package_limit + 1)
        result = run_compiler(self.temp, "build", "package", "-o", "package-output.ll", "--runtime=core")
        self.assertEqual(result.returncode, 2)
        self.assertEqual(result.stdout, b"")
        self.assertIn("source byte limit of 67108864 per package exceeded", result.stderr.decode(errors="replace"))


class CompilerCache(unittest.TestCase):
    def test_concurrent_cold_cache_builds_publish_reusable_artifacts(self):
        with tempfile.TemporaryDirectory(prefix="nl-cache-") as temp:
            env = dict(os.environ, CARGO_TARGET_DIR=str(pathlib.Path(temp) / "target"))
            command = [sys.executable, str(ROOT / "scripts" / "build-selfhost-cached.py")]

            def start():
                return subprocess.Popen(command, cwd=ROOT, env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE)

            first, second = start(), start()
            out1, err1 = first.communicate()
            out2, err2 = second.communicate()
            self.assertEqual(first.returncode, 0, err1.decode(errors="replace"))
            self.assertEqual(second.returncode, 0, err2.decode(errors="replace"))
            self.assertEqual(out1, out2)
            binary = pathlib.Path(out1.decode().strip())
            self.assertTrue(binary.is_file())
            binary.write_bytes(b"corrupt")
            repaired = subprocess.run(command, cwd=ROOT, env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            self.assertEqual(repaired.returncode, 0, "corrupt artifact was not rebuilt: " + repaired.stderr.decode(errors="replace"))
            pathlib.Path(repaired.stdout.decode().strip()).unlink()
            rebuilt = subprocess.run(command, cwd=ROOT, env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            self.assertEqual(rebuilt.returncode, 0, "missing artifact was not rebuilt: " + rebuilt.stderr.decode(errors="replace"))


if __name__ == "__main__":
    unittest.main()
