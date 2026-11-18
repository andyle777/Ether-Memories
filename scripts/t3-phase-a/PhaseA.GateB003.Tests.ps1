$ErrorActionPreference='Stop'
Add-Type -Path @("$PSScriptRoot/PhaseA.EtwNative.Preparation.cs","$PSScriptRoot/PhaseA.EtwLifecycle.cs","$PSScriptRoot/PhaseA.EtwLifecycle.TestBackend.cs","$PSScriptRoot/gate-b-controller/GateBWorkload.cs","$PSScriptRoot/gate-b-controller/GateBReceipt.cs","$PSScriptRoot/gate-b-controller/GateB003.TestBackend.cs")
function Assert($v,$m){if(-not $v){throw $m}}
$program=Get-Content -Raw "$PSScriptRoot/gate-b-controller/Program.cs"
Assert ($program.Contains('Workload.Run(') -and $program.Contains('ControllerReceipt.Serialize(') -and (Get-Content -Raw "$PSScriptRoot/gate-b-controller/GateBSerializedReceipt.cs").Contains('Receipt.Statistics(')) 'RED_CONTROLLER_NOT_CONNECTED'
$dir=Join-Path ([IO.Path]::GetTempPath()) ('orion-gb003-'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($dir)
$path=Join-Path $dir 'fixture.bin'; [Orion.GateB.Workload]::CreateFixture($path)
try {[Orion.GateB.Workload]::CreateFixture($path);throw 'COLLISION_ACCEPTED'}catch [IO.IOException]{}
$r=[Orion.GateB.Workload]::Run($true,$path,[Orion.GateB.FileReadAttempt]::new());Assert ($r.Outcome -ceq 'READ_COMPLETE' -and $r.ActualBytes -eq $r.RequestedBytes -and $r.ThreadId -gt 0) 'REAL_READ_FAILED'
$f=[FakeRead]::new();$f.Count=1;$r=[Orion.GateB.Workload]::Run($false,$path,$f);Assert ($f.Calls -eq 0 -and $r.Outcome -ceq 'NOT_RUN') 'PRESTART_READ'
foreach($pair in @(@(0,'READ_EMPTY'),@(1,'READ_SHORT'),@(1000,'DIGEST_MISMATCH'))) {$f=[FakeRead]::new();$f.Count=$pair[0];$f.Bad=$true;$r=[Orion.GateB.Workload]::Run($true,$path,$f);Assert ($f.Calls -eq 1 -and $r.Outcome -ceq $pair[1]) ('BAD_READ_'+$pair[1])}
$f=[FakeRead]::new();$f.Fail=$true;$r=[Orion.GateB.Workload]::Run($true,$path,$f);Assert ($r.Outcome -ceq 'READ_FAILED' -and $f.Calls -eq 1) 'EXCEPTION_LOST'
$r=[Orion.GateB.Workload]::Run($true,(Join-Path $dir 'missing'),[Orion.GateB.FileReadAttempt]::new());Assert ($r.Outcome -ceq 'FIXTURE_MISSING') 'MISSING_FILE'
foreach($code in @(234,4201,2402,5,1460)) {$o=[Orion.EtwPrepared.EtwObservation]::new();$o.Code=$code;$s=[Orion.GateB.Receipt]::Statistics($o,'INCOMPLETE');$j=$s | ConvertTo-Json | ConvertFrom-Json;Assert (-not $j.StatisticsValid -and $null -eq $j.EventsLost -and $null -eq $j.LogBuffersLost -and $null -eq $j.RealTimeBuffersLost) ('LOSS_COERCION_'+$code)}
$o=[Orion.EtwPrepared.EtwObservation]::new();$o.EventsLost=3;$o.LogBuffersLost=4;$o.RealTimeBuffersLost=5;$j=[Orion.GateB.Receipt]::Statistics($o,'RETURNED_UNVERIFIED') | ConvertTo-Json | ConvertFrom-Json;Assert ($j.StatisticsValid -and $j.EventsLost -eq 3 -and $j.LogBuffersLost -eq 4 -and $j.RealTimeBuffersLost -eq 5) 'VALID_LOSS_DISCARDED'
$o=[Orion.EtwPrepared.EtwObservation]::new();$j=[Orion.GateB.Receipt]::Statistics($o,'RETURNED_UNVERIFIED') | ConvertTo-Json | ConvertFrom-Json;Assert ($j.StatisticsValid -and $j.EventsLost -eq 0 -and $j.LogBuffersLost -eq 0 -and $j.RealTimeBuffersLost -eq 0) 'VALID_ZERO_LOST'
$j=[Orion.GateB.Receipt]::Statistics($o,'INCOMPLETE') | ConvertTo-Json | ConvertFrom-Json;Assert ($null -eq $j.EventsLost) 'INVALID_OUTPUT_ACCEPTED'
Write-Output 'PASS bounded workload and nullable serialized loss controls'
