# Windows process recoverability

The durable factory accepts one optional public setting:

```ts
await openDurableEtherMemories({
  userId: "owner",
  directory: "C:\\local-memory",
  durabilityGuarantee: "recoverable"
});
```

Omission means `"strict"`. Strict retains the v0.6 contract and fails closed
with `DURABILITY_UNAVAILABLE` on native Windows where directory barriers and
strict activation cannot be proven. It never silently downgrades or falls back
per operation. Supported POSIX backends retain strict barriers even when a
caller requests the weaker recoverable guarantee.

Recoverability means recovery across application/Node process termination while
the operating system and filesystem remain operating. The empirical scope is
the tested local Windows environment and NTFS-style behavior exercised on
Node22 and Node24, including the Windows Server2025 native CI jobs. A drive-letter
path does not establish NTFS or local storage; filesystem type is not detected.
Universal Windows filesystem support is not claimed.

Power loss, kernel/BSOD crashes, hard resets, controller/cache/media failure,
volume corruption, arbitrary external mutation, network/mapped drives, SMB/NAS
and cloud-sync guarantees are excluded. Process termination probes do not
simulate or certify a machine crash.

## One capability, truthful acknowledgements

The runtime selects and captures its DirectoryIO capability and operations once
before runtime I/O. Bootstrap, startup recovery, WAL, object installation, HEAD
activation, rotation, garbage collection and maintenance reuse that backend.
There is no strict-then-recoverable fallback or per-call switching.

Regular-file sync remains mandatory. Recoverable directory operations validate
safe existing entries; they do not claim a directory metadata flush. Weak
internal WAL acknowledgements and HEAD activation use `"process-recoverable"`,
never `durability: "confirmed"` or `activation: "atomic"`. Existing strict
receipt/activation types retain their confirmed/atomic meanings. Internal unions
and adapters are not package-root APIs. Ordinary mutation `Result<T>` shapes
remain unchanged.

Receipt ledgerv1 records stable identity and effects, not the original writer's
durability profile. Historical durability stays unknown. Retry acknowledgement
describes the current invocation's capability; a later strict or recoverable
open cannot fabricate historical provenance. No capability history, receiptv2,
WALv2, migration, new journal or format change is introduced.

## Filesystem safety and writer authority

The Windows pre-I/O fence rejects UNC/device namespaces, ADS, DOS aliases,
trailing-dot/space components and the problematic U+10FFFF path case. Ordinary
Unicode and spaces remain usable. Junction ancestors and hardlinked authority
files fail closed. Bounded Windows reads compare exact bigint device/file IDs
and nanosecond timestamps.

Production never automatically breaks `writer.lock`, guesses a dead PID or
takes over after a timeout. State may be recoverable while writer authority
remains unavailable. Explicit operator handling must resolve stale authority.
Crash probes assert production refusal first; only the harness removes the known
stale lock after its known child has terminated.

## Frozen T4 behavior and evidence gates

`explainMemory`, `inspectMemoryHealth`, `previewDreamCycle` and `runDreamCycle`
keep their signatures, authority precedence and read-only semantics. CLOSED and
RECOVERY_REQUIRED precede input processing. Equivalent readable logical state
and the same plan produce identical `ether.dream.v1` results regardless of
durability mode. Dream performs no durability I/O or persistence mutation and
does not include a durability capability in its identity or output.

Historical standalone T5 `e8c45b8fde108e3d50241d8dd30c67118e460968` / draft PR24
remains the immutable audit anchor from released v0.6. This reconciliation branch
starts from frozen T4 `bf9808c0222bcf66dea54bafef61e5e846f8957b`; it does not rewrite
or merge the standalone proof. The six production persistence files retain the
historical semantics; the Durable overlap preserves all T1–T4 methods.

All twelve historical capability cases remain active. Additive integration
tests cover inspection/Dream parity, zero captured-backend I/O, stable retries,
authority and once-captured operations. Installed consumers check strict defaults,
explicit recoverable declarations/operations and private API containment.

The reused Round11 probe names preserve their historical boundaries: partial WAL
write, complete WAL write, post-file-sync, post-public-ACK, immediately before
and immediately after rotation HEAD replacement. Semantic markers trigger
termination; a timeout or premature child exit fails. Each scenario requires
stable identity, exactly one effect, a second reopen, unchanged committed retry
tip and truthful internal retry acknowledgement. Junction evidence is mandatory;
negative controls prove missing evidence cannot yield a passing native gate.

Final freeze requires clean Node22/24 local security/regression/package gates,
four standard CI jobs, both dedicated native Windows jobs at the exact candidate
SHA, and fresh independent hostile review with no unresolved material finding.
Raw JSON reports include candidate/runtime identity and checkout cleanliness.
At the frozen T5 checkpoint, package version remained0.6.0 and release metadata,
merging and T6 were excluded. T6 advances only the release identity to0.7.0;
the Windows contract and native proof mechanics above remain unchanged.
