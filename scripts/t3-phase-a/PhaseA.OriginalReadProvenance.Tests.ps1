$ErrorActionPreference='Stop'
. "$PSScriptRoot/PhaseA.Entry.Tests.ps1"
$record=$wResult.evidence.unauthorizedRead
if(-not $record.ContainsKey('originalReadEvidence')){throw 'ORIGINAL_READ_PROVENANCE_MISSING'}
if($record.originalReadEvidence.status -cne 'UNVERIFIED' -or $record.originalReadEvidence.reason -cne 'INDEPENDENT_OBSERVATION_MISSING'){throw 'SELF_REPORTED_READ_PROMOTED'}
if($record.originalReadEvidence.kind -cne 'ORIGINAL_ACTOR_READ' -or $record.witness.status -cne 'OBSERVED'){throw 'ORIGINAL_AND_SEPARATE_WITNESS_CONFLATED'}
Write-Output 'PASS original actor read remains distinct and unverified'
