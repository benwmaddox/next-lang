"""Env.db_query / db_text / db_row: prepared statements with the key bound to ?1, run on the program's own SQLite
connection; SQLite runs on one block of memory given to it at startup."""

import os
import sqlite3
import tempfile
import unittest

from support import selfhost
from test_jobs import run_program

EXPECTED = ["true", "4242", "6", "31", "true", "false", "4242", "-2", "6", "6", "119", "-1", "5"]


def make_database(directory):
    path = os.path.join(directory, "test.db")
    connection = sqlite3.connect(path)
    connection.execute("create table t (id integer primary key, v integer, name text, small integer, flag integer)")
    connection.execute("insert into t values (7, 4242, 'widget', 31, 1)")
    connection.commit()
    connection.close()
    return path


class DbQuery(unittest.TestCase):
    def run_with(self, **environment):
        os.environ.setdefault("NLC_SELFHOST", str(selfhost()))
        with tempfile.TemporaryDirectory(prefix="nl-db-") as directory:
            saved = {key: os.environ.get(key) for key in ("NLC_DB", *environment)}
            os.environ["NLC_DB"] = make_database(directory)
            os.environ.update(environment)
            try:
                return run_program("db_query")
            finally:
                for key, value in saved.items():
                    if value is None:
                        os.environ.pop(key, None)
                    else:
                        os.environ[key] = value

    def test_returns_the_first_column_of_the_first_row_or_none(self):
        ran = self.run_with()
        self.assertEqual(ran.returncode, 0, ran.stderr.decode(errors="replace"))
        self.assertEqual(ran.stdout.decode().split(), EXPECTED)

    def test_the_smallest_heap_is_enough_for_simple_queries(self):
        ran = self.run_with(NLC_DB_HEAP_BYTES=str(1 << 20))
        self.assertEqual(ran.returncode, 0, ran.stderr.decode(errors="replace"))
        self.assertEqual(ran.stdout.decode().split(), EXPECTED)

    def test_a_heap_setting_that_is_too_small_is_ignored(self):
        ran = self.run_with(NLC_DB_HEAP_BYTES="1000")
        self.assertEqual(ran.returncode, 0, ran.stderr.decode(errors="replace"))
        self.assertEqual(ran.stdout.decode().split(), EXPECTED)


if __name__ == "__main__":
    unittest.main()
