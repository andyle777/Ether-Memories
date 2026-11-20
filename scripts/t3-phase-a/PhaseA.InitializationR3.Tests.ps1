param([string]$Source,[string]$Mode='main',[string]$Directory='')
$ErrorActionPreference='Stop'
. $Source
function Need($v,$m){if(-not $v){throw $m}}
function NewRoot {$d=Join-Path $env:TEMP ('orion-r3-'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($d);$d}
. (Join-Path (Split-Path -Parent $Source) 'PhaseA.RestartProbeValidation.ps1')
function Reject($d){
 try{
  $root=Get-AdmissionRoot $d;$claim=Get-Item -LiteralPath (Join-Path $root 'admission.lock') -Force -ErrorAction Stop
  if($claim.PSIsContainer -or ($claim.Attributes -band [IO.FileAttributes]::ReparsePoint)){return $false}
  $nonce=[guid]::NewGuid().ToString('N');$p=New-Object Diagnostics.ProcessStartInfo;$p.FileName=Join-Path $PSHOME 'powershell.exe'
  $probe=Join-Path (Split-Path -Parent $Source) 'PhaseA.RestartProbe.ps1'
  $p.Arguments='-NoProfile -NonInteractive -File "'+$probe+'" -Source "'+$Source+'" -Nonce '+$nonce+' -Root "'+$root+'"'
  $p.UseShellExecute=$false;$p.CreateNoWindow=$true;$p.RedirectStandardOutput=$true;$p.RedirectStandardError=$true
  $c=[Diagnostics.Process]::Start($p)
  try{if(-not $c.WaitForExit(15000)){try{$c.Kill()}catch{throw 'PROBE_TERMINATION_UNCONFIRMED'};if(-not $c.WaitForExit(5000)){throw 'PROBE_TERMINATION_UNCONFIRMED'};throw 'PROBE_TIMEOUT'};$out=$c.StandardOutput.ReadToEnd();$err=$c.StandardError.ReadToEnd();return ($err.Length -eq 0 -and (Test-PhaseARestartProbeResult $out $c.ExitCode $nonce))}finally{$c.Dispose()}
 }catch{if($_.Exception.GetBaseException().Message -cin @('PROBE_TERMINATION_UNCONFIRMED','PROBE_TIMEOUT')){throw};return $false}
}
if($Mode -ceq 'exit_before'){Initialize-PhaseAAdmissionStore $Directory {param($p) if($p -ceq 'INIT_JOURNAL_FLUSHED'){[Environment]::Exit(7)}};exit 8}
if($Mode -ceq 'exit_after'){Initialize-PhaseAAdmissionStore $Directory {param($p) if($p -ceq 'INIT_RECEIPT_FLUSHED'){[Environment]::Exit(7)}};exit 8}
function Child($mode,$d){
 $p=New-Object Diagnostics.ProcessStartInfo;$p.FileName=Join-Path $PSHOME 'powershell.exe'
 $p.Arguments='-NoProfile -NonInteractive -File "'+$PSCommandPath+'" -Source "'+$Source+'" -Mode '+$mode+' -Directory "'+$d+'"'
 $p.UseShellExecute=$false;$p.CreateNoWindow=$true
 $c=[Diagnostics.Process]::Start($p);try{if(-not $c.WaitForExit(15000)){try{$c.Kill()}catch{throw 'CHILD_TERMINATION_UNCONFIRMED'};if(-not $c.WaitForExit(5000)){throw 'CHILD_TERMINATION_UNCONFIRMED'};throw 'TIMEOUT'};return $c.ExitCode}finally{$c.Dispose()}
}
$a=NewRoot;$b=NewRoot;$owner=Initialize-PhaseAAdmissionStore $a;Close-PhaseAAdmissionLease $owner
Get-ChildItem -LiteralPath $a -File | ForEach-Object { [IO.File]::Copy($_.FullName,(Join-Path $b $_.Name)) }
Need (Reject $b) 'COPIED_DOMAIN_ACCEPTED'
'PASS domain binding'
foreach($point in @('INIT_LOCK_BEFORE_CREATE','INIT_LOCK_CREATED','INIT_JOURNAL_BEFORE_CREATE','INIT_JOURNAL_CREATED','INIT_JOURNAL_BEFORE_WRITE','INIT_JOURNAL_PARTIAL','INIT_JOURNAL_WRITTEN','INIT_JOURNAL_FLUSHED','INIT_RECEIPT_CREATED','INIT_RECEIPT_PARTIAL','INIT_RECEIPT_WRITTEN','INIT_RECEIPT_FLUSHED')){
 $d=NewRoot;$script:point=$point;$threw=$false
 try {Initialize-PhaseAAdmissionStore $d {param($p) if($p -ceq $script:point){throw 'INJECTED_INIT_FAILURE'}}} catch {$threw=$true}
 if($point -ceq 'INIT_LOCK_BEFORE_CREATE'){
  Need ($threw -and -not [IO.File]::Exists((Join-Path $d 'admission.lock'))) 'PRECLAIM_FAILURE_INVALID'
  $fresh=Initialize-PhaseAAdmissionStore $d;Close-PhaseAAdmissionLease $fresh
  Need (Reject $d) 'FRESH_AFTER_PRECLAIM_NOT_SEALED'
 }else{Need ($threw -and (Reject $d)) ('INIT_FAILURE_ACCEPTED_'+$point)}
 "PASS $point"
}
$d=NewRoot;Need ((Child 'exit_before' $d) -eq 7) 'EXIT_BEFORE_NOT_EXERCISED';Need (Reject $d) 'EXIT_BEFORE_ADMITTED'
'PASS process exit before receipt publication'
$d=NewRoot;Need ((Child 'exit_after' $d) -eq 7) 'EXIT_AFTER_NOT_EXERCISED'
Need (Reject $d) 'EXIT_AFTER_NOT_SEALED'
'PASS process exit after flushed initialization receipt denies reopening'
$d=NewRoot;$owner=Initialize-PhaseAAdmissionStore $d;$before=[IO.File]::ReadAllBytes((Join-Path $d 'admission.journal'));$threw=$false
try{Initialize-PhaseAAdmissionStore $d}catch{$threw=$true}
Need ($threw -and [Convert]::ToBase64String($before) -ceq [Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $d 'admission.journal')))) 'DUPLICATE_TRUNCATED'
'PASS duplicate initialization preserves journal'
foreach($kind in @('MISSING','MALFORMED')){$d=NewRoot;$owner=Initialize-PhaseAAdmissionStore $d;$p=Join-Path $d 'admission.initialized';if($kind -ceq 'MISSING'){[IO.File]::Delete($p)}else{[IO.File]::WriteAllText($p,'invalid')};try{$l=Open-PhaseAAdmissionLease $owner ('b'*32);throw 'ACCEPTED'}catch{if($_.Exception.Message -eq 'ACCEPTED'){throw}}; "PASS receipt $kind rejected"}
'PASS initialization regression completed'