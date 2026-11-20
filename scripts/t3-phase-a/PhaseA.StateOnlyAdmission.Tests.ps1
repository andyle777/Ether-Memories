param([string]$Mode='main',[string]$Directory='')
$ErrorActionPreference='Stop'
. "$PSScriptRoot/PhaseA.StateOnlyAdmission.ps1"
if($Mode -ceq 'exit_after_marker'){
 $f={param($point) if($point -ceq 'MARKER_FLUSHED'){[Environment]::Exit(7)}}
 $owner=Initialize-PhaseAAdmissionStore $Directory; $null=Open-PhaseAAdmissionLease $owner ('f'*32) $f
 exit 8
}
function Need($v,$m){if(-not $v){throw $m}}
function NewRoot {$d=Join-Path ([IO.Path]::GetTempPath()) ('orion-r1-'+[Guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($d);return $d}
function Rejected($d){try{$o=Initialize-PhaseAAdmissionStore $d;Close-PhaseAAdmissionLease $o;return $false}catch{return $true}}
$script:t=[long]0;$clock={return $script:t};$script:starts=0
$backend=@{
 Start={param($a,$mode) $script:starts++;$a.pid=[int]123;$a.createdAt='2026-01-01T00:00:00Z';$a.contained=$true;$a.identity=$true}
 Wait={param($a,$ms) return $true};Terminate={param($a)};Close={param($a) return $true}
}
foreach($point in @('MARKER_CREATED','MARKER_PARTIAL','MARKER_WRITTEN','MARKER_FLUSHED','INTENT_JOURNAL_BEFORE_OPEN','INTENT_JOURNAL_BEFORE_WRITE','INTENT_JOURNAL_PARTIAL','INTENT_JOURNAL_WRITTEN','INTENT_JOURNAL_FLUSHED')){
 $d=NewRoot;$script:starts=0;$script:faultPoint=$point
 $fault={param($p) if($p -ceq $script:faultPoint){throw 'injected persistence failure'}}
 $r=Invoke-PhaseAStateOnlyAttempt $d ('a'*32) 1000 $backend $clock $fault
 Need ($r.status -ceq 'UNVERIFIED' -and $script:starts -eq 0 -and (Rejected $d)) ('FAILED_OPEN_'+$point)
 "PASS $point"
}
foreach($point in @('CLEAN_JOURNAL_BEFORE_OPEN','CLEAN_JOURNAL_BEFORE_WRITE','CLEAN_JOURNAL_PARTIAL','CLEAN_JOURNAL_WRITTEN','CLEAN_JOURNAL_FLUSHED')){
 $d=NewRoot;$script:starts=0;$script:faultPoint=$point
 $fault={param($p) if($p -ceq $script:faultPoint){throw 'injected clean publication failure'}}
 $r=Invoke-PhaseAStateOnlyAttempt $d ('a'*32) 1000 $backend $clock $fault
 Need ($r.status -ceq 'UNVERIFIED' -and $script:starts -eq 1 -and (Rejected $d)) ('FAILED_CLEAN_'+$point)
 "PASS $point"
}
$d=NewRoot;$script:starts=0
$r=Invoke-PhaseAStateOnlyAttempt $d ('a'*32) 1000 $backend $clock
$state=Read-PhaseAAdmissionStore (Join-Path $d 'admission.journal')
Need ($r.status -ceq 'SIMULATED_COMPLETE' -and $r.source -ceq 'LOCAL_UNTRUSTED' -and $script:starts -eq 1 -and $state.phase -ceq 'CLEAN') 'SYNTHETIC_CLEAN'
Need (Rejected $d) 'SYNTHETIC_CLEAN_REOPENED'
'PASS one-shot synthetic clean remains non-authoritative'
$d=NewRoot;$owner=Initialize-PhaseAAdmissionStore $d;$l=Open-PhaseAAdmissionLease $owner ('a'*32)
$bad=@{source='LOCAL_UNTRUSTED';classification='OBSERVED';reason='NORMAL';wait='SIGNALED';cleanup='CONFIRMED';descendants='UNVERIFIED'}
$blocked=$false;try{Add-AdmissionRecord $l 'CLEAN' ('b'*32) 123 'wrong'}catch{$blocked=$true}
Need $blocked 'UNRELATED_CLEAN_ACCEPTED'
$old=$l.sequence;$l.sequence=1;$blocked=$false
try{Publish-PhaseAStateOnlyClean $l $bad}catch{$blocked=$true};$l.sequence=$old
Need $blocked 'STALE_GENERATION_ACCEPTED'
$bad.cleanup='FAILED';$blocked=$false;try{Publish-PhaseAStateOnlyClean $l $bad}catch{$blocked=$true}
Need $blocked 'INVALID_CLEAN_ACCEPTED'
Close-PhaseAAdmissionLease $l
Need (Rejected $d) 'INVALID_CLEAN_RELEASED'
'PASS unrelated, stale and contradictory clean evidence rejected'
$d=NewRoot;$script:starts=0;$badBackend=@{Start={param($a,$m) $script:starts++;throw 'injected'};Wait={param($a,$ms) $false};Terminate={param($a)};Close={param($a) $false}}
$r=Invoke-PhaseAStateOnlyAttempt $d ('a'*32) 1000 $badBackend $clock
Need ($r.status -ceq 'UNVERIFIED' -and $script:starts -eq 1 -and (Rejected $d)) 'UNRESOLVED_READMITTED'
'PASS supervisor exception preserves denial'
$d=NewRoot;$script:starts=0;$native=@{NativeGate=$true;Start={param($a,$m) $script:starts++}}
$r=Invoke-PhaseAStateOnlyAttempt $d ('a'*32) 1000 $native $clock
Need ($r.reason -ceq 'PROTOTYPE_INCIDENT_UNRESOLVED' -and $script:starts -eq 0) 'NATIVE_HOLD_BYPASSED'
'PASS synthetic evidence cannot enter built-in native path'
$d=NewRoot
$p=New-Object Diagnostics.ProcessStartInfo;$p.FileName=Join-Path $PSHOME 'powershell.exe';$p.Arguments='-NoProfile -NonInteractive -File "'+$PSCommandPath+'" -Mode exit_after_marker -Directory "'+$d+'"';$p.UseShellExecute=$false;$p.CreateNoWindow=$true
$c=[Diagnostics.Process]::Start($p)
try{if(-not $c.WaitForExit(15000)){throw 'STATE_PROBE_TIMEOUT'};Need ($c.ExitCode -eq 7) 'MARKER_EXIT_FAILED'}finally{$c.Dispose()}
Need (Rejected $d) 'PROCESS_EXIT_MARKER_READMITTED'
'PASS process exit between marker flush and journal append denies restart'
# Confirm the actual callback sees the persisted intent while the exclusive lock is held.
$script:integrationDir=NewRoot;$script:observedIntent=$false;$script:lockRejected=$false
$verifyBackend=@{
 Start={param($a,$m)
  $state=Read-PhaseAAdmissionStore (Join-Path $script:integrationDir 'admission.journal')
  $script:observedIntent=($state.phase -ceq 'INTENT' -and [IO.File]::Exists((Join-Path $script:integrationDir 'admission.intent')))
  try{$probe=New-Object IO.FileStream((Join-Path $script:integrationDir 'admission.lock'),[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None);$probe.Dispose()}catch{$script:lockRejected=$true}
  $a.pid=[int]321;$a.createdAt='2026-01-01T00:00:00Z';$a.contained=$true;$a.identity=$true
 }
 Wait={param($a,$ms) $true};Terminate={param($a)};Close={param($a) $true}
}
$r=Invoke-PhaseAStateOnlyAttempt $script:integrationDir ('c'*32) 1000 $verifyBackend $clock
Need ($r.status -ceq 'SIMULATED_COMPLETE' -and $script:observedIntent -and $script:lockRejected) 'CALLBACK_PRECEDED_INTENT'
'PASS callback observed persisted intent and locked domain'
foreach($kind in @('MISSING','WRONG','TRUNCATED')){
 $d=NewRoot;$owner=Initialize-PhaseAAdmissionStore $d;$l=Open-PhaseAAdmissionLease $owner ('a'*32);$marker=Join-Path $d 'admission.intent'
 switch($kind){'MISSING'{[IO.File]::Delete($marker)} 'WRONG'{[IO.File]::WriteAllText($marker,(('b'*32)+[char]10))} 'TRUNCATED'{[IO.File]::WriteAllText($marker,'a')}}
 $good=@{source='LOCAL_UNTRUSTED';classification='OBSERVED';reason='NORMAL';wait='SIGNALED';cleanup='CONFIRMED';descendants='UNVERIFIED'}
 $blocked=$false;try{Publish-PhaseAStateOnlyClean $l $good}catch{$blocked=$true}finally{Close-PhaseAAdmissionLease $l}
 Need ($blocked -and (Rejected $d)) ('MARKER_MISMATCH_'+$kind)
 "PASS marker $kind rejected"
}
foreach($path in @('C:.','relative','\\server\share')){
 $blocked=$false;try{$null=Get-AdmissionRoot $path}catch{$blocked=$true};Need $blocked ('PATH_ACCEPTED_'+$path)
}
'PASS drive-relative, relative and UNC paths rejected'
# A lease must not mutate a second domain even when session and owner observations match.
$a=NewRoot;$b=NewRoot
$o1=Initialize-PhaseAAdmissionStore $a;$o2=Initialize-PhaseAAdmissionStore $b;$l1=Open-PhaseAAdmissionLease $o1 ('a'*32);$l2=Open-PhaseAAdmissionLease $o2 ('a'*32)
try {
 $l1.path=$l2.path
 $good=@{source='LOCAL_UNTRUSTED';classification='OBSERVED';reason='NORMAL';wait='SIGNALED';cleanup='CONFIRMED';descendants='UNVERIFIED'}
 $blocked=$false;try{Publish-PhaseAStateOnlyClean $l1 $good}catch{$blocked=$true}
 Need $blocked 'CROSS_DOMAIN_TRANSITION_ACCEPTED'
} finally {Close-PhaseAAdmissionLease $l1;Close-PhaseAAdmissionLease $l2}
'PASS cross-domain transition rejected'