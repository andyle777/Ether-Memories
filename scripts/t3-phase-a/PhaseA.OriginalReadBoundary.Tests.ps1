$ErrorActionPreference='Stop'
. "$PSScriptRoot/PhaseA.Stage3.ps1"
$expected=@{experiment=('a'*32);nonce=('b'*32);pid=4242;createdAt='2026-11-17T00:00:00Z';sid='S-1-5-21-1';authenticationId='1';targetId='protectedFile';fileId=('c'*32);actorOutcome='ALLOWED'}
$candidate=$expected.Clone(); $candidate.source='INJECTED'; $candidate.recordId=1; $candidate.completed=$true; $candidate.eventLoss=$false; $candidate.nativeOutcome='ALLOWED'; $candidate.eventKind='OPEN'; $candidate.requestedBytes=1; $candidate.completedBytes=1
$r=Get-PhaseAOriginalReadCorrelation $expected $candidate @()
if($r.status -cne 'UNVERIFIED' -or $r.reason -cne 'READ_OPERATION_MISSING'){ throw "OPEN_ONLY_NOT_REJECTED_AS_READ:$($r.reason)" }
Write-Output 'PASS open is not read'
$candidate.eventKind='READ'; $candidate.requestedBytes=8; $candidate.completedBytes=8
$r=Get-PhaseAOriginalReadCorrelation $expected $candidate @()
if($r.status -cne 'UNVERIFIED' -or $r.reason -cne 'INJECTED_MATCH_NOT_PROOF'){throw 'INJECTED_READ_PROMOTED'}
$candidate.completedBytes=9
$r=Get-PhaseAOriginalReadCorrelation $expected $candidate @()
if($r.reason -cne 'INVALID_READ_COMPLETION'){throw 'IMPOSSIBLE_BYTE_COUNT_ACCEPTED'}
$candidate.completedBytes=0; $candidate.requestedBytes=0
$r=Get-PhaseAOriginalReadCorrelation $expected $candidate @()
if($r.reason -cne 'INVALID_READ_COMPLETION'){throw 'ZERO_REQUEST_ACCEPTED'}
$candidate.requestedBytes=1; $candidate.nativeOutcome='DENIED'; $expected.actorOutcome='DENIED'
$r=Get-PhaseAOriginalReadCorrelation $expected $candidate @()
if($r.status -cne 'UNVERIFIED' -or $r.reason -cne 'DENIAL_NOT_INDEPENDENTLY_OBSERVED'){throw 'DENIAL_PROMOTED'}
Write-Output 'PASS injected byte bounds and denial remain unverified'
