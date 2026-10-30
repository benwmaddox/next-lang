"""Env.net_listen / net_accept / http_read / http_write / net_close: a blocking HTTP server answered by urllib."""

import http.client
import os
import socket
import subprocess
import time
import unittest

from support import ROOT, selfhost


class HttpEcho(unittest.TestCase):
    @unittest.skipIf(os.name == "nt", "Net is Linux-only for now")
    def test_keep_alive_requests_get_their_target_back(self):
        env = dict(os.environ, NLC_SELFHOST=str(selfhost()))
        built = subprocess.run([str(ROOT / "scripts" / "nlc"), "build", "tests/py/programs/http_echo", "-o", ".http-echo-test"],
                               cwd=ROOT, env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        self.assertEqual(built.returncode, 0, built.stderr.decode(errors="replace"))
        server = subprocess.Popen([str(ROOT / ".http-echo-test")], cwd=ROOT, stdout=subprocess.PIPE)
        try:
            for _ in range(100):
                try:
                    socket.create_connection(("127.0.0.1", 18080), timeout=0.2).close()
                    break
                except OSError:
                    time.sleep(0.05)
            connection = http.client.HTTPConnection("127.0.0.1", 18080, timeout=5)
            for path in ["/", "/item/42", "/search?q=a+b&n=3"]:
                connection.request("GET", path)  # the same connection each time: keep-alive
                answer = connection.getresponse()
                self.assertEqual(answer.status, 200)
                self.assertEqual(answer.read().decode(), path)
            connection.request("POST", "/x", body=b"hello body")
            answer = connection.getresponse()
            self.assertEqual(answer.status, 400)
            self.assertEqual(answer.read(), b"bad method")
        finally:
            server.kill()
            server.wait()
            try:
                os.remove(ROOT / ".http-echo-test")
            except OSError:
                pass


if __name__ == "__main__":
    unittest.main()
