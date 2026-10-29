import { afterEach, describe, expect, it } from "vitest";
import * as fs from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { EtherMemoriesCore } from "../src/core/EtherMemories.js";
import { MindGraphManager } from "../src/core/MindGraph.js";
import { openDurableEtherMemories } from "../src/core/DurableEtherMemories.js";
import { prepareCoreMutation } from "../src/persistence/mutationPreparation.js";
import { validateStateRoot } from "../src/persistence/stateRoot.js";
import { hydrateSnapshot } from "../src/persistence/snapshotPayload.js";
import { value } from "./helpers/persistence.js";
import { sourceSnapshot } from "./helpers/recovery.js";

const directories: string[] = [];
afterEach(async () => {
  for (const directory of directories.splice(0)) await fs.rm(directory, { recursive: true, force: true });
});

function graph() {
  const graph = new MindGraphManager();
  value(graph.addNode({ id: "a", type: "topic", data: {} }));
  value(graph.addNode({ id: "b", type: "topic", data: {} }));
  return graph;
}

describe("fresh graph metadata fidelity", () => {
  // The existing generated-edge rule is the oracle: unsupported input wins
  // over caller rawRelation; canonical relations retain opaque caller data.
  for (const explicit of [false, true]) {
    it(`${explicit ? "explicit" : "generated"} malformed metadata fails without an uncaught error or inserted edge`, () => {
      const g = graph();
      const data = Object.defineProperty({}, "bad", { enumerable: true, get() { throw new Error("bad metadata"); } });
      const result = explicit ? g.addEdgeWithId("edge", "a", "b", "custom", data) : g.addEdge("a", "b", "custom", data);
      expect(result).toMatchObject({ ok: false, error: { code: "CONFLICT" } });
      expect(g.getAllEdges()).toEqual([]);
    });
    for (const supplied of [{}, { rawRelation: "custom" }, { rawRelation: "caller-value" }]) {
      it(`${explicit ? "explicit" : "generated"} fresh edge returns and stores its original unsupported relation (${JSON.stringify(supplied)})`, () => {
        const g = graph();
        const input = { ...supplied, nested: { marker: 1 } };
        const edge = value(explicit ? g.addEdgeWithId("edge", "a", "b", "custom", input)
          : g.addEdge("a", "b", "custom", input));
        expect(edge).toEqual({ id: edge.id, source: "a", target: "b", relationship: "related_to",
          data: { rawRelation: "custom", nested: { marker: 1 } } });
        expect(g.getAllEdges()).toEqual([edge]);
        input.nested.marker = 2;
        (edge.data.nested as { marker: number }).marker = 3;
        expect(g.getAllEdges()[0].data).toEqual({ rawRelation: "custom", nested: { marker: 1 } });
      });
    }
    it(`${explicit ? "explicit" : "generated"} canonical edge preserves opaque rawRelation and failed insertion changes nothing`, () => {
      const g = graph();
      const insert = (target: string) => explicit ? g.addEdgeWithId("edge", "a", target, "supports", { rawRelation: 17 })
        : g.addEdge("a", target, "supports", { rawRelation: 17 });
      const edge = value(insert("b"));
      expect(edge.data).toEqual({ rawRelation: 17 });
      expect(insert("b")).toMatchObject({ ok: false, error: { code: "CONFLICT" } });
      expect(insert("missing")).toMatchObject({ ok: false, error: { code: "NOT_FOUND" } });
      expect(g.getAllEdges()).toEqual([edge]);
    });
  }

  it("does not silently add new blank-input rejection policy", () => {
    const g = graph();
    const edge = value(g.addEdgeWithId("blank", "a", "b", "", {}));
    expect(edge.relationship).toBe("related_to");
    expect(edge.data).toEqual({ rawRelation: "" });
    expect(g.getAllEdges()).toEqual([edge]);
  });
});

describe("historical graph reconstruction", () => {
  for (const relationship of ["related_to", "historical-custom"]) {
    for (const data of [{ marker: 1 }, { marker: 1, rawRelation: { opaque: true } }]) {
      it(`preserves accepted data for ${relationship} without inventing lost raw values (${JSON.stringify(data)})`, () => {
        const raw = sourceSnapshot();
        raw.graph.edges[0].relationship = relationship;
        raw.graph.edges[0].data = data;
        const snapshot = value(hydrateSnapshot(raw, raw.identity.userId));
        const core = new EtherMemoriesCore({ userId: raw.identity.userId });
        value(core.importData(snapshot));
        const expected = { ...snapshot.graph.edges[0], relationship: "related_to", data };
        expect(core.graph.getAllEdges()).toEqual([expected]);
        expect(core.exportData().graph.edges).toEqual([expected]);
        const root = value(validateStateRoot(snapshot));
        expect(root.snapshot.graph.edges).toEqual([expected]);
        expect(root.graph.getAllEdges()).toEqual([expected]);
        const prepared = value(prepareCoreMutation(snapshot,
          { kind: "note.update", id: "alpha", patch: { content: "Unrelated new content" } }));
        expect(prepared.after.graph.edges).toEqual([expected]);
        expect(prepared.operations.filter(op => op.type === "ether.graph-edge.put")).toEqual([]);
      });
    }
  }
});

it("Durable fresh edge agrees with snapshot and retains metadata across retry, rotation and reopen", { timeout: 30_000 }, async () => {
  const directory = await fs.mkdtemp(join(tmpdir(), "ether-graph-fidelity-"));
  directories.push(directory);
  const options = { userId: "graph-fidelity", directory: join(directory, "store"),
    durabilityGuarantee: process.platform === "win32" ? "recoverable" as const : "strict" as const };
  let runtime = value(await openDurableEtherMemories(options));
  try {
    const note = value(await runtime.addMemory({ content: "Graph source" }, "note"));
    const diary = value(await runtime.addDiaryEntry({ content: "Graph target" }, "diary"));
    const source = `memory:${note.id}`, target = `diary:${diary.id}`;
    const edge = value(await runtime.addGraphEdge("fresh-edge", source, target, "custom", { nested: { marker: 1 } }, "edge"));
    expect(edge.data).toEqual({ rawRelation: "custom", nested: { marker: 1 } });
    expect(value(runtime.exportData()).graph.edges.find(e => e.id === edge.id)).toEqual(edge);
    const tip = value(runtime.tip);
    expect(value(await runtime.addGraphEdge("fresh-edge", source, target, "custom", { nested: { marker: 1 } }, "edge"))).toEqual(edge);
    expect(value(runtime.tip)).toEqual(tip);
    value(await runtime.rotate());
    value(await runtime.close());
    runtime = value(await openDurableEtherMemories({ ...options, openMode: "existing" }));
    expect(value(runtime.exportData()).graph.edges.find(e => e.id === edge.id)).toEqual(edge);
    expect(value(await runtime.addGraphEdge("fresh-edge", source, target, "custom", { nested: { marker: 1 } }, "edge"))).toEqual(edge);
    expect(value(runtime.tip)).toEqual(tip);
  } finally { value(await runtime.close()); }
});
