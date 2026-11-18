$ErrorActionPreference='Stop'
. "$PSScriptRoot/PhaseA.Tests.ps1"
$verdict=New-PhaseAManagerVerdictInput ('1'*40) '123'
Add-PhaseAStage3Evidence $verdict $fs 'LIVE_OBSERVED' $journal.ToArray()
if($verdict.cases.unauthorizedWrite.state -cne 'NOT_RUN'){throw ('INJECTED_ACTOR_RELABELLED_AS_LIVE_'+$verdict.cases.unauthorizedWrite.state)}
Write-Output 'PASS untrusted actor journal cannot establish LIVE violation'
