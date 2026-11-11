# FH2 (Xbox One / GCN) tiling for square 8bpp textures, derived from WEL_MagnumIII's AO (FH2 tiled vs FH6 linear).
# 2D thin: 8x8 Morton micro tiles, 128x64-pixel 8 KB macro tiles (row-major), pipe/bank bits XORed from x/y.
# Levels narrower than a macro tile are 1D thin: micro tiles row-major, each level 256-byte aligned.

def bit(v, n): return (v >> n) & 1

def morton(x, y):
    return bit(x, 0) | bit(y, 0) << 1 | bit(x, 1) << 2 | bit(y, 1) << 3 | bit(x, 2) << 4 | bit(y, 2) << 5

def off_2d(x, y, W):
    o = morton(x, y)
    o |= bit(y, 3) << 6 | bit(y, 4) << 7
    o |= (bit(x, 3) ^ bit(x, 4) ^ bit(y, 3)) << 8 | (bit(x, 4) ^ bit(y, 4)) << 9
    o |= (bit(x, 5) ^ bit(y, 7)) << 10 | (bit(x, 6) ^ bit(y, 6) ^ bit(y, 7)) << 11 | (bit(x, 7) ^ bit(y, 5)) << 12
    cols = W // 128
    return o + ((y >> 6) * cols + (x >> 7)) * 8192

def off_1d(x, y, W):
    pitch = max(8, W)
    return ((y >> 3) * (pitch // 8) + (x >> 3)) * 64 + morton(x, y)

def levels(W):
    res = []; off = 0; w = W
    while w >= 1:
        two_d = w >= 128
        size = w * w if two_d else max(8, w) * max(8, w)
        off = (off + 255) & ~255
        res.append((w, off, two_d)); off += size
        w //= 2
    return res, (off + 255) & ~255

def tile(img, W):
    # img: list of W*W levels' linear bytes [level0, level1, ...] -> tiled bytes
    lv, total = levels(W); out = bytearray(total)
    for (w, base, two_d), px in zip(lv, img):
        f = off_2d if two_d else off_1d
        for y in range(w):
            for x in range(w): out[base + f(x, y, w)] = px[y * w + x]
    return bytes(out)

def untile(data, W):
    lv, total = levels(W); res = []
    for w, base, two_d in lv:
        f = off_2d if two_d else off_1d
        res.append(bytes(data[base + f(x, y, w)] for y in range(w) for x in range(w)))
    return res

def mips(px, W):
    res = [bytes(px)]; w = W
    while w > 1:
        h = w // 2; s = res[-1]
        res.append(bytes((s[2*y*w + 2*x] + s[2*y*w + 2*x + 1] + s[(2*y+1)*w + 2*x] + s[(2*y+1)*w + 2*x + 1] + 2) // 4 for y in range(h) for x in range(h)))
        w = h
    return res
