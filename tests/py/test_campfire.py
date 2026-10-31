"""Campfire slice 1 (apps/campfire): reading. The database is made from the app's own schema.sql with a few users, rooms and
messages; the app runs and is asked for its pages with and without a session cookie."""

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


PASSWORD_DIGEST = "$2a$04$dcz.lzds.VCqQ5p7isC1l.H1xOKqPl1yyxP5kt5VQq3EbJn4Rocn."   # bcrypt of "secret"


def make_database(path):
    connection = sqlite3.connect(path)
    connection.executescript((ROOT / "apps" / "campfire" / "schema.sql").read_text())
    now = "2026-03-02 15:00:00"
    users = [(1, "Ada <b>", 0), (2, "Bob", 0), (3, "Cy", 0), (4, "Dee", 1)]   # Dee is deactivated (status 1)
    connection.executemany("insert into users (id, name, role, status, email_address, password_digest, created_at, updated_at) values (?,?,1,?,?,?,?,?)",
                           [(i, n, s, f"{n.split()[0].lower()}@example.com", PASSWORD_DIGEST, now, now) for i, n, s in users])
    connection.executemany("insert into rooms (id, creator_id, name, type, created_at, updated_at) values (?,?,?,?,?,?)",
                           [(10, 1, "Lobby", "Rooms::Open", now, now), (11, 1, "Secret", "Rooms::Closed", now, now), (12, 1, None, "Rooms::Direct", now, now)])
    connection.executemany("insert into memberships (room_id, user_id, created_at, updated_at) values (?,?,?,?)",
                           [(10, 1, now, now), (10, 2, now, now), (11, 1, now, now), (12, 1, now, now), (12, 2, now, now), (10, 4, now, now)])
    connection.executemany("insert into sessions (user_id, token, ip_address, last_active_at, created_at, updated_at) values (?,?,?,?,?,?)",
                           [(1, "ada-token", "127.0.0.1", now, now, now), (2, "bob-token", "127.0.0.1", now, now, now),
                            (3, "cy-token", "127.0.0.1", now, now, now), (4, "dee-token", "127.0.0.1", now, now, now)])
    for number in range(1, 56):   # 55 messages in the Lobby, alternating authors
        creator = 1 if number % 2 else 2
        connection.execute("insert into messages (id, client_message_id, creator_id, room_id, created_at, updated_at) values (?,?,?,?,?,?)",
                           (1000 + number, f"c{number:04d}", creator, 10, f"2026-03-02 15:{number:02d}:00", now))
        body = f"<p>message {number} with <strong>bold</strong> &amp; a &lt;tag&gt;</p>"
        connection.execute("insert into action_text_rich_texts (record_type, record_id, name, body, created_at, updated_at) values ('Message',?,'body',?,?,?)",
                           (1000 + number, body, now, now))
    connection.execute("insert into messages (id, client_message_id, creator_id, room_id, created_at, updated_at) values (2000,'s0001',1,11,?,?)", (now, now))
    connection.execute("insert into action_text_rich_texts (record_type, record_id, name, body, created_at, updated_at) values ('Message',2000,'body','<p>secret</p>',?,?)", (now, now))
    connection.commit()
    connection.close()


class Campfire(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if os.name == "nt":
            raise unittest.SkipTest("Net is Linux-only for now")
        env = dict(os.environ, NLC_SELFHOST=str(selfhost()))
        built = subprocess.run([str(ROOT / "scripts" / "nlc"), "build", "apps/campfire", "-o", ".campfire-test"],
                               cwd=ROOT, env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        assert built.returncode == 0, built.stderr.decode(errors="replace")
        cls.directory = tempfile.TemporaryDirectory(prefix="nl-campfire-")
        path = os.path.join(cls.directory.name, "campfire.db")
        make_database(path)
        server_env = dict(env, NLC_DB=path, NLC_STACK_RESERVE_BYTES=str(1 << 30), NLC_JOB_STACK_RESERVE_BYTES=str(64 << 20))
        cls.server = subprocess.Popen([str(ROOT / ".campfire-test")], cwd=ROOT, env=server_env, stdout=subprocess.PIPE)
        for _ in range(100):
            try:
                socket.create_connection(("127.0.0.1", 18090), timeout=0.2).close()
                break
            except OSError:
                time.sleep(0.05)

    @classmethod
    def tearDownClass(cls):
        cls.server.kill()
        cls.server.wait()
        cls.directory.cleanup()
        try:
            os.remove(ROOT / ".campfire-test")
        except OSError:
            pass

    def get(self, target, token=None, cookie=None):
        connection = http.client.HTTPConnection("127.0.0.1", 18090, timeout=5)
        headers = {}
        if cookie is not None:
            headers["Cookie"] = cookie
        elif token is not None:
            headers["Cookie"] = f"session_token={token}"
        connection.request("GET", target, headers=headers)
        answer = connection.getresponse()
        return answer.status, answer.read().decode()

    def test_the_home_page_lists_only_the_rooms_you_are_in(self):
        status, body = self.get("/", "bob-token")
        self.assertEqual(status, 200)
        self.assertIn("<h1>Bob</h1>", body)
        self.assertEqual(sorted(re.findall(r'<a href="/rooms/(\d+)">', body)), ["10", "12"])   # Bob is not in Secret
        self.assertIn(">Direct<", body)                                                          # a room with no name

    def test_the_names_are_escaped(self):
        status, body = self.get("/", "ada-token")
        self.assertIn("<h1>Ada &lt;b&gt;</h1>", body)

    def test_a_room_shows_its_last_forty_messages_oldest_first(self):
        status, body = self.get("/rooms/10", "ada-token")
        self.assertEqual(status, 200)
        ids = [int(i) for i in re.findall(r'data-message-id="(\d+)"', body)]
        self.assertEqual(ids, list(range(1016, 1056)))      # messages 16 to 55
        self.assertIn('id="message_c0055"', body)
        self.assertIn('id="presentation_message_1055"', body)
        self.assertIn("<p>message 55 with <strong>bold</strong> &amp; a &lt;tag&gt;</p>", body)   # the rich text is written as it is
        self.assertIn('<strong class="message__author">Ada &lt;b&gt;</strong>', body)
        self.assertIn("<title>Lobby - Campfire</title>", body)
        self.assertTrue(body.startswith("<!doctype html>") and body.endswith("</html>"))

    def test_the_sidebar_is_on_the_room_page_too(self):
        status, body = self.get("/rooms/10", "bob-token")
        self.assertEqual(sorted(re.findall(r'<li><a href="/rooms/(\d+)">', body)), ["10", "12"])

    def test_a_cookie_among_others(self):
        status, body = self.get("/", cookie="theme=dark; session_token=cy-token; other=1")
        self.assertEqual(status, 200)
        self.assertIn("<h1>Cy</h1>", body)

    def send(self, method, target, body=None, headers=None):
        connection = http.client.HTTPConnection("127.0.0.1", 18090, timeout=5)
        connection.request(method, target, body=body, headers=headers or {})
        answer = connection.getresponse()
        return answer.status, answer.getheaders(), answer.read().decode()

    def sign_in(self, email, password):
        from urllib.parse import urlencode
        return self.send("POST", "/session", urlencode({"email_address": email, "password": password}),
                         {"Content-Type": "application/x-www-form-urlencoded", "User-Agent": "test-agent"})

    def test_signing_in_makes_a_session_and_a_cookie(self):
        status, headers, body = self.sign_in("bob@example.com", "secret")
        self.assertEqual(status, 303)
        self.assertEqual(dict(headers)["Location"], "/")
        cookie = dict(headers)["Set-Cookie"]
        match = re.fullmatch(r"session_token=([1-9A-HJ-NP-Za-km-z]{32}); HttpOnly; Path=/; SameSite=Lax", cookie)
        self.assertTrue(match, cookie)
        status, page = self.get("/", match.group(1))
        self.assertEqual(status, 200)
        self.assertIn("<h1>Bob</h1>", page)
        stored = sqlite3.connect(os.path.join(self.directory.name, "campfire.db")).execute(
            "select user_id, ip_address, user_agent from sessions where token = ?", (match.group(1),)).fetchone()
        self.assertEqual(stored, (2, "127.0.0.1", "test-agent"))

    def test_a_form_with_encoded_characters(self):
        status, headers, body = self.send("POST", "/session", "password=secret&email_address=cy%40example.com&x=1",
                                          {"Content-Type": "application/x-www-form-urlencoded"})
        self.assertEqual((status, dict(headers)["Location"]), (303, "/"))

    def test_wrong_password_unknown_user_and_deactivated_user_are_sent_back(self):
        for email, password in [("bob@example.com", "wrong"), ("nobody@example.com", "secret"), ("dee@example.com", "secret"),
                                ("", "secret"), ("bob@example.com", "")]:
            status, headers, body = self.sign_in(email, password)
            self.assertEqual(status, 303, (email, password))
            self.assertEqual(dict(headers)["Location"], "/session/new?failed=1")
            self.assertNotIn("Set-Cookie", dict(headers))

    def test_the_sign_in_form(self):
        status, page = self.get("/session/new")
        self.assertEqual(status, 200)
        self.assertIn('<form action="/session" method="post">', page)
        self.assertNotIn("Try another", page)
        status, page = self.get("/session/new?failed=1")
        self.assertIn("Try another", page)
        self.assertEqual(self.send("GET", "/session/new", headers={"Cookie": "session_token=ada-token"})[0:2][0], 303)   # already in

    def test_signing_out_removes_the_session(self):
        token = re.search(r"session_token=(\w+)", dict(self.sign_in("ada@example.com", "secret")[1])["Set-Cookie"]).group(1)
        self.assertEqual(self.get("/", token)[0], 200)
        status, headers, body = self.send("DELETE", "/session", headers={"Cookie": f"session_token={token}"})
        self.assertEqual((status, dict(headers)["Location"]), (303, "/session/new"))
        self.assertIn("Max-Age=0", dict(headers)["Set-Cookie"])
        self.assertEqual(self.get("/", token)[0], 303)

    def test_not_a_member_is_a_404_and_no_session_is_a_redirect_to_sign_in(self):
        self.assertEqual(self.get("/rooms/11", "bob-token")[0], 404)         # Bob is not in Secret
        self.assertEqual(self.get("/rooms/10", "cy-token")[0], 404)          # Cy is in no room
        self.assertEqual(self.get("/rooms/99999", "ada-token")[0], 404)      # no such room
        self.assertEqual(self.get("/rooms/10")[0], 303)                      # no cookie
        self.assertEqual(self.get("/rooms/10", "nope")[0], 303)              # unknown token
        self.assertEqual(self.get("/", cookie="session_token=")[0], 303)     # empty token
        self.assertEqual(self.get("/rooms/10", "dee-token")[0], 303)         # deactivated user
        self.assertEqual(self.get("/rooms/abc", "ada-token")[0], 404)
        self.assertEqual(self.get("/elsewhere", "ada-token")[0], 404)


if __name__ == "__main__":
    unittest.main()
