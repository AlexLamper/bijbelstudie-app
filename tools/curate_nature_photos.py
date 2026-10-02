"""Curate calm, minimal nature photographs from Pexels.

Fills two libraries, both in the look of the daily verse card: the 365 Dagtekst
backgrounds (`assets/images/daytext/`, mirrored in the website's
`public/images/daytext/`) and one cover per study (the website's
`public/images/study-photos/`, which the app reads over the API).

The bands below are measured off the photos already in the daily verse library,
so a new photo only ships if it looks like one of them: mid-bright, low
contrast, almost no fine detail, muted colour, no people or buildings.

Usage (from the repo root, needs Pillow):
    python tools/curate_nature_photos.py harvest 40 pool.json    # find candidates
    python tools/curate_nature_photos.py measure "assets/images/daytext/*.jpg"
Writing files is deliberately not a one-liner: read a pool first, then feed it
to `write_daytext` / `write_study_cover` from a REPL, so nothing lands in the
repo unseen.
"""

import glob, io, json, os, re, statistics as st, sys, urllib.parse, urllib.request
from PIL import Image, ImageFilter

KEY = 'H2jk9uKnhRmL6WPwh89zBezWvr'  # pexels.com web client key
UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) curation/1.0'

# Measured off assets/images/daytext/001..100.jpg (see measure.py).
MEAN = (0.33, 0.66)     # mean luminance: mid-bright
TL_MAX = 0.82           # top-left quadrant: where the verse text sits
STD_MAX = 0.21          # low contrast
EDGE_MAX = 0.095        # minimal: p75 of the set is 0.061, p95 0.118
SAT_MAX = 0.50          # muted colour
RATIO = (0.55, 2.1)     # crops to 3:4 and to 4:3 without losing the subject

BLOCK = re.compile(
    r'\b(people|person|man|men|woman|women|girl|boy|child|children|kid|baby|'
    r'portrait|face|hand|hands|human|model|fashion|wedding|couple|family|'
    r'city|urban|building|architecture|house|home|street|road|highway|bridge|'
    r'car|vehicle|boat|ship|train|plane|aircraft|window|wall|room|interior|'
    r'ai generated|ai-generated|illustration|render|3d|drawing|painting|'
    r'sketch|graphic|logo|text|sign|dog|cat|horse|cow|sheep|bird|people s)\b')

def http(url, headers=None):
    req = urllib.request.Request(url, headers={'User-Agent': UA, **(headers or {})})
    with urllib.request.urlopen(req, timeout=60) as r:
        return r.read()

def search(query, page, per_page=24):
    url = ('https://www.pexels.com/en-us/api/v3/search/photos?query='
           + urllib.parse.quote(query) + f'&per_page={per_page}&page={page}'
           + '&orientation=all')
    try:
        body = http(url, {'Secret-Key': KEY, 'Accept': 'application/json'})
    except Exception as e:
        print(f'  ! search {query!r} p{page}: {e}', flush=True)
        return []
    return json.loads(body.decode('utf-8')).get('data', [])

def metrics(im):
    im = im.convert('RGB')
    im.thumbnail((160, 160))
    g = im.convert('L')
    px = list(g.getdata())
    w, h = g.size
    q = list(g.crop((0, 0, w // 2, h // 2)).getdata())
    e = g.filter(ImageFilter.FIND_EDGES)
    epx = list(e.crop((1, 1, w - 1, h - 1)).getdata())
    s = list(im.convert('HSV').getdata())
    return {
        'mean': sum(px) / len(px) / 255,
        'tl': sum(q) / len(q) / 255,
        'std': st.pstdev(px) / 255,
        'edge': sum(epx) / len(epx) / 255,
        'sat': sum(p[1] for p in s) / len(s) / 255,
    }

def passes(m):
    return (MEAN[0] <= m['mean'] <= MEAN[1] and m['tl'] <= TL_MAX
            and m['std'] <= STD_MAX and m['edge'] <= EDGE_MAX
            and m['sat'] <= SAT_MAX)

def wordy(a):
    bits = [a.get('title') or '', a.get('description') or '', a.get('alt') or '',
            a.get('slug') or '', ' '.join(a.get('tags') or [])]
    return ' '.join(bits).lower()

def photographer(a):
    u = a.get('user') or {}
    name = f"{(u.get('first_name') or '').strip()} {(u.get('last_name') or '').strip()}".strip()
    return name or 'Pexels', u.get('slug') or ''

def candidate(a):
    """Metadata-only gate. None when the photo is unusable."""
    if a.get('license') != 'Pexels' or not a.get('published'):
        return None
    w, h = a.get('width') or 0, a.get('height') or 0
    if w < 1600 or h < 1600 or not (RATIO[0] <= w / h <= RATIO[1]):
        return None
    if BLOCK.search(wordy(a)):
        return None
    name, slug = photographer(a)
    return {
        'id': int(a['id']), 'slug': a.get('slug') or '', 'title': a.get('title') or '',
        'photographer': name, 'photographer_slug': slug,
        'w': w, 'h': h, 'tags': (a.get('tags') or [])[:8],
    }

def probe(pid):
    url = (f'https://images.pexels.com/photos/{pid}/pexels-photo-{pid}.jpeg'
           f'?auto=compress&cs=tinysrgb&w=360')
    return Image.open(io.BytesIO(http(url)))

def harvest(queries, want, used_ids, pool_path, per_person=4, pages=(1, 2, 3)):
    pool, seen, by_person = [], set(used_ids), {}
    if os.path.exists(pool_path):
        pool = json.load(io.open(pool_path, encoding='utf-8'))
        for p in pool:
            seen.add(p['id'])
            by_person[p['photographer']] = by_person.get(p['photographer'], 0) + 1
    for page in pages:
        for q in queries:
            if len(pool) >= want:
                break
            got = 0
            for a in search(q, page):
                if len(pool) >= want:
                    break
                c = candidate(a.get('attributes') or {})
                if not c or c['id'] in seen:
                    continue
                if by_person.get(c['photographer'], 0) >= per_person:
                    continue
                seen.add(c['id'])
                try:
                    m = metrics(probe(c['id']))
                except Exception:
                    continue
                if not passes(m):
                    continue
                c['m'] = {k: round(v, 4) for k, v in m.items()}
                c['query'] = q
                pool.append(c)
                by_person[c['photographer']] = by_person.get(c['photographer'], 0) + 1
                got += 1
            print(f'  p{page} {q!r}: +{got} (pool {len(pool)})', flush=True)
            with io.open(pool_path, 'w', encoding='utf-8') as f:
                json.dump(pool, f, ensure_ascii=False, indent=1)
    return pool

# --- writing files ----------------------------------------------------------

DAYTEXT_DIRS = (
    r'C:\Projects\bijbelstudie-app\bijbelstudie_mobile\assets\images\daytext',
    r'C:\Projects\bijbelstudie\public\images\daytext',
)
STUDY_DIR = r'C:\Projects\bijbelstudie\public\images\study-photos'


def credit_row(slot, p):
    """One row of `CREDITS.md`, for the file `slot` holds."""
    return (f"| {slot:03d}.jpg | [{p['photographer']}]"
            f"(https://www.pexels.com/@{p['photographer_slug']}) | "
            f"https://www.pexels.com/photo/{p['slug']}-{p['id']}/ |")


def write_daytext(slot, p):
    """Write one daily verse background: centre crop 3:4, 900x1200, JPEG q65.

    Returns False when the crop itself falls outside the bands - the probe
    measures the whole frame, and cropping to 3:4 can push a photo out.
    """
    url = (f"https://images.pexels.com/photos/{p['id']}/pexels-photo-{p['id']}"
           f".jpeg?cs=srgb&fit=crop&w=900&h=1200")
    im = Image.open(io.BytesIO(http(url))).convert('RGB')
    if im.size != (900, 1200):
        im = im.resize((900, 1200), Image.LANCZOS)
    if not passes(metrics(im.copy())):
        return False
    for d in DAYTEXT_DIRS:
        im.save(os.path.join(d, f'{slot:03d}.jpg'), 'JPEG', quality=65,
                optimize=True, progressive=True)
    return True


def write_study_cover(p):
    """Write one study cover: 800 px WebP banner + 240 px square thumbnail."""
    url = (f"https://images.pexels.com/photos/{p['id']}/pexels-photo-{p['id']}"
           f".jpeg?cs=srgb&w=800")
    im = Image.open(io.BytesIO(http(url))).convert('RGB')
    im.save(os.path.join(STUDY_DIR, f"p-{p['id']}.webp"), 'WEBP', quality=70,
            method=5)
    w, h = im.size
    s = min(w, h)
    box = ((w - s) // 2, (h - s) // 2, (w - s) // 2 + s, (h - s) // 2 + s)
    im.crop(box).resize((240, 240), Image.LANCZOS).save(
        os.path.join(STUDY_DIR, f"p-{p['id']}-sm.webp"), 'WEBP', quality=70,
        method=5)


# --- queries ----------------------------------------------------------------

# The idiom of the library: wide, calm, nothing in the foreground.
QUERIES = [
    'misty field at dawn', 'fog over hills', 'calm sea horizon',
    'soft clouds blue sky', 'sand dunes minimal', 'snow covered field',
    'wheat field sunset', 'lake reflection calm', 'pastel sky sunset',
    'desert minimal landscape', 'forest in fog', 'tall grass close up',
    'ripples in sand', 'frozen lake winter', 'heather moorland',
    'dune grass beach', 'overcast sky sea', 'rolling green hills',
    'mountain silhouette haze', 'empty beach sand', 'morning mist meadow',
    'minimal seascape', 'smooth water long exposure', 'snowy mountain slope',
    'olive grove hills', 'white sky minimal', 'dry grass field wind',
    'single tree in field', 'mountain lake still', 'clouds from above',
    'fields from above minimal', 'sky gradient dusk', 'salt flat horizon',
    'soft waves ocean', 'green meadow horizon', 'moss covered rocks',
    'canyon rock minimal', 'cliffs over sea', 'reeds in water',
    'terraced hills mist', 'frost on grass', 'soft sunrise hills',
    'blue hour landscape', 'haze over valley', 'distant mountain range',
    'island in mist', 'aerial beach minimal', 'snow dune', 'cotton clouds',
    'pastel ocean morning', 'savanna grass horizon', 'minimal lake fog',
    'autumn field minimal', 'glacier ice minimal', 'minimal horizon line',
    'calm river bend', 'high desert plateau', 'soft dune shadows',
]


def measure_dir(pattern):
    """Print the bands of a directory, the way the ones above were derived."""
    rows = [metrics(Image.open(f)) for f in sorted(glob.glob(pattern))]
    print(f'n={len(rows)}')
    for key in ('mean', 'tl', 'std', 'edge', 'sat'):
        v = sorted(r[key] for r in rows)
        k = len(v)
        print(f'{key:5s} min={v[0]:.3f} p25={v[k // 4]:.3f} med={v[k // 2]:.3f} '
              f'p75={v[3 * k // 4]:.3f} max={v[-1]:.3f}')


if __name__ == '__main__':
    cmd = sys.argv[1] if len(sys.argv) > 1 else 'measure'
    if cmd == 'harvest':
        want = int(sys.argv[2])
        out = sys.argv[3] if len(sys.argv) > 3 else 'pool.json'
        pool = harvest(QUERIES, want, set(), out)
        print('POOL', len(pool), '->', out)
    elif cmd == 'measure':
        measure_dir(sys.argv[2])
    else:
        print(__doc__)
