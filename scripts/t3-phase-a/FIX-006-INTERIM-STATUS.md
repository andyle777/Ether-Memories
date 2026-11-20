# FIX_006 — Interim historical authority and acceptance reconciliation

Status: **INCOMPLETE** — research checkpoint only; not an adopted acceptance contract.

## Pinned baseline

- Repository: `andyle777/Ether-Memories`
- Branch: `fix/t3-gate-b1-reproducible-build`
- Research baseline (published Checkpoint 3): `2a6ee20fbf1142e06813278916dbcf9ac221596a`
- Baseline tree: `12a99e1f14dffd71a8ae54cf3ce9f83f2a887438`
- Standard CI at that baseline: [run 44693307606, attempt 1](https://github.com/andyle777/Ether-Memories/actions/runs/44693307606), four matrix jobs successful.
- Baseline runtime reproducibility: previously verified 26 retained pins. This documentation checkpoint does not modify or repin them.

## Interim historical research (reported, not independently authenticated)

The current research report identifies B2.1 as a proposed HEAD v2 design with a 14-case acceptance matrix explicitly not frozen. B2.2 is reported as proposed and not owner-approved; subsequent broader B2.4 disposition wording is reported as AMBER and unfrozen.

A narrower B2.4 authorization is reported to select a dormant admission candidate while preserving public HEAD v1 behavior. It does not establish approval of HEAD v2 activation, release, or the broader deferred dispositions. Reported narrower historical decisions remain research leads pending reconciliation with original decision records.

These summaries do not authenticate the original historical contract, establish the authority of individual provisions, or exclude missing historical obligations. Private source records and their local manifests are intentionally not published.

## Independently inspected source at the pinned baseline

- [Provisional policy and verdict evaluator](https://github.com/andyle777/Ether-Memories/blob/2a6ee20fbf1142e06813278916dbcf9ac221596a/scripts/t3-phase-a/PhaseA.Verdict.ps1): 30 provisional controls; missing/untrusted evidence and cleanup prerequisites can yield UNVERIFIED before evaluation of an overall RED result (lines 35–64). The implications for preserving verified violations require further contract adjudication.
- [Evidence map](https://github.com/andyle777/Ether-Memories/blob/2a6ee20fbf1142e06813278916dbcf9ac221596a/scripts/t3-phase-a/EVIDENCE-MAP.md): documentary counts of 13 Connected, 6 Partial, 11 Missing. These are not LIVE control results.
- [Evidence adapters and verifier](https://github.com/andyle777/Ether-Memories/blob/2a6ee20fbf1142e06813278916dbcf9ac221596a/scripts/t3-phase-a/PhaseA.Evidence.ps1): verifier recognition covers 19 control identifiers; the actor adapter returns early for LIVE_OBSERVED (lines 39–42), and the Stage 3 adapter returns before original-access verdict processing for LIVE_OBSERVED (lines 352–373). Other evidence paths exist and their completeness and reachability remain to be reconciled. Do not remove these trust guards to manufacture acceptance.
- [Manager](https://github.com/andyle777/Ether-Memories/blob/2a6ee20fbf1142e06813278916dbcf9ac221596a/scripts/t3-phase-a/Invoke-PhaseA.ps1): invokes the adapters with LIVE_OBSERVED and sets ownerAuthorizationVerified to false (lines 78–91). Contract adoption and execution authorization remain distinct.

## Next bounded research work

1. Locate and authenticate original owner decision records; complete the relevant authorized history, review and archive searches. Distinguish recovered content, adoption, applicability and disputes.
2. Reconcile all 30 provisional identifiers across policy, documentation, verifier recognition, producers, manager integration, tests and potential LIVE paths. Preserve unknowns and counterevidence.
3. Resolve the FIX_006 V3 contract questions, including violation preservation during incomplete cleanup, and compare any proposed changes against authenticated obligations.
4. Prepare a versioned, digest-bound prospective acceptance proposal (or authenticated historical contract reconciliation), a minimal dependency roadmap and an independent review packet. Owner adoption is a separate decision.

No implementation, contract adoption, or security experiment is authorized by this record.

## Dispositions at the research baseline

| Gate | Disposition |
| --- | --- |
| Baseline identity | GREEN |
| Search process | INCOMPLETE |
| Historical content | PARTIAL |
| Historical adoption | PARTIAL; not fully authenticated |
| Provisional control inventory | Reconciled against policy and documentation; producer and LIVE sets partial |
| Evidence package | INCOMPLETE |
| Independent review | PENDING |
| Owner adoption | PENDING_OWNER_DECISION |
| FIX_006 | INCOMPLETE |
| Prototype child reconciliation | UNKNOWN |
| Native worker execution | HOLD |
| Native stall verification | BLOCKED_ENVIRONMENT |
| Independent startup / descendant accounting / aggregate watchdog | NOT_GREEN |
| FIX_005 overall | BLOCKED |
| Gate B1 hosted feasibility / cross-identity security | UNVERIFIED |
| Historical RED authentication / power-loss durability | UNVERIFIED |
| Coordinated rollback protection | UNSUPPORTED |
| T3 security acceptance | HOLD |
| Official release | NOT_AUTHORIZED |

This record is a documentation-only progress snapshot. It does not alter the pinned research baseline or establish new execution evidence. Standard CI, synthetic verification and documentary bridge counts cannot substitute for authorized LIVE security observations.
