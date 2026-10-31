"""Env.http_header: a header of the request last read on a connection, case-insensitive, per request on a keep-alive connection."""

import http.client
import os
import socket
import subprocess
import time
import unittest

from support import ROOT, selfhost


class HttpHeaders(unittest.TestCase):
    @unittest.skipIf(os.name == "nt", "Net is Linux-only for now")
    def test_headers_of_each_request(self):
        env = dict(os.environ, NLC_SELFHOST=str(selfhost()))
        built = subprocess.run([str(ROOT / "scripts" / "nlc"), "build", "tests/py/programs/http_headers", "-o", ".http-headers-test"],
                               cwd=ROOT, env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        self.assertEqual(built.returncode, 0, built.stderr.decode(errors="replace"))
        server_env = dict(env, NLC_STACK_RESERVE_BYTES=str(1 << 30), NLC_JOB_STACK_RESERVE_BYTES=str(16 << 20))
        server = subprocess.Popen([str(ROOT / ".http-headers-test")], cwd=ROOT, env=server_env, stdout=subprocess.PIPE)
        try:
            for _ in range(100):
                try:
                    socket.create_connection(("127.0.0.1", 18085), timeout=0.2).close()
                    break
                except OSError:
                    time.sleep(0.05)
            connection = http.client.HTTPConnection("127.0.0.1", 18085, timeout=5)

            def get(headers):
                connection.request("GET", "/", headers=headers)
                return connection.getresponse().read().decode()

            self.assertEqual(get({}), "no user cookie=-")
            self.assertEqual(get({"X-Test-User": "ada"}), "user=ada cookie=-")
            self.assertEqual(get({"x-test-user": "bob", "Cookie": "session_token=abc; theme=dark"}), "user=bob cookie=session_token=abc; theme=dark")
            self.assertEqual(get({"X-Test-User": "  padded  "}), "user=padded cookie=-")   # surrounding spaces are not part of the value
            self.assertEqual(get({"X-Test-Users": "not it"}), "no user cookie=-")           # a longer name is a different header
        finally:
            server.kill()
            server.wait()
            try:
                os.remove(ROOT / ".http-headers-test")
            except OSError:
                pass


if __name__ == "__main__":
    unittest.main()
