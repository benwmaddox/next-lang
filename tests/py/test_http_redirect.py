"""Env.http_set_header: a redirect, cookies, refused header lines, and headers that do not leak into the next response."""

import http.client
import os
import socket
import subprocess
import time
import unittest

from support import ROOT, selfhost


class HttpRedirect(unittest.TestCase):
    @unittest.skipIf(os.name == "nt", "Net is Linux-only for now")
    def test_headers_of_responses(self):
        env = dict(os.environ, NLC_SELFHOST=str(selfhost()))
        built = subprocess.run([str(ROOT / "scripts" / "nlc"), "build", "tests/py/programs/http_redirect", "-o", ".http-redirect-test"],
                               cwd=ROOT, env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        self.assertEqual(built.returncode, 0, built.stderr.decode(errors="replace"))
        server_env = dict(env, NLC_STACK_RESERVE_BYTES=str(1 << 30), NLC_JOB_STACK_RESERVE_BYTES=str(16 << 20))
        server = subprocess.Popen([str(ROOT / ".http-redirect-test")], cwd=ROOT, env=server_env, stdout=subprocess.PIPE)
        try:
            for _ in range(100):
                try:
                    socket.create_connection(("127.0.0.1", 18086), timeout=0.2).close()
                    break
                except OSError:
                    time.sleep(0.05)
            connection = http.client.HTTPConnection("127.0.0.1", 18086, timeout=5)

            def get(path):
                connection.request("GET", path)
                answer = connection.getresponse()
                return answer.status, answer.reason, answer.getheaders(), answer.read().decode()

            status, reason, headers, body = get("/go")
            self.assertEqual((status, reason, body), (302, "Found", ""))
            self.assertEqual(dict(headers)["Location"], "/rooms/7")
            status, reason, headers, body = get("/cookie")
            self.assertEqual((status, body), (200, "cookies"))
            self.assertEqual([v for k, v in headers if k == "Set-Cookie"], ["session_token=abc123; HttpOnly; Path=/", "theme=dark"])
            status, reason, headers, body = get("/inject")
            self.assertEqual((status, body), (200, "refused"))
            self.assertNotIn("X-Evil", dict(headers))
            self.assertEqual([v for k, v in headers if k == "Set-Cookie"], [])
            status, reason, headers, body = get("/else")     # same keep-alive connection: nothing left over from /cookie
            self.assertEqual((status, body), (200, "plain"))
            self.assertEqual([k for k, v in headers if k in ("Set-Cookie", "Location")], [])
        finally:
            server.kill()
            server.wait()
            try:
                os.remove(ROOT / ".http-redirect-test")
            except OSError:
                pass


if __name__ == "__main__":
    unittest.main()
