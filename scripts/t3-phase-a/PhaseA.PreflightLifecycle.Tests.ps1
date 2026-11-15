$ErrorActionPreference='Stop'
. "$PSScriptRoot/PhaseA.Core.ps1"
$journal=New-Object 'System.Collections.Generic.List[object]'
$result=Invoke-PhaseAGit $PSScriptRoot 'rev-parse --is-inside-work-tree' $journal
if($journal.Count -ne 1){throw 'PREFLIGHT_RECORD_MISSING'}
$r=$journal[0]
if($r.role -cne 'CHECKOUT_PREFLIGHT' -or $r.launch -cne 'CREATED' -or $r.pid -le 0 -or $r.createdAt -notmatch '^\d{4}-' -or $r.wait -cne 'SIGNALED' -or $r.managedDispose -cne 'DISPOSE_RETURNED'){throw 'PREFLIGHT_OBSERVATION_INCOMPLETE'}
if($r.nativeClose -cne 'NOT_OBSERVED'){throw 'MANAGED_DISPOSAL_CLAIMED_NATIVE_CLOSE'}
$before=$journal.Count
$null=Invoke-PhaseAGit (Join-Path $PSScriptRoot 'nonexistent-directory-for-preflight') 'status' $journal
if($journal.Count -ne ($before+1) -or $journal[1].launch -cne 'FAILED' -or $null -ne $journal[1].pid){throw 'PREFLIGHT_FAILED_LAUNCH_NOT_RETAINED'}
$fake=[pscustomobject]@{StartInfo=$null;Id=123;StartTime=[datetime]::UtcNow;ExitCode=0;StandardOutput=$null;StandardError=$null;waitCount=0;disposed=$false}
$stream=New-Object psobject
$stream | Add-Member ScriptMethod ReadToEndAsync { [Threading.Tasks.Task]::FromResult('') }
$fake.StandardOutput=$stream;$fake.StandardError=$stream
$fake | Add-Member ScriptMethod Start { $true }
$fake | Add-Member ScriptMethod WaitForExit { param($ms) $this.waitCount++;$false }
$fake | Add-Member ScriptMethod Kill { }
$fake | Add-Member ScriptMethod Dispose { $this.disposed=$true }
$factory={return $fake}.GetNewClosure();$probe=New-Object 'System.Collections.Generic.List[object]'
$null=Invoke-PhaseAGit $PSScriptRoot 'status' $probe $factory
if($probe.Count -ne 1 -or $probe[0].wait -cne 'UNCONFIRMED' -or $probe[0].managedDispose -cne 'RETAINED' -or $fake.disposed){throw 'PREFLIGHT_UNCONFIRMED_PROCESS_NOT_RETAINED'}
$attempt='aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
$fake.waitCount=0;$fake.disposed=$false
$fake | Add-Member -Force ScriptMethod WaitForExit { param($ms) $true }
$observer={param($pidValue) @{pid=$pidValue;createdAt=$fake.StartTime.ToUniversalTime().ToString('o')}}.GetNewClosure()
$observations=New-Object 'System.Collections.Generic.List[object]'
$null=Invoke-PhaseAGit $PSScriptRoot 'status' $observations $factory $attempt 'HEAD' 0 $observer
if($observations[0].experiment -cne $attempt -or $observations[0].operation -cne 'HEAD' -or $observations[0].identity -cne 'MATCHED' -or $observations[0].exitCode -ne 0 -or -not $observations[0].waitAttempted -or $observations[0].firstWait -cne 'SIGNALED' -or -not $observations[0].exitObserved){throw 'MANAGER_PROCESS_RECORD_INCOMPLETE'}
if(-not (Test-PhaseAPreflightJournal $observations $attempt @('HEAD'))){throw 'MANAGER_PROCESS_RECORD_REJECTED'}
$wrong=$observations[0].Clone();$wrong.observedPid=124
if(Test-PhaseAPreflightJournal @($wrong) $attempt @('HEAD')){throw 'WRONG_PID_ACCEPTED'}
$wrong=$observations[0].Clone();$wrong.observedCreatedAt='2000-01-01T00:00:00Z'
if(Test-PhaseAPreflightJournal @($wrong) $attempt @('HEAD')){throw 'WRONG_TIME_ACCEPTED'}
if(Test-PhaseAPreflightJournal @($observations[0],$observations[0]) $attempt @('HEAD')){throw 'DUPLICATE_ACCEPTED'}
if(Test-PhaseAPreflightJournal $observations ('b'*32) @('HEAD')){throw 'STALE_ATTEMPT_ACCEPTED'}
if(Test-PhaseAPreflightJournal @() $attempt @('HEAD')){throw 'MISSING_RECORD_ACCEPTED'}
$second=$observations[0].Clone();$second.sequence=1;$second.operation='ANCESTOR';$second.attempt='cccccccccccccccccccccccccccccccc'
if(Test-PhaseAPreflightJournal @($second,$observations[0]) $attempt @('HEAD','ANCESTOR')){throw 'REORDER_ACCEPTED'}
$wrong=$observations[0].Clone();$wrong.wait='UNCONFIRMED'
if(Test-PhaseAPreflightJournal @($wrong) $attempt @('HEAD')){throw 'CONTRADICTORY_WAIT_ACCEPTED'}
$fake | Add-Member -Force ScriptMethod WaitForExit { param($ms) throw 'injected wait failure' }
$fake.disposed=$false;$failed=New-Object 'System.Collections.Generic.List[object]'
$r=Invoke-PhaseAGit $PSScriptRoot 'status' $failed $factory $attempt 'HEAD' 0 $observer
if($null -ne $r -or $failed[0].wait -cne 'UNCONFIRMED' -or $failed[0].managedDispose -cne 'RETAINED' -or $fake.disposed){throw 'WAIT_FAILURE_RELEASED_PROCESS'}
$fake | Add-Member -Force ScriptMethod WaitForExit { param($ms) $true }
$fake | Add-Member -Force ScriptMethod Dispose { throw 'injected disposal failure' }
$failed=New-Object 'System.Collections.Generic.List[object]'
$r=Invoke-PhaseAGit $PSScriptRoot 'status' $failed $factory $attempt 'HEAD' 0 $observer
if($null -ne $r -or $failed[0].managedDispose -cne 'FAILED'){throw 'DISPOSAL_FAILURE_NOT_RETAINED'}
$failed=New-Object 'System.Collections.Generic.List[object]'
try{$null=Invoke-PhaseAGit $PSScriptRoot 'status' $failed {throw 'synthetic factory error'} $attempt 'HEAD' 0 $observer}catch{}
if($failed.Count -ne 1 -or $failed[0].launch -cne 'FAILED' -or $null -ne $failed[0].pid){throw 'PROCESS_FACTORY_FAILURE_NOT_RETAINED'}
$fake | Add-Member -Force ScriptMethod Dispose { $this.disposed=$true }
$failed=New-Object 'System.Collections.Generic.List[object]'
$null=Invoke-PhaseAGit $PSScriptRoot 'status' $failed $factory $attempt 'HEAD' 0 {param($id) throw 'process already exited'}
if($failed[0].identity -cne 'UNAVAILABLE' -or (Test-PhaseAPreflightJournal $failed $attempt @('HEAD'))){throw 'MISSING_IDENTITY_ACCEPTED'}
foreach($kind in @('wrongPid','wrongTime')){
  $script:badKind=$kind;$badObserver={param($id) @{pid=$(if($script:badKind -ceq 'wrongPid'){$id+1}else{$id});createdAt=$(if($script:badKind -ceq 'wrongTime'){'2000-01-01T00:00:00Z'}else{$fake.StartTime.ToUniversalTime().ToString('o')})}}.GetNewClosure()
  $mismatch=New-Object 'System.Collections.Generic.List[object]'
  $null=Invoke-PhaseAGit $PSScriptRoot 'status' $mismatch $factory $attempt 'HEAD' 0 $badObserver
  if($mismatch[0].identity -cne 'MISMATCH' -or (Test-PhaseAPreflightJournal $mismatch $attempt @('HEAD'))){throw ('OBSERVED_IDENTITY_MISMATCH_ACCEPTED_'+$kind)}
}
$priorAttempt=$observations[0].attempt
try{$null=Invoke-PhaseAGit $PSScriptRoot 'status' $observations {throw 'later error'} $attempt 'ANCESTOR' 1 $observer}catch{}
if($observations.Count -ne 2 -or $observations[0].attempt -cne $priorAttempt -or $observations[0].identity -cne 'MATCHED' -or $observations[1].launch -cne 'FAILED'){throw 'EARLIER_PREFLIGHT_RECORD_LOST'}
$fake | Add-Member -Force ScriptMethod WaitForExit { param($ms) $false }
$checkoutJournal=New-Object 'System.Collections.Generic.List[object]'
$passed=Test-PhaseACheckout $PSScriptRoot ('a'*40) ('b'*40) $checkoutJournal $factory $observer
if($passed -or $checkoutJournal.Count -ne 1 -or $checkoutJournal[0].wait -cne 'UNCONFIRMED'){throw 'UNCONFIRMED_PREFLIGHT_ACCEPTED'}
Write-Output 'PASS preflight lifecycle producer'
