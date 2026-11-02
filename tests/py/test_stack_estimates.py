"""The data stack a job reserves comes from the build's bound for its entry point, not from a fixed 64 MiB: it is never below what
the job used (NLC_REPORT_STACKS=1 prints both) and far below the old default."""

import http.client
import os
import re
import signal
import socket
import subprocess
import tempfile
import time
import sqlite3
import unittest

from support import ROOT, selfhost


class StackEstimates(unittest.TestCase):
    @unittest.skipIf(os.name == "nt", "Net is Linux-only for now")
    def test_a_connection_job_reserves_its_bound_and_not_the_default(self):
        env = dict(os.environ, NLC_SELFHOST=str(selfhost()))
        built = subprocess.run([str(ROOT / "scripts" / "nlc"), "build", "tests/py/programs/identity", "-o", ".estimate-test"],
                               cwd=ROOT, env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        self.assertEqual(built.returncode, 0, built.stderr.decode(errors="replace"))
        with tempfile.TemporaryDirectory(prefix="nl-estimate-") as directory:
            path = os.path.join(directory, "t.db")
            connection = sqlite3.connect(path)
            connection.execute("CREATE TABLE notes (id integer PRIMARY KEY AUTOINCREMENT NOT NULL, owner integer NOT NULL, text varchar)")
            connection.commit()
            report = os.path.join(directory, "report.txt")
            server_env = dict(env, NLC_DB=path, NLC_REPORT_STACKS="1", NLC_STACK_RESERVE_BYTES=str(1 << 30))
            server_env.pop("NLC_JOB_STACK_RESERVE_BYTES", None)
            with open(report, "w") as errors:
                server = subprocess.Popen([str(ROOT / ".estimate-test")], cwd=ROOT, env=server_env, stdout=subprocess.PIPE, stderr=errors)
            try:
                for _ in range(100):
                    try:
                        socket.create_connection(("127.0.0.1", 18087), timeout=0.2).close()
                        break
                    except OSError:
                        time.sleep(0.05)
                for _ in range(20):                       # twenty connections, each a job that ends
                    client = http.client.HTTPConnection("127.0.0.1", 18087, timeout=5)
                    client.request("POST", "/echo", "hello")
                    client.getresponse().read()
                    client.close()
                time.sleep(0.3)
                server.send_signal(signal.SIGUSR2)
                time.sleep(0.3)
            finally:
                server.kill()
                server.wait()
                try:
                    os.remove(ROOT / ".estimate-test")
                except OSError:
                    pass
            text = open(report).read()
            match = re.search(r"stacks: data: (\d+) jobs, largest (\d+) bytes.*reserved per job: (\d+) to (\d+) bytes", text)
            self.assertTrue(match, text)
            jobs, largest, reserved_low, reserved_high = (int(match.group(i)) for i in range(1, 5))
            self.assertGreaterEqual(jobs, 10)
            self.assertGreaterEqual(reserved_low, largest, "a job reserved less than it used")
            self.assertLess(reserved_high, 4 << 20, "the reservation is still the generic default")


if __name__ == "__main__":
    unittest.main()
