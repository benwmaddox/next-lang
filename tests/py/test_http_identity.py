"""Env.http_body, http_peer, random_token, password_verify and db_exec through a small server."""

import http.client
import os
import re
import socket
import sqlite3
import subprocess
import tempfile
import time
import unittest

from support import ROOT, selfhost


class HttpIdentity(unittest.TestCase):
    @unittest.skipIf(os.name == "nt", "Net is Linux-only for now")
    def test_capabilities(self):
        env = dict(os.environ, NLC_SELFHOST=str(selfhost()))
        built = subprocess.run([str(ROOT / "scripts" / "nlc"), "build", "tests/py/programs/identity", "-o", ".identity-test"],
                               cwd=ROOT, env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        self.assertEqual(built.returncode, 0, built.stderr.decode(errors="replace"))
        with tempfile.TemporaryDirectory(prefix="nl-identity-") as directory:
            path = os.path.join(directory, "t.db")
            connection = sqlite3.connect(path)
            connection.execute("CREATE TABLE notes (id integer PRIMARY KEY AUTOINCREMENT NOT NULL, owner integer NOT NULL, text varchar)")
            connection.commit()
            server_env = dict(env, NLC_DB=path, NLC_STACK_RESERVE_BYTES=str(1 << 30), NLC_JOB_STACK_RESERVE_BYTES=str(16 << 20))
            server = subprocess.Popen([str(ROOT / ".identity-test")], cwd=ROOT, env=server_env, stdout=subprocess.PIPE)
            try:
                for _ in range(100):
                    try:
                        socket.create_connection(("127.0.0.1", 18087), timeout=0.2).close()
                        break
                    except OSError:
                        time.sleep(0.05)
                client = http.client.HTTPConnection("127.0.0.1", 18087, timeout=5)

                def call(method, target, body=None):
                    client.request(method, target, body=body)
                    answer = client.getresponse()
                    return answer.status, answer.read().decode()

                self.assertEqual(call("POST", "/echo", "a=1&b=2"), (222, "a=1&b=2"))   # 220 + method code 2
                self.assertEqual(call("DELETE", "/echo", "x"), (224, "x"))
                self.assertEqual(call("PUT", "/echo", "y"), (225, "y"))
                self.assertEqual(call("PATCH", "/echo", "z"), (226, "z"))
                self.assertEqual(call("GET", "/echo"), (221, ""))                       # no body: empty, not left over
                self.assertEqual(call("GET", "/peer"), (200, "127.0.0.1"))
                status, first = call("GET", "/token")
                status, second = call("GET", "/token")
                self.assertTrue(re.fullmatch(r"[1-9A-HJ-NP-Za-km-z]{24}", first), first)
                self.assertNotEqual(first, second)
                self.assertEqual(call("POST", "/verify", "secret")[0], 200)
                self.assertEqual(call("POST", "/verify", "Secret")[0], 403)
                self.assertEqual(call("POST", "/verify", "")[0], 403)
                self.assertEqual(call("POST", "/note", "hello"), (200, "1,0"))
                self.assertEqual(call("DELETE", "/note", "again"), (200, "1,2"))        # inserts one, deletes both
                rows = sqlite3.connect(path).execute("select count(*) from notes").fetchone()[0]
                self.assertEqual(rows, 0)
            finally:
                server.kill()
                server.wait()
                try:
                    os.remove(ROOT / ".identity-test")
                except OSError:
                    pass


if __name__ == "__main__":
    unittest.main()
