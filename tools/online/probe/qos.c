// Included by fh2net.c after the token code. Windows.Xbox.Networking.QualityOfService, which Azimuth answers
// offline: with [net] FakeQos=1 its statics are wrapped, and MeasureQualityOfServiceAsync (slot 6: addresses,
// metrics, timeout ms, probes, out operation) answers an already-completed operation. Its result is, for now,
// a "probe" object that logs every call the game makes on it, to learn the interfaces it needs.

static int g_fakeQos;
static const GUID IID_IQualityOfServiceStatics = { 0xe58ad357, 0xb957, 0x4cce, { 0x92, 0xad, 0x83, 0x30, 0xfb, 0x13, 0x35, 0x2e } };

// ---- probe objects: every slot logs its call; 6 and up answer E_NOTIMPL --------------------------------
typedef struct { void **vtbl; const char *name; } Probe;
static HRESULT STDMETHODCALLTYPE pr_QI(Probe *t, const GUID *iid, void **out) {
  char b[40]; guidstr(iid, b);
  if (iid->Data1 == 0x00000003 || iid->Data1 == 0x00000038 || iid->Data1 == 0x00000037) { *out = NULL; return E_NOINTERFACE; }
  logf("probe %s QI {%s}: answered as itself", t->name, b);
  *out = t; return S_OK;
}
static ULONG STDMETHODCALLTYPE pr_AddRef(Probe *t) { (void)t; return 2; }
static ULONG STDMETHODCALLTYPE pr_Release(Probe *t) { (void)t; return 1; }
#define PR_SLOT(n) static HRESULT STDMETHODCALLTYPE pr_##n(Probe *t, void *a, void *b, void *c, void *d) { \
  logf("probe %s slot %d (%p %p %p %p): E_NOTIMPL, called from %p", t->name, n, a, b, c, d, __builtin_return_address(0)); return E_NOTIMPL; }
PR_SLOT(6) PR_SLOT(7) PR_SLOT(8) PR_SLOT(9) PR_SLOT(10) PR_SLOT(11) PR_SLOT(12) PR_SLOT(13) PR_SLOT(14) PR_SLOT(15)
PR_SLOT(16) PR_SLOT(17) PR_SLOT(18) PR_SLOT(19) PR_SLOT(20) PR_SLOT(21) PR_SLOT(22) PR_SLOT(23)
static void *g_probeVtbl[] = { pr_QI, pr_AddRef, pr_Release, prof_GetIids, prof_GetRuntimeClassName, prof_GetTrustLevel,
  pr_6, pr_7, pr_8, pr_9, pr_10, pr_11, pr_12, pr_13, pr_14, pr_15, pr_16, pr_17, pr_18, pr_19, pr_20, pr_21, pr_22, pr_23 };
// ---- the measurement result ------------------------------------------------------------------------
// What the game uses (14179B030): result slot 8 GetMeasurementsForMetric(metric, out IVectorView); it QIs that
// for IIterable<QualityOfServiceMeasurement> (36a3a9bb-...) and walks it (First 6; iterator Current 6,
// HasCurrent 7, MoveNext 8). Per measurement: Status (6, must be 1), MetricValue (8, an IPropertyValue read
// with GetUInt32, slot 12, as latency in ms), DeviceAddress (9, the address object it passed in, whose
// base64 it matches against its server list). Everything else stays a logging probe.
#ifndef E_BOUNDS
#define E_BOUNDS ((HRESULT)0x8000000BL)
#endif
static UINT32 g_qosLatency = 20;
#define MAX_QOS 16
typedef struct { Obj *addr[MAX_QOS]; int n; int metric; } QosData;
typedef struct { void **vtbl; QosData *q; int i; } QosMeasure;
typedef struct { void **vtbl; QosData *q; int i; } QosIter;
typedef struct { void **viewVtbl; void **iterableVtbl; QosData *q; } QosView;
typedef struct { void **vtbl; QosData *q; } QosResult;

static const GUID IID_IIterableQosMeasurement = { 0x36a3a9bb, 0x712a, 0x5297, { 0xb5, 0xa0, 0xec, 0xdc, 0x0c, 0xb2, 0x4b, 0x9f } };
static void *heap(size_t n) { return HeapAlloc(GetProcessHeap(), HEAP_ZERO_MEMORY, n); }
static HRESULT STDMETHODCALLTYPE self_QI(void *t, const GUID *iid, void **out) {
  if (iid->Data1 == 0x00000003 || iid->Data1 == 0x00000038 || iid->Data1 == 0x00000037) { *out = NULL; return E_NOINTERFACE; }
  *out = t; return S_OK;
}

// IPropertyValue holding the latency: every numeric getter answers it.
static HRESULT STDMETHODCALLTYPE pv_Type(void *t, int *ty) { (void)t; *ty = 6; return S_OK; }   // PropertyType_UInt32
static HRESULT STDMETHODCALLTYPE pv_IsScalar(void *t, BYTE *b) { (void)t; *b = 1; return S_OK; }
static HRESULT STDMETHODCALLTYPE pv_U8(void *t, BYTE *v) { (void)t; *v = (BYTE)g_qosLatency; return S_OK; }
static HRESULT STDMETHODCALLTYPE pv_16(void *t, UINT16 *v) { (void)t; *v = (UINT16)g_qosLatency; return S_OK; }
static HRESULT STDMETHODCALLTYPE pv_32(void *t, UINT32 *v) { (void)t; *v = g_qosLatency; logf("QoS: latency read (%u ms)", g_qosLatency); return S_OK; }
static HRESULT STDMETHODCALLTYPE pv_64(void *t, UINT64 *v) { (void)t; *v = g_qosLatency; return S_OK; }
static HRESULT STDMETHODCALLTYPE pv_F32(void *t, float *v) { (void)t; *v = (float)g_qosLatency; return S_OK; }
static HRESULT STDMETHODCALLTYPE pv_F64(void *t, double *v) { (void)t; *v = g_qosLatency; return S_OK; }
static void *g_pvVtbl[] = { self_QI, pr_AddRef, pr_Release, prof_GetIids, prof_GetRuntimeClassName, prof_GetTrustLevel,
  pv_Type, pv_IsScalar, pv_U8, pv_16, pv_16, pv_32, pv_32, pv_64, pv_64, pv_F32, pv_F64,
  pr_17, pr_18, pr_19, pr_20, pr_21, pr_22, pr_23 };
static Obj g_latencyValue = { g_pvVtbl };

// QualityOfServiceMeasurement
static HRESULT STDMETHODCALLTYPE qm_Status(QosMeasure *t, int *s) { (void)t; *s = 1; return S_OK; }
static HRESULT STDMETHODCALLTYPE qm_Metric(QosMeasure *t, int *m) { *m = t->q->metric; return S_OK; }
static HRESULT STDMETHODCALLTYPE qm_Value(QosMeasure *t, Obj **v) { (void)t; *v = &g_latencyValue; return S_OK; }
static HRESULT STDMETHODCALLTYPE qm_Address(QosMeasure *t, Obj **a) {
  *a = t->q->addr[t->i]; VCALL(*a, 1, ULONG (STDMETHODCALLTYPE *)(void *))(*a); return S_OK;
}
static void *g_qmVtbl[] = { self_QI, pr_AddRef, pr_Release, prof_GetIids, prof_GetRuntimeClassName, prof_GetTrustLevel,
  qm_Status, qm_Metric, qm_Value, qm_Address, pr_10, pr_11, pr_12, pr_13 };
static QosMeasure *qos_measure(QosData *q, int i) { QosMeasure *m = heap(sizeof *m); m->vtbl = g_qmVtbl; m->q = q; m->i = i; return m; }

// IIterator<QualityOfServiceMeasurement>
static HRESULT STDMETHODCALLTYPE qi_Current(QosIter *t, void **out) {
  if (t->i >= t->q->n) { *out = NULL; return E_BOUNDS; }
  *out = qos_measure(t->q, t->i); return S_OK;
}
static HRESULT STDMETHODCALLTYPE qi_HasCurrent(QosIter *t, BYTE *b) { *b = t->i < t->q->n; return S_OK; }
static HRESULT STDMETHODCALLTYPE qi_MoveNext(QosIter *t, BYTE *b) { t->i++; *b = t->i < t->q->n; return S_OK; }
static void *g_qiVtbl[] = { self_QI, pr_AddRef, pr_Release, prof_GetIids, prof_GetRuntimeClassName, prof_GetTrustLevel,
  qi_Current, qi_HasCurrent, qi_MoveNext, pr_9 };

// IVectorView<QualityOfServiceMeasurement> (+0) and IIterable<...> (+8)
static HRESULT STDMETHODCALLTYPE qv_QI(void *t, const GUID *iid, void **out) {
  QosView *v = t;
  if (IsEqualGUID(iid, &IID_IIterableQosMeasurement)) { *out = &v->iterableVtbl; return S_OK; }
  if (iid->Data1 == 0x00000003 || iid->Data1 == 0x00000038 || iid->Data1 == 0x00000037) { *out = NULL; return E_NOINTERFACE; }
  if (!IsEqualGUID(iid, &IID_IUnknown_) && !IsEqualGUID(iid, &IID_IInspectable_)) { char b[40]; guidstr(iid, b); logf("QoS measurement list QI {%s}: answered as the list", b); }
  *out = v; return S_OK;
}
static HRESULT STDMETHODCALLTYPE qv_GetAt(QosView *t, UINT32 i, void **out) {
  if ((int)i >= t->q->n) { *out = NULL; return E_BOUNDS; }
  *out = qos_measure(t->q, (int)i); return S_OK;
}
static HRESULT STDMETHODCALLTYPE qv_Size(QosView *t, UINT32 *n) { *n = (UINT32)t->q->n; return S_OK; }
static void *g_qvVtbl[] = { qv_QI, pr_AddRef, pr_Release, prof_GetIids, prof_GetRuntimeClassName, prof_GetTrustLevel,
  qv_GetAt, qv_Size, pr_8, pr_9 };
static QosView *qv_of_iterable(void *t) { return (QosView *)((BYTE *)t - 8); }
static HRESULT STDMETHODCALLTYPE qa_QI(void *t, const GUID *iid, void **out) { return qv_QI(qv_of_iterable(t), iid, out); }
static HRESULT STDMETHODCALLTYPE qa_First(void *t, void **out) {
  QosIter *it = heap(sizeof *it); it->vtbl = g_qiVtbl; it->q = qv_of_iterable(t)->q; it->i = 0;
  *out = it; return S_OK;
}
static void *g_qaVtbl[] = { qa_QI, pr_AddRef, pr_Release, prof_GetIids, prof_GetRuntimeClassName, prof_GetTrustLevel, qa_First };

// MeasureQualityOfServiceResult
static HRESULT STDMETHODCALLTYPE qr_ForMetric(QosResult *t, int metric, void **out) {
  QosView *v = heap(sizeof *v); v->viewVtbl = g_qvVtbl; v->iterableVtbl = g_qaVtbl; v->q = t->q;
  t->q->metric = metric;
  logf("QoS result: GetMeasurementsForMetric(%d) -> %d measurements of %u ms", metric, t->q->n, g_qosLatency);
  *out = v; return S_OK;
}
static void *g_qrVtbl[] = { self_QI, pr_AddRef, pr_Release, prof_GetIids, prof_GetRuntimeClassName, prof_GetTrustLevel,
  pr_6, pr_7, qr_ForMetric, pr_9, pr_10, pr_11, pr_12 };

// The addresses the game measures: walk its IIterable<SecureDeviceAddress> (First 6; iterator Current 6,
// HasCurrent 7, MoveNext 8), keeping a reference to each.
static void qos_collect(QosData *q, Obj *iterable) {
  Obj *it = NULL;
  if (!iterable || FAILED(VCALL(iterable, 6, HRESULT (STDMETHODCALLTYPE *)(void *, Obj **))(iterable, &it)) || !it) return;
  BYTE has = 0;
  VCALL(it, 7, HRESULT (STDMETHODCALLTYPE *)(void *, BYTE *))(it, &has);
  while (has && q->n < MAX_QOS) {
    Obj *a = NULL;
    if (SUCCEEDED(VCALL(it, 6, HRESULT (STDMETHODCALLTYPE *)(void *, Obj **))(it, &a)) && a) q->addr[q->n++] = a;
    if (FAILED(VCALL(it, 8, HRESULT (STDMETHODCALLTYPE *)(void *, BYTE *))(it, &has))) break;
  }
  VCALL(it, 2, ULONG (STDMETHODCALLTYPE *)(void *))(it);
}

// ---- QualityOfService statics wrapper --------------------------------------------------------------
typedef struct { void **vtbl; Obj *real; LONG refs; } QosStatics;
#define QS(t) ((QosStatics *)(t))
static HRESULT STDMETHODCALLTYPE qs_QI(void *t, const GUID *iid, void **out) {
  if (IsEqualGUID(iid, &IID_IQualityOfServiceStatics) || IsEqualGUID(iid, &IID_IUnknown_) || IsEqualGUID(iid, &IID_IInspectable_)) {
    InterlockedIncrement(&QS(t)->refs); *out = t; return S_OK;
  }
  return VCALL(QS(t)->real, 0, HRESULT (STDMETHODCALLTYPE *)(void *, const GUID *, void **))(QS(t)->real, iid, out);
}
static ULONG STDMETHODCALLTYPE qs_AddRef(void *t) { return InterlockedIncrement(&QS(t)->refs); }
static ULONG STDMETHODCALLTYPE qs_Release(void *t) { return InterlockedDecrement(&QS(t)->refs); }
#define QS_FWD(slot) static HRESULT STDMETHODCALLTYPE qs_##slot(void *t, void *a, void *b, void *c, void *d, void *e, void *f) { \
  logf("QualityOfService statics slot %d (forwarded to Azimuth)", slot); \
  return VCALL(QS(t)->real, slot, HRESULT (STDMETHODCALLTYPE *)(void *, void *, void *, void *, void *, void *, void *))(QS(t)->real, a, b, c, d, e, f); }
QS_FWD(3) QS_FWD(4) QS_FWD(5) QS_FWD(7) QS_FWD(8) QS_FWD(9) QS_FWD(10) QS_FWD(11) QS_FWD(12) QS_FWD(13)
static HRESULT STDMETHODCALLTYPE qs_Measure(void *t, void *addresses, void *metrics, UINT32 timeoutMs, UINT32 probes, void **out) {
  (void)t;
  QosResult *r = heap(sizeof *r); r->vtbl = g_qrVtbl; r->q = heap(sizeof *r->q);
  qos_collect(r->q, addresses);
  logf("QualityOfService.MeasureQualityOfServiceAsync(%d addresses, metrics %p, timeout %u ms, %u probes) -> completed", r->q->n, metrics, timeoutMs, probes);
  TokenOp *o = HeapAlloc(GetProcessHeap(), 0, sizeof *o);
  o->vtbl = g_opVtbl; o->infoVtbl = g_infVtbl; o->refs = 1; o->handler = NULL;
  o->result = (Obj *)r; o->what = "QoS";
  *out = o;
  return S_OK;
}
static void *g_qsVtbl[] = { qs_QI, qs_AddRef, qs_Release, qs_3, qs_4, qs_5, qs_Measure, qs_7, qs_8, qs_9, qs_10, qs_11, qs_12, qs_13 };

// ---- SecureDeviceAddress statics ----------------------------------------------------------------------
// Azimuth's GetLocal (statics slot 9) answers an address whose base64 is empty; the Xbox Live library then
// fails to serialize the session member (secureDeviceAddress) and never writes the session. With
// [net] LocalAddress=<base64>, GetLocal answers FromBase64String (slot 11) of that, which Azimuth handles.
static const GUID IID_ISecureDeviceAddressStatics = { 0x02addb0f, 0x4880, 0x4b1e, { 0x98, 0xb8, 0xee, 0x63, 0x8a, 0xd8, 0x9b, 0x55 } };
static wchar_t g_localAddress[256];
#define SA_FWD(slot) static HRESULT STDMETHODCALLTYPE sa_##slot(void *t, void *a, void *b, void *c, void *d, void *e, void *f) { \
  return VCALL(QS(t)->real, slot, HRESULT (STDMETHODCALLTYPE *)(void *, void *, void *, void *, void *, void *, void *))(QS(t)->real, a, b, c, d, e, f); }
SA_FWD(3) SA_FWD(4) SA_FWD(5) SA_FWD(6) SA_FWD(7) SA_FWD(8) SA_FWD(10) SA_FWD(11) SA_FWD(12) SA_FWD(13)
static HRESULT STDMETHODCALLTYPE sa_QI(void *t, const GUID *iid, void **out) {
  if (IsEqualGUID(iid, &IID_ISecureDeviceAddressStatics) || IsEqualGUID(iid, &IID_IUnknown_) || IsEqualGUID(iid, &IID_IInspectable_)) {
    InterlockedIncrement(&QS(t)->refs); *out = t; return S_OK;
  }
  return VCALL(QS(t)->real, 0, HRESULT (STDMETHODCALLTYPE *)(void *, const GUID *, void **))(QS(t)->real, iid, out);
}
// An address object: Azimuth's, wrapped to answer GetBase64String (instance slot 10) with the base64 it was
// made from (Azimuth's answers an empty string); every other slot goes to Azimuth's object.
typedef struct { void **vtbl; Obj *real; LONG refs; wchar_t *b64; } SdaWrap;
#define SW(t) ((SdaWrap *)(t))
static HRESULT STDMETHODCALLTYPE sdw_QI(void *t, const GUID *iid, void **out) {
  HRESULT hr = VCALL(SW(t)->real, 0, HRESULT (STDMETHODCALLTYPE *)(void *, const GUID *, void **))(SW(t)->real, iid, out);
  if (SUCCEEDED(hr) && *out == SW(t)->real) *out = t;
  return hr;
}
static ULONG STDMETHODCALLTYPE sdw_AddRef(void *t) { return VCALL(SW(t)->real, 1, ULONG (STDMETHODCALLTYPE *)(void *))(SW(t)->real); }
static ULONG STDMETHODCALLTYPE sdw_Release(void *t) { return VCALL(SW(t)->real, 2, ULONG (STDMETHODCALLTYPE *)(void *))(SW(t)->real); }
#define SDW_FWD(slot) static HRESULT STDMETHODCALLTYPE sdw_##slot(void *t, void *a, void *b, void *c, void *d, void *e, void *f) { \
  return VCALL(SW(t)->real, slot, HRESULT (STDMETHODCALLTYPE *)(void *, void *, void *, void *, void *, void *, void *))(SW(t)->real, a, b, c, d, e, f); }
SDW_FWD(3) SDW_FWD(4) SDW_FWD(5) SDW_FWD(6) SDW_FWD(7) SDW_FWD(8) SDW_FWD(9) SDW_FWD(11) SDW_FWD(12) SDW_FWD(13) SDW_FWD(14) SDW_FWD(15)
static HRESULT STDMETHODCALLTYPE sdw_Base64(void *t, void **out) {
  return p_WindowsCreateString(SW(t)->b64, (UINT32)wcslen(SW(t)->b64), out);
}
static void *g_sdwVtbl[] = { sdw_QI, sdw_AddRef, sdw_Release, sdw_3, sdw_4, sdw_5, sdw_6, sdw_7, sdw_8, sdw_9, sdw_Base64,
  sdw_11, sdw_12, sdw_13, sdw_14, sdw_15 };

static HRESULT sda_from_base64(void *statics, const wchar_t *b64, void **out) {
  void *s = NULL; p_WindowsCreateString(b64, (UINT32)wcslen(b64), &s);
  HRESULT hr = VCALL(QS(statics)->real, 11, HRESULT (STDMETHODCALLTYPE *)(void *, void *, void **))(QS(statics)->real, s, out);
  if (SUCCEEDED(hr) && *out) {
    void *az = NULL;
    VCALL(*out, 10, HRESULT (STDMETHODCALLTYPE *)(void *, void **))(*out, &az);
    logf("SecureDeviceAddress(%ls): Azimuth's object %p answers base64 '%ls'", b64, *out, hs(az));
    SdaWrap *w = HeapAlloc(GetProcessHeap(), 0, sizeof *w);
    w->vtbl = g_sdwVtbl; w->real = *out; w->refs = 1; w->b64 = wdup(b64);
    *out = w;
  }
  return hr;
}
static HRESULT STDMETHODCALLTYPE sa_GetLocal(void *t, void **out) {
  HRESULT hr = sda_from_base64(t, g_localAddress, out);
  logf("SecureDeviceAddress.GetLocal -> %ls (0x%08lx)", g_localAddress, hr);
  return hr;
}
static HRESULT STDMETHODCALLTYPE sa_FromBase64(void *t, void *str, void **out) {
  return sda_from_base64(t, hs(str), out);
}
static void *g_saVtbl[] = { sa_QI, qs_AddRef, qs_Release, sa_3, sa_4, sa_5, sa_6, sa_7, sa_8, sa_GetLocal, sa_10, sa_FromBase64, sa_12, sa_13 };

static int wrap_address(const wchar_t *cls, GUID *iid, void **out) {
  if (!g_localAddress[0] || !*out || !IsEqualGUID(iid, &IID_ISecureDeviceAddressStatics) || wcscmp(cls, L"Windows.Xbox.Networking.SecureDeviceAddress")) return 0;
  QosStatics *w = HeapAlloc(GetProcessHeap(), 0, sizeof *w);
  w->vtbl = g_saVtbl; w->real = *out; w->refs = 1;
  *out = w;
  return 1;
}

// For the activation hook: wraps the QualityOfService statics when FakeQos is on; returns 1 if it did.
static int wrap_qos(const wchar_t *cls, GUID *iid, void **out) {
  if (wrap_address(cls, iid, out)) return 1;
  if (!g_fakeQos || !*out || !IsEqualGUID(iid, &IID_IQualityOfServiceStatics) || wcscmp(cls, L"Windows.Xbox.Networking.QualityOfService")) return 0;
  QosStatics *w = HeapAlloc(GetProcessHeap(), 0, sizeof *w);
  w->vtbl = g_qsVtbl; w->real = *out; w->refs = 1;
  *out = w;
  logf("  wrapped QualityOfService statics");
  return 1;
}
