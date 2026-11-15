$ErrorActionPreference='Stop'
. "$PSScriptRoot/PhaseA.Stage2.ps1"
. "$PSScriptRoot/PhaseA.Accounts.ps1"
$calls=@{close=0;remove=0;fixture=0}
$accounts=@{Create={param($r) @{role=$r;sid=$(if($r -ceq 'broker'){'S-1-5-21-1'}else{'S-1-5-21-2'})}};Authenticate={param($a) @{sid=$a.sid;primary=$true;admin=$false;elevated=$false;standard=$true}};Close={param($t) $calls.close++}.GetNewClosure();Remove={param($a) $calls.remove++}.GetNewClosure()}
$actors=@{Run={param($a,$t) @{role=$a.role;expectedSid=$a.sid;observedSid=$a.sid;reportedSid=$a.sid;expectedPid=123;reportedPid=123;tokenNonAdmin=$true;tokenObserved=$true;createdAt='2026-01-01T00:00:00Z';observedCreatedAt='2026-01-01T00:00:00Z';expectedNonce='n';reportedNonce='n';exitCode=0;outcome='allowed';contained=$true;terminated=$true}}}
$fixture=@{Setup={param($a) $calls.fixture++;throw 'fixture must not start'}.GetNewClosure()}
$savedDispatcher=(Get-Command Invoke-PhaseAHostedSupervision).ScriptBlock
try {
  function Invoke-PhaseAHostedSupervision { throw 'synthetic dispatcher failure' }
  $calls.close=0;$calls.remove=0
  $dispatcherResult=Invoke-PhaseAStages $true $true $accounts $actors $false @{} @{} $true @{Run={}} @{} $false
  if($dispatcherResult -cne 'ACCOUNT_CLEANUP_FAILED' -or $calls.close -ne 0 -or $calls.remove -ne 0){throw 'DISPATCHER_EXCEPTION_RELEASED_RESOURCES'}
} finally { Set-Item Function:Invoke-PhaseAHostedSupervision $savedDispatcher }
try {
  function Invoke-PhaseAHostedSupervision { return @{} }
  $calls.close=0;$calls.remove=0
  $dispatcherResult=Invoke-PhaseAStages $true $true $accounts $actors $false @{} @{} $true @{Run={}} @{} $false
  if($dispatcherResult -cne 'ACCOUNT_CLEANUP_FAILED' -or $calls.close -ne 0 -or $calls.remove -ne 0){throw 'MALFORMED_DISPATCHER_RELEASED_RESOURCES'}
} finally { Set-Item Function:Invoke-PhaseAHostedSupervision $savedDispatcher }
foreach($kind in @('jobClose','handleClose','survivor','waitFailure','ambiguousWait','missing','malformed','missingCleanupDetails','exception','readinessUnconfirmed')) {
  $calls.close=0;$calls.remove=0;$calls.fixture=0;$script:scenario=$kind
  $supervisor=@{Run={param($a,$t,$mode)
    switch($script:scenario){
      'jobClose' {return @{outcome='FAILED';reason='CLEANUP_FAILED';processLifetime=@{mode=$mode;cleanupSucceeded=$false;error='JOB_CLOSE_FAILED'}}}
      'handleClose' {return @{outcome='OBSERVED';identity=$true;pid=$true;creationTime=$true;membership=$true;childTerminated=$true;supervisorTerminated=$true;cleanup=$false;timeoutObserved=$true;processLifetime=@{mode=$mode;cleanupSucceeded=$false;error='CLEANUP_FAILED'}}}
      'survivor' {$e=New-Object InvalidOperationException('STAGE2_CHILD_UNCONFIRMED');$e.Data['PhaseAProcessLifetime']=@{mode=$mode;cleanupSucceeded=$false;childWaitOutcome='TIMEOUT';childAliveAfterWait=$true};throw $e}
      'waitFailure' {$e=New-Object InvalidOperationException('STAGE2_CHILD_UNCONFIRMED');$e.Data['PhaseAProcessLifetime']=@{mode=$mode;cleanupSucceeded=$false;childWaitOutcome='FAILED'};throw $e}
      'ambiguousWait' {return @{outcome='FAILED';reason='TERMINATION_FAILED';processLifetime=@{mode=$mode;cleanupSucceeded=$false;childWaitOutcome='NOT_RUN'}}}
      'missing' {return $null}
      'malformed' {return @{outcome='OBSERVED';cleanup='true';processLifetime=@{mode=$mode;cleanupSucceeded='true'}}}
      'missingCleanupDetails' {return @{outcome='OBSERVED';identity=$true;pid=$true;creationTime=$true;membership=$true;childTerminated=$true;supervisorTerminated=$true;cleanup=$true;timeoutObserved=$true;processLifetime=@{mode=$mode;cleanupSucceeded=$true}}}
      'exception' {throw 'synthetic backend error'}
      'readinessUnconfirmed' {return @{outcome='FAILED';reason='READINESS_MISSING';processLifetime=@{mode=$mode;cleanupSucceeded=$false}}}
    }
  }}
  $sink=@{prior=@{state='FAIL';proof='prior-evidence'}};$result=Invoke-PhaseAStages $true $true $accounts $actors $true $fixture @{} $true $supervisor $sink $false
  if($result -cne 'ACCOUNT_CLEANUP_FAILED' -or $calls.close -ne 0 -or $calls.remove -ne 0 -or $calls.fixture -ne 0){throw ('DEPENDENT_RESOURCE_RELEASED_'+$kind)}
  if($sink.prior.proof -cne 'prior-evidence'){throw ('PRIOR_EVIDENCE_LOST_'+$kind)}
  if($kind -ceq 'jobClose' -and $sink.processLifetime.supervisorDeath.error -cne 'JOB_CLOSE_FAILED'){throw 'HOSTED_EVIDENCE_LOST'}
  if($kind -ceq 'survivor' -and $sink.processLifetime.supervisorDeath.childWaitOutcome -cne 'TIMEOUT'){throw 'SURVIVOR_EVIDENCE_LOST'}
}
$clean=@{jobClose='CLOSED';supervisorCreated=$true;supervisorWait='SIGNALED';supervisorHandle='CLOSED';inspectionHandle='DISPOSE_RETURNED';childRequired=$true;childIdentity='MATCHED';childWait='SIGNALED';childHandle='DISPOSE_RETURNED'}
foreach($pair in @(@('jobClose','FAILED'),@('supervisorWait','FAILED'),@('supervisorWait','TIMEOUT'),@('supervisorHandle','FAILED'),@('inspectionHandle','FAILED'),@('childWait','TIMEOUT'),@('childWait','FAILED'),@('childHandle','FAILED'),@('childRequired','true'))){$bad=$clean.Clone();$bad[$pair[0]]=$pair[1];if(Test-PhaseASupervisorCleanup @{cleanupSucceeded=$true;cleanupObservation=$bad}){throw ('INVALID_CLEANUP_ACCEPTED_'+$pair[0])}}
$bad=$clean.Clone();$bad.supervisorCreated=$false;if(Test-PhaseASupervisorCleanup @{cleanupSucceeded=$true;cleanupObservation=$bad}){throw 'CONTRADICTORY_CHILD_ACCEPTED'}
$bad=$clean.Clone();$null=$bad.Remove('childWait');if(Test-PhaseASupervisorCleanup @{cleanupSucceeded=$true;cleanupObservation=$bad}){throw 'MISSING_CHILD_WAIT_ACCEPTED'}
$bad=$clean.Clone();$bad.childIdentity='NOT_OBSERVED';if(Test-PhaseASupervisorCleanup @{cleanupSucceeded=$true;cleanupObservation=$bad}){throw 'UNVERIFIED_CHILD_IDENTITY_ACCEPTED'}
$calls.close=0;$calls.remove=0;$good=@{Run={param($a,$t,$mode) @{outcome='OBSERVED';identity=$true;pid=$true;creationTime=$true;membership=$true;childTerminated=$true;supervisorTerminated=$true;cleanup=$true;timeoutObserved=$true;processLifetime=@{mode=$mode;cleanupSucceeded=$true;cleanupObservation=$clean}}}.GetNewClosure()}
$ok=Invoke-PhaseAStages $true $true $accounts $actors $false @{} @{} $true $good @{} $false
if($ok -cne 'STAGE2_COMPLETE' -or $calls.close -ne 2 -or $calls.remove -ne 2){throw 'SUCCESSFUL_SUPERVISOR_CLEANUP_REJECTED'}
$unstarted=@{jobClose='NOT_CREATED';supervisorCreated=$false;supervisorWait='NOT_RUN';supervisorHandle='NOT_CREATED';inspectionHandle='NOT_OPENED';childRequired=$false;childIdentity='NOT_OBSERVED';childWait='NOT_RUN';childHandle='NOT_OPENED'}
$calls.close=0;$calls.remove=0;$readiness=@{Run={param($a,$t,$mode) @{outcome='FAILED';reason='READINESS_MISSING';processLifetime=@{mode=$mode;cleanupSucceeded=$true;cleanupObservation=$unstarted}}}.GetNewClosure()}
$ok=Invoke-PhaseAStages $true $true $accounts $actors $false @{} @{} $true $readiness @{} $false
if($ok -cne 'SUPERVISOR_LIVE_FAILED' -or $calls.close -ne 2 -or $calls.remove -ne 2){throw 'CONFIRMED_READINESS_FAILURE_CLEANUP_REJECTED'}
$calls.close=0;$calls.remove=0
$relabeled=Invoke-PhaseAStages $true $true $accounts $actors $false @{} @{} $true $good @{} $true
if($relabeled -cne 'ACCOUNT_CLEANUP_FAILED' -or $calls.close -ne 0 -or $calls.remove -ne 0){throw 'INJECTED_SUPERVISOR_RELABELLED_LIVE'}
$calls.close=0;$calls.remove=0;$defaultGuard=Invoke-PhaseAStages $true $true $accounts $actors $false @{} @{} $true $good @{}
if($defaultGuard -cne 'ACCOUNT_CLEANUP_FAILED' -or $calls.close -ne 0 -or $calls.remove -ne 0){throw 'DEFAULT_SUPERVISOR_GUARD_DISABLED'}
$real=New-PhaseAHostedSupervisorBackend;$real.Run=$good.Run;$calls.close=0;$calls.remove=0
$substituted=Invoke-PhaseAStages $true $true $accounts $actors $false @{} @{} $true $real @{} $true
if($substituted -cne 'ACCOUNT_CLEANUP_FAILED' -or $calls.close -ne 0 -or $calls.remove -ne 0){throw 'SUBSTITUTED_LIVE_SUPERVISOR_ACCEPTED'}
$script:PhaseATrustedHostedBackends.Add($good,$good.Run)
try {$calls.close=0;$calls.remove=0;$accepted=Invoke-PhaseAStages $true $true $accounts $actors $false @{} @{} $true $good @{} $true;if($accepted -cne 'STAGE2_COMPLETE' -or $calls.close -ne 2 -or $calls.remove -ne 2){throw 'TRUSTED_SUPERVISOR_SUCCESS_REJECTED'}} finally {$null=$script:PhaseATrustedHostedBackends.Remove($good)}
. "$PSScriptRoot/PhaseA.Verdict.ps1"
. "$PSScriptRoot/PhaseA.Evidence.ps1"
$sample=@{sid='S-1-5-21-1';primary=$false;admin=$false;elevated=$false;standard=$true;tokenId='0000000000000001';authenticationId='0000000000000010';modifiedId='0000000000000020';statisticsPrimary=$false}
$second=$sample.Clone();$second.handleOpen=$true
$prior=@{role='broker';accountSid='S-1-5-21-1';source='INJECTED';first=$sample;second=$second;closed=$false;inspection='OBSERVED';closeResult='NOT_ATTEMPTED'}
$before=New-PhaseAManagerVerdictInput ('1'*40) '123';Add-PhaseAPrimaryTokenEvidence $before @($prior) @() 'SIMULATED_PASS'
if($before.cases.brokerPrimaryToken.state -cne 'FAIL'){throw 'PRIOR_TOKEN_VIOLATION_NOT_ESTABLISHED'}
$script:scenario='jobClose';$calls.close=0;$calls.remove=0;$sink=@{};$null=Invoke-PhaseAStages $true $true $accounts $actors $false @{} @{} $true $supervisor $sink $false
$after=New-PhaseAManagerVerdictInput ('1'*40) '123';Add-PhaseAPrimaryTokenEvidence $after @($prior) @() 'SIMULATED_PASS'
if($after.cases.brokerPrimaryToken.state -cne 'FAIL' -or $after.cases.brokerPrimaryToken.proof -cne $before.cases.brokerPrimaryToken.proof){throw 'PRIOR_TOKEN_VIOLATION_LOST'}
Write-Output 'PASS supervisor resource retention, failure evidence and safe cleanup controls'
