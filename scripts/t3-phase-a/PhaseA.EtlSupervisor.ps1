# Same-identity offline parser supervision. Does not control an ETW session.
. "$PSScriptRoot/PhaseA.Native.ps1"
. "$PSScriptRoot/PhaseA.Atomic.ps1"
. "$PSScriptRoot/PhaseA.RecoveryJournal.ps1"
if (-not $script:EtlUnconfirmed) { $script:EtlUnconfirmed=New-Object System.Collections.ArrayList }
function Get-PhaseAEtlNativeCategory([Exception]$Exception) {
 while ($Exception) {
  if ($Exception -is [ComponentModel.Win32Exception]) {
   switch ($Exception.NativeErrorCode) {
    4551 {return 'APPLICATION_CONTROL_BLOCKED'}
    1260 {return 'APPLICATION_CONTROL_BLOCKED'}
    5 {return 'ACCESS_DENIED'}
    default {return 'NATIVE_OPERATION_FAILED'}
   }
  }
  $Exception=$Exception.InnerException
 }
 return 'UNCLASSIFIED'
}
function Invoke-PhaseAEtlWait($Child,[uint32]$Milliseconds) {return $Child.Wait($Milliseconds)}
function Close-PhaseAEtlJob($Job) {[EtherPhaseAJob]::Close($Job)}
function Close-PhaseAEtlChildHandles($Child) {return $Child.CloseObserved()}
function Invoke-PhaseAEtlWorker {
 param(
  [Parameter(Mandatory=$true)][string]$Executable,
  [Parameter(Mandatory=$true)][string]$ExecutableHash,
  [Parameter(Mandatory=$true)][string]$ExperimentDirectory,
  [int]$TimeoutMs=10000,[int]$TerminationMs=5000,[int]$MaximumOutputBytes=65536,
  [Threading.CancellationToken]$Cancellation=[Threading.CancellationToken]::None
 )
 $r=@{classification='UNVERIFIED';operationClassification=$null;pid=0;createdAt=$null;sid=$null;tokenProperties=$null;contained=$false;terminationConfirmed=$false;exitCode=$null;stdout='NOT_CAPTURED';stderr='NOT_CAPTURED';outputJson=$null;transfer='NOT_ESTABLISHED';dependencyState='NOT_ATTESTED';dependencyCount=0;cleanup='NOT_CONFIRMED';cleanupDiagnostic='NONE';close=$null;diagnostic='NONE';source='CAPTURED_UNTRUSTED';experiment=[Guid]::NewGuid().ToString('N');journal='NOT_ESTABLISHED'}
 $job=[IntPtr]::Zero;$child=$null;$proc=$null;$root=$null;$inputHandle=$null;$exeHandle=$null;$outputHandle=$null;$pipes=$null;$pipeUnconfirmed=$false;$journal=$null;$preCleanup=$false;$journalFailed=$false;$cleanupAttempted=$false
 $dependencyHandles=New-Object 'System.Collections.Generic.List[System.IO.FileStream]'
 try {
  if ($TimeoutMs -lt 100 -or $TimeoutMs -gt 60000 -or $TerminationMs -lt 100 -or $TerminationMs -gt 10000 -or $MaximumOutputBytes -lt 1 -or $MaximumOutputBytes -gt 1048576) {throw 'INVALID_LIMIT'}
  $root=[IO.Path]::GetFullPath($ExperimentDirectory)
  $entry=Get-Item -LiteralPath $root -Force -ErrorAction Stop
  if (-not $entry.PSIsContainer -or ($entry.Attributes -band [IO.FileAttributes]::ReparsePoint)) {throw 'EXPERIMENT_DIRECTORY_INVALID'}
  $journal=New-PhaseARecoveryJournal (Join-Path $root 'recovery.journal') $r.experiment
  Write-PhaseARecoveryJournal $journal 'STARTED' 0 '' 'UNVERIFIED' 'NOT_STARTED' $false 'NONE' 'NOT_ATTEMPTED'
  $r.journal='STARTED_DURABLE'
  $inputPath=Join-Path $root 'input.etl';$outputPath=Join-Path $root 'result.json'
  if (-not [IO.File]::Exists($inputPath)) {throw 'INPUT_MISSING'}
  if ((Get-Item -LiteralPath $inputPath -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) {throw 'INPUT_REPARSE'}
  if ([IO.File]::Exists($outputPath)) {throw 'OUTPUT_EXISTS'}
  if (-not [IO.File]::Exists($Executable)) {throw 'EXECUTABLE_MISSING'}
  if ((Get-Item -LiteralPath $Executable -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) {throw 'EXECUTABLE_REPARSE'}
  $Executable=[IO.Path]::GetFullPath($Executable)
  if ([IO.Path]::GetExtension($Executable) -ine '.exe') {throw 'EXECUTABLE_TYPE_INVALID'}
  $exeHandle=New-Object IO.FileStream($Executable,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
  if ((Get-FileHash -InputStream $exeHandle -Algorithm SHA256).Hash -cne $ExecutableHash.ToUpperInvariant()) {throw 'EXECUTABLE_HASH_MISMATCH'}
  # A stable local measurement is not an independent trust attestation. Lock
  # existing top-level managed/native assemblies and runtime metadata only.
  $exeDir=[IO.Path]::GetDirectoryName($Executable)
  foreach($dep in @(Get-ChildItem -LiteralPath $exeDir -File -Force | Where-Object {$_.Extension -iin @('.dll','.json')})) {
   if ($dep.Attributes -band [IO.FileAttributes]::ReparsePoint) {throw 'DEPENDENCY_REPARSE'}
   $heldDep=New-Object IO.FileStream($dep.FullName,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
   $dependencyHandles.Add($heldDep)
   [void](Get-FileHash -InputStream $heldDep -Algorithm SHA256)
   $r.dependencyCount++
  }
  $r.dependencyState='HELD_MEASURED_NOT_ATTESTED'
  $inputHandle=New-Object IO.FileStream($inputPath,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
  if ($root.Contains('"') -or $Executable.Contains('"')) {throw 'INVALID_PATH'}
  $pipes=New-Object PhaseAEtlPipes($MaximumOutputBytes,8192)
  $job=[EtherPhaseAJob]::Create()
  $command='"'+$Executable+'" "'+$inputPath+'" "'+$outputPath+'" --pipe-output '+$r.experiment
  $child=[EtherPhaseAAtomic]::CreateSelfWithPipes($job,$Executable,$command,$root,$pipes.StdoutWrite,$pipes.StderrWrite)
  $r.transfer='ANONYMOUS_PIPE'
  $r.pid=$child.Pid
  try {$pipes.CloseParentWriters();$pipes.StartReaders()} catch {$pipeUnconfirmed=$true;throw}
  $r.contained=$child.InJob()
  if (-not $r.contained) {throw 'CONTAINMENT_FAILED'}
  $proc=Get-Process -Id $child.Pid -ErrorAction Stop
  $identity=Get-PhaseAProcessToken $proc $true
  if ($identity.pid -ne $child.Pid -or $identity.sid -cne [Security.Principal.WindowsIdentity]::GetCurrent().User.Value -or [string]::IsNullOrWhiteSpace($identity.createdAt)) {throw 'IDENTITY_UNCONFIRMED'}
  $r.createdAt=$identity.createdAt;$r.sid=$identity.sid
  $r.tokenProperties=@{primary=$identity.primary;admin=$identity.admin;elevated=$identity.elevated;source='PROCESS_TOKEN_ONLY'}
  Write-PhaseARecoveryJournal $journal 'PROCESS_IDENTIFIED' $r.pid $r.createdAt 'UNVERIFIED' 'NOT_STARTED' $true 'PROCESS_JOB_IO' 'NOT_ATTEMPTED'
  $r.journal='PROCESS_IDENTIFIED_DURABLE'
  $child.Resume()
  $watch=[Diagnostics.Stopwatch]::StartNew()
  while ($true) {
   if (Invoke-PhaseAEtlWait $child 0) { $r.terminationConfirmed=$true;break }
   if ($Cancellation.IsCancellationRequested) {$r.classification='CANCELLED';break}
   if ($pipes.Overflow) {$r.classification='OUTPUT_TOO_LARGE';break}
   if ($pipes.ReadFailed) {$r.classification='PIPE_READ_FAILED';break}
   if ($watch.ElapsedMilliseconds -ge $TimeoutMs) {$r.classification='TIMEOUT';break}
   Start-Sleep -Milliseconds 20
  }
  if (-not $r.terminationConfirmed) {
   try {Write-PhaseARecoveryJournal $journal 'PRE_CLEANUP' $r.pid $r.createdAt $r.classification 'NOT_CONFIRMED' $true 'PROCESS_JOB_IO' 'NOT_ATTEMPTED';$preCleanup=$true}
   catch {$journalFailed=$true;throw}
   $cleanupAttempted=$true
   try {$child.Terminate()} catch {$r.diagnostic='TERMINATE_FAILED'}
   try {$r.terminationConfirmed=Invoke-PhaseAEtlWait $child ([uint32]$TerminationMs)} catch {$r.diagnostic='WAIT_FAILED'}
  }
  if ($r.terminationConfirmed) {
   $r.exitCode=$child.ExitCode()
   if (-not $pipes.WaitReaders($TerminationMs)) {$pipeUnconfirmed=$true;if($r.classification -ceq 'UNVERIFIED'){$r.classification='PIPE_UNCONFIRMED'}}
   else {$r.stdout=$pipes.StdoutText();$r.stderr=$pipes.StderrText();if($pipes.Overflow){$r.classification='OUTPUT_TOO_LARGE'}elseif($pipes.ReadFailed){$r.classification='PIPE_READ_FAILED'}}
   if ($r.classification -ceq 'UNVERIFIED') {
    if ($r.exitCode -ne 0) {$r.classification='WORKER_FAILED'}
    elseif ([string]::IsNullOrEmpty($r.stdout)) {$r.classification='OUTPUT_MISSING'}
    else {
     try {$data=$r.stdout | ConvertFrom-Json
      if ($data.Source -cne 'CAPTURED_UNTRUSTED' -or $data.Status -cne 'UNVERIFIED' -or $data.Experiment -cne $r.experiment) {throw 'OUTPUT_SCHEMA_INVALID'}
      $r.outputJson=$r.stdout
      $r.classification='COMPLETE'
     } catch {$r.classification='OUTPUT_INVALID'}
    }
   }
  } else { $r.cleanupDiagnostic='CHILD_UNCONFIRMED' }
 } catch {
  $allowed=@('INVALID_LIMIT','EXPERIMENT_DIRECTORY_INVALID','INPUT_MISSING','INPUT_REPARSE','OUTPUT_EXISTS','EXECUTABLE_MISSING','EXECUTABLE_REPARSE','EXECUTABLE_TYPE_INVALID','EXECUTABLE_HASH_MISMATCH','DEPENDENCY_REPARSE','INVALID_PATH','CONTAINMENT_FAILED','IDENTITY_UNCONFIRMED')
  if ($r.classification -ceq 'UNVERIFIED') {$r.classification=if($allowed -ccontains $_.Exception.Message){$_.Exception.Message}else{'SETUP_FAILED'}}
  if ($r.classification -ceq 'SETUP_FAILED') {$r.diagnostic=Get-PhaseAEtlNativeCategory $_.Exception}
 } finally {
  if ($journal -and -not $preCleanup -and -not $journalFailed) {
   try {$resources=if($child){'PROCESS_JOB_IO'}elseif($job -ne [IntPtr]::Zero -or $inputHandle -or $exeHandle -or $outputHandle -or $dependencyHandles.Count){'UNKNOWN'}else{'NONE'};Write-PhaseARecoveryJournal $journal 'PRE_CLEANUP' $r.pid ([string]$r.createdAt) $r.classification 'NOT_CONFIRMED' $true $resources 'NOT_ATTEMPTED';$preCleanup=$true}
   catch {$journalFailed=$true}
  }
  if ($journalFailed) {
   $r.journal='WRITE_FAILED';$r.cleanup='RESOURCE_RETAINED';$r.cleanupDiagnostic='JOURNAL_WRITE_FAILED'
   if($r.classification -ceq 'COMPLETE'){$r.operationClassification='COMPLETE';$r.classification='CLEANUP_UNCONFIRMED'}
   [void]$script:EtlUnconfirmed.Add(@{job=$job;child=$child;process=$proc;root=$root;inputHandle=$inputHandle;exeHandle=$exeHandle;outputHandle=$outputHandle;pipes=$pipes;dependencyHandles=$dependencyHandles;journal=$journal;reason='JOURNAL_WRITE_FAILED'})
  } else {
  if ($child -and -not $r.terminationConfirmed) {
   $cleanupAttempted=$true
   try {$child.Terminate()} catch {if($r.diagnostic -ceq 'NONE'){$r.diagnostic='TERMINATE_FAILED'}}
   try {$r.terminationConfirmed=Invoke-PhaseAEtlWait $child ([uint32]$TerminationMs)} catch {$r.cleanupDiagnostic='WAIT_FAILED'}
  }
  if ($pipes -and $child -and $r.terminationConfirmed -and -not $pipeUnconfirmed) {
   try {if (-not $pipes.WaitReaders($TerminationMs)) {$pipeUnconfirmed=$true}} catch {$pipeUnconfirmed=$true}
  }
  if (($child -and -not $r.terminationConfirmed) -or $pipeUnconfirmed) {
   [void]$script:EtlUnconfirmed.Add(@{job=$job;child=$child;process=$proc;root=$root;inputHandle=$inputHandle;exeHandle=$exeHandle;outputHandle=$outputHandle;pipes=$pipes;dependencyHandles=$dependencyHandles})
   $r.cleanup='RESOURCE_RETAINED';$r.cleanupDiagnostic=if($pipeUnconfirmed){'PIPE_UNCONFIRMED'}else{'CHILD_UNCONFIRMED'}
  } else {
   $ok=$true
   if($proc -or $child -or $job -ne [IntPtr]::Zero -or $inputHandle -or $exeHandle -or $outputHandle -or $dependencyHandles.Count){$cleanupAttempted=$true}
   if ($proc) {try {$proc.Dispose()} catch {$ok=$false}}
   if ($child) {try {$r.close=Close-PhaseAEtlChildHandles $child;if($r.close.ThreadClose -cne 'CLOSED' -or $r.close.ProcessClose -cne 'CLOSED') {$ok=$false}} catch {$ok=$false}}
   if ($job -ne [IntPtr]::Zero) {try {Close-PhaseAEtlJob $job;$job=[IntPtr]::Zero} catch {$ok=$false}}
   if ($ok -and $pipes) {try {$pipes.Dispose();$pipes=$null} catch {$ok=$false}}
   if ($ok -and $inputHandle) {try {$inputHandle.Dispose();$inputHandle=$null} catch {$ok=$false}}
   if ($ok -and $exeHandle) {try {$exeHandle.Dispose();$exeHandle=$null} catch {$ok=$false}}
   if ($ok -and $outputHandle) {try {$outputHandle.Dispose();$outputHandle=$null} catch {$ok=$false}}
   if ($ok) {foreach($heldDep in $dependencyHandles) {try {$heldDep.Dispose()} catch {$ok=$false}}}
   $r.cleanup=if($ok){'CONFIRMED'}else{'FAILED'}
   if (-not $ok) {
    $r.cleanupDiagnostic='RESOURCE_CLEANUP_FAILED'
    if ($r.classification -ceq 'COMPLETE') {$r.operationClassification='COMPLETE';$r.classification='CLEANUP_UNCONFIRMED'}
    [void]$script:EtlUnconfirmed.Add(@{job=$job;child=$child;process=$proc;root=$root;inputHandle=$inputHandle;exeHandle=$exeHandle;outputHandle=$outputHandle;pipes=$pipes;dependencyHandles=$dependencyHandles;reason='RESOURCE_CLEANUP_FAILED'})
   }
  }
  if($journal) {
   try {$resources=if($r.cleanup -ceq 'CONFIRMED'){'NONE'}elseif($child){'PROCESS_JOB_IO'}else{'UNKNOWN'};$attempt=if($cleanupAttempted){'ATTEMPTED'}else{'NOT_ATTEMPTED'};Write-PhaseARecoveryJournal $journal 'CLEANUP_OBSERVED' $r.pid ([string]$r.createdAt) $r.classification $r.cleanup ($r.cleanup -cne 'CONFIRMED') $resources $attempt;$r.journal='CLEANUP_DURABLE'}
   catch {$r.journal='WRITE_FAILED';$r.cleanupDiagnostic='JOURNAL_WRITE_FAILED';if($r.classification -ceq 'COMPLETE'){$r.operationClassification='COMPLETE';$r.classification='CLEANUP_UNCONFIRMED'}}
   finally {try {$journal.stream.Dispose()} catch {$r.journal='CLOSE_FAILED';if($r.classification -ceq 'COMPLETE'){$r.operationClassification='COMPLETE';$r.classification='CLEANUP_UNCONFIRMED'}}}
  }
  }
 }
 return $r
}
