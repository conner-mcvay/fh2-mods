"""FH2 private-server stub. fh2net.dll sends every game web request here (fh2net.ini [http] Server),
with the host it was meant for in X-Fh2net-Host. Every request is recorded in --out; Forza LSP calls
(X-ClassName / X-Method, binary bodies, see xls.py) that have a handler are answered, everything else
gets 503.

  py -3 -I fh2srv.py --game <FH2 game folder> [--host 0.0.0.0] [--port 8090] [--out <folder>]
"""
import argparse, datetime, hashlib, http.server, json, os, random, struct, sys, threading, time, uuid

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import relay, xls

ap = argparse.ArgumentParser()
ap.add_argument('--port', type=int, default=8090)
ap.add_argument('--host', default='127.0.0.1', help='HTTP address to listen on; 0.0.0.0 for consoles on the LAN')
ap.add_argument('--game-port', type=int, default=5101, help="the relay's UDP port (all addresses, IPv4 and IPv6)")
ap.add_argument('--mirror', type=float, help='testing alone: send each console itself back as a ghost player, its car this many seconds late')
ap.add_argument('--game', default=os.environ.get('FH2_GAME', xls.EXE),
                help='the FH2 game folder (Anthem_1.0.0.64_x64__8wekyb3d8bbwe) or its exe; the message schemas are read from it')
ap.add_argument('--out', default=os.path.join(os.path.dirname(os.path.abspath(__file__)), 'captures'))
args = ap.parse_args()
os.makedirs(args.out, exist_ok=True)
lock = threading.Lock()
seq = [0]

print('reading message schemas from the game...', flush=True)
exe = args.game
if os.path.isdir(exe): exe = os.path.join(exe, 'Mount', 'forza_durango_release_final.exe')
if not os.path.isfile(exe): sys.exit(f'FH2 game not found: {exe} (pass --game <FH2 game folder>)')
schema = xls.Schema(exe)


def lsp_reply(results_type, results):
    """WEB_RESPONSE_HEADER (Result, ErrorCode, DataLength: u32 big-endian) + the encoded results."""
    data = xls.encode(schema.find(results_type), results)
    return struct.pack('>III', 0, 0, len(data)) + data


def logon(params, ctx):
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


# Liveries. Saving a design while online sends it with OnlineProfile.UpdateLivery (name, carId, numberOfLayers,
# isLocked, creatorXuid, data: the compressed design), then ContentVersioning.CreateVersionedLivery (name,
# carId, thumbnail) asks for a versioned copy of that same livery and gets its id, which travels with the car;
# other consoles fetch it with RetrieveVersionedLiveryById (-> VersionedLiveryData: profileId, carId,
# numberOfLayers, creatorXuid, data, thumbnails). Profile liveries are kept in data/profile_liveries/<xuid>/,
# versioned ones in data/liveries/<id>.json. Garage cars whose design was made offline have
# VersionedLiveryId -1 until the design is saved again online.
LIVERIES = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'data', 'liveries')
PROFILE_LIVERIES = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'data', 'profile_liveries')
os.makedirs(LIVERIES, exist_ok=True)
LIVERY_LOCK = threading.Lock()


def profile_livery_path(xuid, car_id, name):
    safe = ''.join(c for c in name if c.isalnum() or c in '_-')[:100]
    return os.path.join(PROFILE_LIVERIES, str(xuid), f'{car_id}_{safe}.json')


def update_livery(params, ctx):
    path = profile_livery_path(ctx['xuid'], params['carId'], params['name'])
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with LIVERY_LOCK, open(path, 'w', encoding='utf-8') as f:
        json.dump(params, f)
    print(f'profile livery from {ctx["xuid"]}: car {params["carId"]} "{params["name"]}", '
          f'{params["numberOfLayers"]} layers, {len(params["data"]) // 2} bytes', flush=True)
    return struct.pack('>III', 0, 0, 0)


def create_versioned_livery(params, ctx):
    with LIVERY_LOCK:
        ids = [int(f.split('.')[0]) for f in os.listdir(LIVERIES) if f.split('.')[0].isdigit()]
        lid = max(ids, default=1000) + 1
        rec = {'id': lid, 'xuid': ctx['xuid'], 'params': params}
        src = profile_livery_path(ctx['xuid'], params['carId'], params['name'])
        if os.path.exists(src):   # the design itself, from the UpdateLivery just before
            with open(src, encoding='utf-8') as f:
                prof = json.load(f)
            rec['data'], rec['layers'] = prof['data'], prof['numberOfLayers']
        with open(os.path.join(LIVERIES, f'{lid}.json'), 'w', encoding='utf-8') as f:
            json.dump(rec, f)
    print(f'livery {lid} created by {ctx["xuid"]}: car {params.get("carId")} "{params.get("name")}", '
          f'design {"found" if "data" in rec else "NOT found"}', flush=True)
    return lsp_reply('ForzaContentVersioningCreateVersionedLivery_Results', {'versionedLiveryId': lid})


def retrieve_versioned_livery(params, ctx):
    lid = params['versionedLiveryId']
    path = os.path.join(LIVERIES, f'{lid}.json')
    if not os.path.exists(path):
        print(f'livery {lid} asked for by {ctx["xuid"]}: not stored', flush=True)
        return struct.pack('>III', 2, 1, 0)   # an error result
    with open(path, encoding='utf-8') as f:
        rec = json.load(f)
    p = rec['params']
    data = {'profileId': 0, 'carId': p.get('carId', 0), 'numberOfLayers': rec.get('layers', 0),
            'creatorXuid': int(rec['xuid']), 'data': rec.get('data', ''),
            'liveryThumbnail': p.get('LiveryThumbnail', '') if params.get('returnThumbnail') else '',
            'liveryThumbnailSmall': ''}
    print(f'livery {lid} sent to {ctx["xuid"]}', flush=True)
    return lsp_reply('ForzaContentVersioningRetrieveVersionedLiveryById_Results', {'versionedLiveryData': data})


# (X-ClassName, X-Method) -> (parameters type, handler(decoded params, ctx) -> reply body); ctx has the raw
# body, where the parameters end in it, and the caller's xuid
LSP = {
    ('Forza.WebServices.User, Forza.WebServices', 'Logon'): ('ForzaUserLogon_Parameters', logon),
    ('Forza.WebServices.OnlineProfile, Forza.WebServices', 'UpdateLivery'):
        ('ForzaWebServicesOnlineProfileUpdateLivery_Parameters', update_livery),
    ('Forza.WebServices.ContentVersioning, Forza.WebServices', 'CreateVersionedLivery'):
        ('ForzaContentVersioningCreateVersionedLivery_Parameters', create_versioned_livery),
    ('Forza.WebServices.ContentVersioning, Forza.WebServices', 'RetrieveVersionedLiveryById'):
        ('ForzaContentVersioningRetrieveVersionedLiveryById_Parameters', retrieve_versioned_livery),
}


def load_drivatar_cache():
    r"""The game's offline drivatars, media\drivatarglobalcache\DefaultCache.bin (Mount\mediapc first): u32
    version 4, u32 count, then count records of 9816 bytes - DrivatarRacingInfo as the game stores the ones it gets
    from GetDrivatarsForCache (it writes them in the same format to its
    Turn10Temp.scratch\DrivatarGlobalCache\DownloadCache.bin). Per record: GamerTag (UTF-16, 16 chars) at 0, Xuid (u64) at 0x28 (0 for all of these),
    CarId/LiveryId/TuneId at 0x30/0x38/0x40 (-1: none), segment slots from 0x48, UserSkillLevel (u32) at 0x2648,
    wristbandLevel at 0x264C (XP-sized: 46000..1850000; the drivatar's level follows it)."""
    mount = os.path.join(os.path.dirname(os.path.dirname(exe)), 'Mount')
    for media in ('mediapc', 'media'):
        p = os.path.join(mount, media, 'drivatarglobalcache', 'DefaultCache.bin')
        if os.path.isfile(p): break
    else:
        print('no drivatarglobalcache\\DefaultCache.bin; drivatars get no names', flush=True)
        return []
    d = open(p, 'rb').read()
    ver, n = struct.unpack_from('<II', d, 0)
    if ver != 4 or 8 + 9816 * n != len(d):
        print(f'unexpected {p} (version {ver}, {n} records, {len(d)} bytes); drivatars get no names', flush=True)
        return []
    out = []
    for i in range(n):
        r = d[8 + 9816 * i:8 + 9816 * (i + 1)]
        out.append({'GamerTag': r[:32].decode('utf-16le').split('\0')[0], 'IsFriend': False,
                    'Xuid': struct.unpack_from('<Q', r, 0x28)[0], 'CarId': struct.unpack_from('<I', r, 0x30)[0],
                    'LiveryId': struct.unpack_from('<Q', r, 0x38)[0], 'TuneId': struct.unpack_from('<Q', r, 0x40)[0],
                    'UserSkillLevel': struct.unpack_from('<I', r, 0x2648)[0],
                    'wristbandLevel': struct.unpack_from('<i', r, 0x264C)[0]})
    return out


DRIVATARS = load_drivatar_cache()


def drivatars_for_cache(params, ctx):
    """The drivatars the game keeps for single player: its own offline ones, as they are. Answering an empty list
    left drivatars nameless (DriverXXX); an error left none at all. A Xuid other than the file's 0 also shows as
    "Driver NNNN", and a small wristbandLevel as level 1."""
    want = params.get('numberOfDrivatars') or len(DRIVATARS)
    return lsp_reply('ForzaWebServicesDrivatarGetDrivatarsForCache_Results', {'drivatarInfos': DRIVATARS[:want]})


LSP[('Forza.WebServices.Drivatar, Forza.WebServices', 'GetDrivatarsForCache')] = \
    ('ForzaWebServicesDrivatarGetDrivatarsForCache_Parameters', drivatars_for_cache)


def drivatars_for_race(params, ctx):
    """Drivatars for a race or free roam (bucketId 0): numberOfDrivatars of the offline ones, different names,
    in the asked bucket; the game picks their cars (CarId -1, as in its own cache)."""
    want = params.get('numberOfDrivatars') or 0
    seen, pick = set(), []
    for i in random.sample(range(len(DRIVATARS)), len(DRIVATARS)):
        if DRIVATARS[i]['GamerTag'] not in seen: seen.add(DRIVATARS[i]['GamerTag']); pick.append(i)
        if len(pick) == want: break
    infos = [dict(DRIVATARS[i], BucketId=params.get('bucketId', 0)) for i in pick]
    return lsp_reply('ForzaWebServicesDrivatarGetDrivatarInformationForRace_Results', {'drivatarInfos': infos})


LSP[('Forza.WebServices.Drivatar, Forza.WebServices', 'GetDrivatarInformationForRace')] = \
    ('ForzaWebServicesDrivatarGetDrivatarInformationForRace_Parameters', drivatars_for_race)


def economy_settings(params, ctx):
    """The game's own built-in economy values (what a profile that never got server values saves in its
    ForzaEconomyState). The game stores whatever this returns in the save, so zeros here zero every race reward
    from then on, offline too."""
    return lsp_reply('ForzaUserGetEconomySettings_Results', {'settings': {
        'creditDestinationBonus': 30000, 'creditDestinationFalloff': 2000,
        'xpPerKmOffline': 800, 'xpPerKmOnline': 640, 'creditPerKm': 960, 'minimumFinishLineXp': 0,
        'tombolaPrizeScale': 1.0, 'promoBonusScale': 1.0, 'wagerRaceCost': 0,
        'enableTokens': False, 'enableXboxMusic': False}})


LSP[('Forza.WebServices.User, Forza.WebServices', 'GetEconomySettings')] = (None, economy_settings)


# Calls answered with an error, as when Turn 10's servers were down, so the game keeps its own values instead
# of taking defaults from a success (online credits: 0).
LSP_UNAVAILABLE = {
    ('Forza.WebServices.User, Forza.WebServices', 'RetrieveOnlineCredits'),
}


def lsp_default(class_name, method, body, rec):
    """Any other LSP call: success, with its _Results type (if it has one) filled with defaults - or, for
    LSP_UNAVAILABLE, an error (Result 2, ErrorCode, DataLength-byte message)."""
    ptype, rtype = schema.call_types(class_name, method)
    if ptype and body:
        try: rec['lsp_params'], _ = xls.decode(ptype, body)
        except Exception as e: rec['lsp_params_error'] = repr(e)
    rec['lsp_types'] = [ptype and ptype['name'], rtype and rtype['name']]
    if (class_name, method) in LSP_UNAVAILABLE:
        msg = b'service unavailable'
        rec['lsp_unavailable'] = True
        return struct.pack('>III', 2, 1, len(msg)) + msg
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


DEFAULT_XUID = '2533274790395904'   # Azimuth's
GAMERTAGS = {}                       # xuid -> gamertag, from the consoles' X-Fh2net-* headers


def mpsd_sessions(method, path, body, xuid=DEFAULT_XUID, gamertag='Player 1'):
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


def profile(method, path, body, xuid=DEFAULT_XUID, gamertag='Player 1'):
    # Profile settings (XSAPI ProfileService): POST /users/batch/profile/settings {userIds, settings} answers
    # every user asked for; GET /users/me/profile/settings/people/People (the friends' profiles) answers none.
    p = path.split('?')[0]
    if p.endswith('/people/People'):
        return 200, {'profileUsers': []}
    if method != 'POST' or not p.endswith('/batch/profile/settings'): return 503, None
    req = json.loads(body or b'{}')
    users = []
    for uid in req.get('userIds', []):
        tag = gamertag if uid == xuid else GAMERTAGS.get(uid, f'Driver {str(uid)[-4:]}')
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
                params, end = xls.decode(schema.find(ptype), body) if ptype else ({}, 0)
                rec['lsp_params'] = params
                ctx = {'body': body, 'end': end, 'xuid': self.headers.get('X-Fh2net-Xuid', DEFAULT_XUID)}
                reply, status, ctype = fn(params, ctx), 200, 'bin/xtsw'
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
                    if fn in (mpsd_sessions, profile):
                        # who is asking (fh2net sends it; every console's token is the same made-up one)
                        xuid = self.headers.get('X-Fh2net-Xuid', DEFAULT_XUID)
                        gamertag = self.headers.get('X-Fh2net-Gamertag', 'Player 1')
                        GAMERTAGS[xuid] = gamertag
                        st, obj = fn(self.command, self.path, body, xuid, gamertag)
                    else:
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


relay.start(args.out, lock, args.game_port, mirror=args.mirror)
print(f'fh2srv listening on {args.host}:{args.port}, captures in {args.out}', flush=True)
http.server.ThreadingHTTPServer((args.host, args.port), Handler).serve_forever()
