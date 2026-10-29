import { afterEach, describe, expect, it } from "vitest";
import * as fs from "node:fs/promises";
import { createHash } from "node:crypto";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { EtherMemoriesCore } from "../src/core/EtherMemories.js";
import { openDurableEtherMemories, openDurableEtherMemoriesInternal } from "../src/core/DurableEtherMemories.js";
import { nodeWalIO, type WalIO } from "../src/persistence/walIO.js";
import { value } from "./helpers/persistence.js";
import type { MemoryStatus } from "../src/types/index.js";
import { prepareCoreMutation, intentDigest, matchesCommittedIntent } from "../src/persistence/mutationPreparation.js";

const cleanup: string[] = [];
afterEach(async () => { for (const path of cleanup.splice(0)) await fs.rm(path, { recursive: true, force: true }); });
const provenance = { kind: "inferred" as const, lastEditKind: "system" as const, detail: "proposal" };
async function open() {
  const parent = await fs.mkdtemp(join(tmpdir(), "ether-promotion-contract-")); cleanup.push(parent);
  const options = { userId: "promotion-contract", directory: join(parent, "store"),
    durabilityGuarantee: process.platform === "win32" ? "recoverable" as const : "strict" as const };
  return { options, runtime: value(await openDurableEtherMemories(options)) };
}
async function inventory(directory: string): Promise<Record<string, string>> {
  const result: Record<string, string> = {};
  for (const entry of await fs.readdir(directory, { withFileTypes: true })) {
    const path = join(directory, entry.name);
    if (entry.isDirectory()) for (const [key, hash] of Object.entries(await inventory(path))) result[`${entry.name}/${key}`] = hash;
    else result[entry.name] = createHash("sha256").update(await fs.readFile(path)).digest("hex");
  }
  return result;
}

describe("T0 fresh promotion contract", { timeout: 60_000 }, () => {
  for (const status of ["active", "archived", "rejected"] as MemoryStatus[]) {
    it(`Core rejects fresh ${status} promotion without changing its snapshot`, () => {
      const core = new EtherMemoriesCore({ userId: "core" });
      const note = value(core.addMemory({ content: "proposal", status, provenance }));
      const before = core.exportData();
      expect(core.promoteCandidate(note.id)).toMatchObject({ ok: false, error: { code: "CONFLICT" } });
      expect(core.exportData()).toEqual(before);
    });
    it(`Durable rejects fresh ${status} promotion without persistent effects`, async () => {
      const { runtime, options } = await open();
      try {
        const note = value(await runtime.addMemory({ content: "proposal", status, provenance }, "add"));
        const before = value(runtime.exportData()), tip = value(runtime.tip), files = await inventory(options.directory);
        expect(await runtime.promoteCandidate(note.id, "fresh")).toMatchObject({ ok: false, error: { code: "CONFLICT" } });
        expect(value(runtime.exportData())).toEqual(before); expect(value(runtime.tip)).toEqual(tip);
        expect(await inventory(options.directory)).toEqual(files);
      } finally { value(await runtime.close()); }
    });
  }
  it("missing target is NOT_FOUND and does not write", async () => {
    const core = new EtherMemoriesCore({ userId: "core" });
    expect(core.promoteCandidate("missing")).toMatchObject({ ok: false, error: { code: "NOT_FOUND" } });
    const { runtime, options } = await open();
    try {
      const before = await inventory(options.directory);
      expect(await runtime.promoteCandidate("missing", "missing")).toMatchObject({ ok: false, error: { code: "NOT_FOUND" } });
      expect(await inventory(options.directory)).toEqual(before);
    } finally { value(await runtime.close()); }
  });
  it("Durable promotion preserves authorship through retry, deletion, rotation and reopen", async () => {
    const opened = await open(); let runtime = opened.runtime;
    try {
      const note = value(await runtime.addMemory({ content: "proposal", status: "candidate", provenance }, "add"));
      const promoted = value(await runtime.promoteCandidate(note.id, "promote"));
      expect(promoted.provenance).toEqual(provenance); expect(promoted.status).toBe("active");
      const tip = value(runtime.tip), files = await inventory(opened.options.directory);
      expect(value(await runtime.promoteCandidate(note.id, "promote"))).toEqual(promoted);
      expect(value(runtime.tip)).toEqual(tip); expect(await inventory(opened.options.directory)).toEqual(files);
      expect(await runtime.updateMemory(note.id, { status: "active" }, "promote")).toMatchObject({ ok: false, error: { code: "PERSISTENCE_CORRUPTION" } });
      value(await runtime.deleteMemory(note.id, "delete")); value(await runtime.rotate()); value(await runtime.collectGarbage());
      value(await runtime.close()); runtime = value(await openDurableEtherMemories({ ...opened.options, openMode: "existing" }));
      const deleted = value(runtime.exportData()), deletedTip = value(runtime.tip), deletedFiles = await inventory(opened.options.directory);
      expect(value(await runtime.promoteCandidate(note.id, "promote"))).toEqual(promoted);
      expect(value(runtime.exportData())).toEqual(deleted); expect(value(runtime.tip)).toEqual(deletedTip);
      expect(await inventory(opened.options.directory)).toEqual(deletedFiles);
    } finally { value(await runtime.close()); }
  });
  it("serialized fresh IDs promote a candidate exactly once", async () => {
    const { runtime } = await open();
    try {
      const note = value(await runtime.addMemory({ content: "proposal", status: "candidate", provenance }, "add"));
      const results = await Promise.all([runtime.promoteCandidate(note.id, "first"), runtime.promoteCandidate(note.id, "second")]);
      expect(results[0]).toMatchObject({ ok: true, value: { status: "active" } });
      expect(results[1]).toMatchObject({ ok: false, error: { code: "CONFLICT" } });
    } finally { value(await runtime.close()); }
  });
  it("queued ordinary edit is observed before fresh eligibility checks", async () => {
    const { runtime } = await open();
    try {
      const note = value(await runtime.addMemory({ content: "proposal", status: "candidate", provenance }, "add"));
      const results = await Promise.all([runtime.updateMemory(note.id, { status: "archived" }, "archive"), runtime.promoteCandidate(note.id, "promote")]);
      expect(results[0].ok).toBe(true); expect(results[1]).toMatchObject({ ok: false, error: { code: "CONFLICT" } });
    } finally { value(await runtime.close()); }
  });
  it("ordinary active updates retain their existing user edit attribution and lifecycle policy", async () => {
    const { runtime } = await open();
    try {
      for (const status of ["candidate", "active", "archived", "rejected"] as MemoryStatus[]) {
        const note = value(await runtime.addMemory({ content: "proposal", status, provenance }, `add-${status}`));
        const updated = value(await runtime.updateMemory(note.id, { status: "active" }, `update-${status}`));
        expect(updated.status).toBe("active"); expect(updated.provenance.lastEditKind).toBe("user");
      }
    } finally { value(await runtime.close()); }
  });
  it("pinned candidates can be explicitly promoted without changing content", async () => {
    const { runtime } = await open();
    try {
      const note = value(await runtime.addMemory({ content: "proposal", status: "candidate", pinned: true, provenance }, "add"));
      const promoted = value(await runtime.promoteCandidate(note.id, "promote"));
      expect(promoted.content).toBe(note.content); expect(promoted.pinned).toBe(true); expect(promoted.expiresAt).toEqual(note.expiresAt);
      expect(promoted.provenance).toEqual(provenance);
    } finally { value(await runtime.close()); }
  });
  it("expired candidates retain expiry under Core and detached durable preparation", () => {
    const core = new EtherMemoriesCore({ userId: "core" });
    const note = value(core.addMemory({ content: "proposal", status: "candidate", pinned: true, expiresAt: new Date("2000-01-01"), provenance }));
    const before = core.exportData();
    const detached = value(prepareCoreMutation(before, { kind: "note.promote", id: note.id }));
    expect(detached.after.memoryNotes.find(n => n.id === note.id)).toMatchObject({ status: "active", expiresAt: note.expiresAt, provenance });
    expect(value(core.promoteCandidate(note.id))).toMatchObject({ status: "active", expiresAt: note.expiresAt, provenance });
  });
  it("legacy lookup matches only the exact prior active-update command", () => {
    const old = value(intentDigest({ kind: "note.update", id: "a", patch: { status: "active" } }));
    expect(matchesCommittedIntent({ kind: "note.promote", id: "a" }, old)).toBe(true);
    expect(matchesCommittedIntent({ kind: "note.promote", id: "b" }, old)).toBe(false);
    expect(matchesCommittedIntent({ kind: "note.promote", id: "a", actor: "user" } as any, old)).toBe(false);
    expect(matchesCommittedIntent({ kind: "note.promote", id: "a" }, value(intentDigest({ kind: "note.update", id: "a", patch: { status: "active", content: "changed" } })))).toBe(false);
    expect(matchesCommittedIntent({ kind: "note.update", id: "a", patch: { status: "active" } }, value(intentDigest({ kind: "note.promote", id: "a" })))).toBe(false);
  });
  it("descriptive provenance cannot claim user-edit authority or self-promote a candidate", async () => {
    const { runtime } = await open();
    try {
      const note = value(await runtime.addMemory({ content: "proposal", status: "candidate", provenance }, "add"));
      const edited = value(await runtime.updateMemory(note.id, { summary: "proposal update",
        provenance: { kind: "system", lastEditKind: "system", detail: "approvedBy: admin" } }, "edit"));
      expect(edited.status).toBe("candidate"); expect(edited.provenance.lastEditKind).toBe("user");
      expect(value(runtime.exportData()).memoryNotes.find(n => n.id === note.id)?.status).toBe("candidate");
    } finally { value(await runtime.close()); }
  });
  it("same-ID concurrent promotions reconcile the original result", async () => {
    const { runtime } = await open();
    try {
      const note = value(await runtime.addMemory({ content: "proposal", status: "candidate", provenance }, "add"));
      const [first, second] = await Promise.all([runtime.promoteCandidate(note.id, "same"), runtime.promoteCandidate(note.id, "same")]);
      expect(value(first)).toEqual(value(second));
    } finally { value(await runtime.close()); }
  });
  it("a second runtime must recover before promoting against a changed durable base", async () => {
    const { runtime, options } = await open();
    const second = value(await openDurableEtherMemories({ ...options, openMode: "existing" }));
    try {
      const note = value(await runtime.addMemory({ content: "proposal", status: "candidate", provenance }, "add"));
      value(await second.recover()); value(await runtime.promoteCandidate(note.id, "first"));
      expect((await second.promoteCandidate(note.id, "second")).ok).toBe(false);
      value(await second.recover());
      expect(await second.promoteCandidate(note.id, "second")).toMatchObject({ ok: false, error: { code: "CONFLICT" } });
      expect(value(await second.promoteCandidate(note.id, "first")).provenance).toEqual(provenance);
    } finally { value(await runtime.close()); value(await second.close()); }
  });
  it("lost promotion acknowledgment recovers and returns its exact effects before checking fresh eligibility", async () => {
    const { runtime: initial, options } = await open(); value(await initial.close());
    let armed = false;
    const files: WalIO = { ...nodeWalIO, open: async (path, create) => {
      const handle = await nodeWalIO.open(path, create);
      let wrote = false;
      return { ...handle, write: async (bytes, position) => {
        const count = await handle.write(bytes, position); wrote ||= count > 0; return count;
      }, sync: async () => {
        await handle.sync();
        if (armed && wrote && /[\\/]wal[\\/]wal-[^\\/]+\.bin$/.test(path)) { armed = false; throw new Error("lost promotion ACK"); }
      } };
    } };
    const runtime = value(await openDurableEtherMemoriesInternal({ ...options, openMode: "existing" }, { files }));
    try {
      const note = value(await runtime.addMemory({ content: "proposal", status: "candidate", provenance }, "add"));
      armed = true;
      expect((await runtime.promoteCandidate(note.id, "promote")).ok).toBe(false);
      value(await runtime.recover());
      const before = value(runtime.exportData()), tip = value(runtime.tip), filesBefore = await inventory(options.directory);
      expect(before.memoryNotes.find(n => n.id === note.id)?.status).toBe("active");
      expect(value(await runtime.promoteCandidate(note.id, "promote"))).toEqual(before.memoryNotes.find(n => n.id === note.id));
      expect(value(runtime.tip)).toEqual(tip); expect(await inventory(options.directory)).toEqual(filesBefore);
    } finally { value(await runtime.close()); }
  });
});
