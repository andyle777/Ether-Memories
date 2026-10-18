# Historical CI failure audit — 18 October 2026

The failed Actions entries inspected in this audit belong to intermediate T4
and Round 11 spike commits. Their corrections already exist in released v0.7.0
and current `main`, `edb56d3ce23c8b060346f654fb7007851f1661ba`.
No additional production or workflow change is needed for these failures.

## Scope and count

GitHub's repository Actions API returned **six distinct runs with a latest
conclusion of `failure`**, rather than seven distinct failed runs. Their latest
attempts contain 13 failed jobs across seven distinct job configurations:
Ubuntu/Windows × Node 22/24 packed consumers, Windows Node 22/24 spike preflights,
and the candidate-application job. Rerun attempts are separate executions of the
same run and commit.

The seven most recent failed attempts are listed below, ordered by attempt start
time. Failed job logs were read for every entry, including all four matrix jobs
in each T4 attempt. Dates and times use Australia/Sydney (AEDT, UTC+11).

| Attempt started | Run / attempt | Commit | Failed jobs and diagnosis |
| --- | --- | --- | --- |
| 17 Oct 2026, 13:59 | [37725749917 / 2](https://github.com/andyle777/ether-memories/actions/runs/37725749917/attempts/2) | `4c109e5` | Windows 22: native Unicode assertion abort; Windows 24: intentionally RED recoverable-open assertion. |
| 16 Oct 2026, 12:14 | [38048351967 / 3](https://github.com/andyle777/ether-memories/actions/runs/38048351967/attempts/3) | `9be2fcb` | All four standard matrix jobs: stale packed-consumer assertion. |
| 16 Oct 2026, 12:08 | [38048351967 / 2](https://github.com/andyle777/ether-memories/actions/runs/38048351967/attempts/2) | `9be2fcb` | Same four packed-consumer failures at the same historical commit. |
| 10 Oct 2026, 22:25 | [38048351967 / 1](https://github.com/andyle777/ether-memories/actions/runs/38048351967/attempts/1) | `9be2fcb` | Same four packed-consumer failures in the original execution. |
| 8 Oct 2026, 15:35 | [37728205951 / 1](https://github.com/andyle777/ether-memories/actions/runs/37728205951/attempts/1) | `d47df57` | PR-triggered spike: Windows 22 Unicode abort; Windows 24 expected RED assertion. |
| 8 Oct 2026, 15:35 | [37728202532 / 1](https://github.com/andyle777/ether-memories/actions/runs/37728202532/attempts/1) | `d47df57` | Guarded candidate codemod: expected two receipt-confirmation matches, found three. |
| 8 Oct 2026, 15:35 | [37728202425 / 1](https://github.com/andyle777/ether-memories/actions/runs/37728202425/attempts/1) | `d47df57` | Push-triggered spike: same Windows 22/24 preflight failures. |

The additional failed run [37725754992](https://github.com/andyle777/ether-memories/actions/runs/37725754992)
at `4c109e5` has the same Windows 22/24 preflight failures. Both job logs were also
read, covering all six distinct failed runs' latest attempts.

## Root causes and existing repairs

### 1. Packed-consumer gate still expected the pre-T4 API

At `9be2fcb`, `scripts/verify-packed-consumer.mjs` asserted
`core.runDreamCycle === undefined`, although T4 had implemented that method.
Each matrix job passed installation, the security baseline, typecheck, the test
suite, worker-exit verification, build and pack, then failed in `consumer.mjs`
with actual `[Function: runDreamCycle]` versus expected `undefined`.

Commit [bf9808c](https://github.com/andyle777/ether-memories/commit/bf9808c0222bcf66dea54bafef61e5e846f8957b)
updated the gate to exercise deterministic, read-only analysis on Core and the
Durable facade, added declaration and exact 32-runtime-export checks, and
retained private-helper containment checks. That commit is an ancestor of current `main`.
Removing `runDreamCycle` or weakening package containment would undo the release
contract.

### 2. The old Windows preflight was a RED implementation probe

The Node 24 jobs reached the explicit assertion
`EXPECTED RED: recoverable Windows profile is not implemented yet.` Native strict
open correctly refused with `DURABILITY_UNAVAILABLE`; the intermediate spike did
not yet implement the requested recoverable profile.

The Node 22 jobs stopped earlier, after junction observation, with
`Assertion failed: code_point < 0x10FFFF` in libuv's `idna.c`. The old preflight
interpolated U+10FFFF into the child command-line source. The maintained
`scripts/round11-windows-native-probe.mjs` constructs that character inside the
child, records child status/stderr, and preserves the parent report. Production
path validation also refuses that problematic path case before I/O.
Directory-sync and held-destination `EPERM` observations in these logs are
filesystem capability measurements; the terminal errors above explain the
failed jobs.

Historical commit [e8c45b8](https://github.com/andyle777/ether-memories/commit/e8c45b8fde108e3d50241d8dd30c67118e460968)
replaced the RED workflow and preflight with explicit Windows recoverability
implementation and native proof. The canonical release lineage reconciled that
behavior onto frozen T4 in [0ce928c](https://github.com/andyle777/ether-memories/commit/0ce928cb65f784d1aebf02043f7e6f00d536aeb5)
and revalidated native proof and packed containment in
[f4c6a94](https://github.com/andyle777/ether-memories/commit/f4c6a94927cb9226252a55adb4ae7cca123c4a1b).
The old RED workflow/preflight are absent from current `main`.

Strict remains the default and fails closed where its barriers cannot be
established. Explicit recoverable mode retains the existing process-termination
scope; it does not promise power-loss durability or automatic writer-lock
takeover. See [Windows process recoverability](t5-windows-recoverability.md).

### 3. Candidate codemod failed its literal-count guard

The `Apply guarded T5 codemod` step failed in
`scripts/round11-apply-t5-production-patch.mjs:53`:
`src/persistence/FsWalStore.ts: expected 2 receipt confirmation literals, found 3`.
The broad text replacement matched an additional confirmation occurrence.
The guard refused to continue; typecheck, tests, build and candidate commit were
skipped. This was a candidate-construction failure, not a failed verified release.

The obsolete workflow and codemod were removed in historical `e8c45b8`.
Current `main` contains the reconciled, reviewed implementation and neither file.
Changing the guard to three or restoring the auto-patching workflow would rerun
an obsolete implementation approach outside the frozen release architecture.

## Current evidence and disposition

At audit time, [main CI run 38837036076](https://github.com/andyle777/ether-memories/actions/runs/38837036076)
at `edb56d3ce23c8b060346f654fb7007851f1661ba` passed all four Ubuntu/Windows ×
Node 22/24 jobs on 16 October. Every job passed the full existing gate chain,
including the packed consumer. The frozen T6 candidate's
[native Windows run 38178427434](https://github.com/andyle777/ether-memories/actions/runs/38178427434)
also passed both Node versions.

Fresh local checks on 18 October used native Windows, Node 24.19.0 and npm
11.17.0 in an isolated checkout of that `main` revision. Exact-lockfile
installation, toolchain verification, typecheck, all 1,039 tests across 41 files,
worker-exit verification, build, pack and the isolated packed consumer passed.
The consumer verified 130 files, 32 runtime exports, 64 blocked internal modules,
declarations, strict Windows refusal and explicit recoverable operations. Local
Node 22 was not rerun; its evidence above comes from GitHub Actions. The audit
document's relative links and whitespace were checked separately.

This audit adds documentation only. Frozen T6
`64fb0198f70f4e3bace22e5c6f1f19eeba263676`, release/tag integration
`17a452ab7356092aa3b84edb1708f8a6688effa6`, package/dependency versions, protocol
formats, five frozen fixtures, source and workflows remain unchanged.
See the [release manifest](../RELEASE-MANIFEST.md).

Rerunning an old Actions entry reuses its historical revision; it cannot pick up
later repairs. Validate the current branch with a new CI run. Preserve the failed
entries as audit evidence and leave frozen branches/tags unchanged. A passing new
PR run verifies its own revision without changing any historical conclusion.
No merge is performed by this audit.
