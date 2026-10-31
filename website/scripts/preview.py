#!/usr/bin/env python3
"""本地预览使用与线上相同的无后缀公开页面路由。"""
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse

DIST = Path(__file__).resolve().parents[1] / 'dist'


class Handler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(DIST), **kwargs)

    def do_GET(self):
        path = urlparse(self.path).path
        if path in ('/portal', '/checkout.html'):
            self.send_response(302)
            self.send_header('Location', '/download')
            self.end_headers()
            return
        candidate = DIST / (path.lstrip('/') + '.html')
        if candidate.is_file():
            self.path = path + '.html'
        super().do_GET()


if __name__ == '__main__':
    print('Local: http://127.0.0.1:8788', flush=True)
    ThreadingHTTPServer(('127.0.0.1', 8788), Handler).serve_forever()
