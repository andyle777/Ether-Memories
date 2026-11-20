param([string]$Source,[string]$Mode='main',[string]$Root='')
$ErrorActionPreference='Stop'
. $Source
if($Mode -cin @('probe','claim')){
 . (Join-Path (Split-Path -Parent $Source) 'PhaseA.RestartProbeValidation.ps1')
 $helper=Join-Path (Split-Path -Parent $Source) 'PhaseA.RestartProbe.ps1'
 $nonce=[guid]::NewGuid().ToString('N')
 $output=@(& $helper -Root $Root -Nonce $nonce -Source $Source)
 $code=$LASTEXITCODE;$text=$output -join "`n"
 if(Test-PhaseARestartProbeResult $text $code $nonce){exit 0}
 if($Mode -ceq 'claim' -and (Test-PhaseAClaimCreatedProbeResult $text $code $nonce)){exit 5}
 exit 9
}
if($Mode -ceq 'crash_CLEAN'){
 . (Join-Path (Split-Path -Parent $Source) 'PhaseA.StateOnlyAdmission.ps1')
 $backend=@{Start={param($a,$m) [IO.File]::WriteAllText((Join-Path $Root 'callback-observed'),'1');$a.pid=[int]123;$a.createdAt='2026-01-01T00:00:00Z';$a.contained=$true;$a.identity=$true};Wait={param($a,$n) $true};Terminate={param($a)};Close={param($a) $true}}
 $null=Invoke-PhaseAStateOnlyAttempt $Root ('a'*32) 1000 $backend {return [long]0} {param($p) if($p -ceq 'CLEAN_JOURNAL_FLUSHED'){[Environment]::Exit(7)}}
 exit 8
}
if($Mode -clike 'crash_*'){
 $point=$Mode.Substring(6)
 if($point -ceq 'INTENT_JOURNAL_FLUSHED'){
  $o=Initialize-PhaseAAdmissionStore $Root
  $null=Open-PhaseAAdmissionLease $o ('a'*32) {param($p) if($p -ceq 'INTENT_JOURNAL_FLUSHED'){[Environment]::Exit(7)}}
 } else {
  $script:crashPoint=$point
  $null=Initialize-PhaseAAdmissionStore $Root {param($p) if($p -ceq $script:crashPoint){[Environment]::Exit(7)}}
 }
 exit 8
}
function Need($v,$m){if(-not $v){throw $m}}
. (Join-Path (Split-Path -Parent $Source) 'PhaseA.RestartProbeValidation.ps1')
function Probe($d,[string]$which='probe'){
 $p=New-Object Diagnostics.ProcessStartInfo;$p.FileName=Join-Path $PSHOME 'powershell.exe';$nonce=''
 if($which -cin @('probe','claim')){
  $validated=Get-AdmissionRoot $d;$claim=Get-Item -LiteralPath (Join-Path $validated 'admission.lock') -Force -ErrorAction Stop
  if($claim.PSIsContainer -or ($claim.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'PROBE_CLAIM_INVALID'}
  $nonce=[guid]::NewGuid().ToString('N');$test=Join-Path (Split-Path -Parent $Source) 'PhaseA.RestartProbe.ps1'
  $p.Arguments='-NoProfile -NonInteractive -File "'+$test+'" -Source "'+$Source+'" -Nonce '+$nonce+' -Root "'+$validated+'"'
 }else{$p.Arguments='-NoProfile -NonInteractive -File "'+$PSCommandPath+'" -Source "'+$Source+'" -Mode '+$which+' -Root "'+$d+'"'}
 $p.UseShellExecute=$false;$p.CreateNoWindow=$true;$p.RedirectStandardError=$true;$p.RedirectStandardOutput=$true
 $c=[Diagnostics.Process]::Start($p)
 try{
  if(-not $c.WaitForExit(15000)){try{$c.Kill()}catch{throw 'PROBE_TERMINATION_UNCONFIRMED'};if(-not $c.WaitForExit(5000)){throw 'PROBE_TERMINATION_UNCONFIRMED'};throw 'PROBE_TIMEOUT'}
  if($which -cin @('probe','claim')){$output=$c.StandardOutput.ReadToEnd();$errors=$c.StandardError.ReadToEnd();if($errors.Length -ne 0 -or -not (Test-PhaseARestartProbeResult $output $c.ExitCode $nonce)){throw 'PROBE_RESULT_UNVERIFIED'};return 0}
  return $c.ExitCode
 }finally{$c.Dispose()}
}
$script:markerAttempts=0
function New-Object {
 if(($args|Out-String) -match 'admission\.init-failed'){$script:markerAttempts++;throw 'INJECTED_MARKER_CREATE_FAILURE'}
 Microsoft.PowerShell.Utility\New-Object @args
}
foreach($point in @('INIT_RECEIPT_FLUSHED','INIT_RECEIPT_WRITTEN')){
 $d=Join-Path $env:TEMP ('orion-r4-test-'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($d)
 $script:point=$point;$errorSeen=$false
 try{Initialize-PhaseAAdmissionStore $d {param($p) if($p -ceq $script:point){throw 'INJECTED_RECEIPT_FAILURE'}}}catch{$errorSeen=$true}
 Need $errorSeen ('FAILURE_NOT_INJECTED_'+$point)
 Need ([IO.File]::Exists((Join-Path $d 'admission.initialized'))) ('RECEIPT_NOT_VISIBLE_'+$point)
 Need (-not [IO.File]::Exists((Join-Path $d 'admission.init-failed'))) ('FAILURE_MARKER_UNEXPECTEDLY_PRESENT_'+$point)
 $result=Probe $d
 Need ($result -eq 0) ('COMPOUND_FAILURE_ISSUED_LEASE_'+$point+'_exit_'+$result)
 Need ($script:markerAttempts -eq 0) ('REMOVED_MARKER_UNEXPECTEDLY_ATTEMPTED_'+$point)
 "PASS $point removed marker NOT_APPLICABLE; restart denied"
}
. (Join-Path (Split-Path -Parent $Source) 'PhaseA.StateOnlyAdmission.ps1')
function Root { $d=Join-Path $env:TEMP ('orion-r4-more-'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($d);return $d }
function NewBackend {
 return @{Start={param($a,$mode) $script:callbackCount++;$a.pid=[int]123;$a.createdAt='2026-01-01T00:00:00Z';$a.contained=$true;$a.identity=$true};Wait={param($a,$ms) $true};Terminate={param($a)};Close={param($a) $true}}
}
$d=Root;$script:callbackCount=0;$r=Invoke-PhaseAStateOnlyAttempt $d ('a'*32) 1000 (NewBackend) {return [long]0}
Need ($r.status -ceq 'SIMULATED_COMPLETE' -and $script:callbackCount -eq 1) 'ORIGINAL_OWNER_DID_NOT_EXECUTE'
Need ((Probe $d) -eq 0) 'CLEAN_REOPENED'
'PASS original owner one callback; CLEAN stays sealed'
$d=Root;$owner=Initialize-PhaseAAdmissionStore $d
Need ((Probe $d) -eq 0) 'SECOND_PROCESS_DURING_LOCK'
$l=Open-PhaseAAdmissionLease $owner ('a'*32);$blocked=$false
try{$null=Open-PhaseAAdmissionLease $owner ('b'*32)}catch{$blocked=$true}
Need $blocked 'OWNER_REUSED'
Close-PhaseAAdmissionLease $l;Need ((Probe $d) -eq 0) 'SECOND_PROCESS_AFTER_LOCK'
$blocked=$false;try{$null=Open-PhaseAAdmissionLease $owner ('a'*32)}catch{$blocked=$true}
Need $blocked 'CLOSED_OWNER_REUSED'
'PASS ownership is exclusive, consumed once and cannot be reconstructed'
$a=Root;$b=Root;$oa=Initialize-PhaseAAdmissionStore $a;$ob=Initialize-PhaseAAdmissionStore $b
try{
 $realRoot=$oa.root;$realPath=$oa.path;$realLock=$oa.lock
 $oa.root=$ob.root;$oa.path=$ob.path;$oa.lock=$ob.lock
 $blocked=$false;try{$null=Open-PhaseAAdmissionLease $oa ('a'*32)}catch{$blocked=$true}
 Need $blocked 'CROSS_DOMAIN_OWNER_ACCEPTED'
 $oa.root=$realRoot;$oa.path=$realPath;$oa.lock=$realLock
}finally{Close-PhaseAAdmissionLease $oa;Close-PhaseAAdmissionLease $ob}
'PASS cross-domain owner substitution denied'
$d=Root;$script:callbackCount=0;$bad=@{NativeGate=$true;Start={param($a,$m) $script:callbackCount++}}
$r=Invoke-PhaseAStateOnlyAttempt $d ('a'*32) 1000 $bad {return [long]0}
Need ($r.reason -ceq 'PROTOTYPE_INCIDENT_UNRESOLVED' -and $script:callbackCount -eq 0 -and -not [IO.File]::Exists((Join-Path $d 'admission.lock'))) 'NATIVE_HOLD_LOST'
'PASS native hold precedes claim and callback'
foreach($point in @('INIT_LOCK_CREATED','INIT_JOURNAL_CREATED','INIT_RECEIPT_FLUSHED','INTENT_JOURNAL_FLUSHED')){
 $d=Root;$code=Probe $d ('crash_'+$point)
 Need ($code -eq 7) ('CRASH_NOT_EXERCISED_'+$point+'_'+$code)
 Need ((Probe $d 'claim') -eq 0 -and (Probe $d) -eq 0) ('CLAIM_REOPENED_AFTER_CRASH_'+$point)
 "PASS process exit at $point preserves claim and denies restart"
}
$d=Root;$owner=Initialize-PhaseAAdmissionStore $d
Need ((Probe $d 'claim') -eq 0) 'SECOND_CLAIM_WHILE_HELD'
Close-PhaseAAdmissionLease $owner
Need ((Probe $d 'claim') -eq 0) 'SECOND_CLAIM_AFTER_RELEASE'
'PASS exclusive create while held and permanent claim after release'
$d=Root;$code=Probe $d 'crash_CLEAN'
Need ($code -eq 7 -and [IO.File]::Exists((Join-Path $d 'callback-observed'))) 'CLEAN_CRASH_NOT_EXERCISED'
Need ((Probe $d 'claim') -eq 0 -and (Probe $d) -eq 0) 'CLAIM_REOPENED_AFTER_CLEAN_CRASH'
Need ((Read-PhaseAAdmissionStore (Join-Path $d 'admission.journal')).phase -ceq 'CLEAN') 'CLEAN_NOT_OBSERVED'
'PASS process exit after CLEAN with observed callback permanently denies restart'
$d=Root;$script:callbackCount=0;$throwBackend=NewBackend
$throwBackend.Start={param($a,$mode) $script:callbackCount++;throw 'injected callback'}
$r=Invoke-PhaseAStateOnlyAttempt $d ('a'*32) 1000 $throwBackend {return [long]0}
Need ($r.status -ceq 'UNVERIFIED' -and $script:callbackCount -eq 1 -and (Probe $d 'claim') -eq 0) 'CALLBACK_FAILURE_REOPENED'
'PASS callback exception retains one-shot claim'
$d=Root;$script:callbackCount=0;$r=Invoke-PhaseAStateOnlyAttempt $d ('a'*32) 1000 (NewBackend) {return [long]0} {param($p) if($p -ceq 'CLEAN_JOURNAL_PARTIAL'){throw 'injected'}}
Need ($r.status -ceq 'UNVERIFIED' -and $script:callbackCount -eq 1 -and (Probe $d 'claim') -eq 0) 'CLEAN_FAILURE_REOPENED'
'PASS failed terminal publication retains one-shot claim'
$d=Root;$ps=@();$helper=Join-Path (Split-Path -Parent $Source) 'PhaseA.RestartProbe.ps1'
foreach($n in 1..2){
 $nonce=[guid]::NewGuid().ToString('N');$start=New-Object Diagnostics.ProcessStartInfo
 $start.FileName=Join-Path $PSHOME 'powershell.exe'
 $start.Arguments='-NoProfile -NonInteractive -File "'+$helper+'" -Source "'+$Source+'" -Nonce '+$nonce+' -Root "'+$d+'"'
 $start.UseShellExecute=$false;$start.CreateNoWindow=$true;$start.RedirectStandardOutput=$true;$start.RedirectStandardError=$true
 $ps+=,@{process=[Diagnostics.Process]::Start($start);nonce=$nonce}
}
try {
 foreach($entry in $ps){
  $proc=$entry.process
  if(-not $proc.WaitForExit(15000)){
   $unconfirmed=$false
   foreach($owned in $ps){try{if(-not $owned.process.HasExited){$owned.process.Kill()}}catch{$unconfirmed=$true}}
   foreach($owned in $ps){try{if(-not $owned.process.WaitForExit(5000)){$unconfirmed=$true}}catch{$unconfirmed=$true}}
   if($unconfirmed){throw 'RACE_TERMINATION_UNCONFIRMED'}
   throw 'RACE_TIMEOUT'
  }
 }
 $created=0;$denied=0
 foreach($entry in $ps){$proc=$entry.process;$output=$proc.StandardOutput.ReadToEnd();$errors=$proc.StandardError.ReadToEnd();Need ($errors.Length -eq 0) 'RACE_STDERR';if(Test-PhaseAClaimCreatedProbeResult $output $proc.ExitCode $entry.nonce){$created++}elseif(Test-PhaseARestartProbeResult $output $proc.ExitCode $entry.nonce){$denied++}else{throw 'RACE_RESULT_UNVERIFIED'}}
 Need ([IO.File]::Exists((Join-Path $d 'admission.lock')) -and $created -eq 1 -and $denied -eq 1) 'CLAIM_RACE_INVALID'
}finally{foreach($entry in $ps){$entry.process.Dispose()}}
'PASS two independent processes race; exactly one creates the claim'
