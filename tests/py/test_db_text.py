"""Text fields in db_row / db_rows: well-formed UTF-8 within the limits is delivered, anything else leaves the field empty."""

import os
import sqlite3
import tempfile
import unittest

from support import selfhost
from test_jobs import run_program


class DbText(unittest.TestCase):
    def test_text_fields_are_validated_when_read(self):
        os.environ.setdefault("NLC_SELFHOST", str(selfhost()))
        with tempfile.TemporaryDirectory(prefix="nl-dbtext-") as directory:
            path = os.path.join(directory, "t.db")
            connection = sqlite3.connect(path)
            connection.execute("create table words (id integer primary key not null, word varchar)")
            rows = [(1, "ok"), (2, "né"), (3, b"\xff\xfe"), (4, "abcdefg"), (5, "日本語"), (6, None), (7, b"\xed\xa0\x80"), (8, "abcdef")]
            connection.executemany("insert into words values (?, ?)", rows)
            connection.commit()
            connection.close()
            os.environ["NLC_DB"] = path
            try:
                ran = run_program("db_text")
            finally:
                del os.environ["NLC_DB"]
            self.assertEqual(ran.returncode, 0, ran.stderr.decode(errors="replace"))
            self.assertEqual(ran.stdout.decode().split("\n"), [
                "1: 2 2 [ok]", "2: 2 3 [né]", "3: 0 0 []", "4: 0 0 []", "5: 3 9 [日本語]", "6: 0 0 []", "7: 0 0 []", "8: 6 6 [abcdef]",
                "true", "né", ""])


if __name__ == "__main__":
    unittest.main()
