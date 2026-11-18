$ErrorActionPreference='Stop'
. "$PSScriptRoot/PhaseA.Stage3.ps1"
$dir=Join-Path ([IO.Path]::GetTempPath()) ('phase-a-witness-life-'+[Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($dir)|Out-Null
try {
 $file=Join-Path $dir 'data.bin';[IO.File]::WriteAllText($file,'synthetic')
 $sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
 $script:originalIoOwner=(Get-Command New-PhaseAWitnessIoOwner).ScriptBlock
 $script:originalIoIssue=(Get-Command Invoke-PhaseAWitnessIoIssue).ScriptBlock
 $script:issuedAfterRegistrationFailure=0
 function New-PhaseAWitnessIoOwner {param($p,$b,$a) throw 'WITNESS_IO_OWNER_UNAVAILABLE'}
 function Invoke-PhaseAWitnessIoIssue {param($o,$op,$issue) $script:issuedAfterRegistrationFailure++; & $script:originalIoIssue $o $op $issue}
 $record=@{};$errorCode='';try{$null=Invoke-PhaseAReadPipeProcess $null $sid $file 'protectedFile' '' $true $false 'Read' $record}catch{$errorCode=$_.Exception.GetBaseException().Message}
 if($errorCode -cne 'WITNESS_IO_OWNER_UNAVAILABLE' -or $script:issuedAfterRegistrationFailure -ne 0 -or $record.launch -cne 'NOT_ATTEMPTED'){throw 'REGISTRATION_FAILURE_DID_NOT_BLOCK_IO'}
 Set-Item Function:New-PhaseAWitnessIoOwner $script:originalIoOwner
 Set-Item Function:Invoke-PhaseAWitnessIoIssue $script:originalIoIssue
 foreach($op in @('Read','Overwrite','Create')){
  $target=if($op -ceq 'Create'){Join-Path $dir 'new.bin'}else{$file};$id=if($op -ceq 'Create'){'authorizedProbeFile'}else{'protectedFile'}
  $record=@{};$result=Invoke-PhaseAReadPipeProcess $null $sid $target $id '' $true $false $op $record
  if($record.operation -cne $op -or $record.launch -cne 'CREATED' -or $record.pid -ne $result.pid -or $record.containment -cne 'MEMBER' -or $record.jobClose -cne 'CLOSED' -or $record.child.finalWait -cne 'SIGNALED' -or $record.child.processClose -cne 'CLOSED' -or $record.child.threadClose -cne 'CLOSED'){throw ('WITNESS_LIFECYCLE_MISSING_'+$op)}
  if($op -ceq 'Create' -and [IO.File]::Exists($target)){[IO.File]::Delete($target)}
 }
 $script:originalWitnessInspect=(Get-Command Get-PhaseAProcessToken).ScriptBlock
 foreach($kind in @('wrongPid','wrongTime','wrongSid')){
  $script:witnessMismatch=$kind
  function Get-PhaseAProcessToken {param($p,[bool]$requireClose=$false) $value=& $script:originalWitnessInspect $p $requireClose;switch($script:witnessMismatch){'wrongPid' {$value.pid++} 'wrongTime' {$value.createdAt='2000-01-01T00:00:00.0000000Z'} 'wrongSid' {$value.sid='S-1-5-21-999'}};return $value}
  $record=@{};$errorCode=''
  try{$null=Invoke-PhaseAReadPipeProcess $null $sid $file 'protectedFile' '' $true $false 'Read' $record}catch{$errorCode=$_.Exception.GetBaseException().Message}
  if($errorCode -cnotin @('WITNESS_IDENTITY_REJECTED','WITNESS_RECEIPT_REJECTED') -or $record.launch -cne 'CREATED' -or $record.child.finalWait -cne 'SIGNALED' -or $record.cleanupDependency -cne 'RELEASE_ELIGIBLE'){throw ('IDENTITY_FAILURE_NOT_RETAINED_'+$kind+'_'+$errorCode)}
 }
 Set-Item Function:Get-PhaseAProcessToken $script:originalWitnessInspect
 $record=@{};$errorCode=''
 try{$null=Invoke-PhaseAReadPipeProcess $null $sid $file 'protectedFile' '' $true $true 'Read' $record}catch{$errorCode=$_.Exception.GetBaseException().Message}
 if($errorCode -cne 'WITNESS_TIMEOUT' -or $record.operationFailure -cne 'WITNESS_TIMEOUT' -or $record.child.finalWait -cne 'SIGNALED' -or $record.child.processClose -cne 'CLOSED' -or $record.child.threadClose -cne 'CLOSED'){throw ('TIMEOUT_LIFECYCLE_NOT_RETAINED_'+$errorCode)}
 function Get-PhaseAProcessToken {param($p,[bool]$requireClose=$false) throw 'PROCESS_TOKEN_QUERY_FAILED'}
 $record=@{};$errorCode=''
 try{$null=Invoke-PhaseAReadPipeProcess $null $sid $file 'protectedFile' '' $true $false 'Read' $record}catch{$errorCode=$_.Exception.GetBaseException().Message}
 if($errorCode -cne 'PROCESS_TOKEN_QUERY_FAILED' -or $record.tokenInspectionClose -cne 'UNKNOWN' -or $record.child.finalWait -cne 'SIGNALED' -or $record.cleanupDependency -cne 'RELEASE_ELIGIBLE'){throw 'TOKEN_QUERY_FAILURE_NOT_RETAINED'}
 Set-Item Function:Get-PhaseAProcessToken $script:originalWitnessInspect
 $script:originalWitnessJob=(Get-Command Invoke-PhaseAActorJobClose).ScriptBlock
 $script:originalWitnessChild=(Get-Command Invoke-PhaseAActorChildCleanup).ScriptBlock
 $script:originalPipeCleanup=(Get-Command Complete-PhaseAWitnessPipeCleanup).ScriptBlock
 foreach($injected in @('jobClose','jobException','childException','processClose','threadClose','waitFailure','survivor','pipePending','pipeException')){
  $script:witnessInjected=$injected;$script:actualWitnessJobClosed=$false
  function Invoke-PhaseAActorJobClose {param($job,$item) $script:capturedJobHandle=$job;$real=& $script:originalWitnessJob $job $item;if($real){$script:actualWitnessJobClosed=$true};if($script:witnessInjected -ceq 'jobException'){throw 'INJECTED_JOB_EXCEPTION'};if($script:witnessInjected -ceq 'jobClose' -and $real){$item.jobClose='FAILED';$item.jobCloseError='WIN32_ACCESS_DENIED';return $false};return $real}
  function Invoke-PhaseAActorChildCleanup {param($child,$item) $real=& $script:originalWitnessChild $child $item;if($script:witnessInjected -ceq 'childException'){throw 'INJECTED_CHILD_EXCEPTION'};switch($script:witnessInjected){'processClose' {$item.processClose='FAILED';$item.processCloseError='WIN32_INVALID_HANDLE';$item.atomicHandleClose='FAILED';$real.cleanupFailed=$true} 'threadClose' {$item.threadClose='FAILED';$item.threadCloseError='WIN32_INVALID_HANDLE';$item.atomicHandleClose='FAILED';$real.cleanupFailed=$true} 'waitFailure' {$item.finalWait='FAILED';$item.exitState='UNKNOWN';$real.confirmed=$false} 'survivor' {$item.finalWait='TIMEOUT';$item.exitState='ALIVE';$real.confirmed=$false}};return $real}
  function Complete-PhaseAWitnessPipeCleanup {param($p,$q,$r,$qw,$rw,$qe,$re,$rec,$io=@{}) if($script:witnessInjected -ceq 'pipePending'){return $false};if($script:witnessInjected -ceq 'pipeException'){throw 'INJECTED_PIPE_EXCEPTION'};return (& $script:originalPipeCleanup $p $q $r $qw $rw $qe $re $rec $io)}
  $record=@{};$errorCode=''
  try{$null=Invoke-PhaseAReadPipeProcess $null $sid $file 'protectedFile' '' $true $false 'Read' $record}catch{$errorCode=$_.Exception.GetBaseException().Message}
  $expected=if($injected -cin @('waitFailure','survivor','childException')){'STAGE2_CHILD_UNCONFIRMED'}else{'WITNESS_CLEANUP_FAILED'}
  if($errorCode -cne $expected -or $record.cleanupDependency -cne 'RETAIN' -or -not $script:actualWitnessJobClosed){throw ('INJECTED_CLEANUP_FAILURE_LOST_'+$injected+'_'+$errorCode)}
  if($injected -ceq 'jobClose' -and (-not $record.ContainsKey('witnessOutcome') -or $record.witnessOutcome.allowed -ne $true -or $record.witnessOutcome.nativeError -ne 0 -or $record.witnessOutcome.operation -cne 'Read')){throw 'EARLIER_WITNESS_OUTCOME_LOST_ON_CLEANUP_FAILURE'}
  if($injected -ceq 'pipePending'){$owners=[AppDomain]::CurrentDomain.GetData('EtherPhaseAWitnessIoOwners');if($owners.Count -lt 1 -or $owners[$owners.Count-1].buffer -isnot [byte[]]){throw 'PENDING_READ_BUFFER_NOT_RETAINED'}}
  $private=$script:PhaseAUnconfirmedWitnessResources;if($injected -cin @('jobClose','jobException') -and (-not $private.ContainsKey('jobHandle') -or $private.jobHandle -ne $script:capturedJobHandle)){throw 'JOB_CLOSE_UNCERTAIN_HANDLE_NOT_RETAINED'};$safeRoot=[IO.Path]::GetFullPath($private.scratch);$temp=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')
  if(-not $safeRoot.StartsWith($temp+'\',[StringComparison]::OrdinalIgnoreCase) -or -not [IO.Path]::GetFileName($safeRoot).StartsWith('ether-phase-a-read-')){throw 'TEST_CLEANUP_PATH_REJECTED'}
  if($injected -cin @('pipePending','pipeException')){$private.pipe.Dispose()}
  if($private.binaryHandle){$private.binaryHandle.Dispose()};$binary=[IO.Path]::Combine($safeRoot,'witness.exe');if([IO.File]::Exists($binary)){[IO.File]::Delete($binary)};[IO.Directory]::Delete($safeRoot,$false)
  $blocked='';try{$null=Invoke-PhaseAReadPipeProcess $null '' '' '' ''}catch{$blocked=$_.Exception.GetBaseException().Message}
  if($blocked -cne 'WITNESS_CLEANUP_FAILED' -or -not [object]::ReferenceEquals($private,$script:PhaseAUnconfirmedWitnessResources)){throw 'REPEATED_UNRESOLVED_WITNESS_NOT_BLOCKED'}
  Remove-Variable -Name PhaseAUnconfirmedWitnessResources -Scope Script
  [AppDomain]::CurrentDomain.SetData('EtherPhaseAWitnessResourceGate',$null)
 }
 Set-Item Function:Invoke-PhaseAActorJobClose $script:originalWitnessJob
 Set-Item Function:Invoke-PhaseAActorChildCleanup $script:originalWitnessChild
 Set-Item Function:Complete-PhaseAWitnessPipeCleanup $script:originalPipeCleanup
}finally{if([IO.File]::Exists((Join-Path $dir 'new.bin'))){[IO.File]::Delete((Join-Path $dir 'new.bin'))};if([IO.File]::Exists((Join-Path $dir 'data.bin'))){[IO.File]::Delete((Join-Path $dir 'data.bin'))};[IO.Directory]::Delete($dir,$false)}
Write-Output 'PASS all witness modes retain process lifecycle'
