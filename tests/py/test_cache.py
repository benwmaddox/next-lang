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


if __name__ == "__main__":
    unittest.main()
