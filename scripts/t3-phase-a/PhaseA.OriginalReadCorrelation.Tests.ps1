$ErrorActionPreference='Stop'
. "$PSScriptRoot/PhaseA.Stage3.ps1"
$expected=@{experiment=('a'*32);nonce=('b'*32);pid=4242;createdAt='2026-11-17T00:00:00.0000000Z';sid='S-1-5-21-101-202-303-1001';authenticationId='0000000000001234';targetId='protectedFile';fileId=('c'*32);actorOutcome='ALLOWED'}
$candidate=$expected.Clone();$candidate.source='INJECTED';$candidate.recordId=1001;$candidate.completed=$true;$candidate.eventLoss=$false;$candidate.nativeOutcome='ALLOWED';$candidate.eventKind='READ';$candidate.requestedBytes=10;$candidate.completedBytes=10
$baseline=Get-PhaseAOriginalReadCorrelation $expected $candidate @()
if($baseline.status -cne 'UNVERIFIED' -or $baseline.reason -cne 'INJECTED_MATCH_NOT_PROOF'){throw 'SYNTHETIC_READ_PROMOTED'}
foreach($spec in @(@('pid',4343,'PROCESS_MISMATCH'),@('createdAt','2026-11-17T00:00:01.0000000Z','PROCESS_MISMATCH'),@('experiment',('d'*32),'EXPERIMENT_MISMATCH'),@('nonce',('e'*32),'NONCE_MISMATCH'),@('sid','S-1-5-21-101-202-303-1002','TOKEN_MISMATCH'),@('authenticationId','0000000000004321','TOKEN_MISMATCH'),@('targetId','controlFile','TARGET_MISMATCH'),@('fileId',('f'*32),'TARGET_MISMATCH'),@('completed',$false,'COMPLETION_MISSING'),@('eventLoss',$true,'EVENT_LOSS'),@('nativeOutcome','DENIED','CONTRADICTORY_OBSERVATION'))){
 $bad=$candidate.Clone();$bad[$spec[0]]=$spec[1];$result=Get-PhaseAOriginalReadCorrelation $expected $bad @()
 if($result.status -cne 'UNVERIFIED' -or $result.reason -cne $spec[2]){throw ('WRONG_REJECTION_'+$spec[0]+'_'+$result.reason)}
}
$result=Get-PhaseAOriginalReadCorrelation $expected $candidate @(1001)
if($result.reason -cne 'REPLAYED_EVENT'){throw 'REPLAY_NOT_REJECTED'}
$result=Get-PhaseAOriginalReadCorrelation $expected $null @()
if($result.reason -cne 'INDEPENDENT_OBSERVATION_MISSING'){throw 'MISSING_EVENT_NOT_REJECTED'}
$bad=$candidate.Clone();$bad.source='LIVE';$result=Get-PhaseAOriginalReadCorrelation $expected $bad @()
if($result.reason -cne 'TRUSTED_COLLECTOR_NOT_CONNECTED'){throw 'RELABELLED_LIVE_NOT_REJECTED'}
Write-Output 'PASS original read candidate rejection reasons; no synthetic proof'
