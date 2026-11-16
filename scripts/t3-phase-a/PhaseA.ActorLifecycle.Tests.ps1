$ErrorActionPreference='Stop'
. "$PSScriptRoot/PhaseA.Stage2.ps1"
foreach($role in @('broker','legacy')){
 $owner=@{role=$role;accountSid='S-1-5-21-1';priorViolation=@{state='FAIL'}};$account=@{role=$role;sid=$owner.accountSid}
 $rec=New-PhaseAActorProcessRecord $owner $account ('a'*32) ('b'*32) 'INJECTED'
 if($owner.processObservations.Count -ne 1 -or -not [object]::ReferenceEquals($owner.processObservations[0],$rec) -or $rec.role -cne $role -or $rec.launchResult -cne 'NOT_ATTEMPTED'){throw 'MANAGER_RECORD_NOT_REGISTERED'}
 try{$null=Invoke-PhaseABoundProcessLaunch $rec {throw 'injected launch failure'}}catch{}
 if($rec.launchResult -cne 'CREATE_FAILED' -or $rec.launchError -cne 'NON_WIN32' -or $rec.ContainsKey('pid') -or $owner.priorViolation.state -cne 'FAIL'){throw 'LAUNCH_FAILURE_RECORD_LOST'}
 $bad=@{role='wrong';sid=$owner.accountSid};try{$null=New-PhaseAActorProcessRecord $owner $bad ('a'*32) ('b'*32) 'INJECTED';throw 'WRONG_ROLE_ACCEPTED'}catch{if($_.Exception.GetBaseException().Message -ceq 'WRONG_ROLE_ACCEPTED'){throw}}
 $bad=@{role=$role;sid='S-1-5-21-9'};try{$null=New-PhaseAActorProcessRecord $owner $bad ('a'*32) ('b'*32) 'INJECTED';throw 'WRONG_ACCOUNT_ACCEPTED'}catch{if($_.Exception.GetBaseException().Message -ceq 'WRONG_ACCOUNT_ACCEPTED'){throw}}
}
$script:case='success'
$child=@{}
$io=@{Wait={param($c,$ms) if($script:case -ceq 'wait'){throw 'secret'};if($script:case -ceq 'survive'){return $false};return $true};Exited={param($c) if($script:case -cin @('survive','contradictory')){return $false};return $true};ExitCode={param($c) return 0};Terminate={param($c)};Dispose={param($c) if($script:case -ceq 'close'){throw (New-Object ComponentModel.Win32Exception(6))}}}
foreach($kind in @('success','survive','wait','close','contradictory')){
 $script:case=$kind;$record=@{};$result=Invoke-PhaseAActorChildCleanup $child $record $io
 switch($kind){
  'success' {if(-not $result.confirmed -or $result.cleanupFailed -or $record.finalWait -cne 'SIGNALED' -or $record.exitState -cne 'EXITED' -or $record.atomicHandleClose -cne 'CLOSED'){throw 'SUCCESS_NOT_RETAINED'}}
  'survive' {if($result.confirmed -or $record.finalWait -cne 'TIMEOUT' -or $record.exitState -cne 'ALIVE' -or $record.atomicHandleClose -cne 'NOT_ATTEMPTED'){throw 'SURVIVOR_NOT_RETAINED'}}
  'wait' {if($result.confirmed -or $record.finalWait -cne 'FAILED' -or $record.exitState -cne 'UNKNOWN'){throw 'WAIT_FAILURE_NOT_RETAINED'}}
  'close' {if(-not $result.confirmed -or -not $result.cleanupFailed -or $record.atomicHandleClose -cne 'FAILED' -or $record.error -cne 'WIN32_INVALID_HANDLE'){throw 'CLOSE_FAILURE_NOT_RETAINED'}}
  'contradictory' {if($result.confirmed -or $record.finalWait -cne 'SIGNALED' -or $record.exitState -cne 'UNKNOWN' -or $record.error -cne 'EXIT_UNCONFIRMED'){throw 'CONTRADICTORY_EXIT_ACCEPTED'}}
 }
}
$owner=@{role='legacy';accountSid='S-1-5-21-2';priorViolation=@{state='FAIL'}}
$account=@{role='legacy';sid=$owner.accountSid};$early=New-PhaseAActorProcessRecord $owner $account ('c'*32) ('d'*32) 'INJECTED'
$script:case='success';$launched=Invoke-PhaseABoundProcessLaunch $early {return @{pid=123}}
try {throw 'injected post-launch callback error'} catch {Save-PhaseAActorOperationFailure $early $_} finally {$cleanup=@{};$null=Invoke-PhaseAActorChildCleanup $launched $cleanup $io;$early.lifecycle.child=$cleanup}
if($early.launchResult -cne 'CREATED' -or $early.lifecycle.operationFailure -cne 'OPERATION_FAILED' -or $early.lifecycle.child.atomicHandleClose -cne 'CLOSED' -or $owner.priorViolation.state -cne 'FAIL' -or -not [object]::ReferenceEquals($owner.processObservations[0],$early)){throw 'POST_LAUNCH_FAILURE_LOST_PRIOR_EVIDENCE'}
Write-Output 'PASS actor cleanup success, survival, wait and handle failure'
$jobRecord=@{jobClose='NOT_ATTEMPTED';jobCloseError='NONE'}
if(Invoke-PhaseAActorJobClose ([IntPtr]123) $jobRecord {param($j) throw (New-Object ComponentModel.Win32Exception(5))}){throw 'FAILED_JOB_CLOSE_ACCEPTED'}
if($jobRecord.jobClose -cne 'FAILED' -or $jobRecord.jobCloseError -cne 'WIN32_ACCESS_DENIED'){throw 'FAILED_JOB_CLOSE_NOT_RETAINED'}
$jobRecord=@{jobClose='NOT_ATTEMPTED';jobCloseError='NONE'}
if(-not (Invoke-PhaseAActorJobClose ([IntPtr]123) $jobRecord {param($j)} ) -or $jobRecord.jobClose -cne 'CLOSED'){throw 'SUCCESS_JOB_CLOSE_NOT_RETAINED'}
. "$PSScriptRoot/PhaseA.Accounts.ps1"
$calls=@{close=0;remove=0;fixture=0}
$accountBackend=@{Create={param($r) @{role=$r;sid=$(if($r -ceq 'broker'){'S-1-5-21-1'}else{'S-1-5-21-2'})}};Authenticate={param($a) @{sid=$a.sid;primary=$true;admin=$false;elevated=$false;standard=$true}};Close={param($t) $calls.close++}.GetNewClosure();Remove={param($a) $calls.remove++}.GetNewClosure()}
$fixtureBackend=@{Setup={param($a) $calls.fixture++}.GetNewClosure()}
foreach($failureRole in @('broker','legacy')){
 $script:failureRole=$failureRole;$calls.close=0;$calls.remove=0;$calls.fixture=0
 $actorBackend=@{Run={param($a,$t) if($a.role -ceq $script:failureRole){throw 'STAGE2_CLEANUP_FAILED'};@{role=$a.role;expectedSid=$a.sid;observedSid=$a.sid;reportedSid=$a.sid;expectedPid=123;reportedPid=123;tokenNonAdmin=$true;tokenObserved=$true;createdAt='2026-01-01T00:00:00Z';observedCreatedAt='2026-01-01T00:00:00Z';expectedNonce='n';reportedNonce='n';exitCode=0;outcome='allowed';contained=$true;terminated=$true}}}
 $outcome=Invoke-PhaseAStages $true $true $accountBackend $actorBackend $true $fixtureBackend @{}
 if($outcome -cne 'ACCOUNT_CLEANUP_FAILED' -or $calls.close -ne 0 -or $calls.remove -ne 0 -or $calls.fixture -ne 0){throw ('ACTOR_CLEANUP_DID_NOT_BLOCK_DEPENDENCIES_'+$failureRole)}
}
Write-Output 'PASS actor job-close classification and dependency gate'
$job=[IntPtr]::Zero;$actualChild=$null;$disposed=$false
try {
 $job=[EtherPhaseAJob]::Create();$exe=Join-Path $PSHOME 'powershell.exe'
 $actualChild=[EtherPhaseAAtomic]::CreateSelfInDirectory($job,$exe,('"'+$exe+'" -NoProfile -NonInteractive -Command "Start-Sleep -Seconds 90"'),[IO.Path]::GetTempPath())
 if(-not $actualChild.InJob() -or $actualChild.Exited()){throw 'REAL_CHILD_CONTAINMENT_FAILED'}
 $proc=Get-Process -Id $actualChild.Pid -ErrorAction Stop
 try{$identity=Get-PhaseAProcessToken $proc;if($identity.pid -ne $actualChild.Pid -or $identity.sid -cne [Security.Principal.WindowsIdentity]::GetCurrent().User.Value){throw 'REAL_CHILD_IDENTITY_MISMATCH'}}finally{$proc.Dispose()}
 $actualChild.Resume();[EtherPhaseAJob]::Close($job);$job=[IntPtr]::Zero
 $real=@{};$result=Invoke-PhaseAActorChildCleanup $actualChild $real;$disposed=$real.atomicHandleClose -ceq 'CLOSED'
 if(-not $result.confirmed -or $result.cleanupFailed -or $real.finalWait -cne 'SIGNALED' -or $real.exitState -cne 'EXITED' -or -not $disposed){throw 'REAL_CHILD_CLEANUP_UNCONFIRMED'}
}finally{
 if($job -ne [IntPtr]::Zero){[EtherPhaseAJob]::Close($job)}
 if($actualChild -and -not $disposed){try{$actualChild.Terminate();$null=$actualChild.Wait(5000);$actualChild.Dispose()}catch{}}
}
Write-Output 'PASS current identity contained actor termination and checked closure'
