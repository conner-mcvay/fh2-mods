# Minimal GLB -> OBJ/MTL: triangle meshes, node transforms (TRS/matrix, nested), normals, UV0, base colour textures.
#   py -3 glb2obj.py <in.glb> <out dir>
import sys, os, json, struct, math

def main(src, out):
    d = open(src, 'rb').read()
    assert d[:4] == b'glTF', 'not a GLB'
    p = 12; j = None; bin_ = b''
    while p < len(d):
        ln, typ = struct.unpack_from('<I4s', d, p); chunk = d[p + 8:p + 8 + ln]; p += 8 + ln
        if typ == b'JSON': j = json.loads(chunk)
        elif typ == b'BIN\x00': bin_ = chunk
    req = j.get('extensionsRequired') or []
    if req: raise SystemExit(f'needs unsupported extensions: {req}')
    CT = {5120: 'b', 5121: 'B', 5122: 'h', 5123: 'H', 5125: 'I', 5126: 'f'}
    NC = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4}
    def acc(i):
        a = j['accessors'][i]; bv = j['bufferViews'][a['bufferView']]
        fmt = CT[a['componentType']]; n = NC[a['type']]; sz = struct.calcsize(fmt)
        stride = bv.get('byteStride') or sz * n; base = bv.get('byteOffset', 0) + a.get('byteOffset', 0)
        res = [struct.unpack_from('<%d%s' % (n, fmt), bin_, base + k * stride) for k in range(a['count'])]
        if a.get('normalized'):
            mx = {'b': 127, 'B': 255, 'h': 32767, 'H': 65535}[fmt]; res = [tuple(max(c / mx, -1) for c in v) for v in res]
        return res

    def mat_mul(a, b): return [[sum(a[r][k] * b[k][c] for k in range(4)) for c in range(4)] for r in range(4)]
    def local(n):
        if 'matrix' in n: m = n['matrix']; return [[m[c * 4 + r] for c in range(4)] for r in range(4)]
        t = n.get('translation', [0, 0, 0]); x, y, z, w = n.get('rotation', [0, 0, 0, 1]); s = n.get('scale', [1, 1, 1])
        R = [[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
             [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
             [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]]
        return [[R[r][0] * s[0], R[r][1] * s[1], R[r][2] * s[2], t[r]] for r in range(3)] + [[0, 0, 0, 1]]

    os.makedirs(out, exist_ok=True)
    stem = os.path.splitext(os.path.basename(src))[0]
    # images: embedded (bufferView) or external (uri)
    imgfiles = {}
    for i, im in enumerate(j.get('images', [])):
        ext = {'image/png': '.png', 'image/jpeg': '.jpg'}.get(im.get('mimeType'), '.png')
        if 'bufferView' in im:
            bv = j['bufferViews'][im['bufferView']]; name = (im.get('name') or f'image{i}') + ext
            open(os.path.join(out, name), 'wb').write(bin_[bv.get('byteOffset', 0):bv.get('byteOffset', 0) + bv['byteLength']])
            imgfiles[i] = name
        elif 'uri' in im and not im['uri'].startswith('data:'): imgfiles[i] = im['uri']
    mtl = []
    for i, m in enumerate(j.get('materials', [])):
        pbr = m.get('pbrMetallicRoughness', {}); c = pbr.get('baseColorFactor', [0.8, 0.8, 0.8, 1])
        mtl += [f'newmtl {m.get("name", f"material{i}")}', f'Kd {c[0]:.4f} {c[1]:.4f} {c[2]:.4f}', 'Ka 0 0 0', 'Ks 0.2 0.2 0.2', 'illum 2']
        if m.get('alphaMode') == 'BLEND' or c[3] < 1: mtl.append(f'd {c[3]:.4f}')
        t = pbr.get('baseColorTexture')
        if t is not None:
            src_i = j['textures'][t['index']].get('source')
            if src_i in imgfiles:
                mtl.append(f'map_Kd {imgfiles[src_i]}')
                if m.get('alphaMode') in ('BLEND', 'MASK'): mtl.append(f'map_d {imgfiles[src_i]}')
        mtl.append('')
    open(os.path.join(out, stem + '.mtl'), 'w').write('\n'.join(mtl))

    lines = [f'# converted from {os.path.basename(src)}', f'mtllib {stem}.mtl']
    vbase = [1, 1, 1]; tris = 0
    def walk(ni, parent):
        nonlocal tris
        n = j['nodes'][ni]; M = mat_mul(parent, local(n))
        if 'mesh' in n:
            mesh = j['meshes'][n['mesh']]
            N3 = [[M[r][c] for c in range(3)] for r in range(3)]
            # normal matrix = inverse-transpose of the 3x3
            a, b, c, d_, e, f, g, h, k = [N3[r][cc] for r in range(3) for cc in range(3)]
            det = a * (e * k - f * h) - b * (d_ * k - f * g) + c * (d_ * h - e * g)
            inv = [[(e * k - f * h) / det, (c * h - b * k) / det, (b * f - c * e) / det],
                   [(f * g - d_ * k) / det, (a * k - c * g) / det, (c * d_ - a * f) / det],
                   [(d_ * h - e * g) / det, (b * g - a * h) / det, (a * e - b * d_) / det]]
            for pi, prim in enumerate(mesh['primitives']):
                if prim.get('mode', 4) != 4: continue
                at = prim['attributes']; pos = acc(at['POSITION'])
                nrm = acc(at['NORMAL']) if 'NORMAL' in at else None; uv = acc(at['TEXCOORD_0']) if 'TEXCOORD_0' in at else None
                idx = [v[0] for v in acc(prim['indices'])] if 'indices' in prim else list(range(len(pos)))
                lines.append(f'o {n.get("name", mesh.get("name", "mesh"))}' + (f'_{pi}' if len(mesh['primitives']) > 1 else ''))
                for v in pos:
                    lines.append('v %.6f %.6f %.6f' % tuple(M[r][0] * v[0] + M[r][1] * v[1] + M[r][2] * v[2] + M[r][3] for r in range(3)))
                if uv: lines.extend('vt %.6f %.6f' % (t[0], 1 - t[1]) for t in uv)
                if nrm:
                    for v in nrm:
                        w = [inv[0][r] * v[0] + inv[1][r] * v[1] + inv[2][r] * v[2] for r in range(3)]; l = math.sqrt(sum(x * x for x in w)) or 1
                        lines.append('vn %.6f %.6f %.6f' % tuple(x / l for x in w))
                if 'material' in prim: lines.append(f'usemtl {j["materials"][prim["material"]].get("name", "material%d" % prim["material"])}')
                for t in range(0, len(idx) - 2, 3):
                    fs = []
                    for vi in idx[t:t + 3]:
                        s = str(vbase[0] + vi)
                        if uv or nrm: s += '/' + (str(vbase[1] + vi) if uv else '')
                        if nrm: s += '/' + str(vbase[2] + vi)
                        fs.append(s)
                    lines.append('f ' + ' '.join(fs)); tris += 1
                vbase[0] += len(pos); vbase[1] += len(uv) if uv else 0; vbase[2] += len(nrm) if nrm else 0
        for c in n.get('children', []): walk(c, M)
    I = [[1 if r == c else 0 for c in range(4)] for r in range(4)]
    for ni in j['scenes'][j.get('scene', 0)]['nodes']: walk(ni, I)
    open(os.path.join(out, stem + '.obj'), 'w').write('\n'.join(lines) + '\n')
    print(f'{stem}.obj: {vbase[0] - 1} vertices, {tris} triangles; {stem}.mtl; images {list(imgfiles.values())}')

if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2])
