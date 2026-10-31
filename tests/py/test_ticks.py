"""Timers: Receiver.recv_for / is_closed, Env.now_ms, and a service with a fixed-rate tick."""

import os
import unittest

from support import selfhost
from test_jobs import run_program


class Ticks(unittest.TestCase):
    def test_timeouts_and_a_ticking_service(self):
        os.environ.setdefault("NLC_SELFHOST", str(selfhost()))
        for attempt in range(3):
            ran = run_program("ticks")
            self.assertEqual(ran.returncode, 0, ran.stderr.decode(errors="replace"))
            self.assertEqual(ran.stdout.decode().split(), ["0", "true", "false", "7", "true", "true", "true", "5000000005"], f"attempt {attempt}")


if __name__ == "__main__":
    unittest.main()
