# Local crash diagnostics only. A hash chain is not authentication or an
# anti-rollback mechanism. This module never authorizes cleanup or acceptance.
function Get-PhaseARecoveryDigest([string]$Text) {
 $sha=[Security.Cryptography.SHA256]::Create()
 try {return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text))).Replace('-','').ToLowerInvariant())}
 finally {$sha.Dispose()}
}
function New-PhaseARecoveryJournal([string]$Path,[string]$Experiment) {
 if($Experiment -cnotmatch '^[0-9a-f]{32}$'){throw 'JOURNAL_EXPERIMENT_INVALID'}
 $s=New-Object IO.FileStream($Path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read)
 return @{stream=$s;experiment=$Experiment;sequence=0;previous=('0'*64);phase='NONE'}
}
function Write-PhaseARecoveryJournal($Journal,[string]$Phase,[int]$WorkerPid,[string]$CreatedAt,[string]$Operation,[string]$Cleanup,[bool]$Unresolved,[string]$Resources='UNKNOWN',[string]$CleanupAttempt='NOT_ATTEMPTED') {
 $next=@{NONE=@('STARTED');STARTED=@('PROCESS_IDENTIFIED','PRE_CLEANUP');PROCESS_IDENTIFIED=@('PRE_CLEANUP');PRE_CLEANUP=@('CLEANUP_OBSERVED');CLEANUP_OBSERVED=@()}
 if($null -eq $Journal -or $next[$Journal.phase] -cnotcontains $Phase -or $WorkerPid -lt 0 -or $CreatedAt -cnotmatch '^[0-9TZ: .+\-]{0,40}$' -or $Operation -cnotmatch '^[A-Z0-9_]{1,64}$' -or $Cleanup -cnotin @('NOT_STARTED','NOT_CONFIRMED','CONFIRMED','FAILED','RESOURCE_RETAINED') -or $Resources -cnotin @('NONE','UNKNOWN','PROCESS_JOB_IO') -or $CleanupAttempt -cnotin @('NOT_ATTEMPTED','ATTEMPTED','UNKNOWN')){throw 'JOURNAL_RECORD_INVALID'}
 if(($WorkerPid -eq 0 -and $CreatedAt -cne '') -or ($Phase -ceq 'PROCESS_IDENTIFIED' -and ($WorkerPid -eq 0 -or $CreatedAt -ceq ''))){throw 'JOURNAL_IDENTITY_INVALID'}
 $seq=[int]$Journal.sequence+1
 if($Journal.ContainsKey('identifiedPid') -and ($WorkerPid -ne $Journal.identifiedPid -or $CreatedAt -cne $Journal.identifiedAt)){throw 'JOURNAL_IDENTITY_MISMATCH'}
 $line=@('1',$Journal.experiment,[string]$seq,$Phase,[string]$WorkerPid,$CreatedAt,$Operation,$Cleanup,$(if($Unresolved){'1'}else{'0'}),$Resources,$CleanupAttempt,$Journal.previous) -join '|'
 $hash=Get-PhaseARecoveryDigest $line
 $bytes=[Text.Encoding]::UTF8.GetBytes($line+'|'+$hash+"`n")
 $Journal.stream.Write($bytes,0,$bytes.Length)
 $Journal.stream.Flush($true)
 $Journal.sequence=$seq;$Journal.previous=$hash;$Journal.phase=$Phase
 if($Phase -ceq 'PROCESS_IDENTIFIED'){$Journal.identifiedPid=$WorkerPid;$Journal.identifiedAt=$CreatedAt}
}
function Read-PhaseARecoveryJournal([string]$Path,[string]$ExpectedExperiment) {
 $bad=@{status='UNVERIFIED';integrity='INVALID';lastTransition='UNKNOWN';unresolved=$true}
 try {
  if($ExpectedExperiment -cnotmatch '^[0-9a-f]{32}$' -or -not [IO.File]::Exists($Path)){return $bad}
  $item=Get-Item -LiteralPath $Path -Force
  if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -or $item.Length -lt 1 -or $item.Length -gt 262144){return $bad}
  $bytes=[IO.File]::ReadAllBytes($Path);if($bytes[$bytes.Length-1] -ne 10){return $bad}
  $utf8=New-Object Text.UTF8Encoding($false,$true);$text=$utf8.GetString($bytes)
  $lines=$text.Substring(0,$text.Length-1).Split("`n");if($lines.Count -lt 1 -or $lines.Count -gt 4){return $bad}
  $prior='0'*64;$seq=0;$phase='NONE';$last=$null;$identifiedPid=$null;$identifiedAt=$null
  $next=@{NONE=@('STARTED');STARTED=@('PROCESS_IDENTIFIED','PRE_CLEANUP');PROCESS_IDENTIFIED=@('PRE_CLEANUP');PRE_CLEANUP=@('CLEANUP_OBSERVED');CLEANUP_OBSERVED=@()}
  foreach($line in $lines) {
   $f=$line.Split('|');$seq++
   if($f.Count -ne 13 -or $f[0] -cne '1' -or $f[1] -cne $ExpectedExperiment -or $f[2] -cne [string]$seq -or $next[$phase] -cnotcontains $f[3] -or $f[4] -cnotmatch '^(0|[1-9][0-9]{0,9})$' -or [long]$f[4] -gt [int]::MaxValue -or $f[5] -cnotmatch '^[0-9TZ: .+\-]{0,40}$' -or $f[6] -cnotmatch '^[A-Z0-9_]{1,64}$' -or $f[7] -cnotin @('NOT_STARTED','NOT_CONFIRMED','CONFIRMED','FAILED','RESOURCE_RETAINED') -or $f[8] -cnotin @('0','1') -or $f[9] -cnotin @('NONE','UNKNOWN','PROCESS_JOB_IO') -or $f[10] -cnotin @('NOT_ATTEMPTED','ATTEMPTED','UNKNOWN') -or $f[11] -cne $prior -or $f[12] -cnotmatch '^[0-9a-f]{64}$'){return $bad}
   if(($f[4] -ceq '0' -and $f[5] -cne '') -or ($f[3] -ceq 'PROCESS_IDENTIFIED' -and ($f[4] -ceq '0' -or $f[5] -ceq ''))){return $bad}
   if($null -ne $identifiedPid -and ($f[4] -cne $identifiedPid -or $f[5] -cne $identifiedAt)){return $bad}
   if($f[3] -ceq 'PROCESS_IDENTIFIED'){$identifiedPid=$f[4];$identifiedAt=$f[5]}
   $body=$f[0..11] -join '|';if((Get-PhaseARecoveryDigest $body) -cne $f[12]){return $bad}
   $prior=$f[12];$phase=$f[3];$last=$f
  }
  return @{status='UNVERIFIED';integrity='VALID';lastTransition=$phase;unresolved=($last[8] -ceq '1');operation=$last[6];cleanup=$last[7];resources=$last[9];cleanupAttempt=$last[10];pid=[int]$last[4];createdAt=$last[5]}
 } catch {return $bad}
}
