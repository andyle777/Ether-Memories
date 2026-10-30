import { describe, expect, it, vi } from "vitest";
import * as api from "../src/index.js";

type Request = { text: string; maxChars: number; allowHostDisclosure: boolean };
type Summary = { text: string; source: "host" | "local" };
type Capability = { summarize?: (input: Readonly<{ text: string; maxChars: number }>) => Promise<string> };
type Outcome = { ok: true; value: Summary } | { ok: false; error: { code: string; message: string; details?: unknown } };
type Helper = (request: Request, capabilities?: Capability) => Promise<Outcome>;

// Root lookup keeps the baseline test executable before the export exists.
function helper(): Helper {
  const fn = (api as unknown as { summarizeWithHost?: Helper }).summarizeWithHost;
  expect(typeof fn, "T1 root export is required").toBe("function");
  return fn!;
}
const request = (overrides: Partial<Request> = {}): Request => ({ text: "abcdef", maxChars: 3, allowHostDisclosure: false, ...overrides });
const local = { ok: true, value: { text: "abc", source: "local" } };
const invalid = expect.objectContaining({ ok: false, error: expect.objectContaining({ code: "INVALID_INPUT" }) });

describe("standalone host summary", () => {
  it("returns the deterministic local excerpt and never inspects capabilities when denied", async () => {
    const traps = { get: 0, getOwnPropertyDescriptor: 0, has: 0, getPrototypeOf: 0, ownKeys: 0 };
    const probe = new Proxy({}, {
      get() { traps.get++; throw Error("get"); }, getOwnPropertyDescriptor() { traps.getOwnPropertyDescriptor++; throw Error("descriptor"); },
      has() { traps.has++; throw Error("has"); }, getPrototypeOf() { traps.getPrototypeOf++; throw Error("prototype"); },
      ownKeys() { traps.ownKeys++; throw Error("keys"); }
    });
    expect(await helper()(request(), probe)).toEqual(local);
    expect(traps).toEqual({ get: 0, getOwnPropertyDescriptor: 0, has: 0, getPrototypeOf: 0, ownKeys: 0 });
    expect(await helper()(request(), probe)).toEqual(local);
  });
  it("invokes once with only a frozen captured payload and undefined thisArg for strict callbacks", async () => {
    let receiver: unknown = "unset";
    let payload: unknown;
    const callback = vi.fn(async function (this: unknown, arg: Readonly<{ text: string; maxChars: number }>) {
      receiver = this; payload = arg;
      expect(Object.isFrozen(arg)).toBe(true);
      expect(Reflect.set(arg, "text", "tampered")).toBe(false);
      return "ok";
    });
    const input = { ...request({ allowHostDisclosure: true }), secret: "SENTINEL" };
    expect(await helper()(input, { summarize: callback })).toEqual({ ok: true, value: { text: "ok", source: "host" } });
    expect(callback).toHaveBeenCalledTimes(1);
    expect(receiver).toBeUndefined();
    expect(payload).toEqual({ text: "abcdef", maxChars: 3 });
    expect(Reflect.ownKeys(payload as object)).toEqual(["text", "maxChars"]);
  });
  it("passes undefined as thisArg while respecting sloppy function receiver substitution", async () => {
    const callback = Function("return function(request) { return Promise.resolve(this === globalThis ? 'yes' : 'no'); }")() as Capability["summarize"];
    expect(await helper()(request({ allowHostDisclosure: true }), { summarize: callback })).toEqual({ ok: true, value: { text: "yes", source: "host" } });
  });
  it("provides a fresh frozen payload for each authorized invocation", async () => {
    const payloads: object[] = [];
    const summarize = async (payload: Readonly<{ text: string; maxChars: number }>) => { payloads.push(payload); return "ok"; };
    await helper()(request({ allowHostDisclosure: true }), { summarize });
    await helper()(request({ allowHostDisclosure: true }), { summarize });
    expect(payloads).toHaveLength(2);
    expect(payloads[0]).not.toBe(payloads[1]);
    expect(payloads.every(Object.isFrozen)).toBe(true);
  });
  it("captures each request descriptor and the capability descriptor exactly once", async () => {
    const observed: string[] = [];
    const input = new Proxy(request({ allowHostDisclosure: true }), { getOwnPropertyDescriptor(target, key) { observed.push(String(key)); return Reflect.getOwnPropertyDescriptor(target, key); }, get() { throw Error("unexpected get"); }, ownKeys() { throw Error("unexpected enumeration"); } });
    const seen: string[] = [];
    const caps = new Proxy({ summarize: async () => "ok" }, { getOwnPropertyDescriptor(target, key) { seen.push(String(key)); return Reflect.getOwnPropertyDescriptor(target, key); }, get() { throw Error("unexpected get"); }, ownKeys() { throw Error("unexpected enumeration"); } });
    expect(await helper()(input, caps)).toEqual({ ok: true, value: { text: "ok", source: "host" } });
    expect(observed.sort()).toEqual(["allowHostDisclosure", "maxChars", "text"]);
    expect(seen).toEqual(["summarize"]);
  });
  it.each([null, undefined, 1, "request", {}, { text: "x", maxChars: 1 }, { text: 1, maxChars: 1, allowHostDisclosure: true }, { text: new String("x"), maxChars: 1, allowHostDisclosure: true }, { text: "x", maxChars: 0, allowHostDisclosure: true }, { text: "x", maxChars: 12001, allowHostDisclosure: true }, { text: "x", maxChars: 1.5, allowHostDisclosure: true }, { text: "x", maxChars: NaN, allowHostDisclosure: true }, { text: "x", maxChars: Infinity, allowHostDisclosure: true }, { text: "x", maxChars: "5", allowHostDisclosure: true }, { text: "x", maxChars: 1, allowHostDisclosure: 1 }, { text: "x", maxChars: 1, allowHostDisclosure: "true" }, { text: "x", maxChars: 1, allowHostDisclosure: new Boolean(true) }, { text: "x".repeat(12001), maxChars: 1, allowHostDisclosure: true }])("rejects invalid request %# before capability inspection", async input => {
    const caps = new Proxy({}, { getOwnPropertyDescriptor() { throw Error("SECRET"); } });
    expect(await helper()(input as Request, caps)).toEqual(invalid);
  });
  it("rejects inherited, accessor and throwing request descriptors without running getters", async () => {
    const getter = vi.fn(() => "SECRET");
    const accessor = Object.defineProperty(request(), "text", { get: getter });
    const inherited = Object.assign(Object.create({ text: "secret" }), { maxChars: 1, allowHostDisclosure: false });
    const trapped = new Proxy(request(), { getOwnPropertyDescriptor() { throw Error("SECRET"); } });
    for (const input of [accessor, inherited, trapped]) expect(await helper()(input)).toEqual(invalid);
    expect(getter).not.toHaveBeenCalled();
  });
  it("rejects inherited and accessor permission and inherited maxChars without invoking accessors", async () => {
    const getter = vi.fn(() => true);
    const permissionAccessor = Object.defineProperty({ text: "SECRET", maxChars: 3 }, "allowHostDisclosure", { get: getter });
    const permissionInherited = Object.assign(Object.create({ allowHostDisclosure: true }), { text: "SECRET", maxChars: 3 });
    const maxInherited = Object.assign(Object.create({ maxChars: 3 }), { text: "SECRET", allowHostDisclosure: true });
    for (const input of [permissionAccessor, permissionInherited, maxInherited]) expect(await helper()(input)).toEqual(invalid);
    expect(getter).not.toHaveBeenCalled();
  });
  it("returns a fixed non-disclosing error for different malformed inputs and exceptions", async () => {
    const trapped = new Proxy(request(), { getOwnPropertyDescriptor() { throw Error("SECRET trap"); } });
    const a = await helper()(trapped);
    const b = await helper()({ text: "SECRET input", maxChars: 0, allowHostDisclosure: true });
    expect(a).toEqual(invalid); expect(b).toEqual(invalid);
    if (a.ok || b.ok) throw Error("expected errors");
    expect(a.error.message).toBe(b.error.message);
    expect(a.error.details).toBeUndefined(); expect(b.error.details).toBeUndefined();
    expect(JSON.stringify([a, b])).not.toContain("SECRET");
  });
  it("accepts an array with the required own data properties", async () => {
    const input = Object.assign([], request());
    expect(await helper()(input as unknown as Request)).toEqual(local);
  });
  it("accepts exact input limit, empty input and slices UTF-16 units", async () => {
    expect(await helper()(request({ text: "x".repeat(12000), maxChars: 12000 }))).toEqual({ ok: true, value: { text: "x".repeat(12000), source: "local" } });
    expect(await helper()(request({ text: "" }))).toEqual({ ok: true, value: { text: "", source: "local" } });
    expect(await helper()(request({ text: "😀z", maxChars: 1 }))).toEqual({ ok: true, value: { text: "\ud83d", source: "local" } });
  });
  it("treats malformed, inherited, accessor and throwing capabilities as unavailable", async () => {
    const getter = vi.fn(() => { throw Error("SECRET"); });
    const accessor = Object.defineProperty({}, "summarize", { get: getter });
    const inherited = Object.create({ summarize: async () => "bad" });
    const trapped = new Proxy({}, { getOwnPropertyDescriptor() { throw Error("SECRET"); } });
    for (const caps of [undefined, null, 2, "prim", {}, { summarize: 42 }, { summarize: "str" }, { summarize: null }, { summarize: {} }, accessor, inherited, trapped]) {
      expect(await helper()(request({ allowHostDisclosure: true }), caps as Capability)).toEqual(local);
    }
    expect(getter).not.toHaveBeenCalled();
  });
  it.each(["", 42, null, {}, "toolong"])("falls back for unusable callback result %#", async output => {
    const summarize = vi.fn(async () => output);
    expect(await helper()(request({ allowHostDisclosure: true }), { summarize } as unknown as Capability)).toEqual(local);
    expect(summarize).toHaveBeenCalledTimes(1);
  });
  it("falls back on thrown or rejected errors without exposing provider details", async () => {
    for (const summarize of [vi.fn(() => { throw Error("SECRET"); }), vi.fn(async () => { throw Error("SECRET"); })]) {
      const result = await helper()(request({ allowHostDisclosure: true }), { summarize } as Capability);
      expect(result).toEqual(local);
      expect(summarize).toHaveBeenCalledTimes(1);
      expect(JSON.stringify(result)).not.toContain("SECRET");
    }
  });
  it("uses captured text for fallback after attempted mutation", async () => {
    const input = request({ allowHostDisclosure: true });
    const summarize = async (payload: Readonly<{ text: string; maxChars: number }>) => {
      input.text = "changed"; Reflect.set(payload, "text", "changed"); return "";
    };
    expect(await helper()(input, { summarize })).toEqual(local);
  });
  it("accepts synchronous and whitespace host strings without rewriting", async () => {
    const summarize = (() => "  ") as unknown as NonNullable<Capability["summarize"]>;
    expect(await helper()(request({ allowHostDisclosure: true }), { summarize })).toEqual({ ok: true, value: { text: "  ", source: "host" } });
  });
  it("preserves exact maximum-length output including whitespace and control characters", async () => {
    expect(await helper()(request({ allowHostDisclosure: true }), { summarize: async () => " \n\t" })).toEqual({ ok: true, value: { text: " \n\t", source: "host" } });
  });
  it("accepts resolving thenables and falls back for rejecting or throwing then getters", async () => {
    const cases: [unknown, unknown][] = [
      [{ then: (resolve: (x: string) => void) => resolve("ok") }, { ok: true, value: { text: "ok", source: "host" } }],
      [{ then: (_resolve: unknown, reject: (x: Error) => void) => reject(Error("SECRET")) }, local],
      [Object.defineProperty({}, "then", { get() { throw Error("SECRET"); } }), local]
    ];
    for (const [output, expected] of cases) {
      const summarize = (() => output) as unknown as NonNullable<Capability["summarize"]>;
      expect(await helper()(request({ allowHostDisclosure: true }), { summarize })).toEqual(expected);
    }
  });
  it("ignores unrelated capability fields and symbol keys without reading or enumerating them", async () => {
    const symbol = Symbol("SECRET");
    const target = { summarize: async () => "ok", rank: "SECRET", then: "SECRET", [symbol]: "SECRET" };
    const observed: PropertyKey[] = [];
    const caps = new Proxy(target, { getOwnPropertyDescriptor(t, key) { observed.push(key); return Reflect.getOwnPropertyDescriptor(t, key); }, get() { throw Error("unexpected get"); }, ownKeys() { throw Error("unexpected enumeration"); }, has() { throw Error("unexpected has"); } });
    expect(await helper()(request({ allowHostDisclosure: true }), caps)).toEqual({ ok: true, value: { text: "ok", source: "host" } });
    expect(observed).toEqual(["summarize"]);
  });
  it("returns the captured excerpt after strict and sloppy provider mutation attempts", async () => {
    const strict = async (payload: Readonly<{ text: string; maxChars: number }>) => { (payload as { text: string }).text = "mutated"; return "bad"; };
    const sloppy = Function("return function(payload) { payload.text = 'mutated'; return ''; }")() as NonNullable<Capability["summarize"]>;
    for (const summarize of [strict, sloppy]) expect(await helper()(request({ allowHostDisclosure: true }), { summarize })).toEqual(local);
  });
  it("does not settle while a provider is pending and completes after the provider resolves", async () => {
    let release!: (value: string) => void;
    const provider = new Promise<string>(resolve => { release = resolve; });
    let settled = false;
    const pending = helper()(request({ allowHostDisclosure: true }), { summarize: () => provider }).then(value => { settled = true; return value; });
    try {
      await new Promise(resolve => setTimeout(resolve, 250));
      expect(settled).toBe(false);
    } finally { release("ok"); }
    expect(await pending).toEqual({ ok: true, value: { text: "ok", source: "host" } });
  });
});
