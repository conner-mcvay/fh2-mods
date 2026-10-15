"""The game server's UDP side: a NerdCore relay (nerd.py has the formats).

Each console (peer) gets the server's side of the connection: OpenConnection is answered Ok, the console's
ResponseAck gets TimeSync and ConnectionSyncDone, Pings get Pongs, sequenced packets are acked.

Objects: the server owns one object itself, the lobby's SessionHost (router 6, type 0), which consoles wait for
before they finish joining (stateflow network_matchmaking.xml wait_for_session_host). Every object a console
creates or updates is forwarded to the other consoles with its handle marked as that console's (peer index),
and kept in a history that is replayed in order to consoles that join later.

Game messages carry no length, so a packet is read only as far as its messages are understood; the rest of it
is logged and dropped (the packet is still acked).
"""
import itertools, json, os, socket, threading, time

import nerd

NAMES = {0: 'OpenConnection', 1: 'OpenConnectionResponse', 2: 'CloseConnection', 3: 'Ping', 4: 'Pong',
         5: 'TimeSync', 6: 'ConnectionSyncDone', 7: 'ObjectCreate', 8: 'ObjectUpdate', 9: 'ObjectDelete',
         10: 'ObjectRequestOwnership', 11: 'ObjectGrantOwnership', 12: 'ObjectTransferOwnership',
         13: 'ObjectNeedsUpdates', 14: 'PlayerInput', 15: 'CarPredictionFull', 34: 'FinaliseSessionEntry'}
OWN_ATTEMPT = 1
SESSION_HOST = (6, 0)        # router, object id of the server's SessionHost


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


class Relay:
    def __init__(self, out_dir, lock, port=5101, host='::1'):
        self.out_dir, self.lock = out_dir, lock
        self.sock = socket.socket(socket.AF_INET6, socket.SOCK_DGRAM)
        self.sock.bind((host, port))
        self.t0 = time.monotonic()
        self.peers = {}
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
        self.sock.sendto(data, peer.addr)
        return data

    def forward(self, owner, msgs):
        """Object messages from `owner` to every other synced peer, marked as owner's."""
        for p in self.peers.values():
            if p is not owner and p.synced:
                for i in range(0, len(msgs), 8):
                    self.send(p, msgs[i:i + 8], sequenced=True)

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
        peer = self.peers.get(addr)
        if peer is None:
            peer = self.peers[addr] = Peer(addr, len(self.peers) + 1)
        out, notes, fwd, out_seq = [], [], [], []
        p = nerd.parse(data)
        if not p:
            return ['short packet'], None
        hdr, r = p
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
                self.history.append((peer.index, msg, o))
                fwd.append(nerd.object_msg(msg, o['router'], o['id'], o['seq'], o['payload'], peer=peer.index, type=o.get('type', 0)))
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
            self.n += 1
            notes, reply = self.handle(data, addr)
            rec = {'n': self.n, 'time': time.time(), 'from': f'[{addr[0]}]:{addr[1]}', 'hex': data.hex(), 'what': ' | '.join(notes)}
            if reply:
                rec['reply'] = reply.hex()
            with self.lock, open(os.path.join(self.out_dir, 'udp.jsonl'), 'a', encoding='utf-8') as f:
                f.write(json.dumps(rec) + '\n')
            quiet = all(x in ('Ping', 'Pong') or x.startswith('peer ') for x in notes) and self.n > 30
            if not quiet or self.n % 100 == 0:
                print(f'{time.strftime("%H:%M:%S")} udp #{self.n} {len(data)} bytes: {rec["what"]}', flush=True)


    def keepalive(self):
        """Consoles drop a server they haven't heard from for 10 s, and stop pinging once they're in: ping each
        synced peer every half second (with the current acks)."""
        while True:
            time.sleep(0.5)
            for p in list(self.peers.values()):
                if p.synced:
                    try:
                        self.send(p, [nerd.ping(self.now())])
                    except OSError:
                        pass


def start(out_dir, lock, port=5101):
    relay = Relay(out_dir, lock, port)
    threading.Thread(target=relay.run, daemon=True).start()
    threading.Thread(target=relay.keepalive, daemon=True).start()
    return relay
