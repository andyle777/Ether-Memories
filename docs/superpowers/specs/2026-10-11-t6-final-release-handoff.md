# ETHER MEMORIES v0.7.0 — TRANCHE 6 FINAL RELEASE INTEGRATION / FREEZE HANDOFF

You are starting the FINAL tranche of Ether Memories v0.7.0:

**Tranche 6 — Release Integration + Final Freeze**

This is NOT a feature tranche.

This is NOT a redesign tranche.

This is NOT an opportunity to add more architecture.

T1–T5 are complete and frozen.

Your job is to turn the canonical T5 tree into a clean, internally consistent, fully verified **v0.7.0 release candidate**, then freeze it.

There is NO T7.

---

# 1. CANONICAL LINEAGE

Released v0.6.0:

`493c7b69813e71af749e34bbf950803eb8ee589b`

Frozen T1:

`438a038f1aafbd636777f0dd7fb2c8eec3597e45`

Canonical security-clean T2:

`10ed0855bdee126bebbfa78efaaa2a7db6b26858`

Frozen T3:

`a1da07bf65813e0c57e9368dec4c777be8e57cf3`

Frozen T4:

`bf9808c0222bcf66dea54bafef61e5e846f8957b`

Historical standalone T5:

`e8c45b8fde108e3d50241d8dd30c67118e460968`

Canonical reconciled T5:

`f4c6a94927cb9226252a55adb4ae7cca123c4a1b`

## T6 MUST START FROM EXACTLY:

`f4c6a94927cb9226252a55adb4ae7cca123c4a1b`

This is the ONLY valid parent for T6.

Do NOT start from:

- main
- T4
- historical T5
- PR synthetic merge commits
- any earlier tranche SHA

---

# 2. CURRENT T5 STATE MUST REMAIN IMMUTABLE

Canonical T5 branch:

`feat/v0.7.0-t5-windows-final-pass`

Canonical T5 candidate:

`f4c6a94927cb9226252a55adb4ae7cca123c4a1b`

PR #30 remains draft and unmerged.

Do NOT rewrite T5.

Do NOT force-push T5.

Do NOT amend its commits.

Do NOT alter the historical evidence.

Branch T6 from exact T5 and leave the frozen ancestor untouched.

---

# 3. CREATE A NEW T6 BRANCH

Suggested:

`release/v0.7.0-t6-final-freeze`

or:

`feat/v0.7.0-t6-release-integration`

The first commit must have parent:

`f4c6a94927cb9226252a55adb4ae7cca123c4a1b`

Verify this before proceeding.

---

# 4. T6 PURPOSE

T6 has exactly these responsibilities:

1. change release/library identity from 0.6.0 to 0.7.0
2. update release-facing documentation
3. update release manifest/integrity metadata
4. ensure all release metadata is internally consistent
5. prove persisted formats remain unchanged
6. rerun the complete modern regression/security/package matrix
7. rerun native Windows T5 evidence on the final exact candidate
8. perform a fresh exact-SHA hostile release review
9. freeze the exact v0.7.0 candidate
10. STOP before merge/tag/release unless Andy separately authorizes those actions

No feature work.

---

# 5. VERSION BUMP

Update release/library version to:

`0.7.0`

Synchronize every legitimate release-version authority, including at minimum:

- `package.json`
- root `package-lock.json` version
- `package-lock.json` `packages[""].version`
- `LIBRARY_VERSION`
- README current-version references where appropriate
- CHANGELOG
- RELEASE-MANIFEST
- any release-integrity expectation that intentionally tracks the library release version

Search for stale `0.6.0` references.

Classify every occurrence.

Do NOT mechanically replace all `0.6.0` strings.

Historical documentation, migration notes, prior release references, fixture descriptions, and lineage records may legitimately retain 0.6.0.

Every change must be semantically justified.

---

# 6. DO NOT BUMP PERSISTENCE FORMATS

The release version becomes:

`0.7.0`

But these MUST remain unchanged:

Store schema:

`ether.memory_store.v0.3`

WAL:

v1

Receipt ledger:

v1

HEAD:

v1

Checkpoint:

v1

MemoryContext:

`ether.memory_context.v1`

Portable Record:

`ether.portable_record.v1`

Dream algorithm:

`ether.dream.v1`

No schema migration.

No WAL v2.

No receipt v2.

No checkpoint version change.

No persistence wire version change.

No Dream algorithm v2.

Release identity and persistence identity are deliberately separate.

---

# 7. VERSION MUST NOT LEAK INTO PERSISTED BYTES

Preserve and strengthen the existing release-integrity invariant:

Changing:

`LIBRARY_VERSION`

from 0.6.0 to 0.7.0 must NOT change persisted:

- HEAD bytes
- checkpoint wire bytes
- WAL wire bytes
- receipt format
- store schema
- fixture identity
- Dream plan algorithm identity

The release number must not become part of persistence identity or Dream digest/plan identity.

Add or update tests only as necessary to prove this.

Do NOT weaken existing no-version-leak tests.

---

# 8. FIVE FROZEN FIXTURES MUST REMAIN EXACTLY IDENTICAL

Do not rewrite:

- `persistence-wire-v1.json`
- `portable-record-v1.json`
- `retrieval-golden-v1.json`
- `store-v0.3.json`
- `wal-wire-v1.json`

Verify exact Git blob/hash identity against canonical T5.

Record all five in the final freeze report.

Any fixture change is presumptively RED.

---

# 9. RELEASE MANIFEST

Update/create the v0.7.0 release manifest according to existing repository conventions.

It should accurately state the final release contract.

At minimum record:

- package version 0.7.0
- store schema v0.3
- WAL v1
- receipt v1
- HEAD/checkpoint v1
- MemoryContext v1
- Portable Record v1
- Dream algorithm `ether.dream.v1`
- supported public additions
- Windows durability support boundary
- exact test/security/release expectations where repository convention includes them

Do not put provisional SHAs into immutable documentation before the final candidate exists unless the format is explicitly designed to be filled at freeze time.

Avoid self-referential commit hashes that make deterministic freezing impossible.

---

# 10. README — REQUIRED v0.7.0 SURFACE

Update README enough to accurately document the release without turning T6 into a documentation rewrite.

README should cover the final v0.7 additions:

- `explainMemory(id)`
- `inspectMemoryHealth()`
- `previewDreamCycle()`
- `runDreamCycle(plan)`
- `durabilityGuarantee?: "strict" | "recoverable"`

Preserve the conceptual split:

**Dreams propose. Memory remains authoritative.**

Document that Dream Cycle:

- is deterministic
- is local
- is bounded
- does not use LLMs
- does not use embeddings/RAG
- does not mutate canonical memory
- does not persist proposals automatically

Document Windows semantics accurately:

strict:

- remains default
- fails closed where strict barriers cannot be established

recoverable:

- explicit opt-in
- covers tested application/Node-process termination conditions
- does NOT claim power-loss or machine-crash durability

Do not overstate Windows support.

---

# 11. CHANGELOG

Add a concise v0.7.0 entry.

Organize by useful release themes, for example:

- Explainability & Memory Health
- Dream Cycle v1
- Windows process-recoverable durability option
- Repository/toolchain/release hardening

Do not dump internal tranche history into the changelog.

Do not claim excluded features.

Explicitly avoid implying:

- RAG
- embeddings
- autonomous Dream scheduler
- Dream persistence
- automatic proposal acceptance
- WAL v2
- migrations
- backup/restore
- universal Windows power-loss durability

---

# 12. FINAL PUBLIC API CONTRACT

Expected intentional v0.7 public behavioral additions:

- `explainMemory(id)`
- `inspectMemoryHealth()`
- `previewDreamCycle()`
- `runDreamCycle(plan)`

Intentional durable-open option:

- `durabilityGuarantee?: "strict" | "recoverable"`

Expected Dream public types include the already frozen intended T3/T4 types.

T5 must NOT introduce extra runtime exports.

Canonical T5 had:

**32 runtime exports**

Final T6 should preserve that unless the release metadata mechanism itself legitimately requires otherwise.

Any runtime-export increase requires explicit review.

Audit generated declarations and package root.

---

# 13. T2 CONTRACT MUST REMAIN FROZEN

`explainMemory()`:

- Memory Note only
- bounded direct relationships
- no adjacent content leak
- no fake relevance
- detached result
- one captured `asOf`
- zero mutation

`inspectMemoryHealth()`:

- logical loaded-state inspection
- bounded coverage
- no fake global score
- no auto-fix
- no persistence fsck
- detached result
- zero mutation

T6 must not alter these semantics.

---

# 14. T3 CONTRACT MUST REMAIN FROZEN

`previewDreamCycle()` must remain:

- deterministic
- bounded
- ephemeral
- explicit selector required
- selector is a hard information boundary
- selected-selected induced graph only
- no Diary
- no Condensation execution
- no proposal generation
- no persistence
- no mutation

Algorithm:

`ether.dream.v1`

Plan identity must not include package release version.

---

# 15. T4 CONTRACT MUST REMAIN FROZEN

`runDreamCycle()` must preserve:

- hostile DreamPlan validation
- recomputed dependency digest
- recomputed plan identity
- stale-plan rejection
- same captured snapshot used for validation and analysis
- zero live canonical reads after successful comparison
- selected-only analysis
- deterministic proposal IDs
- exact duplicate suppression
- bounded proposals/evidence
- Condensation `analyze()` only
- zero `commitAnalysis()`
- zero `condense()`
- no candidate creation
- no canonical mutation
- no Dream persistence

T6 must not modify Dream behavior.

---

# 16. T5 CONTRACT MUST REMAIN FROZEN

Strict remains default.

Windows strict:

`DURABILITY_UNAVAILABLE`

where strict barriers cannot be proven.

Explicit recoverable:

`durabilityGuarantee: "recoverable"`

Recoverable claim remains process-failure only.

Preserve:

- one-time capability capture
- regular-file sync
- weak `process-recoverable` acknowledgement
- weak activation never called atomic
- unknown historical durability remains unknown
- path safety gates
- bigint identity
- nanosecond checks
- junction/hardlink refusal
- stale-lock refusal
- no automatic lock breaking
- no filesystem-universal claim

No T6 semantic change.

---

# 17. RELEASE-INTEGRITY TESTS

Inspect the current `tests/release-integrity.test.ts`.

Update it minimally for v0.7.0.

It must verify, at minimum:

- package.json version = 0.7.0
- package-lock root version = 0.7.0
- package-lock `packages[""].version` = 0.7.0
- LIBRARY_VERSION = 0.7.0
- README release identity agrees
- CHANGELOG contains v0.7.0
- RELEASE-MANIFEST agrees
- persisted schema remains v0.3
- frozen formats remain unchanged
- release version does not leak into persistence wire identity
- durable quick-start still compiles against isolated packed declarations

Preserve the strong v0.6 lockfile-mismatch regression.

Do NOT weaken it.

---

# 18. ADD A NEGATIVE RELEASE-METADATA REGRESSION IF NEEDED

The v0.6 release previously suffered a package-lock root metadata mismatch.

T6 must prove that cannot recur.

If existing tests already cover all authorities strongly, preserve them.

If there is still a gap, add the smallest test needed.

Do not create a metadata framework.

---

# 19. NO PRODUCTION FEATURE CHANGES EXPECTED

The ideal T6 production-code diff is:

**zero behavioral production changes**

except `LIBRARY_VERSION` or equivalent release identity constant.

If T6 needs to modify:

- Core logic
- persistence logic
- Dream algorithms
- Windows durability mechanics

STOP and classify why.

A genuine correctness defect belongs to its owning tranche semantics and must trigger a narrowly justified repair plus full re-freeze evidence.

Do not disguise feature fixes as release integration.

---

# 20. DEFECT OWNERSHIP RULE

If a T1–T5 correctness defect is discovered during T6:

1. reproduce it
2. classify owning tranche
3. add a regression
4. fix minimally
5. rerun all affected gates
6. document that T6 discovered and integrated the repair
7. produce a new T6 candidate

Do not create T7.

If the fix requires excluded architecture:

T6 is RED.

STOP.

---

# 21. INHERITED TEST BASELINE

Canonical T5 has:

**41 files / 1,036 tests**

All 1,036 inherited tests must remain collected and active.

No deletion.

No skip.

No todo.

No weakened assertion.

T6 tests should be additive only where release integration specifically requires them.

---

# 22. SECURITY BASELINE

Preserve:

- Vitest 4.1.11
- Vite 7.3.6
- source-map-js 1.2.2
- Tinypool absent

No dependency update unless a concrete security/correctness issue requires it.

Required:

Node 22 full audit = 0

Node 22 production audit = 0

Node 24 full audit = 0

Node 24 production audit = 0

---

# 23. STANDARD LOCAL GATES — NODE 22

On a CLEAN exact candidate:

- `npm ci`
- `npm run verify:toolchain`
- `npm run typecheck`
- `npm test`
- `npm run verify:workers`
- `npm run build`
- `npm pack`
- `npm run verify:packed`
- `npm audit --json`
- `npm audit --omit=dev --json`

Record exact Node/npm versions.

---

# 24. STANDARD LOCAL GATES — NODE 24

Repeat the complete clean matrix under Node 24.

Do not reuse an old `node_modules`.

Use a clean install.

Record exact Node/npm versions.

---

# 25. STANDARD CI MATRIX

Final exact candidate must run:

- Ubuntu / Node 22
- Ubuntu / Node 24
- Windows / Node 22
- Windows / Node 24

Every job must pass:

- install
- toolchain guard
- typecheck
- full 1,036+ test suite
- worker-exit guard
- build
- npm pack
- packed consumer

No platform skipped.

---

# 26. NATIVE WINDOWS T5 RE-RUN IS MANDATORY

T6 changes release metadata, not persistence mechanics.

Nevertheless, the FINAL RELEASE CANDIDATE must rerun the dedicated T5 Windows-native proof.

Use the existing native workflow.

Required both Node 22 and Node 24:

- exact checkout identity
- production capability/integration tests
- strict refusal
- recoverable success
- negative controls
- filesystem/identity probe
- all six synchronized process-termination scenarios
- stale-lock behavior
- exactly-once convergence
- worker-exit guard
- artifact preservation

Do not reuse the T5 native run as the final T6 evidence.

Final candidate gets fresh evidence.

---

# 27. SIX FINAL NATIVE CRASH SCENARIOS

Required again:

1. partial WAL write
2. after WAL write
3. after WAL sync
4. after public ACK
5. before HEAD rename
6. after HEAD rename

Both Node 22 and Node 24.

All must converge under the exact same stable mutation identity with no duplicate effects.

---

# 28. PACKED CONSUMER

Final v0.7.0 tarball must verify:

Package:

`ether-memories@0.7.0`

Expected package containment:

- public v0.7 APIs work
- strict Windows behavior truthful
- explicit recoverable mode works
- T2 inspection works
- T3 preview works
- T4 run works
- declarations compile
- internal Dream modules remain inaccessible where intentionally private
- persistence internals remain blocked
- Windows backend internals remain blocked

Record:

- file count
- runtime export count
- blocked internal path count

Do not require those counts to equal T5 blindly if release docs legitimately alter package contents.

Runtime exports SHOULD remain 32.

Any deviation must be explained.

---

# 29. TARBALL REVIEW

Inspect the packed tarball contents.

Confirm no accidental inclusion of:

- `.t*-evidence`
- worktrees
- test scratch
- local reports
- native JSON evidence
- secrets
- Git metadata
- private temporary files
- internal planning scratch not intended for package consumers

Package allowlist must remain intentional.

---

# 30. CROSS-PLATFORM TARBALL HASH

Do NOT require Windows and Linux tarballs to have identical archive hashes unless the repository explicitly guarantees reproducible tarball bytes.

T4/T5 already established this is not a release gate.

Instead verify semantic package identity:

- same package version
- same intended file set
- same declarations
- same root API
- same tests/consumer behavior

Do not invent a reproducible-build guarantee during T6.

---

# 31. PERSISTENCE SOURCE AUDIT

Final T6 review must compare persistence-critical files against canonical T5.

Expected behavioral identity.

If any persistence source differs solely because of release metadata, justify it.

Prefer no persistence source changes at all.

Audit especially:

- codecs
- WAL
- receipt ledger
- FsDurableStore
- FsWalStore
- checkpoint rotation
- DirectoryIO
- production operations
- object reclamation
- startup recovery

No hidden format drift.

---

# 32. DREAM SOURCE AUDIT

Compare Dream implementation files against frozen T4/T5.

Expected:

**byte-identical**

unless documentation/type-only release metadata legitimately touches them, which should be unusual.

Algorithm remains:

`ether.dream.v1`

No package version included in:

- dependency digest
- plan ID
- proposal ID

---

# 33. PUBLIC API AUDIT

Generate final declarations.

Review package root.

Expected intentional release surface:

T2:

- explainMemory
- inspectMemoryHealth

T3:

- previewDreamCycle

T4:

- runDreamCycle

T5 option:

- durabilityGuarantee

No:

- Dream history
- accept/reject proposal
- background scheduler
- persistence repair API
- T5 internals
- DirectoryIO
- weak acknowledgement internals
- WAL internals
- GC internals

---

# 34. FINAL DOCUMENTATION CLAIM AUDIT

Search README, CHANGELOG, release manifest and package description for overclaims.

Reject language implying:

- power-loss-safe Windows durability
- universal filesystem support
- machine-crash guarantee
- autonomous Dreaming
- AI-generated memories
- LLM-backed Dream Cycle
- semantic/fuzzy duplicate detection
- automatic proposal persistence
- migrations that do not exist
- backup/restore that does not exist

Documentation must describe only implemented behavior.

---

# 35. RELEASE VERSION SEARCH

Search repository for:

`0.6.0`

For every remaining match, classify:

- historical reference — valid
- released-v0.6 lineage — valid
- stale current-release metadata — FIX
- fixture/persistence identity — likely valid if intentionally versioned independently
- test expectation — inspect carefully

Also search for:

`0.7.0`

Ensure new references are appropriate release-facing identities and do not leak into persisted protocols.

---

# 36. FORMAT VERSION SEARCH

Search for:

- `ether.memory_store.v0.3`
- WAL version constants
- receipt version constants
- HEAD/checkpoint versions
- MemoryContext v1
- Portable Record v1
- `ether.dream.v1`

Confirm T6 has not accidentally changed any.

---

# 37. FINAL HOSTILE REVIEW — EXACT SHA

Only after:

- all local gates
- audits
- standard CI
- native Windows CI
- packed consumer
- declaration audit
- fixture checks

perform a fresh hostile review of the EXACT final candidate SHA.

Do not review an earlier candidate and then make a “tiny docs fix” afterward without rerunning the required freeze gates.

Any material post-review change invalidates the review.

---

# 38. HOSTILE REVIEW TARGETS

Review specifically for:

- package/lockfile/LIBRARY_VERSION mismatch
- stale 0.6 current-version reference
- accidental persistence format bump
- release version leaked into persisted bytes
- Dream identity changed by package version
- T1–T5 behavioral regression
- fixture drift
- dependency drift
- public export leak
- internal Windows backend leak
- Windows support overclaim
- strict→recoverable silent downgrade
- stale-lock auto-break
- Dream mutation
- proposal persistence
- deleted/skipped inherited tests
- release manifest contradiction
- README code sample mismatch
- npm tarball junk
- secret/local artifact inclusion
- synthetic merge SHA treated as canonical
- old T5 SHA treated as final parent
- accidental T7 planning

Critical / Important / Minor counts required.

Unresolved material must be zero.

---

# 39. T6 PR STRATEGY

After local candidate is green and pushed:

Create a NEW DRAFT PR:

head:

T6 release branch

base:

`main`

This final PR should present the complete v0.7.0 delta from released v0.6.0 to final v0.7 candidate.

Do NOT merge PRs #24–#30 individually to reconstruct release history.

They remain tranche/audit artifacts.

The linear T6 branch already contains the canonical stacked lineage.

Keep final T6 PR DRAFT until freeze is complete.

---

# 40. DO NOT MERGE

Even after T6 is GREEN:

DO NOT merge the final PR automatically.

Andy must explicitly authorize merge.

Do NOT tag automatically.

Do NOT publish npm automatically.

Do NOT create a GitHub release automatically.

Do NOT delete branches.

Freeze first.

Then STOP.

---

# 41. FINAL RELEASE CANDIDATE IDENTITY

Canonical T6 identity is:

the reviewed **branch-head exact SHA**.

Do NOT use:

- PR synthetic merge SHA
- CI temporary merge SHA
- eventual GitHub merge commit

as the frozen implementation identity.

Preserve the existing doctrine:

**reviewed exact branch-head SHA = frozen code-lineage SHA**

Any eventual merge/tag SHA is recorded separately as release integration identity.

---

# 42. FINAL FREEZE CRITERIA

T6 may be declared GREEN only if ALL are true:

- exact parent is canonical T5
- package version = 0.7.0
- lockfile root metadata = 0.7.0
- LIBRARY_VERSION = 0.7.0
- README consistent
- CHANGELOG consistent
- RELEASE-MANIFEST consistent
- store schema remains v0.3
- WAL remains v1
- receipt remains v1
- HEAD/checkpoint remain v1
- MemoryContext remains v1
- Portable Record remains v1
- Dream algorithm remains `ether.dream.v1`
- five fixture blobs unchanged
- all 1,036 inherited T5 tests remain active
- all added T6 tests pass
- zero failures
- zero skips
- zero todos
- worker guard clean
- Node22 audits zero
- Node24 audits zero
- standard four-job CI green
- native Windows Node22 green
- native Windows Node24 green
- all six crash scenarios green on both
- packed consumer green
- declarations/public API audited
- no internal export leak
- no behavioral persistence drift
- no Dream drift
- documentation claim audit clean
- hostile review has zero unresolved material findings
- final candidate pushed and local/remote SHA match
- final PR draft/unmerged

---

# 43. FINAL T6 REPORT

Return:

## T6 VERDICT

GREEN / AMBER / RED

## T6 STATUS

If successful:

**T6 CLOSED / GREEN / FROZEN**

## EXACT LINEAGE

v0.6:

`493c7b69813e71af749e34bbf950803eb8ee589b`

T1:

`438a038f1aafbd636777f0dd7fb2c8eec3597e45`

T2:

`10ed0855bdee126bebbfa78efaaa2a7db6b26858`

T3:

`a1da07bf65813e0c57e9368dec4c777be8e57cf3`

T4:

`bf9808c0222bcf66dea54bafef61e5e846f8957b`

T5:

`f4c6a94927cb9226252a55adb4ae7cca123c4a1b`

T6 candidate:

Branch:

Draft PR:

## RELEASE METADATA

package.json:

package-lock root:

package-lock packages[""]:

LIBRARY_VERSION:

README:

CHANGELOG:

RELEASE-MANIFEST:

## PUBLIC API

Runtime exports:

Type exports:

Intentional v0.7 additions:

Unexpected additions:

## PERSISTENCE IDENTITY

Store:

WAL:

Receipt:

HEAD:

Checkpoint:

MemoryContext:

Portable Record:

Dream algorithm:

## FIXTURE IDENTITY

List all five exact blobs/hashes.

## TESTS

Inherited T5:

`1036`

New T6:

Total:

Files:

Failures:

Skips:

Todos:

Warnings:

## SECURITY

Node22 full:

Node22 production:

Node24 full:

Node24 production:

## LOCAL MATRICES

Node22/npm:

Result:

Node24/npm:

Result:

## STANDARD CI

Run ID:

Ubuntu22:

Ubuntu24:

Windows22:

Windows24:

## NATIVE WINDOWS FINAL PROOF

Run ID:

Node22:

Node24:

Capability tests:

Filesystem assertions:

Negative controls:

partial WAL:

after WAL write:

after WAL sync:

after ACK:

before HEAD rename:

after HEAD rename:

Exactly-once convergence:

## PACKED CONSUMER

Package:

Files:

Runtime exports:

Blocked internals:

Declarations:

T2:

T3:

T4:

T5 recoverable:

## SOURCE IDENTITY AUDIT

Persistence drift:

Dream drift:

Dependencies:

Toolchain:

## DOCUMENTATION CLAIM AUDIT

Result:

Remaining 0.6.0 references classified:

## HOSTILE REVIEW

Critical:

Important:

Minor:

Unresolved material:

## FINAL PR STATE

Draft:

Merged:

Base:

Head:

Local/remote identity:

## DEFERRED SCOPE

Post-v0.7 only.

**NO T7.**

## FREEZE DECLARATION

If every gate is GREEN, state exactly:

**T6 CLOSED / GREEN / FROZEN.**

**Ether Memories v0.7.0 release candidate is frozen at `<FULL SHA>`.**

**`<FULL SHA>` is the canonical reviewed branch-head/code-lineage identity for v0.7.0.**

**No merge, tag, npm publish or GitHub release has been performed.**

Then STOP.

---

# 44. ABSOLUTE STOP RULE

After declaring T6 frozen:

DO NOT:

- merge
- tag
- publish
- create a release
- start v0.8
- start another tranche
- invent T7

Wait for Andy.

---

# FINAL DOCTRINE

**T1–T5 are frozen.**

**T6 integrates; it does not innovate.**

**Release version may change. Persistence identity must not.**

**The exact reviewed branch-head SHA is canonical.**

**No T7.**