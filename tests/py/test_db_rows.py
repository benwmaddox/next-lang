"""Env.db_rows: several rows into a list<Row, N> from a query that ends with `limit N` (N no more than the list's capacity)."""

import os
import pathlib
import shutil
import sqlite3
import subprocess
import tempfile
import unittest

from support import ROOT, selfhost
from test_jobs import run_program


class DbRows(unittest.TestCase):
    def test_rows_fill_the_list_up_to_the_limit(self):
        os.environ.setdefault("NLC_SELFHOST", str(selfhost()))
        with tempfile.TemporaryDirectory(prefix="nl-rows-") as directory:
            path = os.path.join(directory, "t.db")
            connection = sqlite3.connect(path)
            connection.execute("create table items (id integer primary key, room integer, v integer, name text)")
            connection.executemany("insert into items values (?,?,?,?)", [(i, 2 if i <= 7 else 3, i * 10, "n%d" % i) for i in range(1, 12)])
            connection.commit()
            connection.close()
            os.environ["NLC_DB"] = path
            try:
                ran = run_program("db_rows")
            finally:
                del os.environ["NLC_DB"]
            self.assertEqual(ran.returncode, 0, ran.stderr.decode(errors="replace"))
            # room 2 has 7 rows but the limit is 5: ids 1..5, v 10+20+30+40+50 = 150, "n1" has 2 bytes, items[2].id is 3
            self.assertEqual(ran.stdout.decode().split(), ["5", "5", "150", "2", "3", "4", "0", "0"])

    def build(self, query, capacity=5):
        package = ROOT / ".rows-test"
        package.mkdir(exist_ok=True)
        (package / "package.toml").write_text('capabilities = ["env", "out"]\n')
        (package / "schema.sql").write_text("create table items (id integer primary key, room integer, v integer, name text);")
        (package / "main.nl").write_text(
            "struct Item {\n    id: long\n    v: long\n}\n\nfn main(env: Env) {\n"
            f"    var items: list<Item, {capacity}> = list {{}}\n"
            f'    print(env.db_rows("{query}", 1L, items))\n' "}\n")
        try:
            return subprocess.run([str(ROOT / "scripts" / "nlc"), "build", ".rows-test", "-o", ".rows-bin"], cwd=ROOT,
                                  env=dict(os.environ, NLC_SELFHOST=str(selfhost())), stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        finally:
            shutil.rmtree(package, ignore_errors=True)
            try:
                os.remove(ROOT / ".rows-bin")
            except OSError:
                pass

    def test_a_query_without_a_limit_is_a_build_error(self):
        built = self.build("from items where room = ?1")
        self.assertNotEqual(built.returncode, 0)
        self.assertIn("limit N", built.stderr.decode())

    def test_a_limit_larger_than_the_list_is_a_build_error(self):
        built = self.build("from items where room = ?1 limit 9")
        self.assertNotEqual(built.returncode, 0)
        self.assertIn("larger than the capacity", built.stderr.decode())

    def test_a_good_query_builds(self):
        built = self.build("from items where room = ?1 limit 5")
        self.assertEqual(built.returncode, 0, built.stderr.decode(errors="replace"))


if __name__ == "__main__":
    unittest.main()
