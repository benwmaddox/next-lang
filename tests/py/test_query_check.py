"""The build prepares every Env.db_row query against the package's schema.sql: a wrong table, column or type is an
error when the program is built, and a plan that reads a whole table is a warning."""

import os
import shutil
import subprocess
import unittest

from support import ROOT, selfhost


class QueryCheck(unittest.TestCase):
    def build(self, query, schema="create table t (id integer primary key, v integer, name text);"):
        env = dict(os.environ, NLC_SELFHOST=str(selfhost()))
        package = ROOT / ".querycheck-test"
        package.mkdir(exist_ok=True)
        (package / "package.toml").write_text('capabilities = ["env", "out"]\n')
        (package / "schema.sql").write_text(schema)
        (package / "main.nl").write_text(
            "struct Item {\n    v: long\n    name: Bytes max 16\n}\n\n"
            "fn main(env: Env) {\n    var item = Item { v: 0L, name: Bytes.empty() }\n"
            f'    print(env.db_row("{query}", 1L, item))\n' "}\n")
        try:
            return subprocess.run([str(ROOT / "scripts" / "nlc"), "build", ".querycheck-test", "-o", ".querycheck-bin"],
                                  cwd=ROOT, env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        finally:
            try:
                os.remove(ROOT / ".querycheck-bin")
            except OSError:
                pass
            shutil.rmtree(package, ignore_errors=True)

    def test_a_good_query_builds(self):
        built = self.build("from t where id = ?1")
        self.assertEqual(built.returncode, 0, built.stderr.decode(errors="replace"))

    def test_an_unknown_table_is_a_build_error(self):
        built = self.build("from missing_table where id = ?1")
        self.assertNotEqual(built.returncode, 0)
        self.assertIn("no such table", built.stderr.decode())

    def test_a_struct_field_with_no_column_is_a_build_error(self):
        built = self.build("from t where id = ?1", schema="create table t (id integer primary key, v integer);")
        self.assertNotEqual(built.returncode, 0)
        self.assertIn("no such column", built.stderr.decode())

    def test_a_column_of_the_wrong_type_is_a_build_error(self):
        built = self.build("from t where id = ?1", schema="create table t (id integer primary key, v text, name text);")
        self.assertNotEqual(built.returncode, 0)
        self.assertIn("declared TEXT", built.stderr.decode())

    def test_a_whole_table_scan_is_a_warning(self):
        built = self.build("from t where v = ?1")
        self.assertEqual(built.returncode, 0, built.stderr.decode(errors="replace"))
        self.assertIn("reads a whole table", built.stderr.decode())


if __name__ == "__main__":
    unittest.main()
