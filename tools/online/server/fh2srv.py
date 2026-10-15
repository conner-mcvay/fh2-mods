"""FH2 private-server stub. fh2net.dll sends every game web request here (fh2net.ini [http] Server),
with the host it was meant for in X-Fh2net-Host. Every request is recorded in --out; Forza LSP calls
(X-ClassName / X-Method, binary bodies, see xls.py) that have a handler are answered, everything else
gets 503.

  py -3 -I fh2srv.py [--port 8090] [--out <folder>]
"""
import argparse, datetime, hashlib, http.server, json, os, struct, sys, threading, time, uuid

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import relay, xls

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


def lsp_default(class_name, method, body, rec):
    """Any other LSP call: success, with its _Results type (if it has one) filled with defaults."""
    ptype, rtype = schema.call_types(class_name, method)
    if ptype and body:
        try: rec['lsp_params'], _ = xls.decode(ptype, body)
        except Exception as e: rec['lsp_params_error'] = repr(e)
    rec['lsp_types'] = [ptype and ptype['name'], rtype and rtype['name']]
    data = xls.encode(rtype, None) if rtype else b''
    return struct.pack('>III', 0, 0, len(data)) + data


# Xbox Live REST stand-ins: (host, path prefix) -> handler(method, path, body) -> (status, json)
GAME_VARIANT = '00000000-0000-0000-0000-00000000f001'
VARIANT_SCHEMA = '00000000-0000-0000-0000-00000000f002'
GSI_SET = '00000000-0000-0000-0000-00000000f003'
# The game picks server images whose name matches 'Release_' + its build hash + '\..*' (141838D70; the hash
# '6CC152FD' is the string at 142F4DAF0), unless a hopper's cloudGsiSetPattern says otherwise.
GSI_NAME = 'Release_6CC152FD.FreeRoam'
LOCATION = 'North Central US'   # the game's default datacenter (1422EDAE8)
# the dedicated server the game is told about (its secure device address is base64 of anything, for now)
SERVER_ADDRESS = 'ZmgybmV0LWdhbWUtc2VydmVy'   # "fh2net-game-server"
SERVER_HOST = '127.0.0.1'


def gsds_variants(method, path, body):
    # The game reads this into its GSDSVariant / GSDSVariantSchema / GSDSGSISet types, whose fields are all
    # strings (a JSON number or bool in a string field throws in its parser), so every value is a string.
    return 200, {
        'variants': [{'gamevariantId': GAME_VARIANT, 'name': GSI_NAME, 'isPublisher': 'false', 'rank': '1',
                      'gameVariantSchemaId': VARIANT_SCHEMA}],
        'variantSchemas': [{'variantSchemaId': VARIANT_SCHEMA, 'schemaContent': '{}', 'name': GSI_NAME}],
        'gsiSets': [{'minRequiredPlayers': '1', 'maxAllowedPlayers': '12', 'gsiSetId': GSI_SET, 'gsiSetName': GSI_NAME,
                     'selectionOrder': '1', 'variantSchemaId': VARIANT_SCHEMA}],
    }


def gsds(method, path, body):
    p = path.split('?')[0]
    if p.endswith('/variants'): return gsds_variants(method, path, body)
    if p == '/qosservers':
        # ForzaLiveThunderheadGetQosServers_Results.qosServers: GSDSQosServer (serverFqdn,
        # serverSecureDeviceAddress (base64), targetLocation), all strings.
        servers = [{'serverFqdn': 'qos.fh2net.local', 'serverSecureDeviceAddress': 'ZmgybmV0LXFvcy1zZXJ2ZXI=',
                    'targetLocation': LOCATION}]
        # Microsoft.Xbox.Services.dll parses this with Windows.Data.Json (Azimuth's) and reads the array named
        # qosServers (1800989C0 -> 18009FF00). With a second 'qosservers' key as well, the game got an empty list.
        return 200, {'qosServers': servers}
    return 503, None


MPSD = {}          # session path -> session document (multiplayer session directory, contract 105)
MPSD_LOCK = threading.Lock()


def merge(dst, src):
    for k, v in src.items():
        if isinstance(v, dict) and isinstance(dst.get(k), dict): merge(dst[k], v)
        elif v is None: dst.pop(k, None)
        else: dst[k] = v


PREALLOCATE = True    # game sessions get their server at once: the game then offers 'free roam session found, press Select to join'


def server_entry(location):
    return {'constants': {'system': {}, 'custom': {}}, 'properties': {'system': {}, 'custom': {
        'status': 'Active', 'datacenter': location, 'secureDeviceAddress': SERVER_ADDRESS, 'hostName': SERVER_HOST}}}


def gsms(method, path, body):
    # Game server management: POST /titles/<gameServerTitleId>/clusters {sessionId ...} (XSAPI AllocateClusterAsync).
    # The session named gets its server entry, and the cluster is answered as fulfilled.
    p = path.split('?')[0]
    if method != 'POST' or not p.endswith('/clusters'): return 503, None
    req = json.loads(body or b'{}')
    sid = req.get('sessionId', '')
    with MPSD_LOCK:
        for k, doc in MPSD.items():
            if sid and (k.lower().endswith(sid.lower().split('/')[-1]) or sid.lower() in k.lower()):
                gsp = doc['constants'].get('custom', {}).get('gameServerPlatform', {})
                doc['servers']['gameServerPlatform'] = server_entry(gsp.get('location', LOCATION))
                break
    return 200, {'pollIntervalMilliseconds': 1000, 'fulfillmentState': 'Fulfilled', 'hostName': SERVER_HOST,
                 'region': LOCATION, 'secureDeviceAddress': SERVER_ADDRESS,
                 'portMappings': [{'name': 'Game', 'value': 5100, 'internal': 5100, 'external': 5100}]}


def mpsd_sessions(method, path, body, xuid='2533274790395904', gamertag='Player 1'):
    p = path.split('?')[0]
    if method == 'GET' and p.endswith('/sessions'):
        # the sessions a user is in; listing earlier runs' sessions made the game try to rejoin them at startup
        return 200, {'results': []}
    if '/sessions/' not in p: return 503, None
    # ISO 8601 with milliseconds, as the session directory wrote them (6-digit fractions are rejected)
    now = datetime.datetime.utcnow().strftime('%Y-%m-%dT%H:%M:%S.%f')[:-3] + 'Z'
    with MPSD_LOCK:
        doc = MPSD.get(p)
        if method == 'GET':
            return (200, doc) if doc else (404, {})
        if method == 'DELETE':
            MPSD.pop(p, None); return 204, {}
        req = json.loads(body or b'{}')
        new = doc is None
        if new:
            # the fields Microsoft.Xbox.Services.dll's session deserializer reads (180112A90, 1801236E0)
            doc = {'contractVersion': 105, 'correlationId': str(uuid.uuid4()), 'startTime': now, 'nextTimer': now,
                   'constants': {'system': {}, 'custom': {}},
                   'properties': {'system': {'keywords': [], 'turn': [], 'joinRestriction': 'none'}, 'custom': {}},
                   'servers': {}, 'members': {}, 'hostCandidates': [],
                   'membersInfo': {'first': 0, 'next': 0, 'count': 0, 'accepted': 0, 'active': 0}}
        members = req.pop('members', None) or {}
        merge(doc, req)
        for key, m in members.items():
            if key == 'me' or key.startswith('reserve_'):
                idx = next((i for i, v in doc['members'].items() if v['constants']['system'].get('xuid') == xuid), None)
                if m is None:
                    if idx is not None: doc['members'].pop(idx)
                    continue
                if idx is None:
                    idx = str(doc['membersInfo']['next']); doc['membersInfo']['next'] += 1
                    doc['members'][idx] = {'constants': {'system': {'xuid': xuid, 'index': int(idx)}, 'custom': {}},
                                           'properties': {'system': {'active': False, 'ready': False}, 'custom': {}}, 'gamertag': gamertag,
                                           'deviceToken': hashlib.md5(('fh2net-device-' + xuid).encode()).hexdigest().upper(), 'nat': 'open', 'activeTitleId': '446059611', 'reserved': False,
                                           'joinTime': now, 'turn': False, 'initializationEpisode': 0}
                merge(doc['members'][idx], m)
        # A game session (constants.custom.gameServerPlatform) gets its dedicated server at once, as Turn 10's
        # allocation (Xbox Live Compute) used to write it: the game (14183B360) reads
        # servers.gameServerPlatform.properties.custom: status Active / Queued / Error / Quarantined, then
        # datacenter, secureDeviceAddress (base64) and hostName.
        gsp = doc['constants'].get('custom', {}).get('gameServerPlatform')
        if gsp and 'gameServerPlatform' not in doc['servers'] and PREALLOCATE:
            doc['servers']['gameServerPlatform'] = {'constants': {'system': {}, 'custom': {}}, 'properties': {'system': {}, 'custom': {
                'status': 'Active', 'datacenter': gsp.get('location', LOCATION),
                'secureDeviceAddress': SERVER_ADDRESS, 'hostName': SERVER_HOST}}}
        mi = doc['membersInfo']; mi['count'] = len(doc['members']); mi['accepted'] = mi['count']
        mi['active'] = sum(1 for v in doc['members'].values() if v['properties']['system'].get('active'))
        if doc['members']: mi['first'] = min(int(i) for i in doc['members'])
        MPSD[p] = doc
        return (201 if new else 200), doc


def profile(method, path, body, xuid='2533274790395904', gamertag='Player 1'):
    # Profile settings (XSAPI ProfileService): POST /users/batch/profile/settings {userIds, settings} answers
    # every user asked for; GET /users/me/profile/settings/people/People (the friends' profiles) answers none.
    p = path.split('?')[0]
    if p.endswith('/people/People'):
        return 200, {'profileUsers': []}
    if method != 'POST' or not p.endswith('/batch/profile/settings'): return 503, None
    req = json.loads(body or b'{}')
    users = []
    for uid in req.get('userIds', []):
        tag = gamertag if uid == xuid else f'Driver {str(uid)[-4:]}'
        # The picture settings must be URLs: XSAPI makes a Uri of each, and the game (14124D790) reads the
        # game picture's Uri without a null check, so an empty value crashes it.
        pic = 'http://images-eds.xboxlive.com/image?url=fh2srv&format=png'
        values = {'Gamertag': tag, 'GameDisplayName': tag, 'AppDisplayName': tag, 'AccountTier': 'Gold',
                  'Gamerscore': '0', 'GameDisplayPicRaw': pic, 'AppDisplayPicRaw': pic}
        users.append({'id': uid, 'hostId': uid, 'isSponsoredUser': False,
                      'settings': [{'id': s, 'value': values.get(s, '')} for s in req.get('settings', [])]})
    return 200, {'profileUsers': users}


REST = [
    ('profile.xboxlive.com', '/users/', profile),
    ('gameserverds.xboxlive.com', '/', gsds),
    ('sessiondirectory.xboxlive.com', '/serviceconfigs/', mpsd_sessions),
    ('gameserverms.xboxlive.com', '/titles/', gsms),
]


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
        elif call[1]:
            try:
                reply, status, ctype = lsp_default(call[0], call[1], body, rec), 200, 'bin/xtsw'
            except Exception as e:
                rec['lsp_error'] = repr(e)
        else:
            for h, prefix, fn in REST:
                if host.lower() == h and self.path.startswith(prefix):
                    st, obj = fn(self.command, self.path, body)
                    if obj is not None:
                        status, reply, ctype = st, json.dumps(obj).encode(), 'application/json'
                        rec['reply_text'] = reply.decode()[:4000]
                    break
        with lock, open(os.path.join(args.out, 'requests.jsonl'), 'a', encoding='utf-8') as f:
            f.write(json.dumps(rec) + '\n')
        what = f' [{call[1]} -> {status}, {len(reply)} bytes]' if call[1] else ''
        print(f'{stamp} #{i} {self.command} {host}{self.path} ({len(body)} bytes){what}', flush=True)
        self.send_response(status)
        if ctype: self.send_header('Content-Type', ctype)
        if ctype == 'application/json': self.send_header('ETag', '"%d"' % i)
        self.send_header('Content-Length', str(len(reply)))
        self.end_headers()
        self.wfile.write(reply)

    do_GET = do_POST = do_PUT = do_DELETE = do_HEAD = handle_any

    def log_message(self, *a): pass


relay.start(args.out, lock)
print(f'fh2srv listening on 127.0.0.1:{args.port}, captures in {args.out}', flush=True)
http.server.ThreadingHTTPServer(('127.0.0.1', args.port), Handler).serve_forever()
