# Ether Memories v0.7.0 Release Manifest

Version: 0.7.0
Tag: v0.7.0

- Lineage: released v0.6.0 → canonical T1–T5 → frozen T6 → v0.7.0 release
- Status: merged into main, tagged, released on GitHub and published on npm
- Canonical T5 parent: `f4c6a94927cb9226252a55adb4ae7cca123c4a1b`
- Frozen T6/code-lineage SHA: `64fb0198f70f4e3bace22e5c6f1f19eeba263676`
- Released integration/tag SHA: `17a452ab7356092aa3b84edb1708f8a6688effa6`
- npm publication: `ether-memories@0.7.0`; publisher `andyle777`; `latest = 0.7.0`
- Published tarball SHA-256: `aa9d978e97d0fdbe68d7f79d9d430d91009ba5a98f09be753e32e1107f3a89e4`

The reviewed frozen T6 SHA remains the canonical code-lineage identity.
The separately authorized normal merge of [PR #31](https://github.com/andyle777/ether-memories/pull/31)
preserved it as an ancestor of the release-integration commit; `v0.7.0` points to
that integration commit. These are distinct identities, not interchangeable SHAs.
The [GitHub Release](https://github.com/andyle777/ether-memories/releases/tag/v0.7.0)
and [npm package](https://www.npmjs.com/package/ether-memories/v/0.7.0) are published.
The registry tarball is byte-for-byte identical to the audited candidate, and a
clean registry consumer install/import passed. This post-release documentation
reconciliation does not alter the frozen tag or published artifact.
Prior release provenance is preserved in
[v0.6.0 integration lineage](docs/v0.6.0-integration.md).

## Frozen protocol identities

Store schema: ether.memory_store.v0.3
WAL version: 1
Receipt version: 1
HEAD version: 1
Checkpoint version: 1
MemoryContext schema: ether.memory_context.v1
Portable Record schema: ether.portable_record.v1
Dream algorithm: ether.dream.v1

Release identity is separate from persistence and Dream identity. The five frozen
fixtures, protocol bytes and dependency/plan/proposal identities remain unchanged
from canonical T5. T6 includes one owning persistence correction: the inherited
durable-runtime directory-binding repair captures an absolute store directory
before asynchronous open and shares it across inspection, bootstrap, recovery,
WAL operations and maintenance. A cwd change therefore cannot redirect the runtime
to another store. All other persistence implementation remains unchanged from T5.
No migration, new WAL/receipt format, activation journal or persisted durability
history is introduced.

## Public release surface

- Memory Notes, Diary and Mind Graph remain the three foundations.
- Condensation remains a processor.
- Deterministic retrieval, bounded MemoryContext and provider-neutral transport remain.
- Core and Durable expose explainMemory(id), inspectMemoryHealth(),
  previewDreamCycle(selector, options?) and runDreamCycle(plan).
- Inspection is bounded logical-state observation, detached and read-only;
  health findings do not repair persistence or produce a global score.
- Dream v1 is deterministic, local, bounded and ephemeral. An explicit selector
  bounds sources; selected-selected relationships only. Run validates the plan
  against the same captured analysis snapshot and proposes detached suggestions.
  **Dreams propose. Memory remains authoritative.**
- Dream uses no LLM, embeddings or RAG, creates no canonical candidate, performs
  no commit/condense, mutation, scheduler, automatic acceptance or proposal persistence.
- Durable-open option: durabilityGuarantee?: "strict" | "recoverable".
- Root runtime exports remain32; internal Dream/persistence/Windows helpers stay private.

## Durable behavior and Windows boundary

- Caller-supplied mutation IDs reconcile lost acknowledgements without duplicate effects.
- A repairable incomplete final WAL tail is synchronized/truncated under writer
  authority and rescanned; authoritative complete/structural corruption always fails closed.
- Explicit rotation preserves cumulative historical receipts and authoritative
  lineage before retired-WAL reclamation. Explicit GC collects only provably
  orphaned payload objects; committed objects remain permanent roots.
- Explicit maintenance preserves failure precedence and committed rotation;
  no automatic thresholds or background operations are introduced.
- Strict remains the default. It fails closed with DURABILITY_UNAVAILABLE on
  Windows where strict directory/activation barriers cannot be established.
  Supported POSIX backends may exceed a requested recoverable guarantee.
- Explicit recoverable mode covers tested application/Node-process termination
  with OS/filesystem still operating in local Windows conditions, including
  Windows Server2025 native Node22/24 evidence. Filesystem type is not detected.
  No universal Windows filesystem, mapped/network/cloud, power-loss, kernel/
  machine-crash, reset, controller/cache/media failure or corruption guarantee.
- One backend capability/operations capture serves every durable path. Regular-file
  sync is mandatory. Weak internal acknowledgement/activation is process-recoverable,
  never confirmed/atomic. Historical durability remains unknown in receipt ledgerv1.
- Unsafe path aliases, junctions and hardlinks fail closed; bounded Windows reads
  use exact bigint identity and nanosecond timestamps. Ordinary Unicode/spaces work.
- Writer locks are never automatically broken, guessed stale by PID or taken over
  after a timeout. State recovery does not reacquire writer authority.

See [Windows process recoverability](docs/t5-windows-recoverability.md),
[inspection](docs/memory-inspection.md), [Dream preview](docs/dream-plan.md)
and [Dream analysis](docs/dream-analysis.md).

## Release gates

Coverage: 1036 inherited cases + 2 release-integrity regressions + 1 durable-runtime
directory-binding regression = 1039 active cases across41files. The regression
checks original-store recovery and tip, write/retry, rotation/GC/maintenance,
untouched other-store contents and cwd changes during pending open. The exact-SHA
freeze evidence recorded all 1,039 tests passing, with zero failures/skips/todos
and zero worker leaks.
Fresh clean Node22/24 gates passed npmci, toolchain, typecheck, full tests,
worker exit, build, npm pack, isolated packed consumer and full/production
audit JSON with all four vulnerability totals0.

All four standard Ubuntu/Windows × Node22/24 jobs passed at the frozen T6 SHA.
The existing Windows2025 workflow freshly passed both Node jobs, all production/
integration cases, required negative controls, filesystem assertions and six
semantic-marker termination scenarios with stable exactly-once retry convergence.
Native JSON identifies the frozen SHA/runtime/clean checkout and is preserved.
After the normal merge, all four standard CI jobs also passed at the released
integration SHA.

Generated declarations, 32 root runtime exports, 64 blocked internal paths,
130 intended tarball files, five exact fixture identities and all documentation claims
were audited before fresh independent hostile review with no unresolved material
finding. Archive-byte reproducibility across OSes is not claimed.

## Completed release actions and excluded scope

The freeze itself did not authorize release actions. After the freeze, the owner
separately authorized the normal merge into main, the `v0.7.0` tag, the GitHub
Release and npm publication. Those actions are complete; the frozen code-lineage,
released integration/tag identity and published npm artifact remain unchanged.
No T7. Post-v0.7 work includes migrations, backup/restore, distributed writers
and broader storage guarantees; none is part of this release.
