"""Pushing the element of a `for x in list` loop into another list (a loop element is a view of the list slot, not a local)."""

import os
import unittest

from support import selfhost
from test_jobs import run_program


class ForeachPush(unittest.TestCase):
    def test_pushing_the_loop_element_copies_it(self):
        os.environ.setdefault("NLC_SELFHOST", str(selfhost()))
        ran = run_program("foreach_push")
        self.assertEqual(ran.returncode, 0, ran.stderr.decode(errors="replace"))
        # two plain elements; then per element (name length, size) seen inside the loop, and the copies afterwards
        self.assertEqual(ran.stdout.decode().split(),
                         ["2", "2", "10", "4", "20", "8", "30", "3", "2", "4", "8", "30"])


if __name__ == "__main__":
    unittest.main()
