"""Input-policy boundaries of the self-hosted compiler: a package exactly at a limit reaches checking, one unit
over is rejected with the limit's diagnostic (ported from input_policy.rs, `build` command only)."""

import pathlib
import shutil
import subprocess
import tempfile
import unittest

from support import selfhost

FILE_LIMIT = 16 * 1024 * 1024
PACKAGE_LIMIT = 64 * 1024 * 1024
FILE_TOKEN_LIMIT = 1_000_000
PACKAGE_TOKEN_LIMIT = 4_000_000
NODE_LIMIT = 2_000_000
WORK_LIMIT = 72_000_000


def simple_main():
    return b"fn main() { missing }\n"


def statement_function(name, statements):
    return (f"fn {name}() {{\n" + "x;\n" * statements + "unknown\n}\n").encode()


def token_boundary_source(function, token_count):
    # Five declaration/header tokens and four trailing tokens surround the semicolons.
    semicolons = token_count - 9
    return f"fn {function}() {{{';' * semicolons}unknown}}\n".encode()


class InputPolicy(unittest.TestCase):
    def setUp(self):
        self.scratch = pathlib.Path(tempfile.mkdtemp(prefix="nl-input-policy-"))
        self.addCleanup(shutil.rmtree, self.scratch, ignore_errors=True)
        self.package = self.scratch / "package"

    def write_package(self, files):
        shutil.rmtree(self.package, ignore_errors=True)
        self.package.mkdir()
        for name, data in files:
            (self.package / name).write_bytes(data)

    def build(self):
        (self.scratch / "output.ll").unlink(missing_ok=True)
        return subprocess.run([str(selfhost()), "build", "package", "-o", "output.ll", "--runtime=core"],
                              cwd=self.scratch, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=600)

    def assert_at_limit(self, message):
        result = self.build()
        stderr = result.stderr.decode(errors="replace")
        self.assertEqual(result.returncode, 2, f"did not reach checking at N for {message}: {stderr}")
        self.assertNotIn(message, stderr, f"rejected N for {message}")

    def assert_over_limit(self, message, location):
        result = self.build()
        stderr = result.stderr.decode(errors="replace")
        self.assertEqual(result.returncode, 2, f"accepted N+1 for {message}: {stderr}")
        self.assertEqual(result.stdout, b"", f"wrote partial stdout for {message}")
        self.assertTrue(stderr.startswith(location) and f"error: {message}" in stderr,
                        f"wrong N+1 diagnostic for {message}: {stderr[:300]}")

    def test_file_count(self):
        message = "source file limit of 256 per package exceeded"
        files = [("file-000.nl", simple_main())] + [(f"file-{index:03}.nl", b"") for index in range(1, 256)]
        self.write_package(files)
        self.assert_at_limit(message)
        (self.package / "file-256.nl").write_bytes(b"")
        self.assert_over_limit(message, "<package>:1:1")

    def test_per_file_bytes(self):
        message = "source byte limit of 16777216 per file exceeded"
        exact = simple_main().ljust(FILE_LIMIT, b" ")
        self.write_package([("main.nl", exact)])
        self.assert_at_limit(message)
        (self.package / "main.nl").write_bytes(simple_main().ljust(FILE_LIMIT + 1, b" "))
        self.assert_over_limit(message, "main.nl:1:1")

    def test_package_bytes(self):
        message = "source byte limit of 67108864 per package exceeded"
        files = [("a.nl", simple_main().ljust(FILE_LIMIT, b" "))] + [(name, b" " * FILE_LIMIT) for name in ("b.nl", "c.nl", "d.nl")]
        self.assertEqual(sum(len(data) for _, data in files), PACKAGE_LIMIT)
        self.write_package(files)
        self.assert_at_limit(message)
        (self.package / "e.nl").write_bytes(b" ")
        self.assert_over_limit(message, "e.nl:1:1")

    def test_per_file_tokens(self):
        message = "token limit of 1000000 per file exceeded"
        self.write_package([("main.nl", token_boundary_source("main", FILE_TOKEN_LIMIT))])
        self.assert_at_limit(message)
        (self.package / "main.nl").write_bytes(token_boundary_source("main", FILE_TOKEN_LIMIT + 1))
        self.assert_over_limit(message, "main.nl:2:1")

    def test_package_tokens(self):
        message = "token limit of 4000000 per package exceeded"
        files = []
        for index, name in enumerate(("a.nl", "b.nl", "c.nl", "d.nl")):
            files.append((name, token_boundary_source("main" if index == 0 else f"helper{index}", FILE_TOKEN_LIMIT)))
        self.assertEqual(4 * FILE_TOKEN_LIMIT, PACKAGE_TOKEN_LIMIT)
        self.write_package(files)
        self.assert_at_limit(message)
        (self.package / "e.nl").write_bytes(b"")  # contributes one end-of-file token
        self.assert_over_limit(message, "e.nl:1:1")

    def test_nodes(self):
        message = "node limit of 2000000 per package exceeded"
        files = [("a.nl", statement_function("main", 333_332)),
                 ("b.nl", statement_function("helper1", 333_331)),
                 ("c.nl", statement_function("helper2", 333_331))]
        self.assertEqual(2 * (333_332 + 333_331 + 333_331) + 4 * 3, NODE_LIMIT)
        self.write_package(files)
        self.assert_at_limit(message)
        (self.package / "d.nl").write_bytes(b"")
        self.assert_over_limit(message, "d.nl:1:1")

    def test_work(self):
        message = "parse work limit of 72000000 units per package exceeded"
        # Work is bytes + tokens + nodes + edges.
        per_function = [283_334, 283_333, 283_333]
        work_files = [("a.nl", statement_function("main", per_function[0])),
                      ("b.nl", statement_function("helper1", per_function[1])),
                      ("c.nl", statement_function("helper2", per_function[2]))]
        total_statements = sum(per_function)
        file_count = 7
        token_count = 2 * total_statements + 11 * 3 + 4
        node_count = 2 * total_statements + 4 * 3 + 4
        edge_count = node_count - file_count
        filler = WORK_LIMIT - token_count - node_count - edge_count - sum(len(data) for _, data in work_files)
        self.assertTrue(0 < filler < 4 * FILE_LIMIT)
        for index in range(4):
            size = filler // 4 + (1 if index < filler % 4 else 0)
            self.assertLessEqual(size, FILE_LIMIT)
            work_files.append((f"pad-{index}.nl", b" " * size))
        self.assertEqual(sum(len(data) for _, data in work_files) + token_count + node_count + edge_count, WORK_LIMIT)
        self.write_package(work_files)
        self.assert_at_limit(message)
        padded = self.package / "pad-3.nl"
        padded.write_bytes(padded.read_bytes() + b" ")
        self.assert_over_limit(message, "pad-3.nl:1:1")

    def test_nesting(self):
        message = "expression nesting limit of 1000 exceeded"

        def source(depth):
            return f"fn main() {{ print({'(' * depth}1{')' * depth}); missing }}\n".encode()

        self.write_package([("main.nl", source(1000))])
        self.assert_at_limit(message)
        (self.package / "main.nl").write_bytes(source(1001))
        self.assert_over_limit(message, "main.nl:1:")

    def test_invalid_utf8(self):
        self.write_package([("main.nl", b"fn main() {}\n\xff")])
        result = self.build()
        self.assertEqual(result.returncode, 2)
        self.assertEqual(result.stdout, b"")
        self.assertEqual(result.stderr, b"main.nl:2:1: error: source is not valid UTF-8; save the file as UTF-8\n")


if __name__ == "__main__":
    unittest.main()
