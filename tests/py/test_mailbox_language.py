"""Mailboxes in the language: `mailbox<T, N>`, `Sender<T>`, `Receiver<T>`, send / recv_wait / close, handles passed to
spawned jobs (programs in tests/py/programs)."""

import unittest

from test_jobs import run_program
from support import selfhost
import os


class MailboxLanguage(unittest.TestCase):
    def setUp(self):
        os.environ.setdefault("NLC_SELFHOST", str(selfhost()))

    def test_three_producers_one_consumer_through_a_small_mailbox(self):
        for attempt in range(3):
            ran = run_program("mailbox")
            self.assertEqual(ran.returncode, 0, ran.stderr.decode(errors="replace"))
            # the sum of 0..999, 100000..100999 and 200000..200999, and the number of messages
            self.assertEqual(ran.stdout.decode().split(), ["301498500", "3000"], f"attempt {attempt}")

    def test_records_arrive_in_order_and_close_ends_the_receiver(self):
        for attempt in range(3):
            ran = run_program("mailbox_structs")
            self.assertEqual(ran.returncode, 0, ran.stderr.decode(errors="replace"))
            # 200 orders; the weights are 2 * (0 + ... + 199) = 39800
            self.assertEqual(ran.stdout.decode().split(), ["200", "39800", "true", "true"], f"attempt {attempt}")


if __name__ == "__main__":
    unittest.main()
