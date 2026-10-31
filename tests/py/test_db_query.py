"""Env.db_query: a prepared statement with the key bound to ?1, run on the program's own SQLite connection."""

import os
import sqlite3
import tempfile
import unittest

from support import selfhost
from test_jobs import run_program


class DbQuery(unittest.TestCase):
    def test_returns_the_first_column_of_the_first_row_or_none(self):
        os.environ.setdefault("NLC_SELFHOST", str(selfhost()))
        with tempfile.TemporaryDirectory(prefix="nl-db-") as directory:
            path = os.path.join(directory, "test.db")
            connection = sqlite3.connect(path)
            connection.execute("create table t (id integer primary key, v integer, name text, small integer, flag integer)")
            connection.execute("insert into t values (7, 4242, 'widget', 31, 1)")
            connection.commit()
            connection.close()
            os.environ["NLC_DB"] = path
            try:
                ran = run_program("db_query")
            finally:
                del os.environ["NLC_DB"]
            self.assertEqual(ran.returncode, 0, ran.stderr.decode(errors="replace"))
            self.assertEqual(ran.stdout.decode().split(), ["true", "4242", "6", "31", "true", "false", "4242", "-2", "6", "6", "119", "-1", "5"])


if __name__ == "__main__":
    unittest.main()
