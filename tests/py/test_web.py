"""bench/web end to end: worker, cache and SQLite jobs behind HTTP; JSON and HTML routes, 404s, escaping, tax."""

import http.client
import json
import os
import socket
import sqlite3
import subprocess
import tempfile
import time
import unittest

from support import ROOT, selfhost


class Web(unittest.TestCase):
    @unittest.skipIf(os.name == "nt", "Net is Linux-only for now")
    def test_routes_answer_from_sqlite_through_the_cache_job(self):
        env = dict(os.environ, NLC_SELFHOST=str(selfhost()))
        built = subprocess.run([str(ROOT / "scripts" / "nlc"), "build", "bench/web", "-o", ".web-test"],
                               cwd=ROOT, env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        self.assertEqual(built.returncode, 0, built.stderr.decode(errors="replace"))
        with tempfile.TemporaryDirectory(prefix="nl-web-") as directory:
            path = os.path.join(directory, "items.db")
            database = sqlite3.connect(path)
            database.execute("create table items (id integer primary key, v integer, name text, price integer)")
            database.executemany("insert into items values (?,?,?,?)", [
                (1, 111, "plain", 1000), (2, 222, "a <b> & \"c\"", 1234)])
            database.commit()
            database.close()
            server_env = dict(env, NLC_DB=path, NLC_STACK_RESERVE_BYTES=str(1 << 30), NLC_JOB_STACK_RESERVE_BYTES=str(16 << 20))
            server = subprocess.Popen([str(ROOT / ".web-test")], cwd=ROOT, env=server_env, stdout=subprocess.PIPE)
            try:
                for _ in range(100):
                    try:
                        socket.create_connection(("127.0.0.1", 18081), timeout=0.2).close()
                        break
                    except OSError:
                        time.sleep(0.05)
                connection = http.client.HTTPConnection("127.0.0.1", 18081, timeout=5)

                def get(target):
                    connection.request("GET", target)
                    answer = connection.getresponse()
                    return answer.status, answer.getheader("Content-Type"), answer.read().decode()

                for _ in range(2):  # the second round is answered by the cache job
                    status, kind, body = get("/item/2")
                    self.assertEqual((status, kind), (200, "application/json"))
                    self.assertEqual(json.loads(body), {"id": 2, "name": "a <b> & \"c\"", "price": 12.34, "v": 222})
                    status, kind, body = get("/page/2")
                    self.assertEqual((status, kind), (200, "text/html; charset=utf-8"))
                    self.assertIn("<h1>a &lt;b&gt; &amp; &quot;c&quot;</h1>", body)
                    self.assertIn("price with tax: $13.32", body)  # 1234 + 8% = 1332
                    self.assertEqual(get("/item/1")[2], '{"id":1,"name":"plain","price":10.00,"v":111}')
                self.assertEqual(get("/item/9")[0], 404)  # no such row
                self.assertEqual(get("/nothing/1")[0], 404)
                self.assertEqual(get("/item/x1")[0], 404)
            finally:
                server.kill()
                server.wait()
                try:
                    os.remove(ROOT / ".web-test")
                except OSError:
                    pass


if __name__ == "__main__":
    unittest.main()
