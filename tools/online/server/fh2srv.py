"""FH2 private-server stub. fh2net.dll sends every game web request here (fh2net.ini [http] Server),
with the host it was meant for in X-Fh2net-Host. Every request is recorded in --out; Forza LSP calls
(X-ClassName / X-Method, binary bodies, see xls.py) that have a handler are answered, everything else
gets 503.

  py -3 -I fh2srv.py [--port 8090] [--out <folder>]
"""
import argparse, datetime, http.server, json, os, struct, sys, threading

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import xls

ap = argparse.ArgumentParser()
ap.add_argument('--port', type=int, default=8090)
ap.add_argument('--out', default=os.path.join(os.path.dirname(os.path.abspath(__file__)), 'captures'))
args = ap.parse_args()
os.makedirs(args.out, exist_ok=True)
lock = threading.Lock()
seq = [0]

print('reading message schemas from the game...', flush=True)
schema = xls.Schema()


def lsp_reply(results_type, results):
    """WEB_RESPONSE_HEADER (Result, ErrorCode, DataLength: u32 big-endian) + the encoded results."""
    data = xls.encode(schema.find(results_type), results)
    return struct.pack('>III', 0, 0, len(data)) + data


def logon(params):
    ld = params['loginData']
    return lsp_reply('ForzaUserLogon_Results', {'responseData': {
        'isProfileValid': True,
        'lastOnlineProfileUpdateAllTablesTranId': 0,
        'permissions': [],
        'featureAreasBanMask': 0,
        'userFlags': 0,
        'upsellOfferId': 0,
        'upsellText': '',
        'vipOfferIds': [],
        'userData': {
            'qwXuid': ld['xuid'], 'wzGamerTag': ld['gamerTag'], 'flags': 0, 'clubId': 0, 'clubTag': '',
            'clubTopTierCount': 0, 'roleInClub': 0, 'acceptsClubInvites': False,
            'currentCareerLevel': ld['currentCareerLevel'], 'currentBadgeId': ld['currentBadgeId'],
            'currentPlayerTitleId': ld['currentPlayerTitleId'],
        },
        'notificationNonce': 0,
        'notificationPollIntervalSeconds': 300,
        'defaultFriendsPollIntervalSeconds': 300,
        'maxFriendsPollIntervalSeconds': 600,
        'notificationCategories': [],
        'gameplayLogConfig': {'Enabled': False, 'FlushInterval': 300, 'Throttle': '00' * 0x15},
        'carsToUnshareFromGame': [],
        'defaultTimeoutMs': 30000,
        'defaultContentTimeoutMs': 60000,
        'defaultInGameTimeoutMs': 30000,
        'makeDiscounts': [], 'carDiscounts': [],
        'allCarDiscount': {'TokenDiscountAmount': 0.0, 'CreditDiscountAmount': 0.0, 'StartDate': xls.EPOCH, 'EndDate': xls.EPOCH, 'OfferId': 0},
        'makePartsDiscounts': [], 'carPartsDiscounts': [],
        'allPartsDiscount': {'TokenDiscountAmount': 0.0, 'CreditDiscountAmount': 0.0, 'StartDate': xls.EPOCH, 'EndDate': xls.EPOCH, 'OfferId': 0},
    }})


# (X-ClassName, X-Method) -> (parameters type, handler(decoded params) -> reply body)
LSP = {
    ('Forza.WebServices.User, Forza.WebServices', 'Logon'): ('ForzaUserLogon_Parameters', logon),
}


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

        status, reply, ctype = 503, b'', None
        call = (self.headers.get('X-ClassName'), self.headers.get('X-Method'))
        if call in LSP:
            ptype, fn = LSP[call]
            try:
                params, end = xls.decode(schema.find(ptype), body)
                rec['lsp_params'] = params
                reply, status, ctype = fn(params), 200, 'bin/xtsw'
                rec['reply_hex'] = reply.hex()
            except Exception as e:
                rec['lsp_error'] = repr(e)
        with lock, open(os.path.join(args.out, 'requests.jsonl'), 'a', encoding='utf-8') as f:
            f.write(json.dumps(rec) + '\n')
        what = f' [{call[1]} -> {status}, {len(reply)} bytes]' if call[1] else ''
        print(f'{stamp} #{i} {self.command} {host}{self.path} ({len(body)} bytes){what}', flush=True)
        self.send_response(status)
        if ctype: self.send_header('Content-Type', ctype)
        self.send_header('Content-Length', str(len(reply)))
        self.end_headers()
        self.wfile.write(reply)

    do_GET = do_POST = do_PUT = do_DELETE = do_HEAD = handle_any

    def log_message(self, *a): pass


print(f'fh2srv listening on 127.0.0.1:{args.port}, captures in {args.out}', flush=True)
http.server.ThreadingHTTPServer(('127.0.0.1', args.port), Handler).serve_forever()
