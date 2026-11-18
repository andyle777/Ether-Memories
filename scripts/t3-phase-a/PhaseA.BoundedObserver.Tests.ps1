$ErrorActionPreference='Stop'
. "$PSScriptRoot/PhaseA.Stage2.ps1"
if(-not (Get-Command Invoke-PhaseABoundedObserverActor -ErrorAction SilentlyContinue)){throw 'BOUNDED_ADAPTER_MISSING'}
$script:calls=New-Object 'System.Collections.Generic.List[string]'
$backend=@{Run={param($a,$t,$op,$target) $script:calls.Add($target); return @{expectedSid=$a.sid;observedSid=$a.sid;reportedSid=$a.sid;expectedPid=123;reportedPid=123;tokenNonAdmin=$true;tokenObserved=$true;createdAt='2026-01-01T00:00:00Z';observedCreatedAt='2026-01-01T00:00:00Z';expectedNonce='n';reportedNonce='n';exitCode=$(if($target -ceq 'control'){0}else{20});outcome=$(if($target -ceq 'control'){'allowed'}else{'denied'});role=$a.role;contained=$true;terminated=$true}}}
$a=@{role='legacy';sid='S-1-5-21-2'};$t=@{sid=$a.sid}
$result=Invoke-PhaseABoundedObserverActor $a $t $backend @{controlFile='control';protectedFile='protected'} 'INJECTED'
if($result.status -cne 'UNVERIFIED' -or $script:calls.Count -ne 2 -or $script:calls[0] -cne 'control' -or $script:calls[1] -cne 'protected'){throw 'BOUNDED_PATH_FAILED'}
try {$null=Invoke-PhaseABoundedObserverActor $a $t $backend @{controlFile='control';protectedFile='protected'} 'LIVE';throw 'LIVE_PATH_ENABLED'} catch {if($_.Exception.Message -cne 'OBSERVER_LIVE_DISABLED'){throw}}
if($script:calls.Count -ne 2){throw 'LIVE_BACKEND_CALLED'}
$failed=@{Run={param($a,$t,$op,$target) throw 'STAGE2_CHILD_UNCONFIRMED'}}
try {$null=Invoke-PhaseABoundedObserverActor $a $t $failed @{controlFile='control';protectedFile='protected'} 'INJECTED';throw 'CHILD_FAILURE_SWALLOWED'}catch{if($_.Exception.Message -cne 'STAGE2_CHILD_UNCONFIRMED'){throw}}
Write-Output 'PASS bounded injected actor path; live disabled; child failure propagated'
