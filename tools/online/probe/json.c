// Included by fh2net.c after qos.c. Diagnostics for Windows.Data.Json (Azimuth's), which the Xbox Live library
// parses replies with: with [debug] Json=1 the JsonValue statics are wrapped, every Parse / TryParse is
// logged, and a reply holding "qosServers" is walked the way the library walks it (GetObject,
// GetNamedArray, QI IIterable<IJsonValue>, First, HasCurrent), logging each step.

static int g_debugJson;
static const GUID IID_IJsonValueStatics = { 0x5f6b544a, 0x2f53, 0x48e1, { 0x91, 0xa3, 0xf7, 0x8b, 0x50, 0xa6, 0x34, 0x5c } };
static const GUID IID_IIterableJsonValue = { 0xcb0492b6, 0x4113, 0x55cf, { 0xb2, 0xc5, 0x99, 0xeb, 0x42, 0x8b, 0xa4, 0x93 } };
static const GUID IID_IIterableJsonValueXsapi = { 0xd44662bc, 0xdce3, 0x59a8, { 0x92, 0x72, 0x4b, 0x21, 0x0f, 0x33, 0x90, 0x8b } };

typedef struct { void **vtbl; Obj *real; LONG refs; } JsonStatics;
#define JS(t) ((JsonStatics *)(t))
static HRESULT STDMETHODCALLTYPE js_QI(void *t, const GUID *iid, void **out) {
  if (IsEqualGUID(iid, &IID_IJsonValueStatics) || IsEqualGUID(iid, &IID_IUnknown_) || IsEqualGUID(iid, &IID_IInspectable_)) {
    InterlockedIncrement(&JS(t)->refs); *out = t; return S_OK;
  }
  return VCALL(JS(t)->real, 0, HRESULT (STDMETHODCALLTYPE *)(void *, const GUID *, void **))(JS(t)->real, iid, out);
}
static ULONG STDMETHODCALLTYPE js_AddRef(void *t) { return InterlockedIncrement(&JS(t)->refs); }
static ULONG STDMETHODCALLTYPE js_Release(void *t) { return InterlockedDecrement(&JS(t)->refs); }
#define JS_FWD(slot) static HRESULT STDMETHODCALLTYPE js_##slot(void *t, void *a, void *b, void *c, void *d) { \
  return VCALL(JS(t)->real, slot, HRESULT (STDMETHODCALLTYPE *)(void *, void *, void *, void *, void *))(JS(t)->real, a, b, c, d); }
JS_FWD(3) JS_FWD(4) JS_FWD(5) JS_FWD(6) JS_FWD(8) JS_FWD(9) JS_FWD(10) JS_FWD(11) JS_FWD(12)

typedef HRESULT (STDMETHODCALLTYPE *QIfn)(void *, const GUID *, void **);
static void json_walk(Obj *val) {
  Obj *obj = NULL, *arr = NULL, *it1 = NULL, *it2 = NULL, *first = NULL;
  int vt = -1;
  HRESULT hr = VCALL(val, 6, HRESULT (STDMETHODCALLTYPE *)(void *, int *))(val, &vt);
  logf("  json walk: ValueType hr 0x%08lx type %d (3 = object)", hr, vt);
  hr = VCALL(val, 12, HRESULT (STDMETHODCALLTYPE *)(void *, Obj **))(val, &obj);   // IJsonValue.GetObject
  logf("  json walk: GetObject hr 0x%08lx -> %p", hr, obj);
  if (!obj) return;
  void *name = NULL; p_WindowsCreateString(L"qosServers", 10, &name);
  hr = VCALL(obj, 9, HRESULT (STDMETHODCALLTYPE *)(void *, void *, Obj **))(obj, name, &arr);   // IJsonObject.GetNamedArray
  logf("  json walk: GetNamedArray(qosServers) hr 0x%08lx -> %p", hr, arr);
  if (!arr) return;
  hr = VCALL(arr, 0, QIfn)(arr, &IID_IIterableJsonValueXsapi, (void **)&it1);
  logf("  json walk: QI IIterable<IJsonValue> {d44662bc-...} hr 0x%08lx -> %p", hr, it1);
  hr = VCALL(arr, 0, QIfn)(arr, &IID_IIterableJsonValue, (void **)&it2);
  logf("  json walk: QI IIterable<IJsonValue> {cb0492b6-...} hr 0x%08lx -> %p", hr, it2);
  Obj *it = it1 ? it1 : it2;
  if (!it) return;
  hr = VCALL(it, 6, HRESULT (STDMETHODCALLTYPE *)(void *, Obj **))(it, &first);   // IIterable.First
  logf("  json walk: First hr 0x%08lx -> %p", hr, first);
  if (!first) return;
  BYTE has = 0;
  hr = VCALL(first, 7, HRESULT (STDMETHODCALLTYPE *)(void *, BYTE *))(first, &has);   // IIterator.HasCurrent
  logf("  json walk: HasCurrent hr 0x%08lx -> %d", hr, has);
}

static HRESULT STDMETHODCALLTYPE js_Parse(void *t, void *str, Obj **out) {
  HRESULT hr = VCALL(JS(t)->real, 6, HRESULT (STDMETHODCALLTYPE *)(void *, void *, Obj **))(JS(t)->real, str, out);
  const wchar_t *s = hs(str);
  logf("JsonValue.Parse(%.120ls) -> 0x%08lx %p", s, hr, out ? *out : NULL);
  if (SUCCEEDED(hr) && *out && wcsstr(s, L"qosServers")) json_walk(*out);
  return hr;
}
static HRESULT STDMETHODCALLTYPE js_TryParse(void *t, void *str, Obj **out, BYTE *ok) {
  HRESULT hr = VCALL(JS(t)->real, 7, HRESULT (STDMETHODCALLTYPE *)(void *, void *, Obj **, BYTE *))(JS(t)->real, str, out, ok);
  const wchar_t *s = hs(str);
  logf("JsonValue.TryParse(%.120ls) -> 0x%08lx ok %d %p", s, hr, ok ? *ok : -1, out ? *out : NULL);
  if (SUCCEEDED(hr) && ok && *ok && *out && wcsstr(s, L"qosServers")) json_walk(*out);
  return hr;
}
static void *g_jsVtbl[] = { js_QI, js_AddRef, js_Release, js_3, js_4, js_5, js_Parse, js_TryParse, js_8, js_9, js_10, js_11, js_12 };

// JsonObject: the library activates its factory (IActivationFactory) and QIs it for IJsonObjectStatics
// (Parse 6, TryParse 7, both answering an IJsonObject). The factory is wrapped so that QI hands out a
// logging statics wrapper.
static const GUID IID_IJsonObjectStatics = { 0x2289f159, 0x54de, 0x45d8, { 0xab, 0xcc, 0x22, 0x60, 0x3f, 0xa0, 0x66, 0xa0 } };
static void json_walk_object(Obj *obj) {
  Obj *arr = NULL, *it1 = NULL, *it2 = NULL, *first = NULL;
  void *name = NULL; p_WindowsCreateString(L"qosServers", 10, &name);
  HRESULT hr = VCALL(obj, 9, HRESULT (STDMETHODCALLTYPE *)(void *, void *, Obj **))(obj, name, &arr);
  logf("  json walk: GetNamedArray(qosServers) hr 0x%08lx -> %p", hr, arr);
  if (!arr) return;
  hr = VCALL(arr, 0, QIfn)(arr, &IID_IIterableJsonValueXsapi, (void **)&it1);
  logf("  json walk: QI IIterable<IJsonValue> {d44662bc-...} hr 0x%08lx -> %p", hr, it1);
  hr = VCALL(arr, 0, QIfn)(arr, &IID_IIterableJsonValue, (void **)&it2);
  logf("  json walk: QI IIterable<IJsonValue> {cb0492b6-...} hr 0x%08lx -> %p", hr, it2);
  Obj *it = it1 ? it1 : it2;
  if (!it) return;
  hr = VCALL(it, 6, HRESULT (STDMETHODCALLTYPE *)(void *, Obj **))(it, &first);
  logf("  json walk: First hr 0x%08lx -> %p", hr, first);
  if (!first) return;
  BYTE has = 0;
  hr = VCALL(first, 7, HRESULT (STDMETHODCALLTYPE *)(void *, BYTE *))(first, &has);
  logf("  json walk: HasCurrent hr 0x%08lx -> %d", hr, has);
}
static HRESULT STDMETHODCALLTYPE jo_Parse(void *t, void *str, Obj **out) {
  HRESULT hr = VCALL(JS(t)->real, 6, HRESULT (STDMETHODCALLTYPE *)(void *, void *, Obj **))(JS(t)->real, str, out);
  const wchar_t *s = hs(str);
  logf("JsonObject.Parse(%.120ls) -> 0x%08lx %p", s, hr, out ? *out : NULL);
  if (SUCCEEDED(hr) && *out && wcsstr(s, L"qosServers")) json_walk_object(*out);
  return hr;
}
static HRESULT STDMETHODCALLTYPE jo_TryParse(void *t, void *str, Obj **out, BYTE *ok) {
  HRESULT hr = VCALL(JS(t)->real, 7, HRESULT (STDMETHODCALLTYPE *)(void *, void *, Obj **, BYTE *))(JS(t)->real, str, out, ok);
  const wchar_t *s = hs(str);
  logf("JsonObject.TryParse(%.120ls) -> 0x%08lx ok %d %p", s, hr, ok ? *ok : -1, out ? *out : NULL);
  if (SUCCEEDED(hr) && ok && *ok && *out && wcsstr(s, L"qosServers")) json_walk_object(*out);
  return hr;
}
static void *g_joVtbl[] = { js_QI, js_AddRef, js_Release, js_3, js_4, js_5, jo_Parse, jo_TryParse, js_8, js_9, js_10, js_11, js_12 };

// The JsonObject factory wrapper: everything forwarded, but a QI for IJsonObjectStatics is answered wrapped.
static HRESULT STDMETHODCALLTYPE jf_QI(void *t, const GUID *iid, void **out) {
  HRESULT hr = VCALL(JS(t)->real, 0, HRESULT (STDMETHODCALLTYPE *)(void *, const GUID *, void **))(JS(t)->real, iid, out);
  char b[40]; guidstr(iid, b);
  logf("JsonObject factory QI {%s} -> 0x%08lx", b, hr);
  if (SUCCEEDED(hr) && *out && IsEqualGUID(iid, &IID_IJsonObjectStatics)) {
    JsonStatics *w = HeapAlloc(GetProcessHeap(), 0, sizeof *w);
    w->vtbl = g_joVtbl; w->real = *out; w->refs = 1;
    *out = w;
  }
  return hr;
}
static void *g_jfVtbl[] = { jf_QI, js_AddRef, js_Release, js_3, js_4, js_5, js_6 };   // IActivationFactory; 6 ActivateInstance

static int wrap_json(const wchar_t *cls, GUID *iid, void **out) {
  if (g_debugJson && *out && !wcscmp(cls, L"Windows.Data.Json.JsonObject")) {
    // asked for IJsonObjectStatics directly (what the Xbox Live library does), or for the plain factory
    JsonStatics *w = HeapAlloc(GetProcessHeap(), 0, sizeof *w);
    w->vtbl = IsEqualGUID(iid, &IID_IJsonObjectStatics) ? g_joVtbl : g_jfVtbl; w->real = *out; w->refs = 1;
    *out = w;
    return 1;
  }
  if (!g_debugJson || !*out || !IsEqualGUID(iid, &IID_IJsonValueStatics) || wcscmp(cls, L"Windows.Data.Json.JsonValue")) return 0;
  JsonStatics *w = HeapAlloc(GetProcessHeap(), 0, sizeof *w);
  w->vtbl = g_jsVtbl; w->real = *out; w->refs = 1;
  *out = w;
  return 1;
}
