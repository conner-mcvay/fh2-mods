"""NerdCore (Engine\\NetV2\\NerdCore) UDP packets, as the game reads and writes them.

Packet: an 11-byte header, then messages in a bit stream (LSB first, padded to a byte at the end).
  header (14176D3E0): id u16, ack u16, ack bits u32, message count u8, packet size u16 (whole packet, bytes);
  little-endian. An id of 0xFFFF skips the receiver's sequence check (Connection::ReadPacketHeader, 1417672B0).
Message: id in 7 bits (BitStream::WriteBits, 14176B380), then its fields.
  Compact uint (14176AA80): 2-bit size s, then 8*s+6 bits.  String (14176A900): compact length, then 8-bit chars.

Connection messages:
  0 OpenConnection (14176D450): version str (max 38), game str (max 16), 2 bits, u64 user id, u32, u32,
    u32 connect attempt (the client's [conn+0x24]).
  1 OpenConnectionResponse (14176D770): 2 bits (echoed), 3-bit reason, u32 (must equal the client's attempt),
    u32 (the sender's own attempt; the client keeps it in [conn+0x28]).
    Reasons (141765B30 / 141765EC0): 0 Ok, 1 version mismatch, 2 game mismatch, 3 banned, 4/5 refused,
    6 ResponseAck (the client's answer to Ok, after which both sides count as connected).
"""
import struct

HEADER = struct.Struct('<HHIBH')
NO_SEQ = 0xFFFF


class BitReader:
    def __init__(self, data, pos=0):
        self.data, self.pos = data, pos

    def bits(self, n):
        v = 0
        for i in range(n):
            p = self.pos + i
            v |= ((self.data[p >> 3] >> (p & 7)) & 1) << i
        self.pos += n
        return v

    def cuint(self):
        return self.bits(8 * self.bits(2) + 6)

    def string(self):
        return bytes(self.bits(8) for _ in range(self.cuint())).decode('latin1')

    def left(self):
        return len(self.data) * 8 - self.pos


class BitWriter:
    def __init__(self):
        self.buf, self.pos = bytearray(), 0

    def bits(self, v, n):
        for i in range(n):
            if self.pos >> 3 >= len(self.buf):
                self.buf.append(0)
            self.buf[self.pos >> 3] |= ((v >> i) & 1) << (self.pos & 7)
            self.pos += 1
        return self

    def cuint(self, v):
        s = 3 if v & 0xFFC00000 else 2 if v & 0xFFC000 else 1 if v & 0xFFC0 else 0
        return self.bits(s, 2).bits(v, 8 * s + 6)

    def string(self, s):
        b = s.encode('latin1')
        self.cuint(len(b))
        for c in b:
            self.bits(c, 8)
        return self


def parse(data):
    """(header dict, BitReader at the first message) or None if too short."""
    if len(data) < HEADER.size:
        return None
    pid, ack, ackbits, count, size = HEADER.unpack_from(data)
    return dict(id=pid, ack=ack, ackbits=ackbits, count=count, size=size), BitReader(data, HEADER.size * 8)


def packet(body: BitWriter, count=1, pid=NO_SEQ, ack=0xFFFE, ackbits=0):
    size = HEADER.size + len(body.buf)
    return HEADER.pack(pid, ack, ackbits, count, size) + bytes(body.buf)


def read_open_connection(r):
    return dict(version=r.string(), game=r.string(), flags=r.bits(2), user=r.bits(64),
                a=r.bits(32), b=r.bits(32), attempt=r.bits(32))


def read_open_response(r):
    return dict(flags=r.bits(2), reason=r.bits(3), attempt=r.bits(32), peer_attempt=r.bits(32))


def open_response(flags, reason, attempt, own_attempt):
    return BitWriter().bits(1, 7).bits(flags, 2).bits(reason, 3).bits(attempt, 32).bits(own_attempt, 32)


# Ping/Pong (14176DA90 / 14176DBA0): the client pings with its time (ms); the answer is Pong(its time, our
# time); it then measures its round trip and answers Pong(0, our time) for ours (1417666C0).
def read_ping(r):
    return dict(time=r.bits(32))


def read_pong(r):
    return dict(echo=r.bits(32), time=r.bits(32))


def ping(now):
    return BitWriter().bits(3, 7).bits(now & 0xFFFFFFFF, 32)


def pong(echo, now):
    return BitWriter().bits(4, 7).bits(echo & 0xFFFFFFFF, 32).bits(now & 0xFFFFFFFF, 32)


# Server to client only. TimeSync (14176DCF0): u16, u32 server time (ms). ConnectionSyncDone (14176DD80):
# u32 that must equal the value the server sent in its OpenConnectionResponse (the client's [conn+0x28]);
# the client then tells its network manager the connection is synchronised (141764C40).
def time_sync(index, now):
    return BitWriter().bits(5, 7).bits(index & 0xFFFF, 16).bits(now & 0xFFFFFFFF, 32)


def sync_done(own_attempt):
    return BitWriter().bits(6, 7).bits(own_attempt, 32)


# Object messages (NerdLib SyncedObject, 1417B1150 / 1417AB160). ObjectCreate (7) and ObjectUpdate (8):
#   router id (4 bits, 1422E4410), handle, [Create, if the router's manager has more than one type: type id],
#   seq u8, payload size u14 (bits), payload (per changed var: var index, var data).
# Handle (1417B0E40): two flag bits a, b, then the id (the manager's width). a=b=1: flag 29; b only: flag 30 and
#   an 8-bit peer index follows (the object belongs to that peer, not to the sender); a only: flag 31.
#   Plain (0, 0): the object belongs to the connection it came from.
# Routers seen (id bits, type bits or 0): 1, 2, 3: (7, 0) - the player's objects; 9: (4, 2), 3 types;
#   12: (4, 2), 2 types; 6: (2, 2), the lobby's: type 0 SessionHost, 1 GameOptions (only the server makes these).
#   Also registered: 8, 10, 11.
ROUTERS = {1: (7, 0), 2: (7, 0), 3: (7, 0), 6: (2, 2), 9: (4, 2), 12: (4, 2)}


def read_object(r, msg):
    """ObjectCreate/ObjectUpdate after the message id; the payload is kept as raw bits."""
    router = r.bits(4)
    idw, typew = ROUTERS.get(router, (None, None))
    if idw is None:
        raise ValueError(f'unknown router {router}')
    a, b = r.bits(1), r.bits(1)
    o = dict(router=router, a=a, b=b, id=r.bits(idw))
    if b and not a:
        o['peer'] = r.bits(8)
    if msg == 7 and typew:
        o['type'] = r.bits(typew)
    o['seq'] = r.bits(8)
    n = r.bits(14)
    o['payload'] = BitWriter()
    for _ in range(n):
        o['payload'].bits(r.bits(1), 1)
    return o


def object_msg(msg, router, id, seq, payload=None, peer=None, type=0):
    idw, typew = ROUTERS[router]
    w = BitWriter().bits(msg, 7).bits(router, 4)
    w.bits(0, 1).bits(1 if peer is not None else 0, 1).bits(id, idw)
    if peer is not None:
        w.bits(peer, 8)
    if msg == 7 and typew:
        w.bits(type, typew)
    w.bits(seq & 0xFF, 8).bits(payload.pos if payload else 0, 14)
    return concat(w, payload) if payload else w


def server_update(router, id, seq, payload):
    """An ObjectUpdate from the server for server-owned vars of a console's own object: handle flags (1, 1)
    and the console's own object id (SyncedObject::PackServerUpdateObjectId, 1417B1A20)."""
    idw, _ = ROUTERS[router]
    w = BitWriter().bits(8, 7).bits(router, 4).bits(1, 1).bits(1, 1).bits(id, idw)
    w.bits(seq & 0xFF, 8).bits(payload.pos, 14)
    return concat(w, payload)


# ConsoleSynced (router 3; NerdLib 1417DE550): 9 vars, so a 4-bit var index. 0 RenderReady, 1 SessionEntryFinalised,
# 2 ParticipatingInRace, 3 RaceInProgress, 4 Ready, 5 HasLoadedCarsForAllParticipants, 6 HasGrid,
# 7 AvailableArbitration, 8 MatchTicketArbiter. Bools are 1 bit; 1, 2 and 4 are the server's (SyncedBool<0,1>).
CONSOLE_SESSION_ENTRY_FINALISED = 1


def bool_var(index, value, index_bits=4):
    return BitWriter().bits(index, index_bits).bits(1 if value else 0, 1)


def concat(*msgs):
    """Messages follow each other in the bit stream with no length or padding between them."""
    w = BitWriter()
    for m in msgs:
        for i in range(m.pos):
            w.bits((m.buf[i >> 3] >> (i & 7)) & 1, 1)
    return w


class Acks:
    """The acks a receiver owes (141766400): ack = newest id seen; bit n-1 of the ack bits = id ack-n seen."""
    def __init__(self):
        self.seen = set()
        self.top = None

    def add(self, pid):
        if pid == NO_SEQ:
            return
        self.seen.add(pid)
        if self.top is None or 0 < (pid - self.top) % 0x10000 < 0x8000:
            self.top = pid

    def header(self):
        if self.top is None:
            return 0xFFFE, 0
        bits = 0
        for n in range(1, 33):
            if (self.top - n) % 0x10000 in self.seen:
                bits |= 1 << (n - 1)
        return self.top, bits
