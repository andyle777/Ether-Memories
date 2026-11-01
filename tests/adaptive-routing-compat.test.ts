import { expect, it, vi } from "vitest";
import { EtherMemoriesCore, summarizeAdaptive, summarizeWithHost } from "../src/index.js";

it("T2-068: T2 does not mutate canonical memories or change graph access", async () => {
  const core = new EtherMemoriesCore({ userId: "t2-compat" });
  const note = core.addMemory({ content: "selected evidence" });
  expect(note.ok).toBe(true);
  if (!note.ok) throw Error("fixture setup");
  const snapshot = core.exportData(), noteRevision = core.notes.revision, diaryRevision = core.diary.revision;
  const result = await summarizeAdaptive({ operation: "semantic_summary", references: [{ kind: "note", id: note.value.id, ref: `note:${note.value.id}` }], maxChars: 12, allowHostDisclosure: true }, { evidence: () => ({ status: "found", content: "selected evidence" }), host: { summarizeEvidence: async () => "selected" } });
  expect(result.ok && result.value.route).toBe("hybrid");
  expect(core.exportData()).toEqual(snapshot); expect(core.notes.revision).toBe(noteRevision); expect(core.diary.revision).toBe(diaryRevision);
  expect(core.graph.getNode(`memory:${note.value.id}`)).toBeTruthy();
  const graphResult = await summarizeAdaptive({ operation: "semantic_summary", references: [{ kind: "node", id: "x", ref: "node:x" }], maxChars: 3 });
  expect(graphResult.ok).toBe(false); expect(core.graph.getNode(`memory:${note.value.id}`)).toBeTruthy();
});

it("T2-068: T1 fallback and unbounded pending behavior remain unchanged", async () => {
  expect(await summarizeWithHost({ text: "abcdef", maxChars: 3, allowHostDisclosure: false })).toEqual({ ok: true, value: { text: "abc", source: "local" } });
  let release!: (value: string) => void;
  const pending = summarizeWithHost({ text: "abcdef", maxChars: 3, allowHostDisclosure: true }, { summarize: () => new Promise(resolve => { release = resolve; }) });
  let settled = false; void pending.then(() => { settled = true; });
  await Promise.resolve(); await Promise.resolve(); expect(settled).toBe(false);
  release("ok"); expect(await pending).toEqual({ ok: true, value: { text: "ok", source: "host" } });
});

it("T2-068: the T2 deadline does not impose a deadline on T1", async () => {
  vi.useFakeTimers();
  try {
    let release!: (value: string) => void;
    const pending = summarizeWithHost({ text: "abcdef", maxChars: 3, allowHostDisclosure: true }, { summarize: () => new Promise(resolve => { release = resolve; }) });
    let settled = false; void pending.then(() => { settled = true; });
    await vi.advanceTimersByTimeAsync(30001); expect(settled).toBe(false);
    release("ok"); expect((await pending).ok).toBe(true);
  } finally { vi.useRealTimers(); }
});

it("T2-065/068: direct excerpts preserve independent note, diary and graph operations", async () => {
  const core = new EtherMemoriesCore({ userId: "t2-three-pillars" });
  const note = core.addMemory({ content: "note before" }); const diary = core.addDiaryEntry({ content: "diary before" });
  expect(note.ok && diary.ok).toBe(true);
  if (!note.ok || !diary.ok) throw Error("fixture setup");
  const before = core.exportData();
  const deps = new Proxy({}, { getOwnPropertyDescriptor() { throw Error("dependencies read"); }, get() { throw Error("dependencies read"); } });
  const result = await summarizeAdaptive({ operation: "local_excerpt", text: "abcdef", maxChars: 3 }, deps);
  expect(result.ok && result.value.text).toBe("abc"); expect(core.exportData()).toEqual(before);
  expect(core.notes.get(note.value.id)).toMatchObject({ ok: true, value: { content: "note before" } });
  expect(core.diary.get(diary.value.id)).toMatchObject({ ok: true, value: { content: "diary before" } });
  expect(core.graph.getNode(`memory:${note.value.id}`)).toBeTruthy();
});
