// Included by fh2wheels.c. As an FH2 Extra Options plugin (Azimuth 1.0 and later; see fh2wheels.c), fh2wheels adds
// its database part to the game itself: Extra Options merges the game database and its mods' changes in memory at
// every start and hands it to each plugin's FH2PluginDatabaseUpdate export on the game thread, before the game reads it.
// That runs fh2wheels.sql (make_gamedb.py's 01-fh2wheels.sql, put beside this DLL by the installer) on it. So the part
// is there whatever the database file on disk is: with the FH2 Mod Platform installed, Mount\mediaoverride's
// gamedbRC.slt is the platform's, rebuilt at every start, and a copy fh2wheels' installer put there doesn't last.
// It also covers cars added since the install. The game's SQLite is 3.6.19, which make_gamedb.py's SQL keeps to.
// The frame is Extra Options' plugin API 1 (FH2PluginDatabaseFrame in its fh2_plugin.h): the database and the
// SQLite calls to use on it, borrowed for the call.

typedef struct {
  unsigned size, api_version;
  void *database;
  int (*prepare)(void *db, const char *sql, int bytes, void **statement, const char **tail);
  int (*step)(void *statement);
  int (*finalize)(void *statement);
  long long (*column_int64)(void *statement, int column);
} Fh2PluginDatabaseFrame;

enum { PLUGIN_SQLITE_OK = 0, PLUGIN_SQLITE_ROW = 100, PLUGIN_SQLITE_DONE = 101 };

// 1 when the database has fh2wheels' part already (the marker table the SQL ends with): a database the installer
// built, or one Extra Options kept from an earlier start. Running the SQL again would add nothing, slowly.
static int plugin_has_part(const Fh2PluginDatabaseFrame *f) {
  void *st = NULL; const char *tail = NULL;
  if (f->prepare(f->database, "SELECT COUNT(*) FROM sqlite_master WHERE name = 'Fh2wheels'", -1, &st, &tail) != PLUGIN_SQLITE_OK || !st)
    return 0;
  int found = f->step(st) == PLUGIN_SQLITE_ROW && f->column_int64(st, 0) > 0;
  f->finalize(st);
  return found;
}

// Every statement of sql in order, stopping at the first that fails (as the installer's sqlite3 -bail does).
static int plugin_run(const Fh2PluginDatabaseFrame *f, const char *sql, int *count) {
  for (const char *at = sql; *at; ) {
    void *st = NULL; const char *tail = NULL;
    if (f->prepare(f->database, at, -1, &st, &tail) != PLUGIN_SQLITE_OK) { logf("plugin: this statement of fh2wheels.sql doesn't prepare: %.120s", at); return 0; }
    if (!st) break;   // only blanks or comments left
    int r;
    while ((r = f->step(st)) == PLUGIN_SQLITE_ROW) {}
    if (f->finalize(st) != PLUGIN_SQLITE_OK || r != PLUGIN_SQLITE_DONE) { logf("plugin: this statement of fh2wheels.sql failed: %.120s", at); return 0; }
    ++*count;
    if (!tail || tail == at) break;
    at = tail;
  }
  return 1;
}

// Extra Options' initializer (after DllMain, on its loader's worker): nothing to do, DllMain did it; exported so this
// DLL is an initialized plugin, which is what Extra Options hands the database to.
__declspec(dllexport) BOOL WINAPI FH2PluginInitialize(const void *context) {
  (void)context;
  return TRUE;
}

__declspec(dllexport) BOOL WINAPI FH2PluginDatabaseUpdate(const Fh2PluginDatabaseFrame *f) {
  if (!f || f->size < sizeof *f || !f->database) return TRUE;
  if (plugin_has_part(f)) { logf("plugin: the game database has fh2wheels' part already"); return TRUE; }
  wchar_t path[MAX_PATH];
  _snwprintf(path, MAX_PATH, L"%lsfh2wheels.sql", g_dllDir);
  HANDLE h = CreateFileW(path, GENERIC_READ, FILE_SHARE_READ, NULL, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL);
  if (h == INVALID_HANDLE_VALUE) { logf("PROBLEM: no %ls, so fh2wheels' options aren't in the game: run Install-Fh2wheels.cmd again", path); return TRUE; }
  LARGE_INTEGER size; DWORD got = 0; char *sql = NULL;
  if (GetFileSizeEx(h, &size) && size.QuadPart < (16 << 20) && (sql = malloc((size_t)size.QuadPart + 1)))
    if (!ReadFile(h, sql, (DWORD)size.QuadPart, &got, NULL) || got != size.QuadPart) { free(sql); sql = NULL; }
  CloseHandle(h);
  if (!sql) { logf("PROBLEM: %ls couldn't be read", path); return TRUE; }
  sql[got] = 0;
  LARGE_INTEGER t0, t1; QueryPerformanceCounter(&t0);
  int count = 0, ok = plugin_run(f, sql, &count);
  free(sql);
  QueryPerformanceCounter(&t1);
  if (ok) logf("plugin: fh2wheels' part added to the game database (%d statements, %.0f ms)", count,
               (double)(t1.QuadPart - t0.QuadPart) * 1000.0 / g_freq.QuadPart);
  return ok;
}
