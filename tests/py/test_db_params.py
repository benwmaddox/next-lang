"""Query parameters as a struct: Env.db_row / db_rows bind its fields to ?1, ?2, ... (text as text)."""

import os
import sqlite3
import tempfile
import unittest

from support import selfhost
from test_jobs import run_program


class DbParams(unittest.TestCase):
    def test_a_struct_binds_text_and_bool_parameters(self):
        os.environ.setdefault("NLC_SELFHOST", str(selfhost()))
        with tempfile.TemporaryDirectory(prefix="nl-params-") as directory:
            path = os.path.join(directory, "t.db")
            connection = sqlite3.connect(path)
            connection.execute("create table sessions (id integer primary key, token text not null, user_id integer not null, active integer not null)")
            connection.executemany("insert into sessions values (?,?,?,?)", [(1, "abc123", 7, 1), (2, "abc123", 8, 1), (3, "abc123", 9, 0), (4, "zzz", 5, 1)])
            connection.commit()
            connection.close()
            os.environ["NLC_DB"] = path
            try:
                ran = run_program("db_params")
            finally:
                del os.environ["NLC_DB"]
            self.assertEqual(ran.returncode, 0, ran.stderr.decode(errors="replace"))
            # the first match is user 7; two active rows; the inactive one is found when active is false; an unknown token finds nothing
            self.assertEqual(ran.stdout.decode().split(), ["true", "7", "2", "true", "false"])


if __name__ == "__main__":
    unittest.main()
