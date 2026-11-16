$ErrorActionPreference='Stop'
. "$PSScriptRoot/PhaseA.Stage2.ps1"
$global:PhaseACloseTest=@{scenario='';calls=@{process=0;thread=0}}
foreach($kind in @('bothOk','processFail','threadFail','bothFail','exception')){
 $global:PhaseACloseTest.scenario=$kind;$global:PhaseACloseTest.calls.process=0;$global:PhaseACloseTest.calls.thread=0
 $callback=[Func[string,int]]{param($name) $global:PhaseACloseTest.calls[$name]++;$s=$global:PhaseACloseTest.scenario;if($s -ceq 'exception' -and $name -ceq 'thread'){throw 'injected'};if($name -ceq 'process' -and $s -cin @('processFail','bothFail')){return 6};if($name -ceq 'thread' -and $s -cin @('threadFail','bothFail')){return 5};return 0}
 $state=[PhaseAHandleCloseState]::CreateInjected($callback)
 $owner=@{role='broker';accountSid='S-1-5-21-1';priorViolation=@{state='FAIL'}};$account=@{role='broker';sid=$owner.accountSid}
 $managerRecord=New-PhaseAActorProcessRecord $owner $account ('a'*32) ('b'*32) 'INJECTED'
 $io=@{Wait={param($c,$ms) $true};Exited={param($c) $true};ExitCode={param($c) 0};Terminate={param($c)};Dispose={param($c) $c.CloseObserved()}}
 $record=@{};$managerRecord.lifecycle.child=$record;$outcome=Invoke-PhaseAActorChildCleanup $state $record $io
 $p=if($kind -cin @('processFail','bothFail')){'FAILED'}else{'CLOSED'};$t=if($kind -cin @('threadFail','bothFail','exception')){'FAILED'}else{'CLOSED'}
 if($record.processClose -cne $p -or $record.threadClose -cne $t -or $record.atomicHandleClose -cne $(if($kind -ceq 'bothOk'){'CLOSED'}else{'FAILED'})){throw ('CLOSE_OUTCOMES_WRONG_'+$kind)}
 if($record.processCloseError -cne $(if($p -ceq 'FAILED'){'WIN32_INVALID_HANDLE'}else{'NONE'}) -or $record.threadCloseError -cne $(if($kind -ceq 'exception'){'CLOSE_EXCEPTION'}elseif($t -ceq 'FAILED'){'WIN32_ACCESS_DENIED'}else{'NONE'})){throw ('CLOSE_CATEGORIES_WRONG_'+$kind)}
 if($kind -cne 'bothOk' -and -not $outcome.cleanupFailed){throw ('FAILURE_PROMOTED_'+$kind)}
 if($owner.priorViolation.state -cne 'FAIL' -or -not [object]::ReferenceEquals($owner.processObservations[0].lifecycle.child,$record)){throw 'MANAGER_RECORD_LOST'}
 for($i=0;$i -lt 2;$i++){try{$state.Dispose();if($kind -cne 'bothOk'){throw 'FAILED_DISPOSE_ACCEPTED'}}catch{if($kind -ceq 'bothOk' -or $_.Exception.GetBaseException().Message -ceq 'FAILED_DISPOSE_ACCEPTED'){throw}}}
 if($global:PhaseACloseTest.calls.process -ne 1 -or $global:PhaseACloseTest.calls.thread -ne 1){throw 'DOUBLE_CLOSE_ATTEMPTED'}
}
Write-Output 'PASS separate atomic close outcomes and no retry'
$owner=@{role='broker';accountSid='S-1-5-21-1'};$account=@{role='broker';sid=$owner.accountSid};$managerRecord=New-PhaseAActorProcessRecord $owner $account ('c'*32) ('d'*32) 'INJECTED'
$managerRecord.lifecycle.jobCreate='CREATED'
if(Invoke-PhaseAActorJobClose ([IntPtr]123) $managerRecord.lifecycle {param($job) throw (New-Object ComponentModel.Win32Exception(5))}){throw 'INJECTED_JOB_FAILURE_ACCEPTED'}
if($owner.processObservations[0].lifecycle.jobClose -cne 'FAILED' -or $owner.processObservations[0].lifecycle.jobCloseError -cne 'WIN32_ACCESS_DENIED'){throw 'JOB_FAILURE_NOT_RETAINED'}
Write-Output 'PASS independent manager job-close failure'
. "$PSScriptRoot/PhaseA.Accounts.ps1"
$global:PhaseACloseGate=@{role='';owner=$null;close=0;remove=0;fixture=0}
$accounts=@{Create={param($r) @{role=$r;sid=$(if($r -ceq 'broker'){'S-1-5-21-1'}else{'S-1-5-21-2'})}};Authenticate={param($a) @{sid=$a.sid;primary=$true;admin=$false;elevated=$false;standard=$true}};Close={param($t) $global:PhaseACloseGate.close++};Remove={param($a) $global:PhaseACloseGate.remove++}}
$actors=@{Run={param($a,$t)
 if($a.role -ceq $global:PhaseACloseGate.role){
  $owner=@{role=$a.role;accountSid=$a.sid;priorViolation=@{state='FAIL'}};$record=New-PhaseAActorProcessRecord $owner $a ('1'*32) ('2'*32) 'INJECTED';$global:PhaseACloseGate.owner=$owner
  $cb=[Func[string,int]]{param($name) if(($global:PhaseACloseGate.role -ceq 'broker' -and $name -ceq 'process') -or ($global:PhaseACloseGate.role -ceq 'legacy' -and $name -ceq 'thread')){return 6};return 0}
  $state=[PhaseAHandleCloseState]::CreateInjected($cb);$record.lifecycle.child=@{}
  $io=@{Wait={param($c,$ms) $true};Exited={param($c) $true};ExitCode={param($c) 0};Terminate={param($c)};Dispose={param($c) $c.CloseObserved()}}
  $closed=Invoke-PhaseAActorChildCleanup $state $record.lifecycle.child $io
  if($closed.cleanupFailed){throw 'STAGE2_CLEANUP_FAILED'};throw 'CLOSE_FAILURE_MISSED'
 }
 return @{role=$a.role;expectedSid=$a.sid;observedSid=$a.sid;reportedSid=$a.sid;expectedPid=123;reportedPid=123;tokenNonAdmin=$true;tokenObserved=$true;createdAt='2026-01-01T00:00:00Z';observedCreatedAt='2026-01-01T00:00:00Z';expectedNonce='n';reportedNonce='n';exitCode=0;outcome='allowed';contained=$true;terminated=$true}
}}
$fixture=@{Setup={param($a) $global:PhaseACloseGate.fixture++}}
foreach($role in @('broker','legacy')){
 $global:PhaseACloseGate.role=$role;$global:PhaseACloseGate.owner=$null;$global:PhaseACloseGate.close=0;$global:PhaseACloseGate.remove=0;$global:PhaseACloseGate.fixture=0
 $result=Invoke-PhaseAStages $true $true $accounts $actors $true $fixture @{}
 if($result -cne 'ACCOUNT_CLEANUP_FAILED' -or $global:PhaseACloseGate.close -ne 0 -or $global:PhaseACloseGate.remove -ne 0 -or $global:PhaseACloseGate.fixture -ne 0){throw ('DEPENDENCIES_RELEASED_'+$role)}
 $r=$global:PhaseACloseGate.owner.processObservations[0].lifecycle.child
 if($global:PhaseACloseGate.owner.priorViolation.state -cne 'FAIL' -or ($role -ceq 'broker' -and $r.processClose -cne 'FAILED') -or ($role -ceq 'legacy' -and $r.threadClose -cne 'FAILED')){throw ('MANAGER_FAILURE_LOST_'+$role)}
}
Write-Output 'PASS broker and legacy dependent-resource gates'
$job=[IntPtr]::Zero;$child=$null;$closed=$false
try {
 $job=[EtherPhaseAJob]::Create();$exe=Join-Path $PSHOME 'powershell.exe';$child=[EtherPhaseAAtomic]::CreateSelfInDirectory($job,$exe,('"'+$exe+'" -NoProfile -NonInteractive -Command "Start-Sleep -Seconds 90"'),[IO.Path]::GetTempPath())
 if(-not $child.InJob() -or $child.Exited()){throw 'REAL_CHILD_NOT_CONTAINED'}
 $owner=@{role='broker';accountSid='S-1-5-21-1'};$account=@{role='broker';sid=$owner.accountSid};$record=New-PhaseAActorProcessRecord $owner $account ('e'*32) ('f'*32) 'INJECTED'
 $child.Resume();if(-not (Invoke-PhaseAActorJobClose $job $record.lifecycle)){throw 'REAL_JOB_CLOSE_FAILED'};$job=[IntPtr]::Zero
 $record.lifecycle.child=@{};$result=Invoke-PhaseAActorChildCleanup $child $record.lifecycle.child;$observed=$record.lifecycle.child;$closed=$observed.atomicHandleClose -ceq 'CLOSED'
 if(-not $result.confirmed -or $result.cleanupFailed -or $observed.exitState -cne 'EXITED' -or $observed.finalWait -cne 'SIGNALED' -or $observed.processClose -cne 'CLOSED' -or $observed.threadClose -cne 'CLOSED' -or $record.lifecycle.jobClose -cne 'CLOSED'){throw 'REAL_CLOSE_EVIDENCE_INCOMPLETE'}
 $child.Dispose()
}finally{if($job -ne [IntPtr]::Zero){[EtherPhaseAJob]::Close($job)};if($child -and -not $closed){try{$child.Terminate();$null=$child.Wait(5000);$child.Dispose()}catch{}}}
Write-Output 'PASS current identity termination and three native close outcomes'
