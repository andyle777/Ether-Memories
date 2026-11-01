import { afterEach, describe, expect, it, vi } from "vitest";
import * as api from "../src/index.js";

type Adaptive = (request: unknown, deps?: unknown) => Promise<any>;
function adaptive(): Adaptive {
  const fn = (api as unknown as { summarizeAdaptive?: Adaptive }).summarizeAdaptive;
  expect(typeof fn, "T2 root export is not implemented").toBe("function");
  return fn!;
}
const request = { operation: "semantic_summary", text: "abcdef", maxChars: 3, allowHostDisclosure: true, allowDegradedFallback: true };
afterEach(() => vi.useRealTimers());

describe("T2 host deadline", () => {
  it("T2-021/033/034: defaults to 3000ms and reports a still-running host", async () => {
    vi.useFakeTimers();
    const summarize = vi.fn(() => new Promise<string>(() => {}));
    const result = adaptive()(request, { host: { summarize } });
    expect(vi.getTimerCount()).toBe(1);
    let settled = false; void result.then(() => { settled = true; });
    await vi.advanceTimersByTimeAsync(2999); expect(settled).toBe(false);
    await vi.advanceTimersByTimeAsync(1);
    expect((await result).value).toMatchObject({ route: "local-deterministic", text: "abc", reason: "timeout", hostMayStillBeProcessing: true });
    expect(summarize).toHaveBeenCalledTimes(1); expect(vi.getTimerCount()).toBe(0);
  });
  it("T2-035/036: discards a late rejection without changing the settled result", async () => {
    vi.useFakeTimers(); let reject!: (error: Error) => void;
    const result = adaptive()({ ...request, timeoutMs: 100 }, { host: { summarize: () => new Promise<string>((_, r) => { reject = r; }) } });
    await vi.advanceTimersByTimeAsync(100);
    const value = await result; reject(Error("private failure")); await Promise.resolve(); await Promise.resolve();
    expect(value.value).toMatchObject({ route: "local-deterministic", reason: "timeout" }); expect(vi.getTimerCount()).toBe(0);
  });
  it("T2-037/038/041: clears timers for repeated synchronous values and thenables", async () => {
    vi.useFakeTimers();
    for (let i = 0; i < 100; i++) {
      const result = await adaptive()(request, { host: { summarize: () => ({ then: (resolve: (x: string) => void) => resolve("ok") }) } });
      expect(result.value).toMatchObject({ route: "native-assisted", text: "ok", hostMayStillBeProcessing: false });
      expect(vi.getTimerCount()).toBe(0);
    }
  });
  it("T2-039/040/062/064: timeout retains the handoff and attributes only excerpt contributions", async () => {
    vi.useFakeTimers();
    const n = { ref: "note:n", kind: "note", id: "n" }, d = { ref: "diary:d", kind: "diary", id: "d" };
    const promise = adaptive()({ operation: "semantic_summary", references: [n, d], maxChars: 2, allowHostDisclosure: true, allowDegradedFallback: true, timeoutMs: 100 }, { evidence: (kind: string) => ({ status: "found", content: kind === "note" ? "abcd" : "efgh" }), host: { summarizeEvidence: () => new Promise(() => {}) } });
    await vi.advanceTimersByTimeAsync(100);
    expect((await promise).value).toMatchObject({ plannedRoute: "hybrid", route: "local-deterministic", text: "ab", reason: "timeout", hostMayStillBeProcessing: true, evidence: { providedToHost: [n, d], excerptSources: [n] } });
    expect(vi.getTimerCount()).toBe(0);
  });
  it("T2-036: a late resolution cannot replace a completed timeout", async () => {
    vi.useFakeTimers(); let release!: (value: string) => void;
    const result = adaptive()({ ...request, timeoutMs: 100 }, { host: { summarize: () => new Promise<string>(resolve => { release = resolve; }) } });
    await vi.advanceTimersByTimeAsync(100); const completed = await result;
    release("ok"); await Promise.resolve(); await Promise.resolve();
    expect(completed.value).toMatchObject({ route: "local-deterministic", text: "abc", reason: "timeout" });
    expect(vi.getTimerCount()).toBe(0);
  });
  it("T2-037: a throwing then accessor is a contained host failure", async () => {
    const thenable = Object.defineProperty({}, "then", { get() { throw Error("SECRET"); } });
    const result = await adaptive()(request, { host: { summarize: () => thenable } });
    expect(result.value).toMatchObject({ route: "local-deterministic", text: "abc", reason: "host_failed" });
    expect(JSON.stringify(result)).not.toContain("SECRET");
  });
  it("T2-033/034: host results before the deadline win and later results time out", async () => {
    vi.useFakeTimers();
    const host = (delay: number) => ({ summarize: () => new Promise<string>(resolve => setTimeout(() => resolve("ok"), delay)) });
    const early = adaptive()(request, { host: host(2999) });
    await vi.advanceTimersByTimeAsync(2999); expect((await early).value).toMatchObject({ route: "native-assisted", text: "ok", hostMayStillBeProcessing: false });
    const late = adaptive()(request, { host: host(3001) });
    await vi.advanceTimersByTimeAsync(3000); expect((await late).value).toMatchObject({ route: "local-deterministic", reason: "timeout", hostMayStillBeProcessing: true });
    await vi.advanceTimersByTimeAsync(1); expect(vi.getTimerCount()).toBe(0);
  });
  it("T2-038: rejecting thenables are contained and clear the host timer", async () => {
    vi.useFakeTimers();
    const thenable = { then: (_resolve: unknown, reject: (reason: Error) => void) => reject(Error("SECRET")) };
    const result = await adaptive()(request, { host: { summarize: () => thenable } });
    expect(result.value).toMatchObject({ route: "local-deterministic", reason: "host_failed" });
    expect(JSON.stringify(result)).not.toContain("SECRET"); expect(vi.getTimerCount()).toBe(0);
  });
  it("T2-041: repeated timeout, rejection and invalid-output paths leave no host timers", async () => {
    vi.useFakeTimers();
    for (let i = 0; i < 100; i++) {
      const outcome = i % 3;
      const summarize = outcome === 0 ? () => new Promise(() => {}) : outcome === 1 ? () => Promise.reject(Error("private")) : () => Promise.resolve("");
      const result = adaptive()({ ...request, timeoutMs: 100 }, { host: { summarize } });
      if (outcome === 0) await vi.advanceTimersByTimeAsync(100);
      expect((await result).value.reason).toBe(outcome === 0 ? "timeout" : outcome === 1 ? "host_failed" : "host_output_invalid");
      expect(vi.getTimerCount()).toBe(0);
    }
  });
});
