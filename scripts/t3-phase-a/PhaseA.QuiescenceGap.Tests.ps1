$ErrorActionPreference='Stop'
. "$PSScriptRoot/PhaseA.Stage3.ps1"
. "$PSScriptRoot/PhaseA.Accounts.ps1"
$root=Join-Path ([IO.Path]::GetTempPath()) ('ether-phase-a-store-'+[guid]::NewGuid().ToString('N'))
$parent=[IO.Path]::GetDirectoryName($root)
$protected=Join-Path $root 'protected';$control=Join-Path $root 'control'
$fixture=@{root=$root;parent=$parent;protectedDir=$protected;controlDir=$control;protectedFile=(Join-Path $protected 'original.bin');controlFile=(Join-Path $control 'original.bin');newFile=(Join-Path $protected 'committed.bin');aclInspected=$true;initialDigest='synthetic'}
$calls=@{cleanup=0}
$backend=@{Setup={param($a,$e,$o,$co) $e['earlierViolation']=@{state='FAIL';proof='retained'};return $fixture}.GetNewClosure(); Exists={param($p) return ($p -cne $fixture.newFile)}.GetNewClosure();Digest={param($p) 'synthetic'};CleanupObservation={param($f,$phase) throw 'cleanup observation must not execute'};Cleanup={param($f) $calls.cleanup++}.GetNewClosure()}
$actor=@{Run={param($a,$t,$op,$path) throw 'STAGE2_CLEANUP_FAILED'}}
$accounts=@(@{sid='S-1-5-21-1';role='broker'},@{sid='S-1-5-21-2';role='legacy'})
$tokens=@(@{sid='S-1-5-21-1'},@{sid='S-1-5-21-2'})
$sink=@{}; $caught='';try {$null=Invoke-PhaseAStage3 $accounts $tokens $backend $actor $sink}catch{$caught=$_.Exception.GetBaseException().Message}
if($calls.cleanup -ne 0){throw 'QUIESCENCE_GAP_CLEANUP_CALLED_AFTER_HANDLE_CLEANUP_FAILURE'}
if($caught -cne 'STAGE2_RESOURCE_UNCONFIRMED' -or $sink.evidence.cleanupVerified){throw 'QUIESCENCE_GAP_SIGNAL_NOT_PROPAGATED'}
if($sink.evidence.fixtureCleanup.reason -cne 'PROCESS_CLEANUP_FAILED' -or $sink.evidence.fixtureCleanup.authorized -or $sink.evidence.fixtureCleanup.attempted){throw 'QUIESCENCE_GAP_FAILURE_NOT_RETAINED'}
$backend['DirectoryExists']={param($p) $true};$backend['Probe']={param($token,$sid,$operation,$path,$root) throw 'WITNESS_CLEANUP_FAILED'}
$sink=@{}; $caught='';try {$null=Invoke-PhaseAStage3 $accounts $tokens $backend $actor $sink}catch{$caught=$_.Exception.GetBaseException().Message}
if($calls.cleanup -ne 0 -or $caught -cne 'STAGE2_RESOURCE_UNCONFIRMED' -or $sink.evidence.fixtureCleanup.reason -cne 'PROCESS_CLEANUP_FAILED'){throw 'WITNESS_CLEANUP_GAP'}
$cleanupCalls=@{close=0;remove=0}
$accountBackend=@{Create={param($role) @{role=$role;sid=$(if($role -ceq 'broker'){'S-1-5-21-1'}else{'S-1-5-21-2'})}};Authenticate={param($a) @{sid=$a.sid;primary=$true;admin=$false;elevated=$false;standard=$true}};Close={param($t) $cleanupCalls.close++}.GetNewClosure();Remove={param($a) $cleanupCalls.remove++}.GetNewClosure()}
$sink=@{};$use={param($a,$t) Invoke-PhaseAStage3 $a $t $backend $actor $sink}.GetNewClosure()
$accountResult=Invoke-PhaseAAccountGate $true $accountBackend $use
if($accountResult -cne 'ACCOUNT_CLEANUP_FAILED' -or $cleanupCalls.close -ne 0 -or $cleanupCalls.remove -ne 0){throw 'UNCONFIRMED_RESOURCE_ACCOUNT_CLEANUP'}
if($sink.evidence.earlierViolation.proof -cne 'retained' -or $sink.evidence.fixtureCleanup.reason -cne 'PROCESS_CLEANUP_FAILED'){throw 'EARLIER_EVIDENCE_LOST'}
Write-Output 'PASS cleanup withheld on process resource cleanup failure'
. "$PSScriptRoot/PhaseA.InventoryBridge.Tests.ps1"
$fakeState.created=$false;$fakeState.mutated=$false;$script:sequence=0;$script:cleanupEvents=New-Object 'System.Collections.Generic.List[string]'
$resourceFailActors=@{Run={param($a,$t,$op,$target) if($a.role -ceq 'legacy' -and $op -ceq 'Overwrite'){throw 'STAGE2_CLEANUP_FAILED'};$r=& $originalRun $a $t $op $target;if($a.role -ceq 'legacy' -and $op -ceq 'Read' -and $target -ceq $fakeFixture.protectedFile){$fakeState.mutated=$true};return $r}.GetNewClosure()}
$records=New-Object 'System.Collections.Generic.List[object]';$wrapped=New-PhaseAActorJournalBackend $resourceFailActors $records;$sink=@{}
$status=Invoke-PhaseAStages $true $true $accountBackend $wrapped $true $failingFixture $sink
$verdict=New-PhaseAManagerVerdictInput ('1'*40) '123';Add-PhaseAStage3Evidence $verdict $sink.evidence 'SIMULATED_PASS' $records.ToArray()
if($status -cne 'ACCOUNT_CLEANUP_FAILED' -or $script:cleanupEvents.Count -ne 0 -or $verdict.cases.protectedInventory.state -cne 'FAIL'){throw 'VERIFIED_VIOLATION_OR_RESOURCES_LOST'}
Write-Output 'PASS inventory violation retained across resource cleanup failure'
