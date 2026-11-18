$ErrorActionPreference='Stop'
if(-not (Test-Path "$PSScriptRoot/PhaseA.EtwLifecycle.cs")){throw 'NATIVE_LIFECYCLE_MISSING'}
Add-Type -Path @("$PSScriptRoot/PhaseA.EtwNative.Preparation.cs","$PSScriptRoot/PhaseA.EtwLifecycle.cs","$PSScriptRoot/PhaseA.EtwLifecycle.TestBackend.cs")
if(-not ('Orion.EtwPrepared.EtwLifecycle' -as [type])){throw 'LIFECYCLE_TYPE_MISSING'}
Write-Output 'PASS lifecycle source compiled'
foreach($case in @(@(0,'SESSION_STOPPED'),@(234,'SESSION_STOPPED_FINAL_STATISTICS_INCOMPLETE'),@(4201,'SESSION_ABSENT_CAUSE_UNKNOWN'),@(2402,'STOP_IN_PROGRESS'),@(5,'STOP_UNCONFIRMED'),@(9999,'STOP_UNCONFIRMED'))) {
 $actual=[Orion.EtwPrepared.EtwLifecycle]::ClassifyStopCode([uint32]$case[0]);if($actual -cne $case[1]){throw ('STOP_CODE_MISMATCH_'+$case[0])}
}
function New-Lifecycle($ops){return [Orion.EtwPrepared.EtwLifecycle]::new($ops,'OrionT3',[guid]::NewGuid(),'C:\synthetic\gate.etl')}
function Assert($condition,$reason){if(-not $condition){throw $reason}}
$o=[EtwTestBackend]::new();$c=New-Lifecycle $o;$c.Start();$c.Query();$c.Stop()
Assert ($c.State.ToString() -ceq 'FINALIZATION_UNVERIFIED' -and $o.StopCalls -eq 1 -and $c.EvidenceClass -ceq 'INJECTED') 'SUCCESS_PATH_FAILED'
foreach($code in @(5,24,183)) {$o=[EtwTestBackend]::new();$o.StartCode=$code;$c=New-Lifecycle $o;$c.Start();$c.Stop();Assert ($o.StopCalls -eq 0 -and $c.OriginalFailure -ceq 'START_FAILED' -and $c.NativeCode -eq $code) 'START_FAILURE_LOST'}
foreach($field in @('WrongId','Replace','WrongSettings')) {$o=[EtwTestBackend]::new();$o.$field=$true;$c=New-Lifecycle $o;$c.Start();$c.Query();$c.Stop();Assert ($o.StopCalls -eq 0 -and $c.State.ToString() -ceq 'OWNERSHIP_UNVERIFIED') ('UNSAFE_STOP_'+$field)}
$o=[EtwTestBackend]::new();$o.QueryCode=5;$c=New-Lifecycle $o;$c.Start();$c.Query();$c.Stop();Assert ($o.StopCalls -eq 0 -and $c.OriginalFailure -ceq 'QUERY_FAILED') 'QUERY_FAILURE_LOST'
$o=[EtwTestBackend]::new();$o.Continuity=$false;$c=New-Lifecycle $o;$c.Start();$c.Query();$c.Stop();Assert ($o.StopCalls -eq 0 -and $c.OriginalFailure -ceq 'CONTINUITY_UNVERIFIED') 'CONTINUITY_BYPASS'
$o=[EtwTestBackend]::new();$o.ReplaceOnSecond=$true;$c=New-Lifecycle $o;$c.Start();$c.Query();$c.Stop();Assert ($o.StopCalls -eq 0 -and $c.State.ToString() -ceq 'OWNERSHIP_UNVERIFIED') 'REPLACEMENT_BEFORE_STOP'
foreach($field in @('EventsLost','BuffersLost')) {$o=[EtwTestBackend]::new();$o.$field=1;$c=New-Lifecycle $o;$c.Start();$c.Query();$c.Stop();Assert ($c.OriginalFailure -ceq 'TRACE_LOSS' -and $c.State.ToString() -cne 'STOP_CONFIRMED') ('LOSS_IGNORED_'+$field)}
foreach($mode in @('StopCode','NullStop','ThrowStop')) {$o=[EtwTestBackend]::new();if($mode -ceq 'StopCode'){$o.StopCode=5}else{$o.$mode=$true};$c=New-Lifecycle $o;$c.Start();$c.Query();$c.Stop();Assert ($c.State.ToString() -ceq 'STOP_UNCONFIRMED' -and $c.CleanupFailure) ('STOP_FAILURE_'+$mode)}
foreach($case in @(@(234,'SESSION_STOPPED'),@(4201,'SESSION_ABSENT_CAUSE_UNKNOWN'),@(2402,'STOP_IN_PROGRESS'))) {$o=[EtwTestBackend]::new();$o.StopCode=$case[0];$c=New-Lifecycle $o;$c.Start();$c.Query();$c.Stop();Assert ($c.StopOutcome -ceq $case[1] -and $c.NativeCode -eq $case[0] -and $o.StopCalls -eq 1) ('STOP_CLASSIFICATION_'+$case[0]);if($case[0] -eq 234){Assert ($c.FinalStatistics -ceq 'INCOMPLETE') 'MISSING_FINAL_STATS_LOST'};$saved=$c.State;$c.Stop();Assert ($o.StopCalls -eq 1 -and $c.State -eq $saved) 'STOP_RETRIED_OR_RESULT_LOST'}
$o=[EtwTestBackend]::new();$o.MissingFinal=$true;$c=New-Lifecycle $o;$c.Start();$c.Query();$c.Stop();Assert ($c.OriginalFailure -ceq 'FINAL_EVIDENCE_INCOMPLETE') 'MISSING_ETL_ACCEPTED'
$o=[EtwTestBackend]::new();$o.EventsLost=1;$o.ThrowStop=$true;$c=New-Lifecycle $o;$c.Start();$c.Query();$c.Stop();Assert ($c.OriginalFailure -ceq 'TRACE_LOSS' -and $c.CleanupFailure -ceq 'STOP_EXCEPTION') 'EARLIER_FAILURE_OVERWRITTEN'
$o=[EtwTestBackend]::new();$o.EventsLost=1;$o.ThrowFinal=$true;$c=New-Lifecycle $o;$c.Start();$c.Query();$c.Stop();Assert ($c.OriginalFailure -ceq 'TRACE_LOSS' -and $c.CleanupFailure -ceq 'FINAL_FILE_CHECK_FAILED' -and $c.State.ToString() -ceq 'FINALIZATION_UNVERIFIED' -and $c.FinalObservation.Code -eq 0) 'STOP_RECEIPT_OVERWRITTEN'
$o=[EtwTestBackend]::new();$c=New-Lifecycle $o;$c.Stop();Assert ($o.StopCalls -eq 0 -and $c.State.ToString() -ceq 'OWNERSHIP_UNVERIFIED') 'RESTART_STOPPED_UNKNOWN'
$native=[Orion.EtwPrepared.EtwLifecycle]::CreateNative('OrionT3',[guid]::NewGuid(),'C:\synthetic\gate.etl');$native.Start();Assert ($native.State.ToString() -ceq 'OWNERSHIP_UNVERIFIED' -and $native.OriginalFailure -ceq 'NATIVE_START_DISABLED_CONTINUITY_UNVERIFIED') 'NATIVE_START_NOT_GUARDED'
try {$null=New-Lifecycle $o; $null=[Orion.EtwPrepared.EtwLifecycle]::new($o,('x'*129),[guid]::NewGuid(),'C:\synthetic\gate.etl');throw 'INVALID_BUFFER_ACCEPTED'} catch {if($_.Exception.Message -ceq 'INVALID_BUFFER_ACCEPTED'){throw}}
Write-Output 'PASS injected lifecycle start, collision, identity, query, loss, stop and recovery controls'
