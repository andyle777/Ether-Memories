# Changelog

## 0.7.0 — Explainability, Dream Cycle & Windows Recoverability

Released as [GitHub v0.7.0](https://github.com/andyle777/ether-memories/releases/tag/v0.7.0)
and published as [ether-memories@0.7.0](https://www.npmjs.com/package/ether-memories/v/0.7.0).
See [the release manifest](RELEASE-MANIFEST.md) for frozen code-lineage,
release-integration and published tarball identities.

- Added bounded, detached, read-only `explainMemory` and `inspectMemoryHealth`
  on Core and the durable facade.
- Added deterministic Dream v1 preview and analysis through `previewDreamCycle`
  and `runDreamCycle`: explicit bounded selection, evidence and ephemeral proposals.
  Dreams propose. Memory remains authoritative. No LLM, embeddings, RAG, automatic
  acceptance, canonical mutation or proposal persistence.
- Added explicit Windows process-recoverable durability. Strict remains default;
  recoverable covers tested application/Node-process termination with the OS and
  local filesystem operating, not power loss or machine/kernel failure. Writer
  locks are never auto-broken and weak acknowledgements remain process-recoverable.
- Preserved Store v0.3, WAL/receipt/HEAD/checkpoint v1, MemoryContext/Portable
  Record v1, Dream `ether.dream.v1`, five frozen fixtures and deterministic identity.
- Cleaned repository/CI and secured the Node22/24 test toolchain, with isolated
  packed-consumer gates and dedicated native Windows filesystem/termination proof.
- Release identity advanced to0.7.0; no migration or new persistence format.
- Fixed inherited durable-runtime directory-binding: capture the absolute store
  directory before asynchronous open so later cwd changes cannot redirect recovery,
  writes or maintenance to another store. Added an isolated real-source regression.

## 0.6.0 — Durable Persistence

- Added an opt-in durable store: `openDurableEtherMemories()` with WAL-transactional commits
  under exclusive writer authority and crash-consistent startup recovery.
- Added deterministic retry identity: caller-supplied mutation IDs reconcile lost
  acknowledgments without duplicate effects, including after restart.
- Added explicit `rotate()`: checkpoint activation, a cumulative durable receipt ledger,
  exact historical result reconstruction, and safe reclamation of the retired WAL segment
  only after the new lineage is authoritative.
- Added explicit `collectGarbage()`: reclaims only payload objects provably unreachable from
  every authoritative structure; committed objects are permanent roots and no tombstone
  engine exists.
- Added explicit `runMaintenance()`: one deterministic maintenance operation deriving a
  rotation recommendation from the configured active-WAL envelope and the frozen WAL v1
  frame cap, performing the existing rotation only when recommended, and following a fully
  successful rotation with the existing orphan collection. No background maintenance.
- T10 is frozen by owner decision at code-lineage SHA
  `6f298aea2cd0278078bf49344f75807355a4e09b`; subsequent naming/status documentation
  cleanup is separate from that frozen code lineage. Maintenance adds no persisted
  policy or formats, does not auto-break writer locks, and does not weaken exact
  mutation admission; GC failures preserve the already-committed rotation.
- Added bounded-memory operation for unbounded histories: streamed directory inventory,
  external cascade sorting, sealed and per-record-authenticated scratch processing, and
  captured-tip plus exact `marks ⊆ inventory` coverage proofs before any unlink.
- Preserved persisted formats: the store schema remains `ether.memory_store.v0.3`; snapshots,
  checkpoints, WAL frames, and frozen fixtures are unchanged.
- Known limitation: native Windows power-loss durability is not claimed; durable-mode
  initialization fails closed with `DURABILITY_UNAVAILABLE` on Windows, and probes use
  simulated directory barriers there.

## 0.5.0 — Deterministic Retrieval & Memory Intelligence

- Added match-class gated deterministic retrieval with a canonical Unicode tokenizer and
  structured retrieval evidence.
- Added deterministic Condensation v2 with candidate isolation and explicit promotion.
- Added transactional Portable Record v1 import with validation receipts.
- Preserved all persisted schema contracts and v0.4 persistence compatibility.

## 0.4.0 — Portable Recall

- Added validated transactional snapshot imports and stable graph-edge identities.
- Added injectable storage, crash-safer filesystem replacement, clone-on-read results,
  opt-in graph-assisted recall, and provider-neutral portable records.

## 0.3.2 — Forward-Compatibility Hardening

- Centralized the current library and schema versions.
- Rejected unsupported snapshot schemas before import state mutation.
- Preserved v0.3 snapshot, identity, hydration, and persistence behavior.

## 0.3.1 — Stability Hardening

- Hardened duplicate graph-edge handling.
- Added Diary text retrieval to `MemoryContext`.
- Kept FoundationLinker lifecycle state coherent through condensation and expiry.
- Corrected retrieval evidence and clarified bounded-context accounting.

## 0.3.0 — Three Rooms, One Transport

- Restored persistent identity and user-ID conflict protection.
- Added complete Diary CRUD.
- Added FoundationLinker and graph neighborhood helpers.
- Added provenance and thin lifecycle status.
- Added pinned edit shield and candidate promotion.
- Added deterministic retrieval explanations.
- Added bounded `MemoryContext` transport with schema version, purpose, budgets, citations, retrieval trace, and truncation reporting.
- Added pure `toPlainJson`, `toAgentToolResult`, and `toRlmEnv` adapters.
- Kept vectors, embeddings, LLM dependencies, autonomy, distributed sync, and runtime installation out of scope.

## 0.2.0 — Three Foundations of Memory

- Memory Notes, Diary, Mind Graph.
- Condensation demoted to processing layer.
- Deterministic retrieval.
- Local JSON persistence.
