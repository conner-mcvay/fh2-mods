// Included by fh2net.c after json.c. A logging proxy: wraps a WinRT object so that every call to its first
// 32 vtable slots is logged (slot, first args, HRESULT) and forwarded. QI for the object's own identity hands
// out the proxy again; other interfaces go straight to the real object. With [debug] Streams=1, every
// Windows.Storage.Streams.DataWriter the factory makes is proxied; IDataWriter.DetachBuffer (slot 31 in the SDK
// order: ... WriteBytes 12 ... WriteString 27, MeasureString 28, StoreAsync 29, FlushAsync 30, DetachBuffer 31)
// also logs the detached buffer's IBuffer.Length (slot 7).

static int g_debugStreams;
typedef struct { void **vtbl; Obj *real; const char *name; LONG refs; } LogProxy;
#define LP(t) ((LogProxy *)(t))
typedef HRESULT (STDMETHODCALLTYPE *Fwd6)(void *, void *, void *, void *, void *, void *, void *);

static HRESULT STDMETHODCALLTYPE lp_QI(void *t, const GUID *iid, void **out) {
  HRESULT hr = VCALL(LP(t)->real, 0, QIfn)(LP(t)->real, iid, out);
  char b[40]; guidstr(iid, b);
  logf("proxy %s QI {%s} -> 0x%08lx%s", LP(t)->name, b, hr, SUCCEEDED(hr) && *out == LP(t)->real ? " (itself)" : "");
  if (SUCCEEDED(hr) && *out == LP(t)->real) *out = t;
  return hr;
}
static ULONG STDMETHODCALLTYPE lp_AddRef(void *t) { return VCALL(LP(t)->real, 1, ULONG (STDMETHODCALLTYPE *)(void *))(LP(t)->real); }
static ULONG STDMETHODCALLTYPE lp_Release(void *t) { return VCALL(LP(t)->real, 2, ULONG (STDMETHODCALLTYPE *)(void *))(LP(t)->real); }
#define LP_SLOT(n) static HRESULT STDMETHODCALLTYPE lp_##n(void *t, void *a, void *b, void *c, void *d, void *e, void *f) { \
  HRESULT hr = VCALL(LP(t)->real, n, Fwd6)(LP(t)->real, a, b, c, d, e, f); \
  logf("proxy %s slot %d (%p %p %p) -> 0x%08lx", LP(t)->name, n, a, b, c, hr); \
  return hr; }
LP_SLOT(3) LP_SLOT(4) LP_SLOT(5) LP_SLOT(6) LP_SLOT(7) LP_SLOT(8) LP_SLOT(9) LP_SLOT(10) LP_SLOT(11) LP_SLOT(12)
LP_SLOT(13) LP_SLOT(14) LP_SLOT(15) LP_SLOT(16) LP_SLOT(17) LP_SLOT(18) LP_SLOT(19) LP_SLOT(20) LP_SLOT(21)
LP_SLOT(22) LP_SLOT(23) LP_SLOT(24) LP_SLOT(25) LP_SLOT(26) LP_SLOT(27) LP_SLOT(28) LP_SLOT(29) LP_SLOT(30)
static HRESULT STDMETHODCALLTYPE lp_31(void *t, void *a, void *b, void *c, void *d, void *e, void *f) {
  HRESULT hr = VCALL(LP(t)->real, 31, Fwd6)(LP(t)->real, a, b, c, d, e, f);
  UINT32 len = (UINT32)-1;
  if (SUCCEEDED(hr) && a && *(Obj **)a) VCALL(*(Obj **)a, 7, HRESULT (STDMETHODCALLTYPE *)(void *, UINT32 *))(*(Obj **)a, &len);
  logf("proxy %s slot 31 (DetachBuffer) -> 0x%08lx, buffer %p length %u", LP(t)->name, hr, a ? *(Obj **)a : NULL, len);
  return hr;
}
static void *g_lpVtbl[] = { lp_QI, lp_AddRef, lp_Release, lp_3, lp_4, lp_5, lp_6, lp_7, lp_8, lp_9, lp_10, lp_11, lp_12,
  lp_13, lp_14, lp_15, lp_16, lp_17, lp_18, lp_19, lp_20, lp_21, lp_22, lp_23, lp_24, lp_25, lp_26, lp_27, lp_28, lp_29, lp_30, lp_31 };

static void *log_proxy(Obj *real, const char *name) {
  LogProxy *p = HeapAlloc(GetProcessHeap(), 0, sizeof *p);
  p->vtbl = g_lpVtbl; p->real = real; p->name = name; p->refs = 1;
  return p;
}

// Factory wrapper: IActivationFactory.ActivateInstance (slot 6) is proxied.
typedef struct { void **vtbl; Obj *real; LONG refs; } FactoryWrap;
static HRESULT STDMETHODCALLTYPE fw_QI(void *t, const GUID *iid, void **out) { return VCALL(((FactoryWrap *)t)->real, 0, QIfn)(((FactoryWrap *)t)->real, iid, out); }
static ULONG STDMETHODCALLTYPE fw_AddRef(void *t) { return InterlockedIncrement(&((FactoryWrap *)t)->refs); }
static ULONG STDMETHODCALLTYPE fw_Release(void *t) { return InterlockedDecrement(&((FactoryWrap *)t)->refs); }
static HRESULT STDMETHODCALLTYPE fw_3(void *t, void *a, void *b) { return VCALL(((FactoryWrap *)t)->real, 3, HRESULT (STDMETHODCALLTYPE *)(void *, void *, void *))(((FactoryWrap *)t)->real, a, b); }
static HRESULT STDMETHODCALLTYPE fw_4(void *t, void *a) { return VCALL(((FactoryWrap *)t)->real, 4, HRESULT (STDMETHODCALLTYPE *)(void *, void *))(((FactoryWrap *)t)->real, a); }
static HRESULT STDMETHODCALLTYPE fw_5(void *t, void *a) { return VCALL(((FactoryWrap *)t)->real, 5, HRESULT (STDMETHODCALLTYPE *)(void *, void *))(((FactoryWrap *)t)->real, a); }
static HRESULT STDMETHODCALLTYPE fw_Activate(void *t, Obj **out) {
  HRESULT hr = VCALL(((FactoryWrap *)t)->real, 6, HRESULT (STDMETHODCALLTYPE *)(void *, Obj **))(((FactoryWrap *)t)->real, out);
  if (SUCCEEDED(hr) && *out) *out = log_proxy(*out, "DataWriter");
  logf("DataWriter created -> 0x%08lx", hr);
  return hr;
}
static void *g_fwVtbl[] = { fw_QI, fw_AddRef, fw_Release, fw_3, fw_4, fw_5, fw_Activate };

static int wrap_streams(const wchar_t *cls, GUID *iid, void **out) {
  static const GUID IID_IActivationFactory_ = { 0x00000035, 0, 0, { 0xc0, 0, 0, 0, 0, 0, 0, 0x46 } };
  if (!g_debugStreams || !*out || wcscmp(cls, L"Windows.Storage.Streams.DataWriter") || !IsEqualGUID(iid, &IID_IActivationFactory_)) return 0;
  FactoryWrap *w = HeapAlloc(GetProcessHeap(), 0, sizeof *w);
  w->vtbl = g_fwVtbl; w->real = *out; w->refs = 1;
  *out = w;
  return 1;
}
