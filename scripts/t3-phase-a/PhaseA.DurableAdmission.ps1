# State-only cooperating-process prototype. No native recovery or anti-rollback authority.
if ($null -eq $script:phaseAAdmissionOwners) { $script:phaseAAdmissionOwners = @{} }
function Get-AdmissionDigest([string]$text) {
 $h=[Security.Cryptography.SHA256]::Create()
 try{return ([BitConverter]::ToString($h.ComputeHash([Text.Encoding]::UTF8.GetBytes($text)))).Replace('-','').ToLowerInvariant()}finally{$h.Dispose()}
}
function Invoke-AdmissionFault([scriptblock]$Fault,[string]$Point) {if($null -ne $Fault){$null=& $Fault $Point}}
# The injectable operation is a local test seam, not evidence of a storage failure.
function Invoke-AdmissionFlush([IO.FileStream]$stream,[string]$operation,[scriptblock]$Flush=$null) {
 if($null -eq $Flush){$stream.Flush($true);return}
 $ErrorActionPreference='Stop'
 $records=@(& $Flush $stream $operation 2>&1)
 foreach($record in $records){if($record -is [Management.Automation.ErrorRecord]){throw $record}}
 if($records.Count -ne 0){throw 'ADMISSION_FLUSH_UNEXPECTED_OUTPUT'}
}
function Get-AdmissionRoot([string]$directory) {
 if([string]::IsNullOrWhiteSpace($directory) -or $directory -cnotmatch '^[A-Za-z]:\\'){throw 'ADMISSION_DIRECTORY_INVALID'}
 $full=[IO.Path]::GetFullPath($directory);$drive=New-Object IO.DriveInfo([IO.Path]::GetPathRoot($full));if($drive.DriveType -ne [IO.DriveType]::Fixed -or $drive.DriveFormat -cne 'NTFS'){throw 'ADMISSION_DIRECTORY_INVALID'};$d=Get-Item -LiteralPath $full -Force -ErrorAction Stop
 if(-not $d.PSIsContainer){throw 'ADMISSION_DIRECTORY_INVALID'}
 $cursor=$d
 while($null -ne $cursor){if($cursor.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'ADMISSION_DIRECTORY_INVALID'};$cursor=$cursor.Parent}
 return $d.FullName
}
function Add-AdmissionRecord($lease,[string]$phase,[string]$session,[int]$ownerPid,[string]$created,[scriptblock]$Fault=$null,[scriptblock]$Flush=$null) {
 if($lease -isnot [hashtable] -or $null -eq $lease.lock -or -not $lease.lock.CanWrite){throw 'LEASE_INVALID'}
 if($phase -ceq 'INIT'){
  if($lease.phase -cne 'NONE' -or $lease.sequence -ne 0 -or $session -cne ('0'*32) -or $ownerPid -ne 0 -or $created -cne ''){throw 'TRANSITION_INVALID'}
 } else {
  if(-not $lease.ownerKey -or -not $script:phaseAAdmissionOwners.ContainsKey($lease.ownerKey)){throw 'LEASE_INVALID'}
  $owned=$script:phaseAAdmissionOwners[$lease.ownerKey]
  if(-not [object]::ReferenceEquals($owned.owner,$lease) -or -not [object]::ReferenceEquals($owned.lock,$lease.lock) -or $owned.root -cne $lease.root -or $owned.path -cne $lease.path -or -not $owned.opened){throw 'LEASE_INVALID'}
  $lockedPath=[IO.Path]::GetFullPath($lease.lock.Name)
  $expectedLock=[IO.Path]::GetFullPath((Join-Path $lease.root 'admission.lock'))
  $expectedJournal=[IO.Path]::GetFullPath((Join-Path $lease.root 'admission.journal'))
  if(-not [string]::Equals($lockedPath,$expectedLock,[StringComparison]::OrdinalIgnoreCase) -or -not [string]::Equals([IO.Path]::GetFullPath($lease.path),$expectedJournal,[StringComparison]::OrdinalIgnoreCase)){throw 'TRANSITION_INVALID'}
  $markerPath=Join-Path $lease.root 'admission.intent'
  $markerItem=Get-Item -LiteralPath $markerPath -Force -ErrorAction Stop
  if($markerItem.PSIsContainer -or ($markerItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -or $markerItem.Length -ne 33){throw 'MARKER_INVALID'}
  $marker=[IO.File]::ReadAllBytes($markerPath)
  $expected=[Text.Encoding]::UTF8.GetBytes($lease.session+[char]10)
  if([Convert]::ToBase64String($marker) -cne [Convert]::ToBase64String($expected)){throw 'MARKER_INVALID'}
  $state=Read-PhaseAAdmissionStore $lease.path
  if($state.sequence -ne $lease.sequence -or $state.previous -cne $lease.previous -or $state.phase -cne $lease.phase -or $session -cne $lease.session -or $ownerPid -ne $lease.ownerPid -or $created -cne $lease.ownerCreated){throw 'TRANSITION_INVALID'}
  if(($phase -ceq 'INTENT' -and $lease.phase -cne 'INIT') -or ($phase -ceq 'CLEAN' -and $lease.phase -cne 'INTENT') -or $phase -cnotin @('INTENT','CLEAN')){throw 'TRANSITION_INVALID'}
  if($phase -ceq 'CLEAN' -and $state.session -cne $session){throw 'TRANSITION_INVALID'}
 }
 $seq=[int]$lease.sequence+1
 $body=@('1',[string]$seq,$phase,$session,[string]$ownerPid,$created,$lease.previous) -join '|'
 $digest=Get-AdmissionDigest $body;$bytes=[Text.Encoding]::UTF8.GetBytes($body+'|'+$digest+[char]10)
 Invoke-AdmissionFault $Fault ($phase+'_JOURNAL_BEFORE_OPEN')
 $s=New-Object IO.FileStream($lease.path,[IO.FileMode]::Open,[IO.FileAccess]::Write,[IO.FileShare]::Read)
 try {
  [void]$s.Seek(0,[IO.SeekOrigin]::End);Invoke-AdmissionFault $Fault ($phase+'_JOURNAL_BEFORE_WRITE')
  $half=[int][Math]::Floor($bytes.Length/2.0);$s.Write($bytes,0,$half);Invoke-AdmissionFault $Fault ($phase+'_JOURNAL_PARTIAL')
  $s.Write($bytes,$half,$bytes.Length-$half);Invoke-AdmissionFault $Fault ($phase+'_JOURNAL_WRITTEN')
  Invoke-AdmissionFlush $s ($phase+'_JOURNAL') $Flush;Invoke-AdmissionFault $Fault ($phase+'_JOURNAL_FLUSHED')
 } finally {$s.Dispose()}
 $lease.sequence=$seq;$lease.previous=$digest;$lease.phase=$phase
}
function Initialize-PhaseAAdmissionStore([string]$directory,[scriptblock]$Fault=$null,[scriptblock]$Flush=$null) {
 $root=Get-AdmissionRoot $directory;$lk=$null
 try {
  Invoke-AdmissionFault $Fault 'INIT_LOCK_BEFORE_CREATE'
  $lk=New-Object IO.FileStream((Join-Path $root 'admission.lock'),[IO.FileMode]::CreateNew,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
  Invoke-AdmissionFault $Fault 'INIT_LOCK_CREATED'
  $p=Join-Path $root 'admission.journal'
  Invoke-AdmissionFault $Fault 'INIT_JOURNAL_BEFORE_CREATE'
  $s=New-Object IO.FileStream($p,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read)
  try{Invoke-AdmissionFault $Fault 'INIT_JOURNAL_CREATED';Invoke-AdmissionFlush $s 'INIT_EMPTY' $Flush}finally{$s.Dispose()}
  $l=@{lock=$lk;path=$p;sequence=0;previous=('0'*64);phase='NONE'}
  Add-AdmissionRecord $l 'INIT' ('0'*32) 0 '' $Fault $Flush
  # This is a local consistency receipt, not an authenticated anti-rollback record.
  $binding=Get-AdmissionDigest ('1|'+$root.ToUpperInvariant()+'|'+$l.previous)
  $bytes=[Text.Encoding]::UTF8.GetBytes('1|'+$binding+[char]10)
  $receipt=New-Object IO.FileStream((Join-Path $root 'admission.initialized'),[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read)
  try{
   Invoke-AdmissionFault $Fault 'INIT_RECEIPT_CREATED'
   $half=[int][Math]::Floor($bytes.Length/2.0);$receipt.Write($bytes,0,$half);Invoke-AdmissionFault $Fault 'INIT_RECEIPT_PARTIAL'
   $receipt.Write($bytes,$half,$bytes.Length-$half);Invoke-AdmissionFault $Fault 'INIT_RECEIPT_WRITTEN'
   Invoke-AdmissionFlush $receipt 'RECEIPT' $Flush;Invoke-AdmissionFault $Fault 'INIT_RECEIPT_FLUSHED'
  }finally{$receipt.Dispose()}
  $key=[Guid]::NewGuid().ToString('N')
  $owner=@{lock=$lk;path=$p;root=$root;sequence=$l.sequence;previous=$l.previous;phase='INIT';ownerKey=$key;consumed=$false}
  $script:phaseAAdmissionOwners[$key]=@{owner=$owner;lock=$lk;root=$root;path=$p;opened=$false}
  $lk=$null
  return $owner
 } finally {if($null -ne $lk){$lk.Dispose()}}
}
function Read-PhaseAAdmissionStore([string]$path) {
 $f=Get-Item -LiteralPath $path -Force -ErrorAction Stop
 if($f.PSIsContainer -or ($f.Attributes -band [IO.FileAttributes]::ReparsePoint) -or $f.Length -lt 1 -or $f.Length -gt 1048576){throw 'STATE_INVALID'}
 $raw=[IO.File]::ReadAllBytes($path);if($raw[$raw.Length-1] -ne 10){throw 'STATE_INVALID'}
 $utf=New-Object Text.UTF8Encoding($false,$true);$text=$utf.GetString($raw);$lines=$text.Substring(0,$text.Length-1).Split([char]10)
 $prior='0'*64;$seq=0;$phase='NONE';$current='';$ownerPid=0;$ownerCreated=''
 foreach($line in $lines){
  $f=$line.Split('|');$seq++
  if($f.Count -ne 8 -or $f[0] -cne '1' -or $f[1] -cne [string]$seq -or $f[2] -cnotin @('INIT','INTENT','CLEAN') -or $f[3] -cnotmatch '^[0-9a-f]{32}$' -or $f[4] -cnotmatch '^(0|[1-9][0-9]{0,9})$' -or [long]$f[4] -gt [int]::MaxValue -or $f[6] -cne $prior -or $f[7] -cnotmatch '^[0-9a-f]{64}$'){throw 'STATE_INVALID'}
  $body=$f[0..6] -join '|';if((Get-AdmissionDigest $body) -cne $f[7]){throw 'STATE_INVALID'}
  if($f[2] -ceq 'INIT'){
   if($phase -cne 'NONE' -or $seq -ne 1 -or $f[3] -cne ('0'*32) -or $f[4] -cne '0' -or $f[5] -cne ''){throw 'STATE_INVALID'}
  } elseif($f[2] -ceq 'INTENT'){
   $stamp=[DateTimeOffset]::MinValue
   if($phase -cne 'INIT' -or $f[3] -ceq ('0'*32) -or $f[4] -ceq '0' -or -not [DateTimeOffset]::TryParseExact($f[5],'o',[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::None,[ref]$stamp)){throw 'STATE_INVALID'}
   $current=$f[3];$ownerPid=[int]$f[4];$ownerCreated=$f[5]
  } else {
   if($phase -cne 'INTENT' -or $f[3] -cne $current -or [int]$f[4] -ne $ownerPid -or $f[5] -cne $ownerCreated){throw 'STATE_INVALID'}
  }
  $prior=$f[7];$phase=$f[2]
 }
 return @{sequence=$seq;previous=$prior;phase=$phase;session=$current;ownerPid=$ownerPid;ownerCreated=$ownerCreated}
}
function Open-PhaseAAdmissionLease($owner,[string]$session,[scriptblock]$Fault=$null,[scriptblock]$Flush=$null) {
 if($session -cnotmatch '^[0-9a-f]{32}$' -or $session -ceq ('0'*32)){throw 'SESSION_INVALID'}
 if($owner -isnot [hashtable] -or -not $owner.ownerKey -or -not $script:phaseAAdmissionOwners.ContainsKey($owner.ownerKey)){throw 'OWNER_REQUIRED'}
 $binding=$script:phaseAAdmissionOwners[$owner.ownerKey]
 if(-not [object]::ReferenceEquals($binding.owner,$owner) -or -not [object]::ReferenceEquals($binding.lock,$owner.lock) -or $binding.root -cne $owner.root -or $binding.path -cne $owner.path -or $binding.opened -or $owner.consumed -or $null -eq $owner.lock -or -not $owner.lock.CanWrite){throw 'OWNER_REQUIRED'}
 $binding.opened=$true
 $owner.consumed=$true
 $lock=$owner.lock
 try {
  $root=Get-AdmissionRoot $owner.root;$path=Join-Path $root 'admission.journal'
  if(-not [string]::Equals([IO.Path]::GetFullPath($owner.lock.Name),[IO.Path]::GetFullPath((Join-Path $root 'admission.lock')),[StringComparison]::OrdinalIgnoreCase) -or -not [string]::Equals([IO.Path]::GetFullPath($owner.path),[IO.Path]::GetFullPath($path),[StringComparison]::OrdinalIgnoreCase)){throw 'OWNER_INVALID'}
  $state=Read-PhaseAAdmissionStore $path
  if($state.phase -cne 'INIT'){throw 'ADMISSION_UNRESOLVED'}
  if(Test-Path -LiteralPath (Join-Path $root 'admission.init-failed')){throw 'INITIALIZATION_FAILED'}
  $receiptPath=Join-Path $root 'admission.initialized'
  $receiptItem=Get-Item -LiteralPath $receiptPath -Force -ErrorAction Stop
  if($receiptItem.PSIsContainer -or ($receiptItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -or $receiptItem.Length -ne 67){throw 'INITIALIZATION_INVALID'}
  $expectedReceipt='1|'+(Get-AdmissionDigest ('1|'+$root.ToUpperInvariant()+'|'+$state.previous))+[char]10
  if([Convert]::ToBase64String([IO.File]::ReadAllBytes($receiptPath)) -cne [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($expectedReceipt))){throw 'INITIALIZATION_INVALID'}
  $p=[Diagnostics.Process]::GetCurrentProcess();try{$pidValue=$p.Id;$created=$p.StartTime.ToUniversalTime().ToString('o')}finally{$p.Dispose()}
  $intentPath=Join-Path $root 'admission.intent'
  if(Test-Path -LiteralPath $intentPath){throw 'ADMISSION_UNRESOLVED'}
  $marker=New-Object IO.FileStream($intentPath,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read)
  try {
   Invoke-AdmissionFault $Fault 'MARKER_CREATED'
   $bytes=[Text.Encoding]::UTF8.GetBytes($session+[char]10);$half=[int][Math]::Floor($bytes.Length/2.0)
   $marker.Write($bytes,0,$half);Invoke-AdmissionFault $Fault 'MARKER_PARTIAL'
   $marker.Write($bytes,$half,$bytes.Length-$half);Invoke-AdmissionFault $Fault 'MARKER_WRITTEN'
   Invoke-AdmissionFlush $marker 'MARKER' $Flush;Invoke-AdmissionFault $Fault 'MARKER_FLUSHED'
  } finally {$marker.Dispose()}
  $owner.session=$session;$owner.ownerPid=$pidValue;$owner.ownerCreated=$created;$lease=$owner
  Add-AdmissionRecord $lease 'INTENT' $session $pidValue $created $Fault $Flush
  return $lease
 } catch {Close-PhaseAAdmissionLease $owner;throw}
}
function Publish-PhaseAStateOnlyClean($lease,[hashtable]$Result,[scriptblock]$Fault=$null,[scriptblock]$Flush=$null) {
 if($lease.phase -cne 'INTENT' -or $Result.source -cne 'LOCAL_UNTRUSTED' -or $Result.classification -cne 'OBSERVED' -or $Result.reason -cne 'NORMAL' -or $Result.wait -cne 'SIGNALED' -or $Result.cleanup -cne 'CONFIRMED' -or $Result.descendants -cne 'UNVERIFIED'){throw 'SYNTHETIC_OBSERVATION_INVALID'}
 Add-AdmissionRecord $lease 'CLEAN' $lease.session $lease.ownerPid $lease.ownerCreated $Fault $Flush
}
function Close-PhaseAAdmissionLease($lease) {
 if($lease -isnot [hashtable] -or -not $lease.ownerKey -or -not $script:phaseAAdmissionOwners.ContainsKey($lease.ownerKey)){return}
 $binding=$script:phaseAAdmissionOwners[$lease.ownerKey]
 if(-not [object]::ReferenceEquals($binding.owner,$lease)){throw 'OWNER_REQUIRED'}
 $script:phaseAAdmissionOwners.Remove($lease.ownerKey)
 if($null -ne $binding.lock){$binding.lock.Dispose()}
 $lease.lock=$null
}