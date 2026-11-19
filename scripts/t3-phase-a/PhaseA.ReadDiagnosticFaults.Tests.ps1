$ErrorActionPreference='Stop'
. "$PSScriptRoot/PhaseA.Stage3.ps1"
$script:mode=''
$io=@{
 Cancel={param($p) if($script:mode -eq 'CANCEL_THROW'){throw 'injected'};if($script:mode -eq 'NOT_FOUND'){return 'NOT_FOUND'};return 'REQUESTED'}
 Wait={param($w) if($script:mode -eq 'WAIT_THROW'){throw 'injected'};if($script:mode -in @('WAIT_FALSE','CANCEL_THROW')){return $false};return $true}
 EndConnection={param($p,$a) if($script:mode -eq 'END_CONNECTION_THROW'){throw 'injected'};return 'CANCELED'}
 EndRead={param($p,$a) if($script:mode -eq 'END_READ_THROW'){throw 'injected'};return 'CANCELED'}
 DisposeWait={param($w) if($script:mode -eq 'DISPOSE_THROW'){throw 'injected'}}
 DisposePipe={param($p)}
}
foreach($mode in @('DELAYED_CONFIRMED','NOT_FOUND','WAIT_FALSE','CANCEL_THROW','WAIT_THROW','END_CONNECTION_THROW','DISPOSE_THROW')){
 $script:mode=$mode;$r=@{};$ok=Complete-PhaseAWitnessPipeCleanup 'pipe' 'pending' $null 'wait' $null $false $false $r $io
 switch($mode){
  'DELAYED_CONFIRMED' {if(-not $ok -or $r.pipeCancel -cne 'REQUESTED' -or $r.connectionEnd -cne 'CANCELED'){throw 'CANCEL_COMPLETION_NOT_PROVED'}}
  'NOT_FOUND' {if(-not $ok -or $r.pipeCancel -cne 'NOT_FOUND' -or $r.connectionEnd -cne 'CANCELED'){throw 'NOT_FOUND_NOT_CONFIRMED'}}
  'WAIT_FALSE' {if($ok -or $r.pipeDispose -cne 'RETAINED'){throw 'WAIT_TIMEOUT_RELEASED'}}
  'CANCEL_THROW' {if($ok -or $r.pipeCancel -cne 'FAILED' -or $r.pipeDispose -cne 'RETAINED'){throw 'CANCEL_THROW_RELEASED'}}
  'WAIT_THROW' {if($ok -or $r.connectionWaitCleanup -cne 'UNCONFIRMED' -or $r.pipeDispose -cne 'RETAINED'){throw 'WAIT_THROW_RELEASED'}}
  'END_CONNECTION_THROW' {if($ok -or $r.connectionEnd -cne 'FAILED' -or $r.pipeDispose -cne 'RETAINED'){throw 'END_CONNECTION_RELEASED'}}
  'DISPOSE_THROW' {if($ok -or $r.connectionWaitCleanup -cne 'FAILED'){throw 'DISPOSAL_FAILURE_PASSED'}}
 }
 Write-Output ('PASS '+$mode)
}
$script:mode='END_READ_THROW';$r=@{};$ok=Complete-PhaseAWitnessPipeCleanup 'pipe' $null 'pending' $null 'wait' $false $false $r $io
if($ok -or $r.readEnd -cne 'FAILED' -or $r.pipeDispose -cne 'RETAINED'){throw 'END_READ_RELEASED'}
Write-Output 'PASS END_READ_THROW'
$owner=New-PhaseAWitnessIoOwner 'pipe' (New-Object byte[] 4) ('a'*32)
try{$null=Invoke-PhaseAWitnessIoIssue $owner 'read' {throw 'injected uncertain issue'}}catch{}
if($owner.read.state -cne 'ISSUE_UNCONFIRMED'){throw 'UNCERTAIN_ISSUE_LOST'}
$blocked=$false;try{Remove-PhaseAWitnessIoOwner $owner}catch{$blocked=$_.Exception.GetBaseException().Message -ceq 'WITNESS_IO_STILL_PENDING'}
if(-not $blocked){throw 'UNCERTAIN_ISSUE_RELEASED'}
Write-Output 'PASS ISSUE_UNCONFIRMED'
$r=@{};$closed=Invoke-PhaseAActorJobClose ([IntPtr]123) $r {param($j) throw [ComponentModel.Win32Exception]::new(5)}
if($closed -or $r.jobClose -cne 'FAILED' -or $r.jobCloseError -cne 'WIN32_ACCESS_DENIED'){throw 'JOB_CLOSE_FAILURE_ACCEPTED'}
Write-Output 'PASS injected job close failure'
$b=@{Exists={param($p) $true};DirectoryExists={param($p) $true};Probe={param($token,$sid,$operation,$target,$root) @{sid=$sid;operation=$operation;attempted=$true;allowed=$false;error=5;handlesClosed=$true;execution='PROCESS';processVerified=$true;terminated=$false;pid=123;pipeClientPid=123;createdAt='2026-01-01T00:00:00Z';nonce=('a'*32)}}}
$v=Invoke-PhaseATrustedAccess $b @{protectedFile='test';protectedDir='test'} @{sid='S-1-5-21-2'} 'S-1-5-21-2' 'Read' 'protectedFile' 'INJECTED'
if($v.status -cne 'UNVERIFIED'){throw 'UNCONFIRMED_CHILD_RECEIPT_ACCEPTED'}
Write-Output 'PASS injected receipt and unconfirmed termination'