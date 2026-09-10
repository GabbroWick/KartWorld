"""Serve the Web export locally: python tools/serve_web.py  ->  http://localhost:8060

Adds the cross-origin isolation headers Godot needs when thread support is on.
Our preset exports without threads, so plain hosting works too; the headers
never hurt.
"""
import http.server, os, sys

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8060
ROOT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "builds", "web")


class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=ROOT, **kwargs)

    def end_headers(self):
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        self.send_header("Cache-Control", "no-store")
        super().end_headers()


if __name__ == "__main__":
    print(f"Serving {ROOT} on http://localhost:{PORT}  (Ctrl+C to stop)")
    http.server.ThreadingHTTPServer(("", PORT), Handler).serve_forever()
