$ErrorActionPreference='Stop'
. "$PSScriptRoot/PhaseA.Stage3.ps1"
. "$PSScriptRoot/PhaseA.ReadProcess.ps1"
$path=Join-Path ([IO.Path]::GetTempPath()) ('ether-read-process-test-'+[Guid]::NewGuid().ToString('N'))
[IO.File]::WriteAllText($path,'synthetic')
try {
 $sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
 $read=Invoke-PhaseAReadPipeProcess $null $sid $path 'protectedFile' '' $true
 if(-not $read.allowed -or $read.error -ne 0 -or -not $read.processVerified -or -not $read.terminated){throw 'current identity read failed'}
 Write-Output "PASS actual read process pid=$($read.pid) pipePid=$($read.pipeClientPid) created=$($read.createdAt)"
 $backend=@{Exists={param($p) [IO.File]::Exists($p)};DirectoryExists={param($p) [IO.Directory]::Exists($p)};Probe={param($token,$expected,$operation,$target,$root) Invoke-PhaseAReadPipeProcess $null $expected $target 'protectedFile' '' $true}}
 $fixture=@{protectedFile=$path;protectedDir=[IO.Path]::GetDirectoryName($path)};$token=@{sid=$sid}
 $mapped=Invoke-PhaseATrustedAccess $backend $fixture $token $sid 'Read' 'protectedFile' 'INJECTED'
 if($mapped.status -cne 'OBSERVED' -or $mapped.execution -cne 'PROCESS' -or $mapped.outcome -cne 'ALLOWED'){throw 'manager adapter did not use process evidence'}
  $identityOutcome='ACCEPTED'
 try {$null=Invoke-PhaseAReadPipeProcess $null 'S-1-5-21-999' $path 'protectedFile' '' $true} catch {
  $category=$_.Exception.GetBaseException().Message
  if($category -ceq 'WITNESS_IDENTITY_REJECTED'){$identityOutcome='IDENTITY_REJECTED'}
  elseif($category -cin @('WITNESS_TIMEOUT','WITNESS_CLIENT_REJECTED','WITNESS_RECEIPT_REJECTED')){$identityOutcome='IPC_OR_TIMEOUT_FAILURE'}
  elseif($category -cin @('WITNESS_CLEANUP_FAILED','STAGE2_CHILD_UNCONFIRMED')){$identityOutcome='CLEANUP_OR_TERMINATION_FAILURE'}
  elseif($category -cin @('WITNESS_CONTAINMENT_FAILED','WITNESS_SETUP_FAILED','WITNESS_BINARY_MISMATCH','WITNESS_SOURCE_MISMATCH','WITNESS_ARGUMENT_REJECTED')){$identityOutcome='LAUNCH_OR_SETUP_FAILURE'}
  elseif($_.Exception.GetBaseException() -is [ComponentModel.Win32Exception]){$identityOutcome='UNEXPECTED_NATIVE_EXCEPTION'}else{$identityOutcome='UNEXPECTED_POWERSHELL_EXCEPTION'}
 }
 if($identityOutcome -ceq 'ACCEPTED'){throw 'WRONG_IDENTITY_ACCEPTED'}
 if($identityOutcome -cne 'IDENTITY_REJECTED'){throw ('IDENTITY_CONTROL_'+$identityOutcome)}
 Write-Output ('PASS identity control: '+$identityOutcome)
 $missing=Invoke-PhaseAReadPipeProcess $null $sid ($path+'.missing') 'protectedFile' '' $true
 if($missing.allowed -or $missing.error -ne 2){throw 'missing file not classified'}
 $caught=$false;try{$null=Invoke-PhaseAReadPipeProcess $null $sid $path 'protectedFile' '' $true $true}catch{$caught=$_.Exception.GetBaseException().Message -ceq 'WITNESS_TIMEOUT'}
 if(-not $caught){throw 'bounded stall was not rejected'}
 Write-Output 'PASS process manager adapter, read, missing, wrong SID and stalled termination'
} finally {if([IO.File]::Exists($path)){[IO.File]::Delete($path)}}
$never=New-Object PSObject
$never | Add-Member ScriptMethod Wait {param($ms) return $false}
$never | Add-Member ScriptMethod Terminate {return}
$unconfirmed=$false;try{Confirm-PhaseAReadChildTermination $never}catch{$unconfirmed=$_.Exception.GetBaseException().Message -ceq 'STAGE2_CHILD_UNCONFIRMED'}
if(-not $unconfirmed){throw 'surviving witness child accepted'}
Write-Output 'PASS injected surviving helper rejects cleanup'
