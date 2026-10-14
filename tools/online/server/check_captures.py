"""Decode every captured LSP request in a captures folder against the game's schemas; report failures.
  py -3 -I check_captures.py <captures folder>"""
import json, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import xls

folder = sys.argv[1]
sc = xls.Schema()
seen = {}
for line in open(os.path.join(folder, 'requests.jsonl'), encoding='utf-8'):
    r = json.loads(line)
    h = r['headers']; m = h.get('X-Method')
    if not m or not r.get('body_file'): continue
    ptype, _ = sc.call_types(h['X-ClassName'], m)
    body = open(os.path.join(folder, r['body_file']), 'rb').read()
    try:
        v, end = xls.decode(ptype, body)
        res = 'ok' if end == len(body) else f'consumed {end} of {len(body)}'
    except Exception as e:
        res = f'FAIL {e}'
    key = (m, res[:4])
    if key in seen: continue
    seen[key] = 1
    print(f"#{r['n']:<5} {m:<34} {len(body):>6} bytes  {res}")
