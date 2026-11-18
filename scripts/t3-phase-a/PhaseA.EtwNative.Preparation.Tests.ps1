$ErrorActionPreference='Stop'
$source=Join-Path $PSScriptRoot 'PhaseA.EtwNative.Preparation.cs'
if(-not (Test-Path -LiteralPath $source)){throw 'ETW_NATIVE_PREPARATION_MISSING'}
Add-Type -Path $source
function Check($condition,$message){if(-not $condition){throw $message}}
function New-EventPair {
 $p=[Orion.EtwPrepared.ReadPair]::new();$p.ProcessId=101;$p.ExpectedProcessId=101;$p.ProcessCreated=1234;$p.ExpectedProcessCreated=1234;$p.ThreadId=202;$p.ExpectedThreadId=202;$p.FileObject=303;$p.ExpectedFileObject=303;$p.RequestId=404;$p.CompletionId=404;$p.RequestedBytes=5;$p.CompletedBytes=5;$p.StartTick=10;$p.EndTick=20;$p.WindowStart=1;$p.WindowEnd=30;$p.Completed=$true;return $p
}
$p=New-EventPair;$r=[Orion.EtwPrepared.ReadVerifier]::CheckInjected($p)
Check ($r.Status -ceq 'UNVERIFIED' -and $r.Reason -ceq 'INJECTED_MATCH_NOT_PROOF') 'INJECTED_PROMOTED'
foreach($item in @(@('ProcessId',102,'ACTOR_LIFETIME_MISMATCH'),@('ProcessCreated',1235,'ACTOR_LIFETIME_MISMATCH'),@('ThreadId',203,'THREAD_MISMATCH'),@('FileObject',304,'FILE_OBJECT_MISMATCH'),@('CompletionId',405,'REQUEST_MISMATCH'),@('Completed',$false,'COMPLETION_MISSING'),@('CompletedBytes',6,'BYTE_COUNT_INVALID'),@('EndTick',31,'WINDOW_MISMATCH'),@('EventsLost',1,'EVENT_LOSS'),@('Replay',$true,'REPLAY_DETECTED'),@('Contradictory',$true,'CONTRADICTORY_COMPLETION'))){$p=New-EventPair;$p.($item[0])=$item[1];$r=[Orion.EtwPrepared.ReadVerifier]::CheckInjected($p);Check ($r.Status -ceq 'UNVERIFIED' -and $r.Reason -ceq $item[2]) ('CASE_'+$item[0]+'_'+$r.Reason)}
Write-Output 'PASS injected read correlation rejects mismatches without LIVE promotion'
$ops=[Orion.EtwPrepared.MockController]::new();$ops.StartCode=183;$start=[Orion.EtwPrepared.ControllerHarness]::Start($ops)
Check ($start.Reason -ceq 'START_FAILED' -and $start.NativeCode -eq 183 -and $start.Lease -eq $null -and $ops.StopCalls -eq 0) 'DUPLICATE_SESSION_HANDLING'
$ops=[Orion.EtwPrepared.MockController]::new();$start=[Orion.EtwPrepared.ControllerHarness]::Start($ops);$ops.ReplaceSession=$true;$stop=[Orion.EtwPrepared.ControllerHarness]::Stop($ops,$start.Lease)
Check ($stop.Reason -ceq 'OWNERSHIP_UNCONFIRMED' -and $ops.StopCalls -eq 0) 'REPLACED_SESSION_STOPPED'
$ops=[Orion.EtwPrepared.MockController]::new();$start=[Orion.EtwPrepared.ControllerHarness]::Start($ops);$other=[Orion.EtwPrepared.MockController]::new();$stop=[Orion.EtwPrepared.ControllerHarness]::Stop($other,$start.Lease)
Check ($stop.Reason -ceq 'OWNERSHIP_UNCONFIRMED' -and $other.StopCalls -eq 0) 'FORGED_BACKEND_STOPPED'
$ops=[Orion.EtwPrepared.MockController]::new();$start=[Orion.EtwPrepared.ControllerHarness]::Start($ops);$ops.StopCode=5;$stop=[Orion.EtwPrepared.ControllerHarness]::Stop($ops,$start.Lease)
Check ($stop.Reason -ceq 'STOP_FAILED' -and $stop.NativeCode -eq 5 -and $stop.ResourceUnresolved) 'STOP_FAILURE_LOST'
Write-Output 'PASS injected session ownership and native-error controls'
