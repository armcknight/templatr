#!/usr/bin/env python3
"""Serves a built site on localhost as CloudFront serves it. `make site serve`
runs it in the site's output directory:

    python3 serve-site.py <port>

Python's own http.server, with two of the distribution's behaviours: a
directory's address gets its index.html, and a page that does not exist is
answered with the site's 404.html and a 404 status, so the not-found page can
be tried before it is deployed. A site without a 404.html gets http.server's
own error page.
"""

import http.server
import os
import sys


class SiteHandler(http.server.SimpleHTTPRequestHandler):
    def send_error(self, code, message=None, explain=None):
        page = os.path.join(self.directory, '404.html')
        if code != 404 or not os.path.isfile(page):
            super().send_error(code, message, explain)
            return

        with open(page, 'rb') as f:
            body = f.read()
        self.send_response(404)
        self.send_header('Content-Type', 'text/html; charset=utf-8')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        if self.command != 'HEAD':
            self.wfile.write(body)


if __name__ == '__main__':
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8000
    server = http.server.ThreadingHTTPServer(('localhost', port), SiteHandler)
    server.serve_forever()
