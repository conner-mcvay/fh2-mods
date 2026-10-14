// Included by fh2net.c. Our own IXMLHTTPRequest2 (FreeThreadedXMLHTTP60), answered in place of Azimuth's
// offline one when [http] Server is set: every request goes over WinHTTP to that server instead of its
// own host, which travels in X-Fh2net-Host (and the scheme in X-Fh2net-Scheme). The callbacks run on a
// worker thread, as a free-threaded request's do.
#include <winhttp.h>
#include <objidl.h>

static const GUID CLSID_FreeThreadedXMLHTTP60_ = { 0x88d96a09, 0xf192, 0x11d4, { 0xa6, 0x5f, 0x00, 0x40, 0x96, 0x32, 0x51, 0xe5 } };
static const GUID IID_IXMLHTTPRequest2_ = { 0xe5d37dc0, 0x552a, 0x4d52, { 0x9c, 0xc0, 0xa1, 0x4d, 0x54, 0x6f, 0xbd, 0x04 } };
static const GUID IID_IUnknown_x = { 0, 0, 0, { 0xc0, 0, 0, 0, 0, 0, 0, 0x46 } };

static wchar_t g_httpServer[256];       // [http] Server, e.g. http://127.0.0.1:8090 (empty: Azimuth's offline requests)
static wchar_t g_srvHost[128]; static INTERNET_PORT g_srvPort; static int g_srvTls;
static HINTERNET g_winhttp;
static volatile LONG g_reqSeq;
typedef void *(WINAPI *CoTaskMemAlloc_t)(SIZE_T);
static CoTaskMemAlloc_t p_GameCoTaskMemAlloc;
static void *iat_lookup(BYTE *base, const char *dllName, const char *fnName);

typedef struct { void **vtbl; } XObj;
#define XCALL(o, slot, T) ((T)((XObj *)(o))->vtbl[slot])

typedef struct {
  void **vtbl; LONG refs; LONG id;
  wchar_t *method, *url;
  XObj *callback;
  wchar_t *headers; size_t headersLen, headersCap;   // "Name: value\r\n" lines
  BYTE *body; DWORD bodyLen;
  wchar_t *respHeaders;                             // raw, CRLF-separated, after the status line
  DWORD status; volatile LONG aborted;
} Xhr;

static wchar_t *wdup(const wchar_t *s) {
  if (!s) return NULL;
  size_t n = (wcslen(s) + 1) * sizeof(wchar_t); wchar_t *d = HeapAlloc(GetProcessHeap(), 0, n); memcpy(d, s, n); return d;
}
static void xfree(void *p) { if (p) HeapFree(GetProcessHeap(), 0, p); }
static wchar_t *game_wstr(const wchar_t *s) {          // freed by the game with its CoTaskMemFree
  size_t n = (wcslen(s) + 1) * sizeof(wchar_t); wchar_t *d = p_GameCoTaskMemAlloc(n); if (d) memcpy(d, s, n); return d;
}

static HRESULT STDMETHODCALLTYPE x_QI(Xhr *x, const GUID *iid, void **out) {
  if (IsEqualGUID(iid, &IID_IXMLHTTPRequest2_) || IsEqualGUID(iid, &IID_IUnknown_x)) { InterlockedIncrement(&x->refs); *out = x; return S_OK; }
  char b[40]; guidstr(iid, b); logf("http #%ld QI {%s}: no", x->id, b);
  *out = NULL; return E_NOINTERFACE;
}
static ULONG STDMETHODCALLTYPE x_AddRef(Xhr *x) { return InterlockedIncrement(&x->refs); }
static ULONG STDMETHODCALLTYPE x_Release(Xhr *x) {
  LONG r = InterlockedDecrement(&x->refs);
  if (!r) {
    if (x->callback) XCALL(x->callback, 2, ULONG (STDMETHODCALLTYPE *)(void *))(x->callback);
    xfree(x->method); xfree(x->url); xfree(x->headers); xfree(x->body); xfree(x->respHeaders); xfree(x);
  }
  return r;
}
static HRESULT STDMETHODCALLTYPE x_Open(Xhr *x, const wchar_t *method, const wchar_t *url, XObj *cb, const wchar_t *u, const wchar_t *p, const wchar_t *pu, const wchar_t *pp) {
  (void)u; (void)p; (void)pu; (void)pp;
  xfree(x->method); xfree(x->url);
  x->method = wdup(method); x->url = wdup(url);
  if (cb) XCALL(cb, 1, ULONG (STDMETHODCALLTYPE *)(void *))(cb);
  if (x->callback) XCALL(x->callback, 2, ULONG (STDMETHODCALLTYPE *)(void *))(x->callback);
  x->callback = cb;
  return S_OK;
}
static HRESULT STDMETHODCALLTYPE x_SetRequestHeader(Xhr *x, const wchar_t *name, const wchar_t *value) {
  size_t need = wcslen(name) + wcslen(value) + 5;
  if (x->headersLen + need >= x->headersCap) {
    size_t cap = (x->headersCap + need) * 2;
    wchar_t *n = HeapAlloc(GetProcessHeap(), 0, cap * sizeof(wchar_t));
    if (x->headers) { memcpy(n, x->headers, x->headersLen * sizeof(wchar_t)); xfree(x->headers); }
    x->headers = n; x->headersCap = cap;
  }
  x->headersLen += swprintf(x->headers + x->headersLen, x->headersCap - x->headersLen, L"%ls: %ls\r\n", name, value);
  return S_OK;
}

static void fail(Xhr *x, HRESULT hr, const char *what) {
  logf("http #%ld %ls %ls: %s (0x%08lx)", x->id, x->method, x->url, what, hr);
  if (x->callback && !x->aborted) XCALL(x->callback, 8, HRESULT (STDMETHODCALLTYPE *)(void *, void *, HRESULT))(x->callback, x, hr);
}

// The response stream handed to the game: an HGlobal stream, wrapped to log every read and seek the
// game makes (how the Xls client walks a reply).
typedef struct { IStreamVtbl *vtbl; LONG refs; IStream *in; LONG id; ULONG pos; int emptyReads; } LogStream;
#define LS(t) ((LogStream *)(t))
static HRESULT STDMETHODCALLTYPE ls_QI(IStream *t, REFIID iid, void **out) {
  static const GUID IID_ISeqStream = { 0x0c733a30, 0x2a1c, 0x11ce, { 0xad, 0xe5, 0x00, 0xaa, 0x00, 0x44, 0x77, 0x3d } };
  static const GUID IID_IStream_ = { 0x0000000c, 0, 0, { 0xc0, 0, 0, 0, 0, 0, 0, 0x46 } };
  if (IsEqualGUID(iid, &IID_IUnknown_x) || IsEqualGUID(iid, &IID_ISeqStream) || IsEqualGUID(iid, &IID_IStream_)) { InterlockedIncrement(&LS(t)->refs); *out = t; return S_OK; }
  char b[40]; guidstr(iid, b); logf("http #%ld stream QI {%s}: no", LS(t)->id, b);
  *out = NULL; return E_NOINTERFACE;
}
static ULONG STDMETHODCALLTYPE ls_AddRef(IStream *t) { return InterlockedIncrement(&LS(t)->refs); }
static ULONG STDMETHODCALLTYPE ls_Release(IStream *t) {
  LONG r = InterlockedDecrement(&LS(t)->refs);
  if (!r) { LS(t)->in->lpVtbl->Release(LS(t)->in); xfree(t); }
  return r;
}
static HRESULT STDMETHODCALLTYPE ls_Read(IStream *t, void *buf, ULONG cb, ULONG *got) {
  ULONG g = 0; HRESULT hr = LS(t)->in->lpVtbl->Read(LS(t)->in, buf, cb, &g);
  // A short read is the end of the response: say so with S_FALSE, as the system's response stream does;
  // the Xls client reads until it sees that (an HGlobal stream's S_OK made it grow its buffer forever).
  if (SUCCEEDED(hr) && g < cb) hr = S_FALSE;
  if (g || LS(t)->emptyReads++ < 3) {
    char hex[3 * 16 + 1] = ""; for (ULONG i = 0; i < g && i < 16; i++) sprintf(hex + 3 * i, "%02x ", ((BYTE *)buf)[i]);
    logf("http #%ld stream read at %lu: asked %lu, got %lu (hr 0x%08lx) %s", LS(t)->id, LS(t)->pos, cb, g, hr, hex);
  }
  LS(t)->pos += g; if (got) *got = g;
  return hr;
}
static HRESULT STDMETHODCALLTYPE ls_Write(IStream *t, const void *b, ULONG cb, ULONG *w) { return LS(t)->in->lpVtbl->Write(LS(t)->in, b, cb, w); }
static HRESULT STDMETHODCALLTYPE ls_Seek(IStream *t, LARGE_INTEGER d, DWORD o, ULARGE_INTEGER *np) {
  ULARGE_INTEGER p; HRESULT hr = LS(t)->in->lpVtbl->Seek(LS(t)->in, d, o, &p);
  logf("http #%ld stream seek %lld from %lu -> %llu", LS(t)->id, d.QuadPart, o, p.QuadPart);
  LS(t)->pos = (ULONG)p.QuadPart; if (np) *np = p;
  return hr;
}
static HRESULT STDMETHODCALLTYPE ls_SetSize(IStream *t, ULARGE_INTEGER n) { return LS(t)->in->lpVtbl->SetSize(LS(t)->in, n); }
static HRESULT STDMETHODCALLTYPE ls_CopyTo(IStream *t, IStream *s, ULARGE_INTEGER n, ULARGE_INTEGER *r, ULARGE_INTEGER *w) {
  logf("http #%ld stream CopyTo %llu", LS(t)->id, n.QuadPart); return LS(t)->in->lpVtbl->CopyTo(LS(t)->in, s, n, r, w);
}
static HRESULT STDMETHODCALLTYPE ls_Commit(IStream *t, DWORD f) { return LS(t)->in->lpVtbl->Commit(LS(t)->in, f); }
static HRESULT STDMETHODCALLTYPE ls_Revert(IStream *t) { return LS(t)->in->lpVtbl->Revert(LS(t)->in); }
static HRESULT STDMETHODCALLTYPE ls_Lock(IStream *t, ULARGE_INTEGER a, ULARGE_INTEGER b, DWORD c) { (void)t; (void)a; (void)b; (void)c; return STG_E_INVALIDFUNCTION; }
static HRESULT STDMETHODCALLTYPE ls_Stat(IStream *t, STATSTG *s, DWORD f) { logf("http #%ld stream Stat", LS(t)->id); return LS(t)->in->lpVtbl->Stat(LS(t)->in, s, f | STATFLAG_NONAME); }
static HRESULT STDMETHODCALLTYPE ls_Clone(IStream *t, IStream **o) { logf("http #%ld stream Clone (refused)", LS(t)->id); *o = NULL; return E_NOTIMPL; }
static IStreamVtbl g_lsVtbl = { ls_QI, ls_AddRef, ls_Release, ls_Read, ls_Write, ls_Seek, ls_SetSize, ls_CopyTo, ls_Commit, ls_Revert, ls_Lock, ls_Lock, ls_Stat, ls_Clone };

static IStream *log_stream(IStream *in, LONG id) {
  LogStream *s = HeapAlloc(GetProcessHeap(), 0, sizeof *s);
  s->vtbl = &g_lsVtbl; s->refs = 1; s->in = in; s->id = id; s->pos = 0; s->emptyReads = 0;
  return (IStream *)s;
}

static DWORD WINAPI x_run(LPVOID param) {
  Xhr *x = param;
  URL_COMPONENTS uc = { sizeof uc };
  wchar_t host[256], path[4096], scheme[16];
  uc.lpszHostName = host; uc.dwHostNameLength = 256; uc.lpszUrlPath = path; uc.dwUrlPathLength = 4096;
  uc.lpszScheme = scheme; uc.dwSchemeLength = 16;
  wchar_t extra[2048] = L""; uc.lpszExtraInfo = extra; uc.dwExtraInfoLength = 2048;
  HINTERNET c = NULL, r = NULL;
  if (!WinHttpCrackUrl(x->url, 0, 0, &uc)) { fail(x, HRESULT_FROM_WIN32(GetLastError()), "bad url"); goto done; }
  wchar_t target[6144]; swprintf(target, 6144, L"%ls%ls", path, extra);
  c = WinHttpConnect(g_winhttp, g_srvHost, g_srvPort, 0);
  r = c ? WinHttpOpenRequest(c, x->method && *x->method ? x->method : L"GET", target, NULL, WINHTTP_NO_REFERER, WINHTTP_DEFAULT_ACCEPT_TYPES, g_srvTls ? WINHTTP_FLAG_SECURE : 0) : NULL;
  if (!r) { fail(x, HRESULT_FROM_WIN32(GetLastError()), "connect"); goto done; }
  wchar_t fwd[512]; swprintf(fwd, 512, L"X-Fh2net-Host: %ls\r\nX-Fh2net-Scheme: %ls\r\n", host, scheme);
  WinHttpAddRequestHeaders(r, fwd, (DWORD)-1L, WINHTTP_ADDREQ_FLAG_ADD | WINHTTP_ADDREQ_FLAG_REPLACE);
  if (x->headersLen) WinHttpAddRequestHeaders(r, x->headers, (DWORD)x->headersLen, WINHTTP_ADDREQ_FLAG_ADD | WINHTTP_ADDREQ_FLAG_REPLACE);
  if (!WinHttpSendRequest(r, WINHTTP_NO_ADDITIONAL_HEADERS, 0, x->body, x->bodyLen, x->bodyLen, 0) || !WinHttpReceiveResponse(r, NULL)) {
    fail(x, HRESULT_FROM_WIN32(GetLastError()), "send"); goto done;
  }
  DWORD st = 0, sz = sizeof st;
  WinHttpQueryHeaders(r, WINHTTP_QUERY_STATUS_CODE | WINHTTP_QUERY_FLAG_NUMBER, NULL, &st, &sz, NULL);
  x->status = st;
  sz = 0; WinHttpQueryHeaders(r, WINHTTP_QUERY_RAW_HEADERS_CRLF, NULL, NULL, &sz, NULL);
  wchar_t *raw = HeapAlloc(GetProcessHeap(), 0, sz + 2);
  if (WinHttpQueryHeaders(r, WINHTTP_QUERY_RAW_HEADERS_CRLF, NULL, raw, &sz, NULL)) {
    wchar_t *nl = wcsstr(raw, L"\r\n");               // drop the status line
    x->respHeaders = wdup(nl ? nl + 2 : raw);
  }
  xfree(raw);
  wchar_t stText[128] = L""; sz = sizeof stText;
  WinHttpQueryHeaders(r, WINHTTP_QUERY_STATUS_TEXT, NULL, stText, &sz, NULL);
  IStream *s = NULL; CreateStreamOnHGlobal(NULL, TRUE, &s);
  DWORD total = 0;
  for (;;) {
    DWORD avail = 0; if (!WinHttpQueryDataAvailable(r, &avail) || !avail) break;
    BYTE buf[16384]; DWORD got = 0;
    if (!WinHttpReadData(r, buf, avail < sizeof buf ? avail : sizeof buf, &got) || !got) break;
    ULONG w; s->lpVtbl->Write(s, buf, got, &w); total += got;
  }
  LARGE_INTEGER zero = { 0 }; s->lpVtbl->Seek(s, zero, STREAM_SEEK_SET, NULL);
  s = log_stream(s, x->id);
  logf("http #%ld %ls %ls -> %lu, %lu bytes", x->id, x->method, x->url, st, total);
  if (!x->aborted && x->callback) {
    // OnHeadersAvailable, OnDataAvailable (the Xls client keeps this stream), OnResponseReceived (it only signals)
    XCALL(x->callback, 4, HRESULT (STDMETHODCALLTYPE *)(void *, void *, DWORD, const wchar_t *))(x->callback, x, st, stText);
    if (!x->aborted) XCALL(x->callback, 5, HRESULT (STDMETHODCALLTYPE *)(void *, void *, void *))(x->callback, x, s);
    if (!x->aborted) XCALL(x->callback, 6, HRESULT (STDMETHODCALLTYPE *)(void *, void *, void *))(x->callback, x, s);
  }
  s->lpVtbl->Release(s);
done:
  if (r) WinHttpCloseHandle(r);
  if (c) WinHttpCloseHandle(c);
  x_Release(x);
  return 0;
}

static HRESULT STDMETHODCALLTYPE x_Send(Xhr *x, ISequentialStream *body, ULONGLONG size) {
  xfree(x->body); x->body = NULL; x->bodyLen = 0;
  if (body && size) {
    x->body = HeapAlloc(GetProcessHeap(), 0, (SIZE_T)size);
    ULONG got = 0;
    while (x->bodyLen < size) {
      if (FAILED(body->lpVtbl->Read(body, x->body + x->bodyLen, (ULONG)(size - x->bodyLen), &got)) || !got) break;
      x->bodyLen += got;
    }
  }
  logf("http #%ld send %ls %ls (%lu body bytes)", x->id, x->method, x->url, x->bodyLen);
  InterlockedIncrement(&x->refs);
  HANDLE t = CreateThread(NULL, 0, x_run, x, 0, NULL);
  if (!t) { x_Release(x); return HRESULT_FROM_WIN32(GetLastError()); }
  CloseHandle(t);
  return S_OK;
}
static HRESULT STDMETHODCALLTYPE x_Abort(Xhr *x) { x->aborted = 1; return S_OK; }
static HRESULT STDMETHODCALLTYPE x_SetCookie(Xhr *x, const void *c, DWORD *st) { (void)x; (void)c; if (st) *st = 0; return S_OK; }
static HRESULT STDMETHODCALLTYPE x_SetCustomResponseStream(Xhr *x, void *s) { logf("http #%ld SetCustomResponseStream (ignored)", x->id); (void)s; return S_OK; }
static HRESULT STDMETHODCALLTYPE x_SetProperty(Xhr *x, int prop, ULONGLONG v) { (void)x; (void)prop; (void)v; return S_OK; }
static HRESULT STDMETHODCALLTYPE x_GetAllResponseHeaders(Xhr *x, wchar_t **out) { *out = game_wstr(x->respHeaders ? x->respHeaders : L""); return *out ? S_OK : E_OUTOFMEMORY; }
static HRESULT STDMETHODCALLTYPE x_GetCookie(Xhr *x, const wchar_t *u, const wchar_t *n, DWORD f, DWORD *count, void **c) { (void)x; (void)u; (void)n; (void)f; *count = 0; *c = NULL; return S_OK; }
static HRESULT STDMETHODCALLTYPE x_GetResponseHeader(Xhr *x, const wchar_t *name, wchar_t **out) {
  *out = NULL;
  size_t n = wcslen(name);
  for (const wchar_t *l = x->respHeaders; l && *l; ) {
    const wchar_t *e = wcsstr(l, L"\r\n"); if (!e) e = l + wcslen(l);
    if ((size_t)(e - l) > n && l[n] == L':' && !_wcsnicmp(l, name, n)) {
      const wchar_t *v = l + n + 1; while (*v == L' ') v++;
      wchar_t tmp[2048]; size_t len = (size_t)(e - v) < 2047 ? (size_t)(e - v) : 2047;
      memcpy(tmp, v, len * sizeof(wchar_t)); tmp[len] = 0;
      *out = game_wstr(tmp); return *out ? S_OK : E_OUTOFMEMORY;
    }
    l = *e ? e + 2 : e;
  }
  return HRESULT_FROM_WIN32(ERROR_WINHTTP_HEADER_NOT_FOUND);
}
static void *g_xhrVtbl[] = { x_QI, x_AddRef, x_Release, x_Open, x_Send, x_Abort, x_SetCookie, x_SetCustomResponseStream,
  x_SetProperty, x_SetRequestHeader, x_GetAllResponseHeaders, x_GetCookie, x_GetResponseHeader };

static int xhr_init(void) {
  if (!g_httpServer[0]) return 0;
  URL_COMPONENTS uc = { sizeof uc };
  uc.lpszHostName = g_srvHost; uc.dwHostNameLength = 128;
  if (!WinHttpCrackUrl(g_httpServer, 0, 0, &uc)) { logf("http: bad Server %ls", g_httpServer); g_httpServer[0] = 0; return 0; }
  g_srvPort = uc.nPort; g_srvTls = uc.nScheme == INTERNET_SCHEME_HTTPS;
  g_winhttp = WinHttpOpen(L"fh2net", WINHTTP_ACCESS_TYPE_NO_PROXY, WINHTTP_NO_PROXY_NAME, WINHTTP_NO_PROXY_BYPASS, 0);
  p_GameCoTaskMemAlloc = iat_lookup(GAME_BASE, "combase.dll", "CoTaskMemAlloc");
  if (!g_winhttp || !p_GameCoTaskMemAlloc) { logf("http: init failed"); g_httpServer[0] = 0; return 0; }
  logf("http: requests go to %ls (host %ls port %u%s)", g_httpServer, g_srvHost, g_srvPort, g_srvTls ? " tls" : "");
  return 1;
}

// For CoCreateInstance: our request in place of Azimuth's, or 0 to let Azimuth answer.
static int xhr_create(REFCLSID c, REFIID i, void **pv, HRESULT *hr) {
  if (!g_winhttp || !IsEqualGUID(c, &CLSID_FreeThreadedXMLHTTP60_)) return 0;
  Xhr *x = HeapAlloc(GetProcessHeap(), HEAP_ZERO_MEMORY, sizeof *x);
  x->vtbl = g_xhrVtbl; x->refs = 1; x->id = InterlockedIncrement(&g_reqSeq);
  *hr = x_QI(x, i, pv);
  x_Release(x);
  return 1;
}
