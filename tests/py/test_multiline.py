"""Multi-line string literals (three quotes): lengths, escapes, line numbers after them, and a multi-line query checked at build time."""

import os
import shutil
import sqlite3
import subprocess
import tempfile
import unittest

from support import ROOT, selfhost
from test_jobs import run_program


class Multiline(unittest.TestCase):
    def test_text_and_a_query_over_several_lines(self):
        os.environ.setdefault("NLC_SELFHOST", str(selfhost()))
        with tempfile.TemporaryDirectory(prefix="nl-multi-") as directory:
            path = os.path.join(directory, "t.db")
            connection = sqlite3.connect(path)
            connection.execute("create table items (id integer primary key, room integer, v integer, name text)")
            connection.executemany("insert into items values (?,?,?,?)", [(i, 2, i, "n") for i in range(1, 6)])
            connection.commit()
            connection.close()
            os.environ["NLC_DB"] = path
            try:
                ran = run_program("multiline")
            finally:
                del os.environ["NLC_DB"]
            self.assertEqual(ran.returncode, 0, ran.stderr.decode(errors="replace"))
            # the text is "one\n  two \"quoted\" \"escaped\"\nthree": 3 + 1 + 2 + 3 + 1 + 8 + 1 + 9 + 1 + 5 = 34... counted below
            text = 'one\n  two "quoted" "escaped"\nthree'
            self.assertEqual(ran.stdout.decode().split("\n")[:3], [str(len(text)), str(text[3].encode()[0]), str(text[6].encode()[0])])
            self.assertEqual(ran.stdout.decode().split("\n")[3:5], ["4", "2"])    # ids 2..5, the first being 2

    def test_a_query_without_a_limit_is_still_an_error_when_it_spans_lines(self):
        os.environ.setdefault("NLC_SELFHOST", str(selfhost()))
        package = ROOT / ".multiline-test"
        package.mkdir(exist_ok=True)
        (package / "package.toml").write_text('capabilities = ["env", "out"]\n')
        (package / "schema.sql").write_text("create table items (id integer primary key, room integer);")
        (package / "main.nl").write_text('struct Item {\n    id: long\n}\n\nfn main(env: Env) {\n    var items: list<Item, 5> = list {}\n'
                                         '    print(env.db_rows("""\n        from items\n        where room = ?1\n    """, 2L, items))\n}\n')
        try:
            built = subprocess.run([str(ROOT / "scripts" / "nlc"), "build", ".multiline-test", "-o", ".multiline-bin"], cwd=ROOT,
                                   env=dict(os.environ), stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            self.assertNotEqual(built.returncode, 0)
            self.assertIn("limit N", built.stderr.decode())
            self.assertIn("main.nl:7:", built.stderr.decode())   # the error is on the line the literal starts
        finally:
            shutil.rmtree(package, ignore_errors=True)
            try:
                os.remove(ROOT / ".multiline-bin")
            except OSError:
                pass

    def test_an_unclosed_multi_line_string_is_an_error(self):
        os.environ.setdefault("NLC_SELFHOST", str(selfhost()))
        package = ROOT / ".multiline-test2"
        package.mkdir(exist_ok=True)
        (package / "package.toml").write_text('capabilities = ["out"]\n')
        (package / "main.nl").write_text('fn main() {\n    let text = """never closed\n    print(1L)\n}\n')
        try:
            built = subprocess.run([str(ROOT / "scripts" / "nlc"), "build", ".multiline-test2", "-o", ".multiline-bin2"], cwd=ROOT,
                                   env=dict(os.environ), stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            self.assertNotEqual(built.returncode, 0)
            self.assertIn("main.nl:2:", built.stderr.decode())
        finally:
            shutil.rmtree(package, ignore_errors=True)


if __name__ == "__main__":
    unittest.main()
