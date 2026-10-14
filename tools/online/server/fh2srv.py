"""FH2 private-server stub. fh2net.dll sends every game web request here (fh2net.ini [http] Server),
with the host it was meant for in X-Fh2net-Host. Stage 1: record each request, answer 503.

  py -3 -I fh2srv.py [--port 8090] [--out <folder>]
"""
import argparse, datetime, http.server, json, os, threading

ap = argparse.ArgumentParser()
ap.add_argument('--port', type=int, default=8090)
ap.add_argument('--out', default=os.path.join(os.path.dirname(os.path.abspath(__file__)), 'captures'))
args = ap.parse_args()
os.makedirs(args.out, exist_ok=True)
lock = threading.Lock()
seq = [0]


class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'

    def handle_any(self):
        n = int(self.headers.get('Content-Length') or 0)
        body = self.rfile.read(n) if n else b''
        host = self.headers.get('X-Fh2net-Host', self.headers.get('Host', '?'))
        with lock:
            seq[0] += 1
            i = seq[0]
        stamp = datetime.datetime.now().strftime('%H:%M:%S.%f')[:-3]
        rec = {'n': i, 'time': stamp, 'method': self.command, 'host': host, 'path': self.path,
               'headers': {k: v for k, v in self.headers.items()}, 'body_len': len(body)}
        if body:
            name = f'{i:05d}-{host}.bin'
            with open(os.path.join(args.out, name), 'wb') as f: f.write(body)
            rec['body_file'] = name
            try: rec['body_text'] = body.decode('utf-8')[:4000]
            except UnicodeDecodeError: rec['body_hex'] = body[:256].hex()
        with lock, open(os.path.join(args.out, 'requests.jsonl'), 'a', encoding='utf-8') as f:
            f.write(json.dumps(rec) + '\n')
        print(f'{stamp} #{i} {self.command} {host}{self.path} ({len(body)} bytes)', flush=True)
        self.send_response(503)
        self.send_header('Content-Length', '0')
        self.end_headers()

    do_GET = do_POST = do_PUT = do_DELETE = do_HEAD = handle_any

    def log_message(self, *a): pass


print(f'fh2srv listening on 127.0.0.1:{args.port}, captures in {args.out}', flush=True)
http.server.ThreadingHTTPServer(('127.0.0.1', args.port), Handler).serve_forever()
