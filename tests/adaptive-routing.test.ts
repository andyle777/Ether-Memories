import { describe, expect, it, vi } from "vitest";
import * as api from "../src/index.js";

// Keep these tests executable against the pre-T2 root export. An absent export
// is recorded separately from a behavioral failure in the RED receipt.
type Adaptive = (request: unknown, deps?: unknown) => Promise<any>;
function adaptive(): Adaptive {
  const fn = (api as unknown as { summarizeAdaptive?: Adaptive }).summarizeAdaptive;
  expect(typeof fn, "T2 root export is not implemented").toBe("function");
  return fn!;
}
const note = { ref: "note:n1", kind: "note", id: "n1" };
const diary = { ref: "diary:d1", kind: "diary", id: "d1" };
const native = { operation: "semantic_summary", text: "abcdef", maxChars: 3 };
const hybrid = { operation: "semantic_summary", references: [note, diary], maxChars: 3 };
const noDependencies = new Proxy({}, { get() { throw Error("dependency read"); }, getOwnPropertyDescriptor() { throw Error("dependency descriptor"); } });
const invalid = expect.objectContaining({ ok: false, error: expect.objectContaining({ code: "INVALID_INPUT", message: "Invalid adaptive summary request." }) });
const trace = { providedToHost: [], excerptSources: [] };

describe("T2 adaptive contract", () => {
  it("T2-001/025/065: direct excerpt does not inspect dependencies", async () => {
    expect(await adaptive()({ operation: "local_excerpt", text: "abcdef", maxChars: 3 }, noDependencies)).toEqual({ ok: true, value: { operation: "local_excerpt", plannedRoute: "local-deterministic", route: "local-deterministic", kind: "local_excerpt", text: "abc", textOrigin: "local", degraded: false, evidence: trace, hostMayStillBeProcessing: false } });
  });
  it("T2-002/026: denied semantic request is unavailable without dependency access", async () => {
    expect(await adaptive()(native, noDependencies)).toEqual({ ok: true, value: { operation: "semantic_summary", plannedRoute: "unavailable", route: "unavailable", kind: "unavailable", reason: "disclosure_denied", evidence: trace, hostMayStillBeProcessing: false } });
  });
  it("T2-003/067: explicit degradation yields a local excerpt without host access", async () => {
    const result = await adaptive()({ ...native, allowDegradedFallback: true }, noDependencies);
    expect(result.value).toMatchObject({ plannedRoute: "local-deterministic", route: "local-deterministic", text: "abc", degraded: true, reason: "disclosure_denied", evidence: trace });
  });
  it("T2-004/006: missing host is unavailable when degradation is absent", async () => {
    const result = await adaptive()({ ...native, allowHostDisclosure: true });
    expect(result.value).toMatchObject({ route: "unavailable", reason: "capability_absent" });
    expect(result.value).not.toHaveProperty("text");
  });
  it("T2-005/022/066: native host receives one frozen minimal payload", async () => {
    let receiver: unknown; let payload: unknown;
    const summarize = vi.fn(async function(this: unknown, value: unknown) { receiver = this; payload = value; return "ok"; });
    const result = await adaptive()({ ...native, allowHostDisclosure: true }, { host: { summarize } });
    expect(result.value).toMatchObject({ plannedRoute: "native-assisted", route: "native-assisted", kind: "host_text", text: "ok", degraded: false, evidence: trace });
    expect(summarize).toHaveBeenCalledTimes(1); expect(receiver).toBeUndefined();
    expect(payload).toEqual({ text: "abcdef", maxChars: 3 }); expect(Object.isFrozen(payload)).toBe(true);
  });
  it.each([1, "true", new Boolean(true), null])("T2-007/008/050: malformed own permission %s is invalid", async permission => {
    expect(await adaptive()({ ...native, allowHostDisclosure: permission }, noDependencies)).toEqual(invalid);
  });
  it("T2-009/051: inherited permission is denied and accessors never execute", async () => {
    const inherited = Object.assign(Object.create({ allowHostDisclosure: true }), native);
    expect((await adaptive()(inherited, noDependencies)).value.reason).toBe("disclosure_denied");
    const getter = vi.fn(() => true);
    expect(await adaptive()(Object.defineProperty({ ...native }, "allowHostDisclosure", { get: getter }), noDependencies)).toEqual(invalid);
    expect(getter).not.toHaveBeenCalled();
  });
  it.each([{ ...native, operation: "other" }, { ...native, maxChars: 0 }, { ...native, maxChars: 12001 }, { ...native, maxChars: 1.5 }, { ...native, text: "" }, { ...native, text: "x".repeat(12001) }, { ...native, timeoutMs: 99 }, { ...native, timeoutMs: 30001 }])("T2-011/012: rejects invalid request %# before dependencies", async request => {
    expect(await adaptive()(request, noDependencies)).toEqual(invalid);
  });
  it.each([[{ status: "missing" }, "NOT_FOUND"], [{ status: "unsupported_schema" }, "UNSUPPORTED_SCHEMA"], [{ status: "failed" }, "STORAGE_ERROR"], [{ status: "found", content: 1 }, "STORAGE_ERROR"]])("T2-013/014/015/056: resolver result maps to %s", async (lookup, code) => {
    const host = vi.fn(); const result = await adaptive()({ ...hybrid, allowHostDisclosure: true }, { evidence: () => lookup, host: { summarizeEvidence: host } });
    expect(result).toMatchObject({ ok: false, error: { code } }); expect(host).not.toHaveBeenCalled();
  });
  it("T2-016/017/018/019/062: bounds and freezes evidence, tracking only passed records", async () => {
    let payload: any; const summarizeEvidence = vi.fn(async (value: unknown) => { payload = value; return "ok"; });
    const result = await adaptive()({ ...hybrid, allowHostDisclosure: true }, { evidence: (kind: string) => ({ status: "found", content: kind === "note" ? "x".repeat(12000) : "hidden" }), host: { summarizeEvidence } });
    expect(payload.evidence).toEqual([{ id: "n1", kind: "note", excerpt: "x".repeat(12000) }]);
    expect(Reflect.ownKeys(payload)).toEqual(["evidence", "maxChars"]);
    expect(Object.isFrozen(payload) && Object.isFrozen(payload.evidence) && Object.isFrozen(payload.evidence[0])).toBe(true);
    expect(result.value.evidence).toEqual({ providedToHost: [note], excerptSources: [] });
    expect(Object.isFrozen(result.value.evidence.providedToHost[0])).toBe(true);
  });
  it("T2-023/024/027/040/055/064: fallback traces handoff separately from contributing evidence", async () => {
    const callback = vi.fn(async () => { throw Error("secret"); });
    const result = await adaptive()({ ...hybrid, allowHostDisclosure: true, allowDegradedFallback: true }, { evidence: (kind: string) => ({ status: "found", content: kind === "note" ? "abc" : "def" }), host: { summarizeEvidence: callback } });
    expect(result.value).toMatchObject({ plannedRoute: "hybrid", route: "local-deterministic", text: "abc", reason: "host_failed", evidence: { providedToHost: [note, diary], excerptSources: [note] } });
    expect(callback).toHaveBeenCalledTimes(1);
  });
  it.each(["", 5, null, "long"])("T2-028/029/030: invalid host output %# degrades only with permission", async output => {
    const host = { summarize: async () => output };
    expect((await adaptive()({ ...native, allowHostDisclosure: true }, { host })).value).toMatchObject({ route: "unavailable", reason: "host_output_invalid" });
    expect((await adaptive()({ ...native, allowHostDisclosure: true, allowDegradedFallback: true }, { host })).value).toMatchObject({ route: "local-deterministic", text: "abc", reason: "host_output_invalid" });
  });
  it.each([[[{ ...note, ref: "note:wrong" }], "INVALID_INPUT"], [[note, note], "INVALID_INPUT"], [[{ ref: "node:x", kind: "node", id: "x" }], "UNSUPPORTED_SCHEMA"], [[{ ref: "edge:x", kind: "edge", id: "x" }], "UNSUPPORTED_SCHEMA"]] as const)("T2-052/053/054: invalid or unsupported references never inspect dependencies", async (references, code) => {
    const result = await adaptive()({ ...hybrid, references, allowHostDisclosure: true }, noDependencies);
    expect(result.ok).toBe(false); expect(result.error.code).toBe(code);
  });
  it("T2-061: mixed text and references are invalid before dependency reads", async () => {
    expect(await adaptive()({ ...hybrid, text: "question", allowHostDisclosure: true }, noDependencies)).toEqual(invalid);
  });
  it("T2-063: missing resolver cannot produce an invented fallback", async () => {
    const result = await adaptive()({ ...hybrid, allowDegradedFallback: true });
    expect(result.value).toMatchObject({ route: "unavailable", reason: "hybrid_unsupported", evidence: trace });
  });
  it.each([null, undefined, 0, "PRIVATE_SENTINEL", {}])("K11: a present non-callable resolver fails with a fixed storage error %#", async evidence => {
    const hostGetter = vi.fn(() => { throw Error("HOST_SECRET"); });
    const deps = Object.defineProperty({ evidence }, "host", { get: hostGetter });
    const result = await adaptive()({ ...hybrid, allowHostDisclosure: true, allowDegradedFallback: true }, deps);
    expect(result).toEqual({ ok: false, error: { code: "STORAGE_ERROR", message: "Evidence lookup failed.", details: undefined } });
    expect(hostGetter).not.toHaveBeenCalled();
    expect(JSON.stringify(result)).not.toContain("SECRET");
  });
  it("K11: absent and inaccessible resolver descriptors stay unavailable without executing getters", async () => {
    const getter = vi.fn(() => { throw Error("PRIVATE_SENTINEL"); });
    const accessor = Object.defineProperty({}, "evidence", { get: getter });
    const trapped = new Proxy({}, { getOwnPropertyDescriptor() { throw Error("PRIVATE_SENTINEL"); } });
    for (const deps of [{}, accessor, trapped]) {
      const result = await adaptive()({ ...hybrid, allowDegradedFallback: true }, deps);
      expect(result.value).toMatchObject({ route: "unavailable", reason: "hybrid_unsupported", evidence: trace });
      expect(JSON.stringify(result)).not.toContain("PRIVATE_SENTINEL");
    }
    expect(getter).not.toHaveBeenCalled();
  });
  it("T2-010/057: captures own descriptors once and only inspects the selected host capability", async () => {
    const requestReads: string[] = []; const hostReads: string[] = [];
    const input = new Proxy({ ...native, allowHostDisclosure: true }, { getOwnPropertyDescriptor(target, key) { requestReads.push(String(key)); return Reflect.getOwnPropertyDescriptor(target, key); }, get() { throw Error("get request"); } });
    const host = new Proxy({ summarize: async () => "ok" }, { getOwnPropertyDescriptor(target, key) { hostReads.push(String(key)); return Reflect.getOwnPropertyDescriptor(target, key); }, get() { throw Error("get host"); } });
    expect((await adaptive()(input, { host })).value.route).toBe("native-assisted");
    expect(requestReads.sort()).toEqual(["allowDegradedFallback", "allowHostDisclosure", "maxChars", "operation", "references", "text", "timeoutMs"]);
    expect(hostReads).toEqual(["summarize"]);
  });
  it("T2-016/052: validates every reference before resolver access", async () => {
    const resolver = vi.fn(() => ({ status: "found", content: "x" }));
    expect(await adaptive()({ ...hybrid, references: [note, { ...diary, ref: "bad" }], allowHostDisclosure: true }, { evidence: resolver })).toEqual(invalid);
    expect(resolver).not.toHaveBeenCalled();
    expect(await adaptive()({ ...hybrid, references: Array.from({ length: 33 }, (_, i) => ({ kind: "note", id: String(i), ref: `note:${i}` })) }, noDependencies)).toEqual(invalid);
  });
  it("T2-031/032/058/059: throw and reject are safe failures and fallback requires permission", async () => {
    for (const summarize of [() => { throw Error("SECRET"); }, () => Promise.reject(Error("SECRET"))]) {
      const absent = await adaptive()({ ...native, allowHostDisclosure: true }, { host: { summarize } });
      const allowed = await adaptive()({ ...native, allowHostDisclosure: true, allowDegradedFallback: true }, { host: { summarize } });
      expect(absent.value).toMatchObject({ route: "unavailable", reason: "host_failed" });
      expect(allowed.value).toMatchObject({ route: "local-deterministic", text: "abc", reason: "host_failed" });
      expect(JSON.stringify([absent, allowed])).not.toContain("SECRET");
    }
  });
  it("T2-042/067: disclosure denial permits local evidence only with explicit fallback", async () => {
    const resolver = vi.fn((kind: string) => ({ status: "found", content: kind === "note" ? "ab" : "cd" }));
    const hostGetter = vi.fn(() => { throw Error("host read"); });
    const deps = Object.defineProperty({ evidence: resolver }, "host", { get: hostGetter });
    const denied = await adaptive()(hybrid, deps); expect(denied.value.reason).toBe("disclosure_denied"); expect(resolver).not.toHaveBeenCalled();
    const local = await adaptive()({ ...hybrid, maxChars: 4, allowDegradedFallback: true }, deps);
    expect(local.value).toMatchObject({ text: "ab\nc", reason: "disclosure_denied", evidence: { providedToHost: [], excerptSources: [note, diary] } });
    expect(hostGetter).not.toHaveBeenCalled();
  });
  it("T2-056: resolver exceptions and descriptor traps never disclose their contents", async () => {
    const result = await adaptive()({ ...hybrid, allowHostDisclosure: true }, { evidence: () => { throw Error("SECRET"); }, host: noDependencies });
    expect(result).toMatchObject({ ok: false, error: { code: "STORAGE_ERROR", message: "Evidence lookup failed." } });
    expect(JSON.stringify(result)).not.toContain("SECRET");
  });
  it("T2-060: irrelevant request fields are ignored without inspection", async () => {
    const extra = Object.defineProperty({ ...native }, "policy", { get() { throw Error("should not read"); } });
    expect((await adaptive()(extra, noDependencies)).value.reason).toBe("disclosure_denied");
  });
  it("T2-010/057: hybrid only inspects summarizeEvidence and freezes detached payloads", async () => {
    const reads: string[] = []; const payloads: any[] = [];
    const host = new Proxy({ summarizeEvidence: async (p: unknown) => { payloads.push(p); return "ok"; } }, { getOwnPropertyDescriptor(t, k) { reads.push(String(k)); return Reflect.getOwnPropertyDescriptor(t, k); }, get() { throw Error("unexpected get"); } });
    const deps = { evidence: () => ({ status: "found", content: "abcdef" }), host };
    await adaptive()({ ...hybrid, references: [note], allowHostDisclosure: true }, deps);
    await adaptive()({ ...hybrid, references: [note], allowHostDisclosure: true }, deps);
    expect(reads).toEqual(["summarizeEvidence", "summarizeEvidence"]);
    expect(payloads[0]).not.toBe(payloads[1]); expect(payloads[0].evidence[0]).not.toBe(payloads[1].evidence[0]);
    expect(Reflect.set(payloads[0].evidence[0], "excerpt", "tampered")).toBe(false);
  });
  it("T2-012/050: throwing descriptors and accessors are invalid without invoking accessors", async () => {
    const getter = vi.fn(() => "abcdef");
    const request = Object.defineProperty({ ...native }, "text", { get: getter });
    expect(await adaptive()(request, noDependencies)).toEqual(invalid);
    expect(getter).not.toHaveBeenCalled();
    expect(await adaptive()(new Proxy(native, { getOwnPropertyDescriptor() { throw Error("secret"); } }), noDependencies)).toEqual(invalid);
  });
  it("T2-013: blank found content is missing, and malformed resolver responses disclose no details", async () => {
    const result = await adaptive()({ ...hybrid, allowHostDisclosure: true }, { evidence: () => ({ status: "found", content: " \n" }), host: noDependencies });
    expect(result).toMatchObject({ ok: false, error: { code: "NOT_FOUND", message: "Unknown evidence reference." } });
    const malformed = await adaptive()({ ...hybrid, allowHostDisclosure: true }, { evidence: () => new Proxy({}, { getOwnPropertyDescriptor() { throw Error("SECRET"); } }), host: noDependencies });
    expect(malformed).toMatchObject({ ok: false, error: { code: "STORAGE_ERROR", message: "Evidence lookup failed." } });
  });
  it("T2-043/044/045: authorized host is called once and deterministic outcomes repeat", async () => {
    const summarize = vi.fn(async () => "ok");
    const input = { ...native, allowHostDisclosure: true };
    const first = await adaptive()(input, { host: { summarize } });
    const second = await adaptive()(input, { host: { summarize } });
    expect(first).toEqual(second); expect(summarize).toHaveBeenCalledTimes(2);
  });
  it("T2-020: host-generated claims cannot add references to structured evidence", async () => {
    const result = await adaptive()({ ...hybrid, references: [note], maxChars: 40, allowHostDisclosure: true }, { evidence: () => ({ status: "found", content: "authorized" }), host: { summarizeEvidence: async () => "diary:forged says otherwise" } });
    expect(result.value.text).toBe("diary:forged says otherwise");
    expect(result.value.evidence).toEqual({ providedToHost: [note], excerptSources: [] });
  });
  it.each(["", "a".repeat(257), "a\u0000b", "a\u009fb"])("T2-052: invalid reference id %# fails before resolution", async id => {
    expect(await adaptive()({ ...hybrid, references: [{ kind: "note", id, ref: `note:${id}` }], allowHostDisclosure: true }, noDependencies)).toEqual(invalid);
  });
  it("T2-016: the separator consumes budget and over-budget references are still resolved", async () => {
    const lookup = vi.fn((kind: string) => ({ status: "found", content: kind === "note" ? "a".repeat(11998) : "bcdef" }));
    const host = vi.fn(async (_payload: { evidence: unknown[] }) => "ok");
    await adaptive()({ ...hybrid, allowHostDisclosure: true }, { evidence: lookup, host: { summarizeEvidence: host } });
    expect(lookup).toHaveBeenCalledTimes(2);
    expect(host.mock.calls[0][0].evidence).toEqual([{ id: "n1", kind: "note", excerpt: "a".repeat(11998) }, { id: "d1", kind: "diary", excerpt: "b" }]);
  });
  it("T2-056: an error after the budget is exhausted prevents disclosure", async () => {
    const host = vi.fn(async () => "ok");
    const result = await adaptive()({ ...hybrid, allowHostDisclosure: true }, { evidence: (kind: string) => kind === "note" ? { status: "found", content: "a".repeat(12000) } : { status: "failed" }, host: { summarizeEvidence: host } });
    expect(result).toMatchObject({ ok: false, error: { code: "STORAGE_ERROR" } }); expect(host).not.toHaveBeenCalled();
  });
  it("T2-028/029: exact-length host strings retain whitespace and control characters", async () => {
    const result = await adaptive()({ ...native, allowHostDisclosure: true }, { host: { summarize: async () => " \n\u0000" } });
    expect(result.value).toMatchObject({ route: "native-assisted", text: " \n\u0000" });
  });
  it("T2-058/059: malformed capability never runs its getter or grants degradation", async () => {
    const getter = vi.fn(() => { throw Error("SECRET"); });
    const host = Object.defineProperty({}, "summarize", { get: getter });
    const denied = await adaptive()({ ...native, allowHostDisclosure: true }, { host });
    expect(denied.value).toMatchObject({ route: "unavailable", reason: "capability_malformed" });
    expect(getter).not.toHaveBeenCalled();
  });
  it("T2-011/012: accepts both deadline and UTF-16 limits, including empty local input", async () => {
    expect((await adaptive()({ operation: "local_excerpt", text: "", maxChars: 1, timeoutMs: 100 })).value.text).toBe("");
    expect((await adaptive()({ operation: "local_excerpt", text: "😀x", maxChars: 1, timeoutMs: 30000 })).value.text).toBe("\ud83d");
    expect((await adaptive()({ operation: "local_excerpt", text: "x".repeat(12000), maxChars: 12000 })).value.text.length).toBe(12000);
  });
  it("T2-052: reference accessors are rejected without execution", async () => {
    const getter = vi.fn(() => "n1");
    const ref = Object.defineProperty({ ...note }, "id", { get: getter });
    expect(await adaptive()({ ...hybrid, references: [ref], allowHostDisclosure: true }, noDependencies)).toEqual(invalid);
    expect(getter).not.toHaveBeenCalled();
  });
  it("T2-016/055: no trailing separator or attribution when only separator could fit", async () => {
    const result = await adaptive()({ ...hybrid, maxChars: 4, allowDegradedFallback: true }, { evidence: (kind: string) => ({ status: "found", content: kind === "note" ? "abc" : "def" }) });
    expect(result.value).toMatchObject({ text: "abc", evidence: { providedToHost: [], excerptSources: [note] } });
  });
  it("T2-023/024: hybrid requires resolved nonempty evidence and a successful host result", async () => {
    const summarizeEvidence = vi.fn(async (_payload: unknown) => "ok");
    const deps = { evidence: () => ({ status: "found", content: "evidence" }), host: { summarizeEvidence } };
    const good = await adaptive()({ ...hybrid, references: [note], allowHostDisclosure: true }, deps);
    expect(good.value).toMatchObject({ route: "hybrid", kind: "host_text_with_evidence", text: "ok", evidence: { providedToHost: [note], excerptSources: [] } });
    expect(summarizeEvidence).toHaveBeenCalledTimes(1);
    expect(await adaptive()({ ...hybrid, references: [], allowHostDisclosure: true }, noDependencies)).toEqual(invalid);
    for (const outcome of [{ status: "missing" }, { status: "found", content: "  " }]) {
      const host = vi.fn(async () => "ok");
      const result = await adaptive()({ ...hybrid, references: [note], allowHostDisclosure: true }, { evidence: () => outcome, host: { summarizeEvidence: host } });
      expect(result).toMatchObject({ ok: false, error: { code: "NOT_FOUND" } }); expect(host).not.toHaveBeenCalled();
    }
    const withoutHost = await adaptive()({ ...hybrid, references: [note], allowHostDisclosure: true }, { evidence: deps.evidence });
    expect(withoutHost.value).toMatchObject({ plannedRoute: "hybrid", route: "unavailable", reason: "capability_absent", evidence: trace });
    const badHost = await adaptive()({ ...hybrid, references: [note], allowHostDisclosure: true }, { evidence: deps.evidence, host: { summarizeEvidence: async () => "" } });
    expect(badHost.value).toMatchObject({ plannedRoute: "hybrid", route: "unavailable", reason: "host_output_invalid", evidence: { providedToHost: [note], excerptSources: [] } });
  });
  it("T2-066: explicit consent enables both native text and selected note/diary host operations", async () => {
    const summarize = vi.fn(async () => "ok");
    const nativeResult = await adaptive()({ ...native, allowHostDisclosure: true }, { host: { summarize } });
    expect(nativeResult.value).toMatchObject({ route: "native-assisted", text: "ok" }); expect(summarize).toHaveBeenCalledTimes(1);
    const resolver = vi.fn((kind: string) => ({ status: "found", content: kind === "note" ? "authorized note" : "authorized diary" }));
    const summarizeEvidence = vi.fn(async (_payload: unknown) => "ok");
    const hybridResult = await adaptive()({ ...hybrid, allowHostDisclosure: true }, { evidence: resolver, host: { summarizeEvidence } });
    expect(hybridResult.value).toMatchObject({ route: "hybrid", text: "ok", evidence: { providedToHost: [note, diary], excerptSources: [] } });
    expect(resolver).toHaveBeenCalledTimes(2); expect(summarizeEvidence).toHaveBeenCalledTimes(1);
    expect(summarizeEvidence.mock.calls[0][0]).toEqual({ evidence: [{ id: "n1", kind: "note", excerpt: "authorized note" }, { id: "d1", kind: "diary", excerpt: "authorized diary" }], maxChars: 3 });
  });
  it.each([1, "true", new Boolean(true), null])("T2-050: malformed fallback permission cannot authorize degradation %#", async permission => {
    expect(await adaptive()({ ...native, allowDegradedFallback: permission }, noDependencies)).toEqual(invalid);
  });
  it("T2-051: inherited fallback permission does not enable degradation", async () => {
    const request = Object.assign(Object.create({ allowDegradedFallback: true }), native);
    expect((await adaptive()(request, noDependencies)).value).toMatchObject({ route: "unavailable", reason: "disclosure_denied" });
  });
  it("T2-052: reference descriptor values are captured once without running getters", async () => {
    const seen: string[] = [];
    const reference = new Proxy(note, { getOwnPropertyDescriptor(target, key) { seen.push(String(key)); return Reflect.getOwnPropertyDescriptor(target, key); }, get() { throw Error("unexpected get"); } });
    const result = await adaptive()({ ...hybrid, references: [reference], allowDegradedFallback: true }, { evidence: () => ({ status: "found", content: "abc" }) });
    expect(result.value).toMatchObject({ text: "abc", evidence: { excerptSources: [note], providedToHost: [] } });
    expect(seen.sort()).toEqual(["id", "kind", "ref"]);
  });
  it("T2-062: both returned traces and their detached citation entries are immutable", async () => {
    const result = await adaptive()({ ...hybrid, references: [note], allowHostDisclosure: true, allowDegradedFallback: true }, { evidence: () => ({ status: "found", content: "abc" }), host: { summarizeEvidence: async () => { throw Error("failed"); } } });
    const { providedToHost, excerptSources } = result.value.evidence;
    expect(Object.isFrozen(providedToHost)).toBe(true); expect(Object.isFrozen(excerptSources)).toBe(true);
    expect(Object.isFrozen(providedToHost[0])).toBe(true); expect(Object.isFrozen(excerptSources[0])).toBe(true);
    expect(providedToHost[0]).not.toBe(note); expect(Reflect.set(providedToHost[0], "id", "forged")).toBe(false);
    expect(Reflect.set(excerptSources, "0", diary)).toBe(false);
  });
  it.each([
    { ...native, maxChars: NaN }, { ...native, maxChars: Infinity }, { ...native, maxChars: "3" },
    { ...native, text: new String("text") }, { ...native, text: 5 }, { ...native, timeoutMs: NaN },
    { ...native, timeoutMs: Infinity }, { ...native, timeoutMs: 100.5 }, { ...native, timeoutMs: "100" },
    { ...native, references: [] }, { operation: "semantic_summary", references: [], maxChars: 3 },
    { operation: "local_excerpt", maxChars: 3 }, { ...native, allowDegradedFallback: undefined }
  ])("T2-011/012: rejects malformed numeric, text and request shapes %#", async input => {
    expect(await adaptive()(input, noDependencies)).toEqual(invalid);
  });
  it.each([
    [{ status: "missing" }, "NOT_FOUND", "Unknown evidence reference."],
    [{ status: "found", content: "  " }, "NOT_FOUND", "Unknown evidence reference."],
    [{ status: "unsupported_schema" }, "UNSUPPORTED_SCHEMA", "Unsupported evidence record."],
    [{ status: "failed" }, "STORAGE_ERROR", "Evidence lookup failed."],
    [{ status: "found", content: 8 }, "STORAGE_ERROR", "Evidence lookup failed."],
    [{ status: "unknown", secret: "SENTINEL" }, "STORAGE_ERROR", "Evidence lookup failed."]
  ])("T2-013/014/015/056: lookup errors use fixed non-disclosing messages %#", async (lookup, code, message) => {
    const host = vi.fn();
    const result = await adaptive()({ ...hybrid, references: [note], allowHostDisclosure: true }, { evidence: () => lookup, host: { summarizeEvidence: host } });
    expect(result).toMatchObject({ ok: false, error: { code, message } });
    expect(JSON.stringify(result)).not.toContain("SENTINEL"); expect(host).not.toHaveBeenCalled();
  });
});
