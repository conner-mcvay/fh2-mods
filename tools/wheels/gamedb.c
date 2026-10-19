// Included by fh2wheels.c before rims.c. Reads, with a small read-only SQLite file reader (format: sqlite.org/
// fileformat.html), the rims' Ids and MediaNames (List_Wheels) from the game database file and the garage's rims
// (Career_Garage) from the save, for rims.c. The game
// folder is the one Azimuth runs (data\azimuth.ini, [title-1a96545b] folder=); its database is Mount\mediapc\stripped\
// gamedbRC.slt (mods) or Mount\media\stripped\gamedbRC.slt.

typedef struct { const BYTE *data; size_t size; unsigned page, usable; } SqliteFile;

static unsigned be16(const BYTE *p) { return p[0] << 8 | p[1]; }
static unsigned be32(const BYTE *p) { return (unsigned)p[0] << 24 | p[1] << 16 | p[2] << 8 | p[3]; }
static unsigned long long varint(const BYTE *p, int *len) {
  unsigned long long v = 0;
  for (int i = 0; i < 8; i++) { v = v << 7 | (p[i] & 0x7F); if (!(p[i] & 0x80)) { *len = i + 1; return v; } }
  *len = 9; return v << 8 | p[8];
}
static const BYTE *sqlite_page(const SqliteFile *f, unsigned n) {
  return n && (size_t)n * f->page <= f->size ? f->data + (size_t)(n - 1) * f->page : NULL;
}

// A row's payload, joined from its overflow pages when it doesn't fit in the leaf (malloc'd).
static BYTE *sqlite_payload(const SqliteFile *f, const BYTE *cell, const BYTE *pageEnd, size_t size) {
  size_t maxLocal = f->usable - 35, minLocal = (f->usable - 12) * 32 / 255 - 23, local = size;
  if (size > maxLocal) { local = minLocal + (size - minLocal) % (f->usable - 4); if (local > maxLocal) local = minLocal; }
  if (cell + local + (local < size ? 4 : 0) > pageEnd) return NULL;
  BYTE *out = malloc(size ? size : 1);
  if (!out) return NULL;
  memcpy(out, cell, local);
  size_t have = local; unsigned next = local < size ? be32(cell + local) : 0;
  while (have < size && next) {
    const BYTE *p = sqlite_page(f, next);
    if (!p) { free(out); return NULL; }
    size_t n = size - have < f->usable - 4 ? size - have : f->usable - 4;
    memcpy(out + have, p + 4, n); have += n; next = be32(p);
  }
  if (have < size) { free(out); return NULL; }
  return out;
}

// Column `col` of a record: its text (copied into out, "" when not text) or its integer (*num; *isNull when NULL).
static void sqlite_column(const BYTE *rec, size_t size, int col, char *out, size_t cap, long long *num, int *isNull) {
  int len; out[0] = 0; *num = 0; *isNull = 1;
  size_t hdr = (size_t)varint(rec, &len), at = len, body = hdr;
  for (int i = 0; at < hdr; i++) {
    unsigned long long t = varint(rec + at, &len); at += len;
    size_t n = t >= 12 ? (size_t)(t - 12) / 2 : t == 7 ? 8 : t <= 4 ? (size_t)t : t == 5 ? 6 : t == 6 ? 8 : 0;
    if (i == col) {
      if (body + n > size) return;
      if (t >= 13 && t % 2) { size_t k = n < cap - 1 ? n : cap - 1; memcpy(out, rec + body, k); out[k] = 0; *isNull = 0; }
      else if (t >= 1 && t <= 6) { long long v = (signed char)rec[body]; for (size_t j = 1; j < n; j++) v = v << 8 | rec[body + j]; *num = v; *isNull = 0; }
      else if (t == 8 || t == 9) { *num = t == 9; *isNull = 0; }
      return;
    }
    body += n;
  }
}

typedef void (*SqliteRowFn)(void *ctx, long long rowid, const BYTE *rec, size_t size);
// Every row of the table b-tree rooted at page `root` (depth-limited against a damaged file).
static void sqlite_rows(const SqliteFile *f, unsigned root, SqliteRowFn fn, void *ctx, int depth) {
  const BYTE *p = sqlite_page(f, root);
  if (!p || depth > 20) return;
  const BYTE *h = p + (root == 1 ? 100 : 0), *pageEnd = p + f->usable;
  unsigned cells = be16(h + 3);
  if (h[0] == 0x05) {   // interior: left children, then the right-most one
    for (unsigned i = 0; i < cells; i++) sqlite_rows(f, be32(p + be16(h + 12 + 2 * i)), fn, ctx, depth + 1);
    sqlite_rows(f, be32(h + 8), fn, ctx, depth + 1);
  } else if (h[0] == 0x0D) {
    for (unsigned i = 0; i < cells; i++) {
      const BYTE *c = p + be16(h + 8 + 2 * i); int len;
      size_t size = (size_t)varint(c, &len); c += len;
      long long rowid = (long long)varint(c, &len); c += len;
      BYTE *rec = sqlite_payload(f, c, pageEnd, size);
      if (rec) { fn(ctx, rowid, rec, size); free(rec); }
    }
  }
}

// sqlite_master: type, name, tbl_name, rootpage, sql. The root page and CREATE statement of a table.
typedef struct { const char *name; unsigned root; char sql[2048]; } SqliteFind;
static void sqlite_find_row(void *ctx, long long rowid, const BYTE *rec, size_t size) {
  (void)rowid; SqliteFind *q = ctx; char text[128]; long long num; int isNull;
  sqlite_column(rec, size, 0, text, sizeof text, &num, &isNull);
  if (strcmp(text, "table")) return;
  sqlite_column(rec, size, 1, text, sizeof text, &num, &isNull);
  if (_stricmp(text, q->name)) return;
  sqlite_column(rec, size, 3, text, sizeof text, &num, &isNull); q->root = (unsigned)num;
  sqlite_column(rec, size, 4, q->sql, sizeof q->sql, &num, &isNull);
}

// The 0-based place of column `name` in a CREATE TABLE statement ("[name]" or a bare word), or -1.
static int sqlite_column_index(const char *sql, const char *name) {
  const char *p = strchr(sql, '(');
  for (int i = 0; p; i++) {
    p++;
    while (*p == ' ' || *p == '\n' || *p == '\r' || *p == '\t' || *p == '[' || *p == '"') p++;
    size_t k = strlen(name);
    if (!_strnicmp(p, name, k) && !isalnum((unsigned char)p[k]) && p[k] != '_') return i;
    p = strchr(p, ',');
  }
  return -1;
}

// The rims: Id -> MediaName, sorted by Id.
typedef struct { int id; char name[48]; } RimRow;
static RimRow *g_rims; static int g_rimCount;
typedef struct { int idCol, nameCol, cap; } RimScan;
static void rim_row(void *ctx, long long rowid, const BYTE *rec, size_t size) {
  RimScan *s = ctx; char text[48]; long long id; int idNull, nameNull; long long unused;
  sqlite_column(rec, size, s->idCol, text, sizeof text, &id, &idNull);
  if (idNull) id = rowid;   // an INTEGER PRIMARY KEY is the rowid
  sqlite_column(rec, size, s->nameCol, text, sizeof text, &unused, &nameNull);
  if (!text[0]) return;
  if (g_rimCount == s->cap) { RimRow *r = realloc(g_rims, (s->cap = s->cap ? s->cap * 2 : 1024) * sizeof *r); if (!r) return; g_rims = r; }
  g_rims[g_rimCount].id = (int)id; snprintf(g_rims[g_rimCount].name, sizeof g_rims[g_rimCount].name, "%s", text); g_rimCount++;
}
static int rim_cmp(const void *a, const void *b) { return ((const RimRow *)a)->id - ((const RimRow *)b)->id; }

// A database file in memory (malloc'd, NULL when it isn't one), after `skip` bytes of header (a save's has 8).
static BYTE *sqlite_open(const wchar_t *path, size_t skip, SqliteFile *f) {
  HANDLE h = CreateFileW(path, GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, NULL, OPEN_EXISTING, 0, NULL);
  if (h == INVALID_HANDLE_VALUE) { logf("can't open %ls (%lu)", path, GetLastError()); return NULL; }
  LARGE_INTEGER size; GetFileSizeEx(h, &size);
  BYTE *data = size.QuadPart > (LONGLONG)(100 + skip) && size.QuadPart < (1LL << 31) ? malloc((size_t)size.QuadPart) : NULL;
  DWORD got = 0;
  if (data && !ReadFile(h, data, (DWORD)size.QuadPart, &got, NULL)) got = 0;
  CloseHandle(h);
  if (!data || got != size.QuadPart || memcmp(data + skip, "SQLite format 3", 16)) { logf("%ls isn't readable as a database", path); free(data); return NULL; }
  const BYTE *db = data + skip;
  f->data = db; f->size = got - skip; f->page = be16(db + 16) == 1 ? 65536 : be16(db + 16); f->usable = f->page - db[20];
  return data;
}

static void rims_read_gamedb(const wchar_t *dllDir) {
  wchar_t ini[MAX_PATH], game[MAX_PATH], db[MAX_PATH];
  _snwprintf(ini, MAX_PATH, L"%ls..\\azimuth.ini", dllDir);
  GetPrivateProfileStringW(L"title-1a96545b", L"folder", L"", game, MAX_PATH, ini);
  if (!game[0]) { logf("rims: no game folder in %ls", ini); return; }
  _snwprintf(db, MAX_PATH, L"%ls\\Mount\\mediapc\\stripped\\gamedbRC.slt", game);
  if (GetFileAttributesW(db) == INVALID_FILE_ATTRIBUTES) _snwprintf(db, MAX_PATH, L"%ls\\Mount\\media\\stripped\\gamedbRC.slt", game);
  SqliteFile f; BYTE *data = sqlite_open(db, 0, &f);
  if (!data) return;
  SqliteFind q = { "List_Wheels", 0, "" };
  sqlite_rows(&f, 1, sqlite_find_row, &q, 0);
  RimScan s = { sqlite_column_index(q.sql, "ID"), sqlite_column_index(q.sql, "MediaName"), 0 };
  if (q.root && s.idCol >= 0 && s.nameCol >= 0) sqlite_rows(&f, q.root, rim_row, &s, 0);
  free(data);
  if (g_rimCount) qsort(g_rims, g_rimCount, sizeof *g_rims, rim_cmp);
  logf("rims: %d rims read from %ls", g_rimCount, db);
}

// The garage's rim pairs (WheelStyle, TireBrand) in the newest save revision (data\titles\1A96545B\saves\<player>\<user>
// \revisions\<revision>\data\PlayerDatabase, after an 8-byte header), handed to fn row by row.
typedef void (*GarageRimFn)(int front, int rear);
typedef struct { int frontCol, rearCol; GarageRimFn fn; } GarageScan;
static void garage_row(void *ctx, long long rowid, const BYTE *rec, size_t size) {
  (void)rowid; GarageScan *s = ctx; char text[16]; long long front, rear; int frontNull, rearNull;
  sqlite_column(rec, size, s->frontCol, text, sizeof text, &front, &frontNull);
  sqlite_column(rec, size, s->rearCol, text, sizeof text, &rear, &rearNull);
  s->fn(frontNull ? -1 : (int)front, rearNull ? -1 : (int)rear);
}
// The newest (by write time) file `dir`\<pattern levels, '|' apart>\`leaf`, into best (folder times don't follow their
// files, so every one is looked at).
static void newest_file(const wchar_t *dir, const wchar_t *levels, const wchar_t *leaf, wchar_t *best, FILETIME *bestTime) {
  wchar_t find[MAX_PATH], pattern[64], sub[MAX_PATH];
  if (!*levels) {
    WIN32_FILE_ATTRIBUTE_DATA a;
    _snwprintf(sub, MAX_PATH, L"%ls%ls", dir, leaf);
    if (GetFileAttributesExW(sub, GetFileExInfoStandard, &a) && (!best[0] || CompareFileTime(&a.ftLastWriteTime, bestTime) > 0)) {
      wcscpy(best, sub); *bestTime = a.ftLastWriteTime;
    }
    return;
  }
  const wchar_t *bar = wcschr(levels, L'|'), *rest = bar ? bar + 1 : levels + wcslen(levels);
  size_t k = bar ? (size_t)(bar - levels) : wcslen(levels);
  if (k >= 64) return;
  wmemcpy(pattern, levels, k); pattern[k] = 0;
  _snwprintf(find, MAX_PATH, L"%ls%ls", dir, pattern);
  WIN32_FIND_DATAW fd; HANDLE h = FindFirstFileW(find, &fd);
  if (h == INVALID_HANDLE_VALUE) return;
  do {
    if (fd.cFileName[0] == L'.' || !(fd.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY)) continue;
    _snwprintf(sub, MAX_PATH, L"%ls%ls\\", dir, fd.cFileName);
    newest_file(sub, rest, leaf, best, bestTime);
  } while (FindNextFileW(h, &fd));
  FindClose(h);
}
static void garage_read_save(const wchar_t *dllDir, GarageRimFn fn) {
  wchar_t saves[MAX_PATH], path[MAX_PATH] = L""; FILETIME t;
  _snwprintf(saves, MAX_PATH, L"%ls..\\titles\\1A96545B\\saves\\", dllDir);
  newest_file(saves, L"player-*|User_*|revisions|*", L"data\\PlayerDatabase", path, &t);
  if (!path[0]) { logf("rims: no save under %ls", saves); return; }
  SqliteFile f; BYTE *data = sqlite_open(path, 8, &f);
  if (!data) return;
  SqliteFind q = { "Career_Garage", 0, "" };
  sqlite_rows(&f, 1, sqlite_find_row, &q, 0);
  GarageScan s = { sqlite_column_index(q.sql, "WheelStyle"), sqlite_column_index(q.sql, "TireBrand"), fn };
  if (q.root && s.frontCol >= 0 && s.rearCol >= 0) sqlite_rows(&f, q.root, garage_row, &s, 0);
  else logf("rims: no Career_Garage rims in %ls", path);
  free(data);
  logf("rims: garage read from %ls", path);
}

static const char *rim_lookup(int id) {
  int lo = 0, hi = g_rimCount - 1;
  while (lo <= hi) { int m = (lo + hi) / 2; if (g_rims[m].id == id) return g_rims[m].name; if (g_rims[m].id < id) lo = m + 1; else hi = m - 1; }
  return NULL;
}
static int rim_id_of(const char *name) {
  for (int i = 0; i < g_rimCount; i++) if (!_stricmp(g_rims[i].name, name)) return g_rims[i].id;
  return 0;
}
