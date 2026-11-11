# Copies the motion-blur meshes of one converted FH2 wheel (donor) into another that has none (RimStudio output).
# In driving mode FH2 swaps a spinning wheel for its blur meshes (wheel_blur: a generic streak texture over discs in
# the normalised wheel space every wheel shares), so a wheel without them disappears at speed.
#   py -3 add_blur.py <target.modelbin> <donor.modelbin> <out.modelbin>
import sys, struct
import burg
from fh6model import meta, blob_id

def mati_path(b):
    inner = burg.read(b['data']); d = [c for c in inner['blobs'] if c['tag'] == 'MATI'][0]['data']
    return d[1:1 + d[0]].decode('latin1').lower()

def main(tpath, dpath, out):
    T = burg.read(open(tpath, 'rb').read())['blobs']; D = burg.read(open(dpath, 'rb').read())['blobs']
    tm = lambda tag: [b for b in T if b['tag'] == tag]
    dm = lambda tag: [b for b in D if b['tag'] == tag]
    if any('wheel_blur' in mati_path(b) for b in tm('MatI')): raise SystemExit('target already has blur meshes')
    dblur = {blob_id(b) for b in dm('MatI') if 'wheel_blur' in mati_path(b)}
    meshes = [b for b in dm('Mesh') if struct.unpack_from('<h', b['data'], 0)[0] in dblur and b['data'][8] == 0x1C]
    if not meshes: raise SystemExit('donor has no blur meshes')

    tpos = [b for b in tm('VerB') if blob_id(b) == -1][0]; dpos = [b for b in dm('VerB') if blob_id(b) == -1][0]
    tcount = struct.unpack_from('<I', tpos['data'], 0)[0]
    tib = tm('IndB')[0]; dib = dm('IndB')[0]
    ticount, tisize, tistride = struct.unpack_from('<IIH', tib['data'], 0)
    dicount, disize, distride = struct.unpack_from('<IIH', dib['data'], 0)
    assert tistride == distride, 'index sizes differ'
    new_mat = len(tm('MatI'))
    new_vb = max(blob_id(b) for b in tm('VerB')) + 1
    new_lay = len(tm('VLay'))
    dvbs = {struct.unpack_from('<i', m['data'], 0x49)[0] for m in meshes}
    dlays = {struct.unpack_from('<i', m['data'], 0x31)[0] for m in meshes}
    assert len(dvbs) == 1 and len(dlays) == 1, (dvbs, dlays)
    dvb, dlay = dvbs.pop(), dlays.pop()

    # positions and indices: the donor's whole buffers appended; its blur meshes moved past the target's
    pd = dpos['data']; dcount = struct.unpack_from('<I', pd, 0)[0]
    posdata = tpos['data'][16:] + pd[16:]
    tpos['data'] = struct.pack('<IIHHI', tcount + dcount, len(posdata), 12, 1, 6) + posdata
    idata = tib['data'][16:16 + tisize] + dib['data'][16:16 + disize]
    tib['data'] = struct.pack('<II', ticount + dicount, len(idata)) + tib['data'][8:16] + idata

    new_meshes = []
    for b in meshes:
        d = bytearray(b['data'])
        struct.pack_into('<h', d, 0, new_mat)
        struct.pack_into('<i', d, 0x19, struct.unpack_from('<i', d, 0x19)[0] + ticount)
        struct.pack_into('<i', d, 0x31, new_lay)
        struct.pack_into('<i', d, 0x39 + 12, struct.unpack_from('<i', d, 0x39 + 12)[0] + tcount * 12)
        struct.pack_into('<i', d, 0x49, new_vb)
        struct.pack_into('<i', d, 0x59, new_vb)
        new_meshes.append(dict(b, data=bytes(d)))
    mat = [b for b in dm('MatI') if blob_id(b) in dblur][0]
    new_matb = dict(mat, meta=[('Name', b'blur_lip'), ('Id  ', struct.pack('<i', new_mat))])
    lay = [b for b in dm('VLay') if blob_id(b) == dlay][0]
    new_layb = dict(lay, meta=[('Id  ', struct.pack('<i', new_lay))])
    vb = [b for b in dm('VerB') if blob_id(b) == dvb][0]; mb = [b for b in dm('MBuf') if blob_id(b) == dvb]
    extra_bufs = [dict(vb, meta=[('Id  ', struct.pack('<i', new_vb))])] + [dict(x, meta=[('Id  ', struct.pack('<i', new_vb))]) for x in mb]

    def last(tag): return max(i for i, b in enumerate(T) if b['tag'] == tag)
    out_blobs = list(T)
    modl = out_blobs.pop(last('Modl'))
    out_blobs += extra_bufs
    out_blobs.insert(last('VLay') + 1, new_layb)
    out_blobs.insert(last('Mesh') + 1, None); i = out_blobs.index(None); out_blobs[i:i + 1] = new_meshes
    out_blobs.insert(last('MatI') + 1, new_matb)
    nmesh, nbuf, nlay, nmat = struct.unpack_from('<HHHH', modl['data'], 0)
    tref_t = meta(modl, 'TRef'); tref_d = meta(dm('Modl')[0], 'TRef')
    refs = set(tref_t[4 + 4 * k:8 + 4 * k] for k in range(struct.unpack_from('<I', tref_t, 0)[0]))
    refs |= set(tref_d[4 + 4 * k:8 + 4 * k] for k in range(struct.unpack_from('<I', tref_d, 0)[0]))
    tr = struct.pack('<I', len(refs)) + b''.join(sorted(refs))
    modl = dict(modl, data=struct.pack('<HHHH', nmesh + len(new_meshes), nbuf + len(extra_bufs), nlay + 1, nmat + 1) + modl['data'][8:],
                meta=[(k, tr if k == 'TRef' else v) for k, v in modl['meta']])
    out_blobs.append(modl)
    open(out, 'wb').write(burg.write(out_blobs))
    print(f'added {len(new_meshes)} blur meshes ({dcount} positions, {dicount} indices, layout {new_lay}, buffer {new_vb}, material {new_mat})')

if __name__ == '__main__':
    main(*sys.argv[1:4])
