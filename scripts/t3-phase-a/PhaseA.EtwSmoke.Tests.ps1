$ErrorActionPreference='Stop'
$source=Join-Path $PSScriptRoot 'PhaseA.EtwSmoke.Sim.cs'
if(-not (Test-Path -LiteralPath $source)){throw 'ETW_SMOKE_CONTROLLER_MISSING'}
Add-Type -Path $source
$root=Join-Path ([IO.Path]::GetTempPath()) ('orion-etw-sim-'+[guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($root)|Out-Null
function RunCase($plan,[int]$timeout=300){[Orion.EtwSmoke.Simulation]::Run($root,[guid]::NewGuid().ToString('N'),$plan,$timeout)}
function Check($v,$m){if(-not $v){throw $m}}
$p=[Orion.EtwSmoke.Plan]::new();$r=RunCase $p
Check ($r.Status -ceq 'UNVERIFIED' -and $r.Reason -ceq 'SIMULATED_COMPLETE' -and $r.StopAttempts -eq 1 -and $r.Cleanup -ceq 'CONFIRMED_SIMULATED') 'POSITIVE_FAILED'
$id=[guid]::NewGuid().ToString('N');$r=[Orion.EtwSmoke.Simulation]::Run($root,$id,[Orion.EtwSmoke.Plan]::new(),300);$r2=[Orion.EtwSmoke.Simulation]::Run($root,$id,[Orion.EtwSmoke.Plan]::new(),300)
Check ($r2.Reason -ceq 'DIRECTORY_COLLISION' -and $r2.StopAttempts -eq 0) 'COLLISION_FAILED'
foreach($item in @(@('OwnerMismatch','OWNERSHIP_UNCONFIRMED'),@('SettingsMismatch','SETTINGS_MISMATCH'),@('CollectorFailure','COLLECTOR_FAILED'),@('StopFailure','STOP_FAILED'),@('EventLoss','EVENT_LOSS'),@('BufferLoss','BUFFER_LOSS'),@('MissingCompletion','COMPLETION_MISSING'),@('Replay','REPLAY_DETECTED'),@('Contradictory','CONTRADICTORY_RECORDS'),@('Cancellation','CANCELLED'))){$p=[Orion.EtwSmoke.Plan]::new();$p.($item[0])=$true;$r=RunCase $p;Check ($r.Status -ceq 'UNVERIFIED' -and $r.Reason -ceq $item[1]) ('CASE_'+$item[0]+'_'+$r.Reason);if($item[0] -ceq 'OwnerMismatch'){Check ($r.StopAttempts -eq 0 -and $r.Cleanup -ceq 'UNCONFIRMED') 'WRONG_OWNER_STOPPED'}}
$p=[Orion.EtwSmoke.Plan]::new();$p.DelayMs=1000;$sw=[Diagnostics.Stopwatch]::StartNew();$r=RunCase $p 100;$sw.Stop();Check ($r.Reason -ceq 'TIMEOUT' -and $r.StopAttempts -eq 0 -and $r.Cleanup -ceq 'UNCONFIRMED' -and $sw.ElapsedMilliseconds -lt 2000) 'TIMEOUT_NOT_BOUNDED'
Write-Output 'PASS simulated collision, ownership, timeout, cancellation, failure, loss, replay and contradiction controls'
$p=[Orion.EtwSmoke.Plan]::new();$p.EventLoss=$true;$p.StopFailure=$true;$r=RunCase $p
Check ($r.Reason -ceq 'EVENT_LOSS' -and $r.Cleanup -ceq 'UNCONFIRMED' -and $r.CleanupReason -ceq 'STOP_FAILED' -and $r.EvidenceRetained) 'ORIGINAL_FAILURE_LOST_DURING_STOP'
Write-Output 'PASS simulated loss survives stop failure'
$p=[Orion.EtwSmoke.Plan]::new();$p.AcceptedBufferKB=32;$r=RunCase $p
Check ($r.Reason -ceq 'SETTINGS_MISMATCH') 'ACCEPTED_SETTINGS_NOT_CHECKED'
$p=[Orion.EtwSmoke.Plan]::new();$p.EventsLost=1;$r=RunCase $p
Check ($r.Reason -ceq 'EVENT_LOSS' -and $r.EventsLost -eq 1) 'EVENT_COUNTER_NOT_RETAINED'
$p=[Orion.EtwSmoke.Plan]::new();$p.BuffersLost=2;$r=RunCase $p
Check ($r.Reason -ceq 'BUFFER_LOSS' -and $r.BuffersLost -eq 2) 'BUFFER_COUNTER_NOT_RETAINED'
Write-Output 'PASS simulated accepted settings and loss counts'
$p=[Orion.EtwSmoke.Plan]::new();$p.FinalEventsLost=1;$r=RunCase $p
Check ($r.Reason -ceq 'EVENT_LOSS' -and $r.FinalEventsLost -eq 1 -and $r.Cleanup -ceq 'CONFIRMED_SIMULATED') 'FINAL_LOSS_IGNORED'
$p=[Orion.EtwSmoke.Plan]::new();$p.OwnershipChangesBeforeStop=$true;$r=RunCase $p
Check ($r.Reason -ceq 'OWNERSHIP_UNCONFIRMED' -and $r.StopAttempts -eq 0 -and $r.ResourceUnresolved) 'OWNERSHIP_CHANGE_STOPPED'
Write-Output 'PASS final loss and pre-stop ownership recheck'
