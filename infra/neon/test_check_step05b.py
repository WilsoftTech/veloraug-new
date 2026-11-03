"""Tests for check_step05b.py. Run with: python -m unittest discover infra/neon

They use real HTTP responses from a local server, and make no outside request.
"""

import threading
import unittest
from http.server import BaseHTTPRequestHandler, HTTPServer

from check_step05b import denies_framing, fetch

POLICY = "default-src 'self'; frame-ancestors 'none'; base-uri 'none'"

RESPONSES = {
    "/lower-case": [("content-security-policy", POLICY)],
    "/usual-case": [("Content-Security-Policy", POLICY)],
    "/no-policy": [],
    "/no-directive": [("content-security-policy", "default-src 'self'")],
    "/allows-framing": [("content-security-policy", "frame-ancestors *")],
    "/report-only": [("content-security-policy-report-only", POLICY)],
}


class _Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        for name, value in RESPONSES[self.path]:
            self.send_header(name, value)
        self.send_header("Content-Length", "0")
        self.end_headers()

    def log_message(self, *args):
        pass


class DeniesFramingTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.server = HTTPServer(("127.0.0.1", 0), _Handler)
        threading.Thread(target=cls.server.serve_forever, daemon=True).start()
        cls.addClassCleanup(cls.server.server_close)
        cls.addClassCleanup(cls.server.shutdown)

    def _denies(self, path: str) -> bool:
        port = self.server.server_address[1]
        _, headers, _ = fetch(f"http://127.0.0.1:{port}{path}")
        return denies_framing(headers)

    def test_finds_the_policy_whatever_the_header_name_case(self):
        self.assertTrue(self._denies("/lower-case"))
        self.assertTrue(self._denies("/usual-case"))

    def test_still_fails_without_the_requirement(self):
        for path in ("/no-policy", "/no-directive", "/allows-framing", "/report-only"):
            with self.subTest(path):
                self.assertFalse(self._denies(path))


if __name__ == "__main__":
    unittest.main()
