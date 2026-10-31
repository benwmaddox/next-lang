"""One job per connection: many open keep-alive connections are served by a few worker threads."""

import http.client
import os
import socket
import subprocess
import time
import unittest

from support import ROOT, selfhost


class HttpJobs(unittest.TestCase):
    @unittest.skipIf(os.name == "nt", "Net is Linux-only for now")
    def test_two_hundred_open_connections_all_get_answers(self):
        env = dict(os.environ, NLC_SELFHOST=str(selfhost()))
        # the server runs with small reservations so 200 jobs fit under a 40 GB address-space limit
        server_env = dict(env, NLC_WORKERS="2", NLC_STACK_RESERVE_BYTES=str(1 << 30), NLC_JOB_STACK_RESERVE_BYTES=str(16 << 20))
        built = subprocess.run([str(ROOT / "scripts" / "nlc"), "build", "tests/py/programs/http_jobs", "-o", ".http-jobs-test"],
                               cwd=ROOT, env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        self.assertEqual(built.returncode, 0, built.stderr.decode(errors="replace"))
        server = subprocess.Popen([str(ROOT / ".http-jobs-test")], cwd=ROOT, env=server_env, stdout=subprocess.PIPE)
        connections = []
        try:
            for _ in range(100):
                try:
                    socket.create_connection(("127.0.0.1", 18083), timeout=0.2).close()
                    break
                except OSError:
                    time.sleep(0.05)
            # all connections stay open at the same time, then each makes requests; two workers cannot hold 200 threads
            for _ in range(200):
                connections.append(http.client.HTTPConnection("127.0.0.1", 18083, timeout=10))
            for round_number in range(3):
                for index, connection in enumerate(connections):
                    path = f"/c{index}/r{round_number}"
                    connection.request("GET", path)
                    answer = connection.getresponse()
                    self.assertEqual(answer.status, 200)
                    self.assertEqual(answer.read().decode(), path)
        finally:
            for connection in connections:
                connection.close()
            server.kill()
            server.wait()
            try:
                os.remove(ROOT / ".http-jobs-test")
            except OSError:
                pass


if __name__ == "__main__":
    unittest.main()
