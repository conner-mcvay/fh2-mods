"""The game server's UDP side: a NerdCore relay (nerd.py has the formats).

Each console (peer) gets the server's side of the connection: OpenConnection is answered Ok, the console's
ResponseAck gets TimeSync and ConnectionSyncDone, Pings get Pongs, sequenced packets are acked, and the server
pings every half second (consoles drop a server that is quiet for 10 s).

Objects: the server owns one object itself, the lobby's SessionHost (router 6, type 0), which consoles wait for
before they finish joining (stateflow network_matchmaking.xml wait_for_session_host). Every object a console
creates or updates is forwarded to the other consoles with its handle marked as that console's (the relay
handle: peer index), and kept in a history that is replayed in order to consoles that join later. A console's
car (CarPredictionFull, ~30 a second, unsequenced) is forwarded the same way but not kept.

A console that starts over (an OpenConnection in packet 0: a new launch), goes quiet for 15 s or closes the
connection is dropped: the others get an ObjectDelete for each of its objects.

Game messages carry no length, so a packet is read only as far as its messages are understood; the rest of it
is logged and dropped (the packet is still acked).
"""
import itertools, json, os, socket, threading, time

import nerd

NAMES = {0: 'OpenConnection', 1: 'OpenConnectionResponse', 2: 'CloseConnection', 3: 'Ping', 4: 'Pong',
         5: 'TimeSync', 6: 'ConnectionSyncDone', 7: 'ObjectCreate', 8: 'ObjectUpdate', 9: 'ObjectDelete',
         10: 'ObjectRequestOwnership', 11: 'ObjectGrantOwnership', 12: 'ObjectTransferOwnership',
         13: 'ObjectNeedsUpdates', 14: 'PlayerInput', 15: 'CarPredictionFull', 34: 'FinaliseSessionEntry',
         35: 'MsgRepairDamage', 71: 'ServerTrafficMessage', 72: 'ClientTrafficMessage'}
OWN_ATTEMPT = 1
SESSION_HOST = (6, 0)        # router, object id of the server's SessionHost
QUIET_DROP_S = 15


class Peer:
    def __init__(self, addr, index):
        self.addr, self.index = addr, index
        self.acks = nerd.Acks()
        self.seq = itertools.count(1)        # our sequenced packet ids to this peer
        self.synced = False
        self.sync_index = 0
        self.user = None
        self.finalised = False               # SessionEntryFinalised sent
        self.console_id = None               # its ConsoleSynced object (router 3)
        self.server_seq = {}                 # (router, id) -> last server-update seq sent
        self.objects = {}                    # (router, id) -> last seq: what it owns
        self.last_seen = time.monotonic()
        self.cars = 0


class Relay:
    def __init__(self, out_dir, lock, port=5101, host='::'):
        self.out_dir, self.lock = out_dir, lock
        self.sock = socket.socket(socket.AF_INET6, socket.SOCK_DGRAM)
        self.sock.setsockopt(socket.IPPROTO_IPV6, socket.IPV6_V6ONLY, 0)   # IPv4 consoles too (as ::ffff:a.b.c.d)
        self.sock.bind((host, port))
        self.mu = threading.RLock()
        self.t0 = time.monotonic()
        self.peers = {}
        self.indices = itertools.count(1)
        self.history = []                    # (owner index, msg id, object dict) in arrival order
        self.seen = set()                    # (owner, msg, router, id, seq): consoles resend unacked messages
        self.n = 0
        print(f'fh2srv game UDP (relay) on [{host}]:{port}', flush=True)

    def now(self):
        return int((time.monotonic() - self.t0) * 1000) + 1

    def send(self, peer, msgs, sequenced=False):
        ack, ackbits = peer.acks.header()
        pid = next(peer.seq) & 0xFFFF if sequenced else nerd.NO_SEQ
        data = nerd.packet(nerd.concat(*msgs), count=len(msgs), pid=pid, ack=ack, ackbits=ackbits)
        try:
            self.sock.sendto(data, peer.addr)
        except OSError:
            pass
        return data

    def others(self, peer):
        return [p for p in self.peers.values() if p is not peer and p.synced]

    def forward(self, owner, msgs, sequenced=True):
        """Messages from `owner` to every other synced peer."""
        for p in self.others(owner):
            for i in range(0, len(msgs), 8):
                self.send(p, msgs[i:i + 8], sequenced=sequenced)

    def drop(self, peer, why):
        """Forget a console: its objects go from the history, and the others delete them."""
        self.peers.pop(peer.addr, None)
        self.history = [h for h in self.history if h[0] != peer.index]
        self.seen = {k for k in self.seen if k[0] != peer.index}
        deletes = [nerd.object_delete(router, id, seq + 1, peer=peer.index) for (router, id), seq in peer.objects.items()]
        if deletes:
            for p in self.peers.values():
                if p.synced:
                    for i in range(0, len(deletes), 8):
                        self.send(p, deletes[i:i + 8], sequenced=True)
        print(f'{time.strftime("%H:%M:%S")} peer {peer.index} [{peer.addr[0]}]:{peer.addr[1]} dropped ({why}); '
              f'{len(deletes)} objects deleted for the others', flush=True)

    def set_console_var(self, peer, index, value):
        """A server update of one of the server's bools on the peer's own ConsoleSynced object."""
        # The receiver takes updates strictly in order (link seq + 1, mod 255; 1417B1E70) and the first one
        # it expects from us is 0; later ones wait for the gap to fill.
        key = (3, peer.console_id)
        seq = peer.server_seq[key] = (peer.server_seq.get(key, -1) + 1) % 255
        return nerd.server_update(3, peer.console_id, seq, nerd.bool_var(index, value))

    def on_synced(self, peer):
        """The peer finished the handshake: TimeSync and ConnectionSyncDone, then the server's objects and
        everything the others own."""
        self.send(peer, [nerd.time_sync(peer.sync_index, self.now()), nerd.sync_done(OWN_ATTEMPT)])
        peer.sync_index += 1
        world = [nerd.object_msg(7, SESSION_HOST[0], SESSION_HOST[1], 0, type=0)]
        for owner, msg, o in self.history:
            world.append(nerd.object_msg(msg, o['router'], o['id'], o['seq'], o['payload'], peer=owner, type=o.get('type', 0)))
        for i in range(0, len(world), 8):    # a few messages per packet, well under the packet size limit
            self.send(peer, world[i:i + 8], sequenced=True)
        return len(world)

    def handle(self, data, addr):
        p = nerd.parse(data)
        if not p:
            return ['short packet'], None
        hdr, r = p
        peer = self.peers.get(addr)
        # A new launch from the same address starts over at packet 0 with an OpenConnection.
        if peer and peer.synced and hdr['id'] == 0 and r.left() >= 7 and nerd.BitReader(data, r.pos).bits(7) == 0:
            self.drop(peer, 'new connection')
            peer = None
        if peer is None:
            peer = self.peers[addr] = Peer(addr, next(self.indices) % 255 or next(self.indices))
        peer.last_seen = time.monotonic()
        out, notes, fwd, out_seq, cars = [], [], [], [], []
        peer.acks.add(hdr['id'])
        notes.append(f'peer {peer.index} id {hdr["id"]} cnt {hdr["count"]}')
        for _ in range(hdr['count']):
            if r.left() < 7:
                break
            msg = r.bits(7)
            name = NAMES.get(msg, f'msg {msg}')
            if msg == 0:
                oc = nerd.read_open_connection(r)
                peer.user = oc['user']
                notes.append(f'{name} user {oc["user"]} attempt {oc["attempt"]}')
                out.append(nerd.open_response(oc['flags'], 0, oc['attempt'], OWN_ATTEMPT))
            elif msg == 1:
                resp = nerd.read_open_response(r)
                notes.append(f'{name} reason {resp["reason"]}')
                if resp['reason'] == 6 and not peer.synced:
                    peer.synced = True
                    notes.append(f'synced; sent the world ({self.on_synced(peer)} objects)')
            elif msg == 2:
                notes.append(name)
                self.drop(peer, 'closed')
                return notes, None
            elif msg == 3:
                out.append(nerd.pong(nerd.read_ping(r)['time'], self.now()))
                notes.append(name)
            elif msg == 4:
                nerd.read_pong(r)
                notes.append(name)
            elif msg in (7, 8):
                try:
                    o = nerd.read_object(r, msg)
                except ValueError as e:
                    notes.append(f'{name}: {e}; rest not read ({r.left()} bits)')
                    break
                key = (peer.index, msg, o['router'], o['id'], o['seq'])
                notes.append(f'{name} router {o["router"]} id {o["id"]}' + (f' type {o["type"]}' if 'type' in o else '')
                             + f' seq {o["seq"]} {o["payload"].pos} bits' + (' (resent)' if key in self.seen else ''))
                if key in self.seen:
                    continue
                self.seen.add(key)
                if msg == 7 and o['router'] == 3:
                    peer.console_id = o['id']
                peer.objects[(o['router'], o['id'])] = o['seq']
                self.history.append((peer.index, msg, o))
                fwd.append(nerd.object_msg(msg, o['router'], o['id'], o['seq'], o['payload'], peer=peer.index, type=o.get('type', 0)))
            elif msg == 15:
                h, body = nerd.read_car(r)
                cars.append(nerd.car_msg(h['id'], body, peer=peer.index))
                peer.cars += 1
                notes.append(name)
            elif msg == 34:                  # no fields: the console has loaded the session's resources
                notes.append(name)
                if peer.console_id is not None and not peer.finalised:
                    peer.finalised = True
                    out_seq.append(self.set_console_var(peer, nerd.CONSOLE_SESSION_ENTRY_FINALISED, True))
                    notes.append('-> SessionEntryFinalised')
            else:
                notes.append(f'{name} (+{r.left()} bits, not read)')
                break
        if fwd:
            self.forward(peer, fwd)
        if cars:
            self.forward(peer, cars, sequenced=False)
        if out_seq:
            self.send(peer, out_seq, sequenced=True)
        reply = None
        if out or hdr['id'] != nerd.NO_SEQ:
            reply = self.send(peer, out)
        return notes, reply

    def run(self):
        while True:
            try:
                data, addr = self.sock.recvfrom(65536)
            except ConnectionResetError:     # Windows: a send of ours reached a closed port (a console left)
                continue
            with self.mu:
                self.n += 1
                notes, reply = self.handle(data, addr)
            rec = {'n': self.n, 'time': time.time(), 'from': f'[{addr[0]}]:{addr[1]}', 'hex': data.hex(), 'what': ' | '.join(notes)}
            if reply:
                rec['reply'] = reply.hex()
            if notes[1:] != ['CarPredictionFull']:   # the cars would fill the log; they are counted instead
                with self.lock, open(os.path.join(self.out_dir, 'udp.jsonl'), 'a', encoding='utf-8') as f:
                    f.write(json.dumps(rec) + '\n')
            quiet = all(x in ('Ping', 'Pong', 'CarPredictionFull') or x.startswith('peer ') for x in notes) and self.n > 30
            if not quiet or self.n % 500 == 0:
                print(f'{time.strftime("%H:%M:%S")} udp #{self.n} [{addr[0]}]:{addr[1]} {len(data)} bytes: {rec["what"]}', flush=True)

    def keepalive(self):
        """Ping each synced peer every half second (with the current acks); drop peers quiet for 15 s."""
        while True:
            time.sleep(0.5)
            with self.mu:
                for p in list(self.peers.values()):
                    if time.monotonic() - p.last_seen > QUIET_DROP_S:
                        self.drop(p, f'quiet for {QUIET_DROP_S} s')
                    elif p.synced:
                        self.send(p, [nerd.ping(self.now())])


def start(out_dir, lock, port=5101, host='::'):
    relay = Relay(out_dir, lock, port, host)
    threading.Thread(target=relay.run, daemon=True).start()
    threading.Thread(target=relay.keepalive, daemon=True).start()
    return relay
