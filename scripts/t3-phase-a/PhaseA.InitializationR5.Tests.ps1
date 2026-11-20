param([string]$RootSource,[string]$Mode='main',[string]$Root='',[string]$Token='')
$ErrorActionPreference='Stop'
. (Join-Path $RootSource 'PhaseA.StateOnlyAdmission.ps1')
$script:originalOpen=(Get-Item Function:\Open-PhaseAAdmissionLease).ScriptBlock
function Open-PhaseAAdmissionLease($owner,[string]$session,[scriptblock]$Fault=$null,[scriptblock]$Flush=$null) {
 $lease=& $script:originalOpen $owner $session $Fault $Flush
 $script:issued++
 if($Mode -clike 'crash_*'){[IO.File]::WriteAllText((Join-Path $Root 'observed-leases'),[string]$script:issued)}
 return $lease
}
if($Mode -ceq 'race'){
 $script:issued=0;$script:callbacks=0;$claimed=0
 . (Join-Path $RootSource 'PhaseA.RestartProbeValidation.ps1')
 $nonce=$Token;$helper=Join-Path $RootSource 'PhaseA.RestartProbe.ps1'
 $result=@(& $helper -Root $Root -Nonce $nonce -Source (Join-Path $RootSource 'PhaseA.DurableAdmission.ps1'));$code=$LASTEXITCODE;$text=$result -join "`n"
 if(Test-PhaseAClaimCreatedProbeResult $text $code $nonce){$claimed=1}
 elseif(Test-PhaseARestartProbeResult $text $code $nonce){$claimed=0}
 else{throw 'RACE_PROBE_UNVERIFIED'}
 $value=@{claimed=$claimed;leases=$script:issued;callbacks=$script:callbacks;probeNonce=$nonce;probeOutput=$text;probeCode=$code} | ConvertTo-Json -Compress
 [IO.File]::WriteAllText((Join-Path $Root ('race-'+$Token+'.json')),$value)
 exit 0
}
if($Mode -clike 'crash_*'){
 $script:issued=0;$script:callbacks=0
 [IO.File]::WriteAllText((Join-Path $Root 'observed-leases'),'0')
 [IO.File]::WriteAllText((Join-Path $Root 'observed-callbacks'),'0')
 $crashPoint=$Mode.Substring(6)
 if($crashPoint -ceq 'AFTER_LEASE'){
  $o=Initialize-PhaseAAdmissionStore $Root
  $null=Open-PhaseAAdmissionLease $o ('a'*32)
  [Environment]::Exit(7)
 }
 if($crashPoint -ceq 'CLEAN_JOURNAL_FLUSHED'){
  $b=@{Start={param($a,$m) $script:callbacks++;[IO.File]::WriteAllText((Join-Path $Root 'observed-callbacks'),[string]$script:callbacks);$a.pid=[int]123;$a.createdAt='2026-01-01T00:00:00Z';$a.contained=$true;$a.identity=$true};Wait={param($a,$n) $true};Terminate={param($a)};Close={param($a) $true}}
  $null=Invoke-PhaseAStateOnlyAttempt $Root ('a'*32) 1000 $b {return [long]0} {param($point) if($point -ceq 'CLEAN_JOURNAL_FLUSHED'){[Environment]::Exit(7)}}
  exit 8
 }
 if($crashPoint -ceq 'INTENT_JOURNAL_FLUSHED'){
  $o=Initialize-PhaseAAdmissionStore $Root
  $null=Open-PhaseAAdmissionLease $o ('a'*32) {param($point) if($point -ceq 'INTENT_JOURNAL_FLUSHED'){[Environment]::Exit(7)}}
  exit 8
 }
 $script:crashPoint=$crashPoint
 $null=Initialize-PhaseAAdmissionStore $Root {param($point) if($point -ceq $script:crashPoint){[Environment]::Exit(7)}}
 exit 8
}
function Need($v,$m){if(-not $v){throw $m}}
function NewRoot {$d=Join-Path $env:TEMP ('orion-r5-'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($d);return $d}
. (Join-Path $RootSource 'PhaseA.RestartProbeValidation.ps1')
function RejectRestart($d){
 try{
  $root=Get-AdmissionRoot $d;$claim=Join-Path $root 'admission.lock'
  $item=Get-Item -LiteralPath $claim -Force -ErrorAction Stop
  if($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)){return $false}
  $nonce=[guid]::NewGuid().ToString('N')
  $p=New-Object Diagnostics.ProcessStartInfo;$p.FileName=Join-Path $PSHOME 'powershell.exe'
  $test=Join-Path $RootSource 'PhaseA.RestartProbe.ps1';$source=Join-Path $RootSource 'PhaseA.DurableAdmission.ps1'
  $p.Arguments='-NoProfile -NonInteractive -File "'+$test+'" -Source "'+$source+'" -Nonce '+$nonce+' -Root "'+$root+'"'
  $p.UseShellExecute=$false;$p.CreateNoWindow=$true;$p.RedirectStandardOutput=$true;$p.RedirectStandardError=$true
  $c=[Diagnostics.Process]::Start($p)
  try{
   if(-not $c.WaitForExit(15000)){try{$c.Kill()}catch{throw 'PROBE_TERMINATION_UNCONFIRMED'};if(-not $c.WaitForExit(5000)){throw 'PROBE_TERMINATION_UNCONFIRMED'};throw 'PROBE_TIMEOUT'}
   $output=$c.StandardOutput.ReadToEnd();$err=$c.StandardError.ReadToEnd()
   if($err.Length -ne 0){return $false}
   return (Test-PhaseARestartProbeResult $output $c.ExitCode $nonce)
  }finally{$c.Dispose()}
 }catch{if($_.Exception.GetBaseException().Message -cin @('PROBE_TERMINATION_UNCONFIRMED','PROBE_TIMEOUT')){throw};return $false}
}
function Backend {return @{Start={param($a,$m) $script:callbacks++;$a.pid=[int]123;$a.createdAt='2026-01-01T00:00:00Z';$a.contained=$true;$a.identity=$true};Wait={param($a,$n) $true};Terminate={param($a)};Close={param($a) $true}}}
foreach($spec in @(
 @{id='F01';stage='RECEIPT';visible=$false;callbacks=0},
 @{id='F02';stage='RECEIPT';visible=$true;callbacks=0},
 @{id='F03';stage='INIT_JOURNAL';visible=$false;callbacks=0},
 @{id='F04';stage='MARKER';visible=$false;callbacks=0},
 @{id='F05';stage='INTENT_JOURNAL';visible=$false;callbacks=0},
 @{id='F06';stage='CLEAN_JOURNAL';visible=$false;callbacks=1}
)){
 $d=NewRoot;$script:callbacks=0;$script:issued=0;$script:calls=0;$script:target=$spec.stage;$script:visible=$spec.visible
 $flush={param($stream,$stage)
  if($stage -ceq $script:target){
   $script:calls++
   if($script:visible){$stream.Flush($true)}
   throw [IO.IOException]::new('INJECTED_FLUSH_OPERATION')
  }
  $stream.Flush($true)
 }
 $r=Invoke-PhaseAStateOnlyAttempt $d ('a'*32) 1000 (Backend) {return [long]0} $null $flush
 Need ($script:calls -eq 1) ($spec.id+'_OPERATION_NOT_REACHED')
 Need ($script:callbacks -eq $spec.callbacks -and $script:issued -eq $spec.callbacks) ($spec.id+'_CALLBACK_OR_LEASE_COUNT')
 Need ($r.status -ceq 'UNVERIFIED' -and $r.reason -ceq 'ADMISSION_OR_PUBLICATION_FAILED') ($spec.id+'_CLASSIFICATION')
 Need ([IO.File]::Exists((Join-Path $d 'admission.lock'))) ($spec.id+'_MISSING_CLAIM')
 if($spec.visible){Need ((Get-Item -LiteralPath (Join-Path $d 'admission.initialized')).Length -eq 67) 'F02_RECEIPT_NOT_VISIBLE'}
 Need (RejectRestart $d) ($spec.id+'_RESTART_ADMITTED')
 $journalState=try{(Read-PhaseAAdmissionStore (Join-Path $d 'admission.journal')).phase}catch{'INVALID_OR_UNAVAILABLE'}
 "{0} PASS injected IOException operation={1} calls=1 leases={2} callbacks={3} claim=present journal={4} receipt={5} restart=denied status=UNVERIFIED" -f $spec.id,$spec.stage,$script:issued,$script:callbacks,$journalState,[IO.File]::Exists((Join-Path $d 'admission.initialized'))
}
'R4-05 accounted by F02: injected receipt flush IOException calls=1 leases=0 callbacks=0 claim=present journal=INIT receiptBytes=67 restart=denied'
$sourceText=[IO.File]::ReadAllText((Join-Path $RootSource 'PhaseA.DurableAdmission.ps1'))
$markerReferences=[regex]::Matches($sourceText,"'admission\.init-failed'").Count
Need ($markerReferences -eq 1 -and $sourceText.Contains('if(Test-Path -LiteralPath (Join-Path $root ''admission.init-failed''))')) 'REMOVED_MARKER_SOURCE_MISMATCH'
foreach($id in @('R4-06','R4-07','R4-08','R4-09')){"$id NOT_APPLICABLE diagnostic marker persistence removed; no operation, lease or callback issued in this source check"}
$d=NewRoot;$script:throwCalls=0
try{Initialize-PhaseAAdmissionStore $d $null {param($s,$stage) if($stage -ceq 'RECEIPT'){$script:throwCalls++;throw [IO.IOException]::new('INJECTED_FLUSH_OPERATION')};$s.Flush($true)};throw 'FAILURE_NOT_RAISED'}catch{Need ($_.Exception.GetBaseException() -is [IO.IOException]) 'EXCEPTION_NOT_IO'}
Need ($script:throwCalls -eq 1 -and (RejectRestart $d)) 'DIRECT_EXCEPTION_NOT_RETAINED'
'PASS direct initializer retains injected IOException'
foreach($phase in @('INTENT','CLEAN')){
 $d=NewRoot;$o=Initialize-PhaseAAdmissionStore $d;$path=Join-Path $d 'admission.journal';$old=[IO.File]::ReadAllBytes($path)
 $l=Open-PhaseAAdmissionLease $o ('a'*32)
 if($phase -ceq 'CLEAN'){$good=@{source='LOCAL_UNTRUSTED';classification='OBSERVED';reason='NORMAL';wait='SIGNALED';cleanup='CONFIRMED';descendants='UNVERIFIED'};Publish-PhaseAStateOnlyClean $l $good}
 Close-PhaseAAdmissionLease $l;Need ([IO.File]::Exists((Join-Path $d 'admission.intent'))) 'INTENT_MARKER_MISSING';[IO.File]::WriteAllBytes($path,$old);Need ((Read-PhaseAAdmissionStore $path).phase -ceq 'INIT') 'ROLLBACK_NOT_INSTALLED'
 Need (RejectRestart $d) ('ROLLBACK_READMITTED_'+$phase)
 "PASS $phase journal-only rollback: claim retained and fresh process denied; rollback detection not claimed"
}
Add-Type -TypeDefinition 'using System;using System.Runtime.InteropServices;public static class OrionHandleInfoR5Test {[DllImport("kernel32.dll",SetLastError=true)]public static extern bool GetHandleInformation(IntPtr h,out uint f);}'
$d=NewRoot;$o=Initialize-PhaseAAdmissionStore $d
try{$flags=[uint32]0;$ok=[OrionHandleInfoR5Test]::GetHandleInformation($o.lock.SafeFileHandle.DangerousGetHandle(),[ref]$flags);Need $ok 'GET_HANDLE_INFORMATION_FAILED';Need (($flags -band 1) -eq 0) 'HANDLE_INHERITABLE';"PASS GetHandleInformation result=true flags=$flags inherit=0"}finally{Close-PhaseAAdmissionLease $o}
foreach($kind in @('MALFORMED','COPIED')){
 $d=NewRoot;$o=Initialize-PhaseAAdmissionStore $d;Close-PhaseAAdmissionLease $o
 $candidate=$d
 if($kind -ceq 'MALFORMED'){[IO.File]::WriteAllText((Join-Path $d 'admission.journal'),'malformed')}
 else{
  $candidate=NewRoot
  Get-ChildItem -LiteralPath $d -File | ForEach-Object {[IO.File]::Copy($_.FullName,(Join-Path $candidate $_.Name))}
 }
 Need (RejectRestart $candidate) ('ROLLBACK_CASE_READMITTED_'+$kind)
 "PASS $kind existing claim and fresh-process admission denial"
}
foreach($spec in @(
 @{id='R4-01';point='';callbacks=1;status='SIMULATED_COMPLETE'},
 @{id='R4-02';point='INIT_RECEIPT_CREATED';callbacks=0;status='UNVERIFIED'},
 @{id='R4-03';point='INIT_RECEIPT_PARTIAL';callbacks=0;status='UNVERIFIED'},
 @{id='R4-04';point='INIT_RECEIPT_FLUSHED';callbacks=0;status='UNVERIFIED'},
 @{id='R4-25';point='CLEAN_JOURNAL_PARTIAL';callbacks=1;status='UNVERIFIED'}
)){
 $d=NewRoot;$script:callbacks=0;$script:issued=0;$script:faultCount=0;$script:faultTarget=$spec.point
 $fault={param($point) if($point -ceq $script:faultTarget){$script:faultCount++;throw [IO.IOException]::new('INJECTED_BOUNDARY')}}
 $r=Invoke-PhaseAStateOnlyAttempt $d ('a'*32) 1000 (Backend) {return [long]0} $fault
 Need ($r.status -ceq $spec.status -and $script:callbacks -eq $spec.callbacks -and $script:issued -eq $spec.callbacks) ($spec.id+'_ACCOUNTING')
 if($spec.point){Need ($script:faultCount -eq 1) ($spec.id+'_NOT_REACHED')}
 Need ([IO.File]::Exists((Join-Path $d 'admission.lock')) -and (RejectRestart $d)) ($spec.id+'_CLAIM')
 $j=try{(Read-PhaseAAdmissionStore (Join-Path $d 'admission.journal')).phase}catch{'INVALID_OR_UNAVAILABLE'}
 $receipt=Join-Path $d 'admission.initialized'
 $size=if([IO.File]::Exists($receipt)){(Get-Item -LiteralPath $receipt).Length}else{-1}
 "{0} observed operation={1} faults={2} leases={3} callbacks={4} claim=present journal={5} receiptBytes={6} restart=denied status={7}" -f $spec.id,$spec.point,$script:faultCount,$script:issued,$script:callbacks,$j,$size,$r.status
}
$d=NewRoot;$script:callbacks=0;$script:issued=0;$be=Backend
$be.Start={param($a,$m) $script:callbacks++;throw [IO.IOException]::new('INJECTED_CALLBACK')}
$r=Invoke-PhaseAStateOnlyAttempt $d ('a'*32) 1000 $be {return [long]0}
Need ($r.status -ceq 'UNVERIFIED' -and $script:issued -eq 1 -and $script:callbacks -eq 1 -and (RejectRestart $d)) 'R4-24_ACCOUNTING'
"R4-24 observed callback=throws leases=$script:issued callbacks=$script:callbacks claim=present journal=$((Read-PhaseAAdmissionStore (Join-Path $d 'admission.journal')).phase) receiptBytes=$((Get-Item (Join-Path $d 'admission.initialized')).Length) restart=denied status=UNVERIFIED"
$d=NewRoot;$script:callbacks=0;$script:issued=0
$be=@{NativeGate=$true;Start={param($a,$m) $script:callbacks++}}
$r=Invoke-PhaseAStateOnlyAttempt $d ('a'*32) 1000 $be {return [long]0}
Need ($r.reason -ceq 'PROTOTYPE_INCIDENT_UNRESOLVED' -and $script:issued -eq 0 -and $script:callbacks -eq 0 -and -not [IO.File]::Exists((Join-Path $d 'admission.lock'))) 'R4-26_27_NATIVE_HOLD'
$r2=Invoke-PhaseAStateOnlyAttempt $d ('b'*32) 1000 $be {return [long]0}
Need ($r2.reason -ceq 'PROTOTYPE_INCIDENT_UNRESOLVED' -and $script:issued -eq 0 -and $script:callbacks -eq 0 -and -not [IO.File]::Exists((Join-Path $d 'admission.lock')) -and -not [IO.File]::Exists((Join-Path $d 'admission.journal')) -and -not [IO.File]::Exists((Join-Path $d 'admission.initialized'))) 'R4-26_27_RESTART'
'R4-26/27 observed native gate and repeated attempt leases=0 callbacks=0 claim=absent journal=absent receipt=absent restart=held status=PROTOTYPE_INCIDENT_UNRESOLVED'
foreach($spec in @(
 @{id='R4-10';point='INIT_LOCK_CREATED';leases=0;callbacks=0;journal='ABSENT';receipt=-1},
 @{id='R4-11';point='INIT_JOURNAL_CREATED';leases=0;callbacks=0;journal='INVALID_OR_UNAVAILABLE';receipt=-1},
 @{id='R4-12';point='INIT_RECEIPT_FLUSHED';leases=0;callbacks=0;journal='INIT';receipt=67},
 @{id='R4-13';point='INTENT_JOURNAL_FLUSHED';leases=0;callbacks=0;journal='INTENT';receipt=67},
 @{id='R4-14';point='AFTER_LEASE';leases=1;callbacks=0;journal='INTENT';receipt=67},
 @{id='R4-15';point='CLEAN_JOURNAL_FLUSHED';leases=1;callbacks=1;journal='CLEAN';receipt=67}
)){
 $d=NewRoot;$ps=New-Object Diagnostics.ProcessStartInfo;$ps.FileName=Join-Path $PSHOME 'powershell.exe'
 $ps.Arguments='-NoProfile -NonInteractive -File "'+$PSCommandPath+'" -RootSource "'+$RootSource+'" -Mode crash_'+$spec.point+' -Root "'+$d+'"'
 $ps.UseShellExecute=$false;$ps.CreateNoWindow=$true
 $child=[Diagnostics.Process]::Start($ps)
 try{if(-not $child.WaitForExit(15000)){try{$child.Kill()}catch{throw 'CRASH_CHILD_UNCONFIRMED'};if(-not $child.WaitForExit(5000)){throw 'CRASH_CHILD_UNCONFIRMED'};throw 'CRASH_CHILD_TIMEOUT'};Need ($child.ExitCode -eq 7) ($spec.id+'_EXIT')}finally{$child.Dispose()}
 $leases=[int][IO.File]::ReadAllText((Join-Path $d 'observed-leases'))
 $callbacks=[int][IO.File]::ReadAllText((Join-Path $d 'observed-callbacks'))
 $jp=Join-Path $d 'admission.journal'
 $journal=if(-not [IO.File]::Exists($jp)){'ABSENT'}else{try{(Read-PhaseAAdmissionStore $jp).phase}catch{'INVALID_OR_UNAVAILABLE'}}
 $rp=Join-Path $d 'admission.initialized';$size=if([IO.File]::Exists($rp)){(Get-Item -LiteralPath $rp).Length}else{-1}
 Need ($leases -eq $spec.leases -and $callbacks -eq $spec.callbacks -and $journal -ceq $spec.journal -and $size -eq $spec.receipt) ($spec.id+'_OBSERVATIONS')
 Need ([IO.File]::Exists((Join-Path $d 'admission.lock')) -and (RejectRestart $d)) ($spec.id+'_RESTART')
 "{0} cross-process exit=7 point={1} leases={2} callbacks={3} claim=present journal={4} receiptBytes={5} restart=denied" -f $spec.id,$spec.point,$leases,$callbacks,$journal,$size
}
$d=NewRoot;$script:issued=0;$script:callbacks=0;$owner=Initialize-PhaseAAdmissionStore $d
Need ([IO.File]::Exists((Join-Path $d 'admission.lock')) -and (RejectRestart $d) -and $script:issued -eq 0 -and $script:callbacks -eq 0) 'R4-16_NOT_EXCLUDED'
"R4-16 observed second claimant while held leases=$script:issued callbacks=$script:callbacks claim=present journal=$((Read-PhaseAAdmissionStore (Join-Path $d 'admission.journal')).phase) receiptBytes=$((Get-Item (Join-Path $d 'admission.initialized')).Length) restart=denied"
Close-PhaseAAdmissionLease $owner
Need ([IO.File]::Exists((Join-Path $d 'admission.lock')) -and (RejectRestart $d) -and $script:issued -eq 0 -and $script:callbacks -eq 0) 'R4-17_READMITTED'
"R4-17 observed second claimant after release leases=$script:issued callbacks=$script:callbacks claim=present journal=$((Read-PhaseAAdmissionStore (Join-Path $d 'admission.journal')).phase) receiptBytes=$((Get-Item (Join-Path $d 'admission.initialized')).Length) restart=denied"
$initState=Read-PhaseAAdmissionStore (Join-Path $d 'admission.journal')
$receiptExpected='1|'+(Get-AdmissionDigest ('1|'+$d.ToUpperInvariant()+'|'+$initState.previous))+[char]10
Need ($initState.phase -ceq 'INIT' -and -not [IO.File]::Exists((Join-Path $d 'admission.init-failed')) -and [IO.File]::ReadAllText((Join-Path $d 'admission.initialized')) -ceq $receiptExpected -and (RejectRestart $d)) 'R4-19_READMITTED'
"R4-19 observed existing receipt without failure marker leases=$script:issued callbacks=$script:callbacks claim=present journal=$((Read-PhaseAAdmissionStore (Join-Path $d 'admission.journal')).phase) receiptBytes=$((Get-Item (Join-Path $d 'admission.initialized')).Length) restart=denied"
$d=NewRoot;$children=@()
try {
$raceNonces=@([guid]::NewGuid().ToString('N'),[guid]::NewGuid().ToString('N'))
foreach($token in $raceNonces){
 $p=New-Object Diagnostics.ProcessStartInfo;$p.FileName=Join-Path $PSHOME 'powershell.exe'
 $p.Arguments='-NoProfile -NonInteractive -File "'+$PSCommandPath+'" -RootSource "'+$RootSource+'" -Mode race -Root "'+$d+'" -Token '+$token
 $p.UseShellExecute=$false;$p.CreateNoWindow=$true;$children+=,[Diagnostics.Process]::Start($p)
}
 foreach($child in $children){if(-not $child.WaitForExit(15000)){throw 'R4-18_TIMEOUT'};Need ($child.ExitCode -eq 0) 'R4-18_CHILD_FAILED'}
 $a=Get-Content -Raw -LiteralPath (Join-Path $d ('race-'+$raceNonces[0]+'.json'))|ConvertFrom-Json
 $b=Get-Content -Raw -LiteralPath (Join-Path $d ('race-'+$raceNonces[1]+'.json'))|ConvertFrom-Json
 foreach($entry in @(@($a,$raceNonces[0]),@($b,$raceNonces[1]))){
  $value=$entry[0];$expectedNonce=$entry[1]
  Need ($value.probeNonce -ceq $expectedNonce) 'R4-18_NONCE'
  if($value.claimed -eq 1){Need (Test-PhaseAClaimCreatedProbeResult $value.probeOutput $value.probeCode $expectedNonce) 'R4-18_CREATED_RESULT'}
  elseif($value.claimed -eq 0){Need (Test-PhaseARestartProbeResult $value.probeOutput $value.probeCode $expectedNonce) 'R4-18_DENIED_RESULT'}
  else{throw 'R4-18_RESULT_INVALID'}
 }
 Need (($a.claimed+$b.claimed) -eq 1 -and ($a.leases+$b.leases) -eq 0 -and ($a.callbacks+$b.callbacks) -eq 0 -and (RejectRestart $d)) 'R4-18_RACE_FAILED'
 "R4-18 cross-process claims=$($a.claimed+$b.claimed) leases=$($a.leases+$b.leases) callbacks=$($a.callbacks+$b.callbacks) claim=present journal=$((Read-PhaseAAdmissionStore (Join-Path $d 'admission.journal')).phase) receiptBytes=$((Get-Item (Join-Path $d 'admission.initialized')).Length) restart=denied"
}finally{
 $unconfirmed=$false
 foreach($child in $children){try{if(-not $child.HasExited){$child.Kill()};if(-not $child.WaitForExit(5000)){$unconfirmed=$true}}catch{$unconfirmed=$true}finally{$child.Dispose()}}
 if($unconfirmed){throw 'R4-18_CHILD_UNCONFIRMED'}
}
foreach($kind in @('MALFORMED','COPIED')){
 $d=NewRoot;$script:issued=0;$script:callbacks=0;$owner=Initialize-PhaseAAdmissionStore $d;Close-PhaseAAdmissionLease $owner
 $candidate=$d;$expected='INVALID_OR_UNAVAILABLE';$case='R4-20'
 if($kind -ceq 'MALFORMED'){[IO.File]::WriteAllText((Join-Path $d 'admission.journal'),'malformed')}
 else{$case='R4-21';$expected='INIT';$candidate=NewRoot;Get-ChildItem -LiteralPath $d -File|ForEach-Object {[IO.File]::Copy($_.FullName,(Join-Path $candidate $_.Name))}}
 $journal=try{(Read-PhaseAAdmissionStore (Join-Path $candidate 'admission.journal')).phase}catch{'INVALID_OR_UNAVAILABLE'}
 Need ([IO.File]::Exists((Join-Path $candidate 'admission.lock')) -and $journal -ceq $expected -and $script:issued -eq 0 -and $script:callbacks -eq 0 -and (RejectRestart $candidate)) ($case+'_READMITTED')
 "$case observed $kind leases=$script:issued callbacks=$script:callbacks claim=present journal=$journal receiptBytes=$((Get-Item (Join-Path $candidate 'admission.initialized')).Length) restart=denied"
}
$a=NewRoot;$b=NewRoot;$script:issued=0;$script:callbacks=0
$oa=Initialize-PhaseAAdmissionStore $a;$ob=Initialize-PhaseAAdmissionStore $b
try{
 $root0=$oa.root;$path0=$oa.path;$lock0=$oa.lock;$oa.root=$ob.root;$oa.path=$ob.path;$oa.lock=$ob.lock
 $blocked=$false;try{$null=Open-PhaseAAdmissionLease $oa ('a'*32)}catch{$blocked=$true}
 $oa.root=$root0;$oa.path=$path0;$oa.lock=$lock0
 Need ($blocked -and $script:issued -eq 0 -and $script:callbacks -eq 0) 'R4-22_CROSS_DOMAIN'
}finally{Close-PhaseAAdmissionLease $oa;Close-PhaseAAdmissionLease $ob}
$staleBlocked=$false;try{$null=Open-PhaseAAdmissionLease $oa ('a'*32)}catch{$staleBlocked=$true}
Need ($staleBlocked -and [IO.File]::Exists((Join-Path $a 'admission.lock')) -and [IO.File]::Exists((Join-Path $b 'admission.lock')) -and (RejectRestart $a) -and (RejectRestart $b)) 'R4-22_RESTART'
"R4-22 observed cross-domain and released owner rejected leases=$script:issued callbacks=$script:callbacks claim=present journal=$((Read-PhaseAAdmissionStore (Join-Path $a 'admission.journal')).phase) receiptBytes=$((Get-Item (Join-Path $a 'admission.initialized')).Length) restart=denied"
$d=NewRoot;$script:issued=0;$script:callbacks=0;$o=Initialize-PhaseAAdmissionStore $d;$l=Open-PhaseAAdmissionLease $o ('a'*32)
$blocked=$false;try{$null=Open-PhaseAAdmissionLease $o ('b'*32)}catch{$blocked=$true}
Close-PhaseAAdmissionLease $l
Need ($blocked -and [IO.File]::Exists((Join-Path $d 'admission.lock')) -and $script:issued -eq 1 -and $script:callbacks -eq 0 -and (RejectRestart $d)) 'R4-23_REUSE'
"R4-23 observed lease reuse rejected leases=$script:issued callbacks=$script:callbacks claim=present journal=$((Read-PhaseAAdmissionStore (Join-Path $d 'admission.journal')).phase) receiptBytes=$((Get-Item (Join-Path $d 'admission.initialized')).Length) restart=denied"
foreach($phase in @('INTENT','CLEAN')){
 $d=NewRoot;$script:issued=0;$script:callbacks=0;$o=Initialize-PhaseAAdmissionStore $d;$jp=Join-Path $d 'admission.journal';$old=[IO.File]::ReadAllBytes($jp)
 $l=Open-PhaseAAdmissionLease $o ('a'*32)
 if($phase -ceq 'CLEAN'){$good=@{source='LOCAL_UNTRUSTED';classification='OBSERVED';reason='NORMAL';wait='SIGNALED';cleanup='CONFIRMED';descendants='UNVERIFIED'};Publish-PhaseAStateOnlyClean $l $good}
 Close-PhaseAAdmissionLease $l;[IO.File]::WriteAllBytes($jp,$old)
 Need ([IO.File]::Exists((Join-Path $d 'admission.lock')) -and [IO.File]::Exists((Join-Path $d 'admission.intent')) -and $script:issued -eq 1 -and $script:callbacks -eq 0 -and (Read-PhaseAAdmissionStore $jp).phase -ceq 'INIT' -and (RejectRestart $d)) ('R4-28_'+$phase)
 "R4-28 observed rollback after $phase leases=1 callbacks=0 claim=present journal=$((Read-PhaseAAdmissionStore $jp).phase) receiptBytes=$((Get-Item (Join-Path $d 'admission.initialized')).Length) restart=denied (not rollback detection)"
}
'R4-29 coordinated rollback is UNSUPPORTED; no bypass test executed'
'R4-30 accounted by R4-01: leases=1 callbacks=1 claim=present journal=CLEAN receiptBytes=67 restart=denied'
