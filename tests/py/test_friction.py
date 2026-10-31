"""Conveniences added after writing the web workload (docs/campfire-friction.md): struct literals in a call inside a match
head, discard of plain values and mailbox sends, while loops."""

import os
import unittest

from support import selfhost
from test_jobs import run_program


class Friction(unittest.TestCase):
    def test_the_conveniences(self):
        os.environ.setdefault("NLC_SELFHOST", str(selfhost()))
        ran = run_program("friction")
        self.assertEqual(ran.returncode, 0, ran.stderr.decode(errors="replace"))
        # send ok; the first message (21) is received and doubled... the second (5) was discarded-sent after it
        self.assertEqual(ran.stdout.decode().split(), ["1", "42", "14", "13", "1", "36"])


if __name__ == "__main__":
    unittest.main()
