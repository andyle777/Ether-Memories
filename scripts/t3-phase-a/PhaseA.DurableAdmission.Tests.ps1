param([string]$Mode='main',[string]$Directory='')
$ErrorActionPreference='Stop'
. "$PSScriptRoot/PhaseA.DurableAdmission.ps1"
if($Mode -ceq 'probe'){
 try{$l=Open-PhaseAAdmissionLease $Directory ('b'*32);Close-PhaseAAdmissionLease $l;exit 5}catch{}
 try{$o=Initialize-PhaseAAdmissionStore $Directory;Close-PhaseAAdmissionLease $o;exit 6}catch{exit 0}
}
if($Mode -ceq 'exit_after_intent'){
 $owner=Initialize-PhaseAAdmissionStore $Directory;$l=Open-PhaseAAdmissionLease $owner ('a'*32)
 [Environment]::Exit(0)
}
function Need($v,$m){if(-not $v){throw $m}}
function NewRoot {$d=Join-Path ([IO.Path]::GetTempPath()) ('orion-admission-'+[Guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($d);return $d}
function Launch([string]$mode,[string]$dir){
 $p=New-Object Diagnostics.ProcessStartInfo
 $p.FileName=Join-Path $PSHOME 'powershell.exe';$p.Arguments='-NoProfile -NonInteractive -File "'+$PSCommandPath+'" -Mode '+$mode+' -Directory "'+$dir+'"'
 $p.UseShellExecute=$false;$p.CreateNoWindow=$true;$p.RedirectStandardError=$true;$p.RedirectStandardOutput=$true
 $c=[Diagnostics.Process]::Start($p)
 try{if(-not $c.WaitForExit(15000)){throw 'STATE_PROBE_TIMEOUT'};return $c.ExitCode}finally{$c.Dispose()}
}
$d=NewRoot;$owner=Initialize-PhaseAAdmissionStore $d
$lease=Open-PhaseAAdmissionLease $owner ('a'*32)
Need ((Read-PhaseAAdmissionStore (Join-Path $d 'admission.journal')).phase -ceq 'INTENT') 'INTENT_NOT_DURABLE'
Need ((Launch 'probe' $d) -eq 0) 'CROSS_PROCESS_LOCK_FAILED'
'PASS cross-process exclusion while intent lease held'
Close-PhaseAAdmissionLease $lease
Need ((Launch 'probe' $d) -eq 0) 'UNRESOLVED_INTENT_READMITTED'
'PASS unresolved survives lease release'
$d=NewRoot
Need ((Launch 'exit_after_intent' $d) -eq 0) 'INTENT_PROCESS_FAILED'
Need ((Launch 'probe' $d) -eq 0) 'INTENT_PROCESS_EXIT_READMITTED'
'PASS process exit after durable intent'
foreach($kind in @('MISSING','TRUNCATED','UNSUPPORTED','HASH')){
 $d=NewRoot;$owner=Initialize-PhaseAAdmissionStore $d;$journal=Join-Path $d 'admission.journal'
 switch($kind){
  'MISSING' {[IO.File]::Delete($journal)}
  'TRUNCATED' {[IO.File]::WriteAllText($journal,'truncated')}
  'UNSUPPORTED' {[IO.File]::WriteAllText($journal,('2|1|INIT|'+('0'*32)+'|0||'+('0'*64)+'|'+('0'*64)+[char]10))}
  'HASH' {[IO.File]::WriteAllText($journal,('1|1|INIT|'+('0'*32)+'|0||'+('0'*64)+'|'+('0'*64)+[char]10))}
  'DUP_INIT' {try{Initialize-PhaseAAdmissionStore $d;throw 'DUP_ACCEPTED'}catch{if($_.Exception.Message -eq 'DUP_ACCEPTED'){throw}};continue}
 }
 $rejected=$false;try{$null=Open-PhaseAAdmissionLease $owner ('c'*32)}catch{$rejected=$true};Need $rejected ('BAD_STATE_'+$kind)
 "PASS reject $kind"
}
$dupe=NewRoot;$dupeOwner=Initialize-PhaseAAdmissionStore $dupe;$blocked=$false;try{Initialize-PhaseAAdmissionStore $dupe}catch{$blocked=$true};Need $blocked 'DUP_INIT_ACCEPTED'
'PASS reject duplicate explicit initialization'
$d=NewRoot;$owner=Initialize-PhaseAAdmissionStore $d
$j=Join-Path $d 'admission.journal';$stale=[IO.File]::ReadAllBytes($j)
$l=Open-PhaseAAdmissionLease $owner ('d'*32);Close-PhaseAAdmissionLease $l
[IO.File]::WriteAllBytes($j,$stale)
$blocked=$false;try{$null=Open-PhaseAAdmissionLease $d ('e'*32)}catch{$blocked=$true}
Need $blocked 'REPLAYED_INIT_ACCEPTED'
'PASS journal rollback rejected while intent marker exists'