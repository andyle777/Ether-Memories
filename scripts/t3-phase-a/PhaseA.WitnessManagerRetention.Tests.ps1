$ErrorActionPreference='Stop'
. "$PSScriptRoot/PhaseA.Entry.Tests.ps1"
foreach($failureKind in @('WITNESS_CLEANUP_FAILED','STAGE2_CHILD_UNCONFIRMED')){
foreach($spec in @(@('Read','existing','protectedFile','unauthorizedRead'),@('Overwrite','existing','protectedFile','unauthorizedWrite'),@('Create','missing','deniedFile','unauthorizedCreate'))){
$script:events.Clear();$script:seq=0;$script:created3=$false;$script:probeAuthorized=$false;$script:probeControl=$false;$script:stage3events.Clear()
$managerFixture=$wFixture.Clone();$originalProbe=$wFixture.Probe;$expectedOperation=$spec[0];$expectedPath=$spec[1];$expectedTarget=$spec[2];$control=$spec[3]
$managerFixture.Probe={param($token,$sid,$op,$path,$root)
 if($sid -ceq 'S-1-5-21-2' -and $op -ceq $expectedOperation -and $path -ceq $expectedPath){
  $e=New-Object InvalidOperationException($failureKind)
  $e.Data['PhaseAWitnessOutcome']=@{operation=$op;target=$expectedTarget;allowed=$true;nativeError=0;source='INJECTED'}
  throw $e
 }
 & $originalProbe $token $sid $op $path $root
}.GetNewClosure()
$stageSink=@{};$result=Invoke-PhaseAStages $true $true $fake $wActors $true $managerFixture $stageSink
if($result -cne 'ACCOUNT_CLEANUP_FAILED'){throw ('MANAGER_RESOURCE_GATE_FAILED_'+$result)}
if($script:events.Contains('close:broker') -or $script:events.Contains('remove:broker') -or $script:stage3events.Contains('cleanup')){throw 'DEPENDENT_RESOURCES_RELEASED'}
if(-not $stageSink.evidence[$control].witness -or $stageSink.evidence[$control].witness.status -cne 'UNVERIFIED' -or $stageSink.evidence[$control].witness.provisionalOutcome -cne 'ALLOWED'){throw ('MANAGER_DROPPED_PRE_CLEANUP_WITNESS_OBSERVATION_'+$control)}
if($control -ceq 'unauthorizedRead' -and ($stageSink.evidence[$control].originalReadEvidence.status -cne 'UNVERIFIED' -or $stageSink.evidence[$control].originalReadEvidence.reason -cne 'INDEPENDENT_OBSERVATION_MISSING')){throw ('ORIGINAL_READ_GAP_LOST_'+$failureKind)}
$verdict=New-PhaseAManagerVerdictInput ('1'*40) '123';Add-PhaseAStage3Evidence $verdict $stageSink.evidence 'SIMULATED_PASS' $wJournal.ToArray()
if($verdict.cases[$control].state -cin @('PASS','FAIL')){throw ('UNCORROBORATED_OBSERVATION_PROMOTED_'+$control)}
}
}
Write-Output 'PASS manager retains unverified witness outcomes and blocks cleanup for three operations'
