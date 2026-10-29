# Ether Memories v0.8.0 T0 repair contract

28 October 2026, Australia/Sydney. Review candidate; no publication authority.

This contract records the bounded implementation selected for the current repair. The owner explicitly selected **trusted-host authority** in this chat: the host application holding a writable Core or Durable runtime authenticates its users, decides whether promotion is authorized, and invokes mutations. This library does not authenticate actor names. Descriptive provenance, model output and an `approvedBy` claim confer no authority. Never expose unrestricted write methods directly to an untrusted model or unauthenticated endpoint.

## Fresh operations

| Operation | Behavior |
| --- | --- |
| Promote existing candidate | Activate it; retain all authorship/provenance fields and content; update timestamp and normal Core links. |
| Promote active, archived or rejected note with a new mutation ID | `CONFLICT`, with unchanged published state, tip, WAL, object and receipt contents. |
| Promote missing note | `NOT_FOUND`, with no durable effects. |
| Promote pinned candidate | Allowed: promotion does not edit its content. |
| Promote expired candidate | Allowed if still present; expiry stays unchanged. Promotion does not extend expiry or undo a prior purge. Core and detached preparation cover this case; Durable Date-valued command inputs retain their existing rejection. |
| Ordinary trusted `updateMemory`, including `status: active` | Existing behavior remains: any existing status may be updated, with `lastEditKind: user`. Explicit provenance replacement retains its old field policy, then the user edit stamp is applied. This is a trusted host write, not candidate approval. |
| Concurrent fresh promotions | Serialized candidate guard admits at most one transition. Other runtimes retain stale-base/recovery behavior. |

## Stable identity and historical retries

Fresh Durable promotion uses exactly `{kind: "note.promote", id}` as its pre-execution command. Ordinary updates retain their existing command bytes. Command kinds are not WAL operation kinds: persisted transactions still contain the frozen v1 explicit effects and digests. There is no new persisted command record or format.

Before fresh state-dependent checks, the existing coordinator validates the command and runtime readiness, then checks authoritative active-WAL and cumulative-ledger history. A matching fresh promotion receipt returns its exact effects. An ordinary update cannot reuse a fresh promotion ID.

For an exact two-field promotion command, receipt lookup also recognizes the digest of the exact released command `{kind: "note.update", id, patch: {status: "active"}}`. This is deliberately **lookup-only** compatibility. v0.7 promotion and ordinary active updates emitted identical bytes, so either old originating method returns that same recorded result. No method or actor is inferred from historical data. Extra fields, a different target, or additional patch fields do not match. A fresh commit always uses the new promotion digest; the legacy match cannot manufacture a transaction.

Historical retries bypass fresh eligibility only after matching verified committed identity. They preserve old user stamps and old graph metadata loss exactly. They do not resurrect deleted notes, repeat effects, grow frames/receipts, or advance the tip. A committed identity ahead of the runtime still requires explicit recovery and same-ID retry.

## Graph repair

Fresh generated and explicit graph edges return their stored normalized representation. Unsupported relationship input is preserved as `data.rawRelation` under the existing generated-edge overwrite rule. Historical reconstruction uses a distinct restore path, preserving recorded metadata and old normalization without inventing raw values. Existing blank-input and conflicting raw-relation policies are unchanged.

## Frozen boundaries and remaining gates

WAL v1, Store v0.3, receipt ledger v1, verified HEAD/checkpoints/receipts, strict default and explicit Windows process recoverability remain unchanged. No history rewrite, speculative WAL redesign, stale-lock takeover, version bump, merge, push, tag or release.

The fixture compatibility evidence is from controlled **released v0.7 producer** stores, not genuine user stores. v0.6 compatibility and the full Windows/Ubuntu × Node 22/24 matrix remain unverified by this session. No authentication-provider integration or external model admission security is claimed; those belong to the selected trusted host boundary. Broader v0.8 tranches remain outside this repair.

## RED-first handoff and reproduction

1. Preserve the original `source-handoff.zip`, its manifest, released producer and fixture masters. Never regenerate those masters with the repaired candidate.
2. Use baseline `edb56d3ce23c8b060346f654fb7007851f1661ba`. In a separate RED checkout, apply `ether-v080-red-first-tests.patch` and run graph and promotion tests to see actual failures. The clean RED run has nine failing promotion assertions and two passing controls; graph has six failures and ten passes. Earlier diagnostic logs also retain the initial Windows environment errors and corrected expired-input setup.
3. In a clean candidate checkout at the same baseline, review and apply `ether-v080-complete-repair.patch`. This full patch includes the final tests; do not stack it over the RED patch. Alternatively use `candidate-source.zip`. Run typecheck, graph/promotion tests, full regression suite, producer control and repaired-consumer historical harness, Windows native and process-termination probes, package consumer and worker-exit checks.
4. Inspect exact candidate commit and file manifest in `verification.json`; base SHA alone never identifies an uncommitted candidate. The single-transfer ZIP also includes repaired source and all final evidence.
5. Treat `recovered/probe-promotion-gates.mjs` as an **old diagnostic**, not the current gate: it assumes fresh cross-method command equivalence and the old Durable bypass. Current gates are the shipped regression tests and released compatibility harness. Prior 1,055-pass claims are historical; use the new session's verification report for current counts.

Typical commands from the candidate source directory:

```text
npm ci
npm run typecheck
npm test -- --maxWorkers=4
npm run build
node ../recovered/check-release-compatibility.mjs /absolute/path/to/candidate/dist/index.js
node scripts/round11-windows-native-probe.mjs
node scripts/round11-windows-crash-probe.mjs
npm pack
npm run verify:packed
npm run verify:workers
```

On restricted Windows runners, put `TEMP` and `TMP` in a writable work directory. Native filesystem probes need permission to create temporary junctions. A permission failure is not a passing native check.
