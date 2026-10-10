import { afterEach, describe, expect, it, vi } from "vitest";
import * as fs from "node:fs/promises";
import { createHash } from "node:crypto";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { EtherMemoriesCore, openDurableEtherMemories, type DurableEtherMemories, type DreamPlan, type DreamSelector } from "../src/index.js";
import { openDurableEtherMemoriesInternal } from "../src/core/DurableEtherMemories.js";
import { windowsRecoverableDirectoryIO, assertWindowsRecoverablePath, type DirectoryIO } from "../src/persistence/directoryIO.js";
import { nodeWalIO } from "../src/persistence/walIO.js";
import { ProductionWalStore } from "../src/persistence/productionOperations.js";
import type { MutationId } from "../src/types/persistence.js";
import { bootstrap } from "./helpers/recovery.js";
import { value } from "./helpers/persistence.js";
import { seedDreamCore, DREAM_AS_OF } from "./helpers/dream-analysis.js";

const roots: string[] = [], runtimes: DurableEtherMemories[] = [];
const own = (runtime: DurableEtherMemories) => { runtimes.push(runtime); return runtime; };
const fixture = () => seedDreamCore([{ id: "a", content: "  Alpha recoverable source fact.  " }, { id: "b", content: "  Beta recoverable source fact.  " }],
  [{ id: "ab", source: "a", target: "b", relationship: "supports" }]);
const setup = async () => { const store = await bootstrap(JSON.parse(JSON.stringify(fixture().exportData()))); roots.push(store.parent); return store; };
const options = (directory: string, userId: string) => ({ directory, userId, durabilityGuarantee: "recoverable" as const, openMode: "existing" as const });
async function hashes(directory: string): Promise<Record<string, string>> {
  const result: Record<string, string> = {};
  const visit = async (parent: string): Promise<void> => {
    for (const entry of await fs.readdir(parent, { withFileTypes: true })) {
      const path = join(parent, entry.name);
      if (entry.isDirectory()) await visit(path);
      else result[path.slice(directory.length)] = createHash("sha256").update(await fs.readFile(path)).digest("hex");
    }
  };
  await visit(directory); return result;
}
afterEach(async () => {
  vi.restoreAllMocks();
  for (const runtime of runtimes.splice(0)) await runtime.close();
  for (const root of roots.splice(0)) await fs.rm(root, { recursive: true, force: true });
});

describe("T5 reconciliation with frozen T2/T3/T4", { timeout: 120000 }, () => {
  it("preserves strict/Core inspection and every Dream selector without durability I/O or identity leakage", async () => {
    const store = await setup(); let forbidden = false, forbiddenCalls = 0;
    const guard = <T extends (...args: any[]) => any>(operation: T): T => ((...args: Parameters<T>) => {
      if (forbidden) { forbiddenCalls++; throw Error("read-only durability I/O"); }
      return operation(...args);
    }) as T;
    const io: DirectoryIO = { ...windowsRecoverableDirectoryIO,
      kind: guard(windowsRecoverableDirectoryIO.kind), readBounded: guard(windowsRecoverableDirectoryIO.readBounded),
      readNames: guard(windowsRecoverableDirectoryIO.readNames), mkdirExclusive: guard(windowsRecoverableDirectoryIO.mkdirExclusive),
      writeExclusive: guard(windowsRecoverableDirectoryIO.writeExclusive), syncDirectory: guard(windowsRecoverableDirectoryIO.syncDirectory),
      activateFile: guard(windowsRecoverableDirectoryIO.activateFile), removeOwnedFile: guard(windowsRecoverableDirectoryIO.removeOwnedFile) };
    const files = { ...nodeWalIO, open: guard(nodeWalIO.open), stamp: guard(nodeWalIO.stamp) };
    const weak = own(value(await openDurableEtherMemoriesInternal(options(store.directory, store.snapshot.identity.userId), { io, files })));
    const strict = own(value(await openDurableEtherMemoriesInternal({ ...options(store.directory, store.snapshot.identity.userId), durabilityGuarantee: "strict" }, { io: store.io })));
    const snapshot = value(weak.exportData()), core = new EtherMemoriesCore({ userId: snapshot.identity.userId }); value(core.importData(snapshot));
    const before = await hashes(store.directory), tip = weak.tip;
    const selectors: DreamSelector[] = [{ kind: "ids", ids: ["a", "b"] }, { kind: "tags", tags: ["shared"] }, { kind: "query", query: "source" },
      { kind: "date-window", from: 10, to: 11 }, { kind: "all_active" }, { kind: "tags", tags: ["absent"] }];
    forbidden = true;
    try {
      expect(weak.inspectMemoryHealth({ asOf: DREAM_AS_OF })).toEqual(strict.inspectMemoryHealth({ asOf: DREAM_AS_OF }));
      expect(weak.inspectMemoryHealth({ asOf: DREAM_AS_OF })).toEqual(core.inspectMemoryHealth({ asOf: DREAM_AS_OF }));
      for (const id of ["a", "b"]) expect(weak.explainMemory(id, { asOf: DREAM_AS_OF })).toEqual(core.explainMemory(id, { asOf: DREAM_AS_OF }));
      for (const selector of selectors) {
        const plan = value(weak.previewDreamCycle(selector, { asOf: DREAM_AS_OF }));
        expect(plan).toEqual(value(strict.previewDreamCycle(selector, { asOf: DREAM_AS_OF })));
        expect(plan).toEqual(value(core.previewDreamCycle(selector, { asOf: DREAM_AS_OF })));
        const expected = core.runDreamCycle(plan);
        expect(weak.runDreamCycle(plan)).toEqual(expected); expect(strict.runDreamCycle(plan)).toEqual(expected);
        expect(weak.runDreamCycle(plan)).toEqual(expected);
        const returned = value(weak.runDreamCycle(plan));
        if (returned.proposals.length) { returned.proposals[0].content = "caller"; returned.proposals[0].evidence.keyFacts.push("caller"); }
        expect(weak.runDreamCycle(plan)).toEqual(expected);
        expect(JSON.stringify(expected)).not.toMatch(/durabilityGuarantee|process-recoverable|activation/);
      }
      expect(weak.exportData()).toEqual({ ok: true, value: snapshot }); expect(weak.tip).toEqual(tip);
      expect(weak.state).toBe("ready"); expect(forbiddenCalls).toBe(0);
    } finally { forbidden = false; }
    expect(await hashes(store.directory)).toEqual(before);
  });

  it("runs public recoverable inspection/Dream after fresh create, mutation, maintenance and reopen", async () => {
    const parent = await fs.mkdtemp(join(tmpdir(), "ether-t5-public-")); roots.push(parent);
    const open = { userId: "t5-public", directory: join(parent, "Café 測試 space"), durabilityGuarantee: "recoverable" as const };
    const runtime = own(value(await openDurableEtherMemories(open)));
    const note = value(await runtime.addMemory({ content: "  Public recoverable facts remain authoritative.  " }, "t5-public-stable"));
    value(await runtime.rotate()); value(await runtime.collectGarbage()); value(await runtime.runMaintenance()); value(await runtime.close());
    const reopened = own(value(await openDurableEtherMemories({ ...open, openMode: "existing" })));
    expect(value(await reopened.addMemory({ content: "  Public recoverable facts remain authoritative.  " }, "t5-public-stable"))).toEqual(note);
    const before = reopened.exportData(), tip = reopened.tip, bytes = await hashes(open.directory);
    const core = new EtherMemoriesCore({ userId: open.userId }); value(core.importData(value(before)));
    expect(reopened.explainMemory(note.id, { asOf: DREAM_AS_OF })).toEqual(core.explainMemory(note.id, { asOf: DREAM_AS_OF }));
    expect(reopened.inspectMemoryHealth({ asOf: DREAM_AS_OF })).toEqual(core.inspectMemoryHealth({ asOf: DREAM_AS_OF }));
    const plan = value(reopened.previewDreamCycle({ kind: "all_active" }, { asOf: DREAM_AS_OF }));
    expect(plan).toEqual(value(core.previewDreamCycle({ kind: "all_active" }, { asOf: DREAM_AS_OF })));
    expect(reopened.runDreamCycle(plan)).toEqual(core.runDreamCycle(plan));
    expect(reopened.exportData()).toEqual(before); expect(reopened.tip).toEqual(tip); expect(await hashes(open.directory)).toEqual(bytes);
  });

  it("captures both capability and operations once through commit, rotation, GC, maintenance and recovery", async () => {
    const store = await setup(); let capabilityReads = 0, replacedCalls = 0;
    const io = { ...windowsRecoverableDirectoryIO };
    Object.defineProperty(io, "guarantee", { enumerable: true, configurable: true, get: () => { capabilityReads++; return "recoverable"; } });
    const runtime = own(value(await openDurableEtherMemoriesInternal(options(store.directory, store.snapshot.identity.userId), { io })));
    expect(capabilityReads).toBe(1);
    Object.defineProperty(io, "guarantee", { enumerable: true, configurable: true, value: "strict" });
    for (const key of ["kind", "readBounded", "readNames", "mkdirExclusive", "writeExclusive", "syncDirectory", "activateFile", "removeOwnedFile"] as const) {
      (io as any)[key] = () => { replacedCalls++; throw Error("replacement backend must not be selected"); };
    }
    value(await runtime.addMemory({ content: "retained operation capability" }, "t5-retained-operations"));
    value(await runtime.rotate()); value(await runtime.collectGarbage()); value(await runtime.runMaintenance()); value(await runtime.recover());
    expect(value(runtime.exportData()).memoryNotes.some(note => note.content === "retained operation capability")).toBe(true);
    expect(replacedCalls).toBe(0); expect(capabilityReads).toBe(1);
  });

  it("keeps historical writer capability unknown while reporting a strict current retry invocation", async () => {
    const store = await setup();
    const weak = own(value(await openDurableEtherMemoriesInternal(options(store.directory, store.snapshot.identity.userId), { io: windowsRecoverableDirectoryIO })));
    const note = value(await weak.addMemory({ content: "historical writer unknown" }, "t5-historical-profile"));
    value(await weak.rotate()); const tip = value(weak.tip), snapshot = value(weak.exportData()); value(await weak.close());
    const before = await hashes(store.directory);
    const retry = value(await new ProductionWalStore(store.directory, store.io).commitMutationDetailed(tip, snapshot, "t5-historical-profile" as MutationId,
      { kind: "note.put", input: { content: "historical writer unknown" } }));
    expect(retry.receipt).toMatchObject({ status: "already-committed", durability: "confirmed" });
    expect(retry.receipt).not.toHaveProperty("acknowledgment");
    expect(await hashes(store.directory)).toEqual(before);
    const reopened = own(value(await openDurableEtherMemoriesInternal(options(store.directory, store.snapshot.identity.userId), { io: windowsRecoverableDirectoryIO })));
    expect(value(await reopened.addMemory({ content: "historical writer unknown" }, "t5-historical-profile"))).toEqual(note);
    expect(value(reopened.exportData()).memoryNotes.filter(n => n.content === "historical writer unknown")).toHaveLength(1);
    expect(await hashes(store.directory)).toEqual(before);
  });

  it.each(["closed", "recovery-required"] as const)("retains %s precedence for all four read surfaces before hostile inputs", async state => {
    const store = await setup(); let fail = false;
    const files = { ...nodeWalIO, open: async (path: string, create: boolean) => {
      const handle = await nodeWalIO.open(path, create);
      return { ...handle, sync: async () => { await handle.sync(); if (fail) { fail = false; throw Error("lost file-sync acknowledgement"); } } };
    } };
    const runtime = own(value(await openDurableEtherMemoriesInternal(options(store.directory, store.snapshot.identity.userId), { io: windowsRecoverableDirectoryIO, files })));
    if (state === "closed") value(await runtime.close());
    else { fail = true; expect((await runtime.updateMemory("b", { content: "ambiguous generation" }, "t5-authority-ambiguous")).ok).toBe(false); }
    expect(runtime.state).toBe(state);
    const trap = vi.fn(() => { throw Error("hostile input"); });
    const hostile = new Proxy({}, { get: trap, ownKeys: trap, getPrototypeOf: trap, getOwnPropertyDescriptor: trap });
    const clock = vi.spyOn(Date, "now").mockImplementation(() => { throw Error("authority precedes clock"); });
    const expected = { ok: false, error: { code: state === "closed" ? "CLOSED" : "RECOVERY_REQUIRED" } };
    expect(runtime.explainMemory("a", hostile)).toMatchObject(expected);
    expect(runtime.inspectMemoryHealth(hostile)).toMatchObject(expected);
    expect(runtime.previewDreamCycle(hostile as DreamSelector)).toMatchObject(expected);
    expect(runtime.runDreamCycle(hostile as DreamPlan)).toMatchObject(expected);
    expect(trap).not.toHaveBeenCalled(); expect(clock).not.toHaveBeenCalled(); vi.restoreAllMocks();
    if (state === "recovery-required") {
      value(await runtime.recover()); expect(runtime.inspectMemoryHealth({ asOf: DREAM_AS_OF }).ok).toBe(true);
      const plan = value(runtime.previewDreamCycle({ kind: "all_active" }, { asOf: DREAM_AS_OF })); expect(runtime.runDreamCycle(plan).ok).toBe(true);
    }
  });

  it("rejects the remaining namespace and DOS aliases without broadening ordinary Unicode path refusal", async () => {
    for (const path of ["\\\\server\\share\\store", "\\\\?\\C:\\store", "\\\\.\\C:\\store", "//server/share/store", "C:\\COM1", "C:\\LPT².txt", "C:\\store:stream", "C:\\store.\\child", "C:\\store \\child"]) {
      expect(() => assertWindowsRecoverablePath(path)).toThrow();
      if (process.platform === "win32") expect(await openDurableEtherMemories({ userId: "t5", directory: path, durabilityGuarantee: "recoverable" })).toMatchObject({ ok: false, error: { code: "DURABILITY_UNAVAILABLE" } });
    }
    expect(() => assertWindowsRecoverablePath("C:\\Ether Café 測試 space\\mémoire")).not.toThrow();
  });
});
