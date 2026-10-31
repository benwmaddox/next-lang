"""Env.cache_get / Env.cache_put: the shared process-wide cache."""

import unittest

from test_jobs import run_program
from support import selfhost
import os


class SharedCache(unittest.TestCase):
    def test_put_get_replace_and_miss(self):
        os.environ.setdefault("NLC_SELFHOST", str(selfhost()))
        ran = run_program("cache_shared")
        self.assertEqual(ran.returncode, 0, ran.stderr.decode(errors="replace"))
        self.assertEqual(ran.stdout.decode().split(), ["-1", "5", "5", "104", "2", "-1"])

    def test_readers_never_see_a_half_written_value(self):
        os.environ.setdefault("NLC_SELFHOST", str(selfhost()))
        for attempt in range(3):
            ran = run_program("cache_race")
            self.assertEqual(ran.returncode, 0, ran.stderr.decode(errors="replace"))
            self.assertEqual(ran.stdout.decode().split(), ["0", "0"], f"attempt {attempt}")


if __name__ == "__main__":
    unittest.main()
