$ErrorActionPreference='Stop'
. "$PSScriptRoot/PhaseA.Stage2.ps1"
Add-Type -Path "$PSScriptRoot/PhaseA.EtwNative.Preparation.cs"
if(-not ('Orion.EtwPrepared.NativePropertiesBuffer' -as [type])) { throw 'NATIVE_PROPERTIES_IMPLEMENTATION_MISSING' }
if(-not (Get-Command Invoke-PhaseAGateBActors -ErrorAction SilentlyContinue)) { throw 'TWO_IDENTITY_ACTOR_INTERFACE_MISSING' }
$id=[guid]::NewGuid(); $name='OrionT3-'+[guid]::NewGuid().ToString('N')
$p=[Orion.EtwPrepared.NativePropertiesBuffer]::new($name,$id,'C:\synthetic\gate.etl')
try {
 if($p.Mode -ne 0x02000001 -or $p.EnableFlags -ne 0x06000303 -or $p.SessionId -ne $id) {throw 'NATIVE_CONFIGURATION_INVALID'}
 if($p.Pointer -eq [IntPtr]::Zero -or $p.TotalBytes -le $p.StructBytes){throw 'NATIVE_BUFFER_INVALID'}
 $pt=[Orion.EtwPrepared.NativePropertiesBuffer].Assembly.GetType('Orion.EtwPrepared.TraceProperties')
 $modeOffset=[int][Runtime.InteropServices.Marshal]::OffsetOf($pt,'LogFileMode')
 $flagsOffset=[int][Runtime.InteropServices.Marshal]::OffsetOf($pt,'EnableFlags')
 if([Runtime.InteropServices.Marshal]::ReadInt32($p.Pointer,$modeOffset) -ne $p.Mode -or [Runtime.InteropServices.Marshal]::ReadInt32($p.Pointer,$flagsOffset) -ne $p.EnableFlags){throw 'NATIVE_BUFFER_CONTENT_MISMATCH'}
} finally {$p.Dispose()}
$calls=New-Object 'System.Collections.Generic.List[string]'
$backend=@{Run={param($a,$t,$op,$target) $calls.Add($a.sid+'|'+$target);@{expectedSid=$a.sid;observedSid=$a.sid;reportedSid=$a.sid;expectedPid=123;reportedPid=123;tokenNonAdmin=$true;tokenObserved=$true;createdAt='2026-01-01T00:00:00Z';observedCreatedAt='2026-01-01T00:00:00Z';expectedNonce='n';reportedNonce='n';exitCode=$(if($target -ceq 'control'){0}else{20});outcome=$(if($target -ceq 'control'){'allowed'}else{'denied'});role=$a.role;contained=$true;terminated=$true}}}
$a=@{role='broker';sid='S-1-5-21-1'};$b=@{role='legacy';sid='S-1-5-21-2'}
$fixture=@{controlFile='control';protectedFile='protected';fixtureId='f'}
$result=Invoke-PhaseAGateBActors $a @{sid=$a.sid} $b @{sid=$b.sid} $backend $fixture 'attempt1' 'experiment1' 'INJECTED'
if($result.status -cne 'UNVERIFIED' -or $calls.Count -ne 2 -or $calls[0] -cne 'S-1-5-21-1|control' -or $calls[1] -cne 'S-1-5-21-2|protected'){throw 'TWO_IDENTITY_BINDING_FAILED'}
try {$null=Invoke-PhaseAGateBActors $a @{sid=$a.sid} $b @{sid=$b.sid} $backend $fixture 'attempt1' 'experiment1' 'LIVE';throw 'LIVE_ACCEPTED'} catch {if($_.Exception.Message -cne 'OBSERVER_LIVE_DISABLED'){throw}}
if($calls.Count -ne 2){throw 'LIVE_BACKEND_CALLED'}
try {$null=Invoke-PhaseAGateBActors $a @{sid=$a.sid} $a @{sid=$a.sid} $backend $fixture 'attempt1' 'experiment1' 'INJECTED';throw 'SAME_SID_ACCEPTED'} catch {if($_.Exception.Message -cne 'OBSERVER_INPUT_REJECTED'){throw}}
try {$null=Invoke-PhaseAGateBActors $a @{sid=$b.sid} $b @{sid=$b.sid} $backend $fixture 'attempt1' 'experiment1' 'INJECTED';throw 'TOKEN_MISMATCH_ACCEPTED'} catch {if($_.Exception.Message -cne 'OBSERVER_INPUT_REJECTED'){throw}}
try {$null=Invoke-PhaseAGateBActors $a @{sid=$a.sid} $b @{sid=$b.sid} $backend @{controlFile='x';protectedFile='y'} 'attempt1' 'experiment1' 'INJECTED';throw 'FIXTURE_ID_MISSING_ACCEPTED'} catch {if($_.Exception.Message -cne 'OBSERVER_INPUT_REJECTED'){throw}}
if($calls.Count -ne 2){throw 'REJECTED_INPUT_LAUNCHED_ACTOR'}
Write-Output 'PASS native properties layout preparation and two-identity injected gate'
