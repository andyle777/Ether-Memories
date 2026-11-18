$ErrorActionPreference='Stop'
. "$PSScriptRoot/PhaseA.Tests.ps1"
$findings=@()
$verdict=New-PhaseAManagerVerdictInput ('1'*40) '123'
Add-PhaseAActorEvidence $verdict $journal.ToArray() 'LIVE_OBSERVED'
if($verdict.cases.actorSidBinding.state -cne 'NOT_RUN'){$findings+=('UNTRUSTED_ACTOR_'+$verdict.cases.actorSidBinding.state)}
foreach($item in $journal){$null=$script:PhaseATrustedActorRecords.Add($item)}
$allowed=$journal[8].observation.Clone();$allowed.errorCategory='NONE';$allowed.errorCode=0;$allowed.digest=('a'*64)
$entry=@{control='unauthorizedWrite';operation='Overwrite';target='protectedFile';accountSid='S-1-5-21-2';tokenSid='S-1-5-21-2';beforeExists=$true;parentExists=$true;beforeInventory=('b'*64);beforeDigest=('a'*64);afterExists=$true;afterInventory=('c'*64);observation=$allowed}
$fs=@{cleanupVerified=$true;unauthorizedWrite=$entry}
$verdict=New-PhaseAManagerVerdictInput ('1'*40) '123'
Add-PhaseAStage3Evidence $verdict $fs 'LIVE_OBSERVED' $journal.ToArray()
if($verdict.cases.unauthorizedWrite.state -cne 'NOT_RUN'){$findings+=('ACTOR_REPORT_WRITE_'+$verdict.cases.unauthorizedWrite.state)}
if($findings.Count){throw ($findings -join ',')}
Write-Output 'PASS uncorroborated actor identity and access FAIL remain NOT_RUN'
