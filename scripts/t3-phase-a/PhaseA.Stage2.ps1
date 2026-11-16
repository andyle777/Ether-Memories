Set-StrictMode -Version Latest
. "$PSScriptRoot/PhaseA.Core.ps1"
. "$PSScriptRoot/PhaseA.Native.ps1"
. "$PSScriptRoot/PhaseA.Atomic.ps1"
. "$PSScriptRoot/PhaseA.HostedSupervision.ps1"
function Test-PhaseAOwnedLaunchToken($Owner,$Account,$Stats) {
  try {
    if($Owner -isnot [hashtable] -or $Account -isnot [hashtable] -or $null -eq $Stats -or $Owner.role -cne $Account.role -or $Owner.accountSid -cne $Account.sid -or $Owner.inspection -cne 'OBSERVED' -or $Owner.closed -isnot [bool] -or $Owner.closed){return $false}
    foreach($key in @('tokenId','authenticationId','modifiedId')){if($Stats.$key -isnot [string] -or $Stats.$key -cnotmatch '^[0-9a-f]{16}$' -or $Stats.$key -cne $Owner.first[$key] -or $Stats.$key -cne $Owner.second[$key]){return $false}}
    return ($Stats.primary -is [bool] -and $Stats.primary -and $Owner.first.statisticsPrimary -is [bool] -and $Owner.first.statisticsPrimary -and $Owner.second.statisticsPrimary -is [bool] -and $Owner.second.statisticsPrimary)
  }catch{return $false}
}
function Invoke-PhaseAActorOperation($Account, $Token, [hashtable]$Backend, [string]$Operation, [string]$Target, [string]$ExpectedOutcome) {
  if ($Operation -notin @('Create','Read','Overwrite','Delete','Rename') -or $ExpectedOutcome -notin @('allowed','denied') -or
      $Token.sid -cne $Account.sid) { throw 'STAGE2_OBSERVATION_REJECTED' }
  $obs=& $Backend.Run $Account $Token $Operation $Target
  if ($obs -isnot [hashtable] -or -not $obs.ContainsKey('terminated') -or
      $obs.terminated -isnot [bool] -or -not $obs.terminated) { throw 'STAGE2_CHILD_UNCONFIRMED' }
  if ($obs.expectedSid -cne $Account.sid -or $obs.contained -isnot [bool] -or -not $obs.contained -or
      -not (Test-ActorObservation $obs $Account.role $ExpectedOutcome)) { throw 'STAGE2_OBSERVATION_REJECTED' }
  return $obs
}
function Invoke-PhaseAStage2($Accounts, $Tokens, [hashtable]$Backend) {
  if ($Accounts.Count -ne 2 -or $Tokens.Count -ne 2) { return 'STAGE2_OBSERVATION_REJECTED' }
  foreach ($i in 0,1) {
    $account=$Accounts[$i]; $token=$Tokens[$i]
    try {
      if ($token.sid -cne $account.sid) { return 'STAGE2_OBSERVATION_REJECTED' }
      $obs=& $Backend.Run $account $token
      if ($obs -isnot [hashtable] -or -not $obs.ContainsKey('terminated') -or
          $obs.terminated -isnot [bool] -or -not $obs.terminated) { throw 'STAGE2_CHILD_UNCONFIRMED' }
      if ($obs.expectedSid -cne $account.sid -or
          $obs.contained -isnot [bool] -or -not $obs.contained -or
          -not (Test-ActorObservation $obs $account.role 'allowed')) { return 'STAGE2_OBSERVATION_REJECTED' }
    } catch {
      $reason=$_.Exception.GetBaseException().Message
      if ($reason -ceq 'STAGE2_CHILD_UNCONFIRMED') { throw 'STAGE2_CHILD_UNCONFIRMED' }
      if ($reason -ceq 'STAGE2_CLEANUP_FAILED') { throw 'STAGE2_RESOURCE_UNCONFIRMED' }
      if ($reason -in @('STAGE2_TIMEOUT','STAGE2_CLEANUP_FAILED','STAGE2_OBSERVATION_REJECTED')) { return $reason }
      return 'STAGE2_LAUNCH_FAILED'
    }
  }
  return 'STAGE2_COMPLETE'
}
function Test-PhaseASupervisorCleanup($Lifetime) {
  try {
    if($Lifetime -isnot [hashtable] -or $Lifetime.cleanupSucceeded -isnot [bool] -or -not $Lifetime.cleanupSucceeded -or $Lifetime.cleanupObservation -isnot [hashtable]){return $false}
    $c=$Lifetime.cleanupObservation
    if($c.supervisorCreated -isnot [bool] -or $c.childRequired -isnot [bool] -or $c.jobClose -cnotin @('CLOSED','NOT_CREATED') -or $c.inspectionHandle -cnotin @('NOT_OPENED','DISPOSE_RETURNED')){return $false}
    if($c.supervisorCreated){if($c.jobClose -cne 'CLOSED' -or $c.supervisorWait -cne 'SIGNALED' -or $c.supervisorHandle -cne 'CLOSED'){return $false}}
    elseif($c.supervisorWait -cne 'NOT_RUN' -or $c.supervisorHandle -cne 'NOT_CREATED' -or $c.childRequired){return $false}
    if($c.childRequired){if(-not $c.supervisorCreated -or $c.childIdentity -cne 'MATCHED' -or $c.childWait -cne 'SIGNALED' -or $c.childHandle -cne 'DISPOSE_RETURNED'){return $false}}
    elseif($c.childIdentity -cne 'NOT_OBSERVED' -or $c.childWait -cne 'NOT_RUN' -or $c.childHandle -cne 'NOT_OPENED'){return $false}
    return $true
  }catch{return $false}
}
function Invoke-PhaseAStages([bool]$AccountEnabled, [bool]$ActorEnabled, [hashtable]$AccountBackend, [hashtable]$ActorBackend, [bool]$FilesystemEnabled=$false, [hashtable]$FixtureBackend=@{}, [hashtable]$Stage3Result=@{}, [bool]$HostedEnabled=$false, [hashtable]$SupervisorBackend=@{}, [hashtable]$HostedResult=@{}, [bool]$RequireTrustedHosted=$true) {
  if ($FilesystemEnabled -and (-not $AccountEnabled -or -not $ActorEnabled)) { return 'STAGE3_GUARD_REJECTED' }
  if ($ActorEnabled -and -not $AccountEnabled) { return 'STAGE2_GUARD_REJECTED' }
  if (-not $AccountEnabled) { return 'LIVE_DISABLED' }
  $trustedHostedRun=$null
  if($RequireTrustedHosted -and (Get-Variable -Name PhaseATrustedHostedBackends -Scope Script -ErrorAction SilentlyContinue) -and $script:PhaseATrustedHostedBackends.ContainsKey($SupervisorBackend)){$trustedHostedRun=$script:PhaseATrustedHostedBackends[$SupervisorBackend]}
  $state=@{reason='IMPLEMENTATION_INCOMPLETE';enabled=$ActorEnabled;backend=$ActorBackend;filesystem=$FilesystemEnabled;fixture=$FixtureBackend;result=$Stage3Result;hosted=$HostedEnabled;supervisor=$SupervisorBackend;hostedResult=$HostedResult;requireTrustedHosted=$RequireTrustedHosted;trustedHostedRun=$trustedHostedRun}
  $callback={
    param($accounts,$tokens)
    if ($state.enabled) {
      $state.reason=Invoke-PhaseAStage2 $accounts $tokens $state.backend
      if ($state.reason -cne 'STAGE2_COMPLETE') { throw 'stage 2 failed' }
      if ($state.hosted) {
        if($state.requireTrustedHosted -and ($null -eq $state.trustedHostedRun -or -not [object]::ReferenceEquals($state.trustedHostedRun,$state.supervisor.Run))){throw 'STAGE2_RESOURCE_UNCONFIRMED'}
        try { $control=Invoke-PhaseAHostedSupervision $accounts[0] $tokens[0] $state.supervisor 'LIVE' $state.hostedResult }
        catch { if ($_.Exception.GetBaseException().Message -ceq 'STAGE2_CHILD_UNCONFIRMED') { throw 'STAGE2_CHILD_UNCONFIRMED' }; throw 'STAGE2_RESOURCE_UNCONFIRMED' }
        if($control -isnot [hashtable] -or $control.cases -isnot [hashtable] -or $control.status -isnot [string]){throw 'STAGE2_RESOURCE_UNCONFIRMED'}
        $state.hostedResult['cases']=$control.cases
        # A failed or malformed supervision result must not release accounts
        # while its backend-owned process resources remain unconfirmed.
        $attempted=0;$cleanupConfirmed=$true
        foreach($mode in @('supervisorDeath','jobClosure','timeout')) {
          if(-not $control.cases.ContainsKey($mode)){$cleanupConfirmed=$false;continue}
          $case=$control.cases[$mode]
          if($case -isnot [hashtable] -or -not $case.ContainsKey('status')){$cleanupConfirmed=$false;continue}
          if($case.status -ceq 'NOT_RUN'){continue}
          $attempted++
          if(-not $state.hostedResult.ContainsKey('processLifetime') -or $state.hostedResult.processLifetime -isnot [hashtable] -or -not $state.hostedResult.processLifetime.ContainsKey($mode)){$cleanupConfirmed=$false;continue}
          $life=$state.hostedResult.processLifetime[$mode]
          if($life -isnot [hashtable] -or -not $life.ContainsKey('mode') -or $life.mode -cne $mode -or -not $life.ContainsKey('source') -or $life.source -cne 'LIVE' -or -not (Test-PhaseASupervisorCleanup $life)){$cleanupConfirmed=$false}
          if($case.ContainsKey('reason') -and $case.reason -ceq 'CLEANUP_FAILED'){$cleanupConfirmed=$false}
        }
        if($attempted -eq 0 -or -not $cleanupConfirmed){throw 'STAGE2_RESOURCE_UNCONFIRMED'}
        if ($control.status -cne 'LIVE_OBSERVED') { $state.reason='SUPERVISOR_LIVE_FAILED'; throw 'hosted supervisor controls failed' }
      }
      if ($state.filesystem) {
        $experiment=Invoke-PhaseAStage3 $accounts $tokens $state.fixture $state.backend $state.result
        $state.reason=$experiment.status
        $state.result['cases']=$experiment.cases
        $state.result['evidence']=$experiment.evidence
        if ($state.reason -cne 'STAGE3_COMPLETE') { throw 'stage 3 failed' }
      }
    }
  }.GetNewClosure()
  $stage=Invoke-PhaseAAccountGate $true $AccountBackend $callback
  if ($stage -ceq 'STAGE1_COMPLETE') { if ($FilesystemEnabled) { return 'STAGE3_COMPLETE' }; if ($ActorEnabled) { return 'STAGE2_COMPLETE' }; return 'STAGE1_COMPLETE' }
  if ($stage -ceq 'ACCOUNT_CONSUMER_FAILED') { return $state.reason }
  return $stage
}
function Invoke-PhaseABoundProcessLaunch($processRecord,[scriptblock]$launch) {
  $processRecord.launchAttempted=$true
  try{$child=& $launch;$processRecord.launchResult='CREATED';return $child}catch{$processRecord.launchResult='CREATE_FAILED';$processRecord.launchError=Get-PhaseAActorErrorCategory $_;throw}
}
function Invoke-PhaseAProcessTokenPair($process,$processRecord,$owner,[scriptblock]$inspect) {
  $processRecord.inspectionAttempted=$true
  try {
    $observed=& $inspect $process
    $first=@{};foreach($key in @('pid','createdAt','sid','primary','admin','elevated','standard','tokenId','authenticationId','modifiedId')){$first[$key]=$observed.$key};$processRecord.first=$first
    $again=& $inspect $process
    $second=@{};foreach($key in @('pid','createdAt','sid','primary','admin','elevated','standard','tokenId','authenticationId','modifiedId')){$second[$key]=$again.$key};$processRecord.second=$second;$processRecord.inspectionResult='OBSERVED'
    return $observed
  } catch {
    $failure=$_.Exception.GetBaseException().Message
    if($failure -ceq 'TOKEN_INSPECTION_CLOSE_FAILED'){$processRecord.inspectionResult='TOKEN_CLOSE_FAILED';$processRecord.cleanup='RESOURCE_FAILED';$owner.launchFailure='PROCESS_TOKEN_CLOSE_FAILED';throw 'STAGE2_CLEANUP_FAILED'}
    $processRecord.inspectionResult=if($failure -cin @('PROCESS_TOKEN_OPEN_DENIED','PROCESS_TOKEN_OPEN_FAILED','PROCESS_TOKEN_QUERY_FAILED')){$failure}else{'PROCESS_OBSERVATION_FAILED'}
    $owner.launchFailure='PROCESS_OBSERVATION_FAILED';throw 'STAGE2_OBSERVATION_REJECTED'
  }
}
function New-PhaseAActorProcessRecord([hashtable]$Owner,[hashtable]$Account,[string]$Experiment,[string]$Attempt,[ValidateSet('LIVE','INJECTED')][string]$Source) {
  if($Owner.role -cne $Account.role -or $Owner.accountSid -cne $Account.sid -or $Account.role -cnotin @('broker','legacy') -or $Experiment -cnotmatch '^[0-9a-f]{32}$' -or $Attempt -cnotmatch '^[0-9a-f]{32}$'){throw 'STAGE2_OBSERVATION_REJECTED'}
  $record=@{source=$Source;experiment=$Experiment;attempt=$Attempt;role=$Account.role;accountSid=$Account.sid;launchAttempted=$false;launchResult='NOT_ATTEMPTED';launchError='NONE';inspectionAttempted=$false;inspectionResult='NOT_ATTEMPTED';cleanup='NOT_OBSERVED';lifecycle=@{jobCreate='NOT_ATTEMPTED';jobCreateError='NONE';jobClose='NOT_ATTEMPTED';jobCloseError='NONE';executionWait='NOT_RUN';executionExitCode=$null;child=$null;processInspectionDispose='NOT_ATTEMPTED';processInspectionDisposeError='NONE';operationFailure='NONE';cleanupDependency='NOT_OBSERVED'}}
  $Owner.processObservation=$record
  if(-not $Owner.ContainsKey('processObservations')){$Owner.processObservations=New-Object 'System.Collections.Generic.List[object]'}
  $Owner.processObservations.Add($record)
  if($Source -ceq 'LIVE'){$null=$script:PhaseATrustedProcessTokenRecords.Add($record)}
  return $record
}
function Get-PhaseAActorErrorCategory($ErrorRecord) {
  $base=$ErrorRecord.Exception.GetBaseException()
  if($base -is [ComponentModel.Win32Exception]){if($base.NativeErrorCode -eq 5){return 'WIN32_ACCESS_DENIED'};if($base.NativeErrorCode -eq 6){return 'WIN32_INVALID_HANDLE'};return 'WIN32_OTHER'}
  return 'NON_WIN32'
}
function Save-PhaseAActorOperationFailure([hashtable]$Record,$ErrorRecord) {
  $failure=$ErrorRecord.Exception.GetBaseException().Message
  $Record.lifecycle.operationFailure=if($failure -cin @('STAGE2_TIMEOUT','STAGE2_OBSERVATION_REJECTED','STAGE2_CLEANUP_FAILED')){$failure}else{'OPERATION_FAILED'}
  if($Record.lifecycle.executionWait -ceq 'ATTEMPTED'){$Record.lifecycle.executionWait='FAILED'}
}
function Invoke-PhaseAActorJobClose([IntPtr]$Job,[hashtable]$Record,[scriptblock]$Close={param($j) [EtherPhaseAJob]::Close($j)}) {
  try{$null=& $Close $Job;$Record.jobClose='CLOSED';return $true}catch{$Record.jobClose='FAILED';$Record.jobCloseError=Get-PhaseAActorErrorCategory $_;return $false}
}
function Invoke-PhaseAActorChildCleanup($Child,[hashtable]$Record,[hashtable]$Io=@{}) {
  $native=($Io.Count -eq 0)
  if($native){$Io=@{Wait={param($c,$ms) $c.Wait([uint32]$ms)};Exited={param($c) $c.Exited()};ExitCode={param($c) $c.ExitCode()};Terminate={param($c) $c.Terminate()};Dispose={param($c) $c.CloseObserved()}}}
  $Record.firstWait='NOT_RUN';$Record.finalWait='NOT_RUN';$Record.termination='NOT_REQUESTED';$Record.exitState='UNKNOWN';$Record.exitCode=$null;$Record.atomicHandleClose='NOT_ATTEMPTED';$Record.processClose='NOT_ATTEMPTED';$Record.processCloseError='NONE';$Record.threadClose='NOT_ATTEMPTED';$Record.threadCloseError='NONE';$Record.error='NONE'
  $confirmed=$false;$cleanupFailed=$false
  try {
    $signal=& $Io.Wait $Child 5000;if($signal -isnot [bool]){throw 'invalid wait'}
    $Record.firstWait=if($signal){'SIGNALED'}else{'TIMEOUT'}
    if(-not $signal){$Record.termination='REQUESTED';$null=& $Io.Terminate $Child;$signal=& $Io.Wait $Child 5000;if($signal -isnot [bool]){throw 'invalid wait'}}
    if(-not $signal){$Record.finalWait='TIMEOUT';try{$exited=& $Io.Exited $Child;if($exited -is [bool] -and -not $exited){$Record.exitState='ALIVE'}}catch{}}
    else {$Record.finalWait='SIGNALED';$exited=& $Io.Exited $Child;if($exited -is [bool] -and $exited){$confirmed=$true;$Record.exitState='EXITED';try{$code=& $Io.ExitCode $Child;if($code -isnot [int]){throw 'invalid exit code'};$Record.exitCode=$code}catch{$cleanupFailed=$true;$Record.error=Get-PhaseAActorErrorCategory $_}}else{$Record.error='EXIT_UNCONFIRMED'}}
  }catch{if($Record.firstWait -ceq 'NOT_RUN'){$Record.firstWait='FAILED'};$Record.finalWait='FAILED';$Record.error=Get-PhaseAActorErrorCategory $_}
  if($confirmed){
    try {
      $close=& $Io.Dispose $Child
      if(($native -and $close -isnot [PhaseAHandleCloseResult]) -or $null -eq $close -or $close.ProcessClose -cnotin @('CLOSED','FAILED') -or $close.ThreadClose -cnotin @('CLOSED','FAILED') -or $close.ProcessError -cnotin @('NONE','WIN32_ACCESS_DENIED','WIN32_INVALID_HANDLE','WIN32_OTHER','CLOSE_EXCEPTION') -or $close.ThreadError -cnotin @('NONE','WIN32_ACCESS_DENIED','WIN32_INVALID_HANDLE','WIN32_OTHER','CLOSE_EXCEPTION') -or (($close.ProcessClose -ceq 'CLOSED') -ne ($close.ProcessError -ceq 'NONE')) -or (($close.ThreadClose -ceq 'CLOSED') -ne ($close.ThreadError -ceq 'NONE'))){throw 'close observation invalid'}
      $Record.processClose=$close.ProcessClose;$Record.processCloseError=$close.ProcessError;$Record.threadClose=$close.ThreadClose;$Record.threadCloseError=$close.ThreadError
      if($close.ProcessClose -ceq 'CLOSED' -and $close.ThreadClose -ceq 'CLOSED'){$Record.atomicHandleClose='CLOSED'}else{$Record.atomicHandleClose='FAILED';$cleanupFailed=$true;$Record.error=if($close.ThreadClose -ceq 'FAILED'){$close.ThreadError}else{$close.ProcessError}}
    }catch{$Record.atomicHandleClose='FAILED';$Record.processClose='UNKNOWN';$Record.threadClose='UNKNOWN';$Record.error=Get-PhaseAActorErrorCategory $_;$cleanupFailed=$true}
  }
  return @{confirmed=$confirmed;cleanupFailed=$cleanupFailed}
}
function New-PhaseAStage2Backend {
  $script:PhaseAActorExperimentId=[Guid]::NewGuid().ToString('N')
  $backend=@{ Run={ param($account,$token,$operation,$operationTarget)
    $common=[Environment]::GetFolderPath([Environment+SpecialFolder]::CommonApplicationData)
    if ([string]::IsNullOrWhiteSpace($common)) { throw 'stage directory unavailable' }
    $parent=[IO.Path]::GetFullPath($common).TrimEnd('\')
    $root=Join-Path $parent ('ether-phase-a-actor-'+[Guid]::NewGuid().ToString('N'))
    $actor=Join-Path $root 'Actor.ps1'; $ready=Join-Path $root 'ready.json'; $gate=Join-Path $root 'gate'
    $result=Join-Path $root 'result.json'; $target=Join-Path $root 'probe.bin'
    if ([string]::IsNullOrEmpty($operation)) { $operation='Create' }
    if ($operation -notin @('Create','Read','Overwrite','Delete','Rename')) { throw 'invalid operation' }
    if ([string]::IsNullOrEmpty($operationTarget)) { $operationTarget=$target }
    $job=[IntPtr]::Zero; $child=$null; $process=$null; $safeToRemove=$true; $cleanupFailed=$false; $createdRoot=$false; $tokenRef=$false; $launchHandle=$null; $processRecord=$null
    try {
      $null=New-Item -ItemType Directory -Path $root -ErrorAction Stop; $createdRoot=$true
      $item=Get-Item -LiteralPath $root -Force -ErrorAction Stop
      if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'reparse point rejected' }
      $acl=New-Object Security.AccessControl.DirectorySecurity
      $acl.SetAccessRuleProtection($true,$false)
      foreach ($sidText in @([Security.Principal.WindowsIdentity]::GetCurrent().User.Value,'S-1-5-18',$account.sid)) {
        $sid=New-Object Security.Principal.SecurityIdentifier($sidText)
        $rule=New-Object Security.AccessControl.FileSystemAccessRule($sid,'FullControl','ContainerInherit,ObjectInherit','None','Allow')
        $acl.AddAccessRule($rule)
      }
      Set-Acl -LiteralPath $root -AclObject $acl -ErrorAction Stop
      Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'Actor.ps1') -Destination $actor -ErrorAction Stop
      $nonce=[Guid]::NewGuid().ToString('N'); $exe=Join-Path $PSHOME 'powershell.exe'
      foreach ($path in @($actor,$ready,$gate,$result,$operationTarget,$exe,$root)) { if ($path.Contains('"')) { throw 'unsafe path' } }
      $cmd='"'+$exe+'" -NoProfile -NonInteractive -File "'+$actor+'" -Operation '+$operation+' -Target "'+$operationTarget+'" -Ready "'+$ready+'" -Gate "'+$gate+'" -Result "'+$result+'" -Nonce '+$nonce
      if(-not (Get-Variable -Name PhaseATokenOwners -Scope Script -ErrorAction SilentlyContinue) -or -not $script:PhaseATokenOwners.ContainsKey($token)){throw 'STAGE2_OBSERVATION_REJECTED'}
      $owner=$script:PhaseATokenOwners[$token]
      $processRecord=New-PhaseAActorProcessRecord $owner $account $script:PhaseAActorExperimentId $nonce 'LIVE'
      $processRecord.lifecycle.jobCreate='ATTEMPTED'
      try{$job=[EtherPhaseAJob]::Create();$processRecord.lifecycle.jobCreate='CREATED'}catch{$processRecord.lifecycle.jobCreate='FAILED';$processRecord.lifecycle.jobCreateError=Get-PhaseAActorErrorCategory $_;throw}
      $launchHandle=$token.handle;$launchHandle.DangerousAddRef([ref]$tokenRef);$tokenPointer=$launchHandle.DangerousGetHandle()
      try{$beforeLaunch=[EtherPhaseANative]::InspectTokenHandle($tokenPointer)}catch{$owner.launchFailure='TOKEN_STATISTICS_FAILED';throw 'STAGE2_OBSERVATION_REJECTED'}
      if(-not (Test-PhaseAOwnedLaunchToken $owner $account $beforeLaunch)){$owner.launchFailure='TOKEN_BINDING_REJECTED';throw 'STAGE2_OBSERVATION_REJECTED'}
      $processRecord.launchTokenId=$beforeLaunch.tokenId;$processRecord.launchAuthenticationId=$beforeLaunch.authenticationId;$processRecord.launchModifiedId=$beforeLaunch.modifiedId
      $child=Invoke-PhaseABoundProcessLaunch $processRecord { [EtherPhaseAAtomic]::CreateWithTokenInDirectory($tokenPointer,$job,$exe,$cmd,$root) }
      $safeToRemove=$false
      $processRecord.contained=$false;$processRecord.pid=[int]$child.Pid
      try{$inJob=$child.InJob();$alreadyExited=$child.Exited()}catch{$processRecord.inspectionResult='CONTAINMENT_QUERY_FAILED';throw 'STAGE2_OBSERVATION_REJECTED'}
      if (-not $inJob -or $alreadyExited) { $processRecord.inspectionResult='CONTAINMENT_REJECTED';throw 'child not contained or already exited' }
      $processRecord.contained=$true
      try{$process=Get-Process -Id $child.Pid -ErrorAction Stop;$processRecord.createdAt=$process.StartTime.ToUniversalTime().ToString('o')}catch{$processRecord.inspectionResult='PROCESS_OPEN_FAILED';throw 'STAGE2_OBSERVATION_REJECTED'}
      try{$observed=Invoke-PhaseAProcessTokenPair $process $processRecord $owner {param($p) Get-PhaseAProcessToken $p $true}}catch{if($_.Exception.GetBaseException().Message -ceq 'STAGE2_CLEANUP_FAILED'){$cleanupFailed=$true};throw}
      $first=$processRecord.first;$second=$processRecord.second
      try{$afterLaunch=[EtherPhaseANative]::InspectTokenHandle($tokenPointer)}catch{$owner.launchFailure='TOKEN_STATISTICS_FAILED';throw 'STAGE2_OBSERVATION_REJECTED'}
      $processRecord.postTokenId=$afterLaunch.tokenId;$processRecord.postAuthenticationId=$afterLaunch.authenticationId;$processRecord.postModifiedId=$afterLaunch.modifiedId
      foreach($key in @('tokenId','authenticationId','modifiedId')){if($afterLaunch.$key -cne $beforeLaunch.$key){$owner.launchFailure='TOKEN_BINDING_REJECTED';throw 'STAGE2_OBSERVATION_REJECTED'}}
      foreach($key in @('pid','createdAt','sid','primary','admin','elevated','standard','tokenId','authenticationId','modifiedId')){if($first[$key] -cne $second[$key]){$owner.launchFailure='PROCESS_OBSERVATION_FAILED';throw 'STAGE2_OBSERVATION_REJECTED'}}
      if ($observed.pid -ne $child.Pid -or $observed.createdAt -cne $processRecord.createdAt -or $observed.sid -cne $account.sid -or $observed.admin -or $observed.elevated -or -not $observed.standard) { $owner.launchFailure='PROCESS_BINDING_REJECTED';throw 'STAGE2_OBSERVATION_REJECTED' }
      if(-not $observed.primary -or $observed.authenticationId -cne $beforeLaunch.authenticationId){$owner.launchFailure='PROCESS_BINDING_REJECTED';throw 'STAGE2_OBSERVATION_REJECTED'}
      $child.Resume()
      $deadline=[DateTime]::UtcNow.AddSeconds(20)
      while (-not [IO.File]::Exists($ready)) {
        if ($child.Exited()) { throw 'actor exited before readiness' }
        if ([DateTime]::UtcNow -ge $deadline) { throw 'STAGE2_TIMEOUT' }
        Start-Sleep -Milliseconds 50
      }
      if ($child.Exited() -or -not $child.InJob() -or (Get-Item -LiteralPath $ready).Length -gt 4096) { throw 'invalid actor readiness' }
      $record=Get-Content -LiteralPath $ready -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
      $t1=[DateTimeOffset]::MinValue; $t2=[DateTimeOffset]::MinValue
      if ($record.pid -ne $child.Pid -or $record.sid -cne $observed.sid -or $record.nonce -cne $nonce -or
          -not [DateTimeOffset]::TryParse([string]$record.createdAt,[ref]$t1) -or
          -not [DateTimeOffset]::TryParse([string]$observed.createdAt,[ref]$t2) -or $t1 -ne $t2) { throw 'STAGE2_OBSERVATION_REJECTED' }
      [IO.File]::WriteAllText($gate,'go')
      $processRecord.lifecycle.executionWait='ATTEMPTED'
      if (-not $child.Wait(20000)) { $processRecord.lifecycle.executionWait='TIMEOUT';throw 'STAGE2_TIMEOUT' }
      $processRecord.lifecycle.executionWait='SIGNALED';$safeToRemove=$true; $code=$child.ExitCode();$processRecord.lifecycle.executionExitCode=$code
      if (-not [IO.File]::Exists($result) -or (Get-Item -LiteralPath $result).Length -gt 4096) { throw 'actor result missing' }
      $final=Get-Content -LiteralPath $result -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
      $obs=@{ role=$account.role; expectedSid=$account.sid; observedSid=$observed.sid; reportedSid=$final.sid;
        expectedPid=$child.Pid; reportedPid=$final.pid; tokenNonAdmin=$true; tokenObserved=$true;
        createdAt=$final.createdAt; observedCreatedAt=$observed.createdAt; expectedNonce=$nonce;
        reportedNonce=$final.nonce; exitCode=$code; outcome=$final.outcome; contained=$true; terminated=$true }
      $obs.lineage=@{source='LIVE';role=$account.role;launchTokenId=$beforeLaunch.tokenId;launchAuthenticationId=$beforeLaunch.authenticationId;launchModifiedId=$beforeLaunch.modifiedId;processTokenId=$observed.tokenId;processAuthenticationId=$observed.authenticationId;processModifiedId=$observed.modifiedId;processPrimary=$observed.primary;pid=$observed.pid;createdAt=$observed.createdAt;contained=$true}
      if ($final.PSObject.Properties.Name -contains 'digest') { $obs.digest=$final.digest }
      if ($final.PSObject.Properties.Name -contains 'errorCategory' -and $final.errorCategory -cin @('NONE','ACCESS_DENIED','FILE_NOT_FOUND','PATH_NOT_FOUND','INVALID_PATH','IO_ERROR','OTHER')) { $obs.errorCategory=$final.errorCategory }
      if ($final.PSObject.Properties.Name -contains 'errorCode' -and $final.errorCode -is [int] -and $final.errorCode -ge 0 -and $final.errorCode -le 65535) { $obs.errorCode=$final.errorCode }
      return $obs
    } catch {
      if($processRecord){Save-PhaseAActorOperationFailure $processRecord $_}
      throw
    } finally {
      if($tokenRef){try{$launchHandle.DangerousRelease()}catch{$cleanupFailed=$true}}
      if ($job -ne [IntPtr]::Zero) { if($processRecord){if(-not (Invoke-PhaseAActorJobClose $job $processRecord.lifecycle)){$cleanupFailed=$true}}else{try{[EtherPhaseAJob]::Close($job)}catch{$cleanupFailed=$true}} }
      if ($child) {
        $childEvidence=@{};if($processRecord){$processRecord.lifecycle.child=$childEvidence}
        $childResult=Invoke-PhaseAActorChildCleanup $child $childEvidence
        $safeToRemove=$childResult.confirmed;if($childResult.cleanupFailed){$cleanupFailed=$true}
      }
      if ($process) { try { $process.Dispose();if($processRecord){$processRecord.lifecycle.processInspectionDispose='DISPOSE_RETURNED'} } catch { $cleanupFailed=$true;if($processRecord){$processRecord.lifecycle.processInspectionDispose='FAILED';$processRecord.lifecycle.processInspectionDisposeError=Get-PhaseAActorErrorCategory $_} } }
      if($processRecord){$processRecord.cleanup=if(-not $safeToRemove){'CHILD_UNCONFIRMED'}elseif($cleanupFailed){'RESOURCE_FAILED'}else{'PROCESS_CONFIRMED'}}
      if(-not $safeToRemove -or $cleanupFailed){$script:PhaseAUnconfirmedActorResources=@{child=$child;process=$process;job=$(if($processRecord -and $processRecord.lifecycle.jobClose -ceq 'CLOSED'){[IntPtr]::Zero}else{$job});root=$root}}
      if (-not $safeToRemove) {if($processRecord){$processRecord.lifecycle.cleanupDependency='RETAIN'};throw 'STAGE2_CHILD_UNCONFIRMED' }
      if ($cleanupFailed) {if($processRecord){$processRecord.lifecycle.cleanupDependency='RETAIN'};throw 'STAGE2_CLEANUP_FAILED'}
      if ($createdRoot -and [IO.Directory]::Exists($root)) {
        $resolved=[IO.Path]::GetFullPath($root)
        if (-not $resolved.StartsWith($parent+'\',[StringComparison]::OrdinalIgnoreCase) -or -not [IO.Path]::GetFileName($resolved).StartsWith('ether-phase-a-actor-')) { throw 'STAGE2_CLEANUP_FAILED' }
        try {
          $rootItem=Get-Item -LiteralPath $resolved -Force -ErrorAction Stop
          if (($rootItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'reparse point rejected' }
          foreach ($path in @($target,$result,$gate,$ready,$actor)) {
            if (Test-Path -LiteralPath $path) {
              $entry=Get-Item -LiteralPath $path -Force -ErrorAction Stop
              if (($entry.Attributes -band ([IO.FileAttributes]::ReparsePoint -bor [IO.FileAttributes]::Directory)) -ne 0) { throw 'unexpected entry' }
              [IO.File]::Delete($path)
            }
          }
          [IO.Directory]::Delete($resolved,$false)
        } catch { $cleanupFailed=$true }
      }
      if ($cleanupFailed) { if($processRecord){$processRecord.cleanup='RESOURCE_FAILED';$processRecord.lifecycle.cleanupDependency='RETAIN'};throw 'STAGE2_CLEANUP_FAILED' }
      if($processRecord){$processRecord.lifecycle.cleanupDependency='RELEASE_ELIGIBLE'}
    }
  } }
  if(-not (Get-Variable -Name PhaseATrustedActorBackends -Scope Script -ErrorAction SilentlyContinue)){$script:PhaseATrustedActorBackends=New-Object 'System.Collections.Generic.Dictionary[object,object]'}
  $script:PhaseATrustedActorBackends.Add($backend,$backend.Run)
  return $backend
}
function Invoke-PhaseAAdversarialControls {
  $base=@{role='legacy';expectedSid='S-1-5-21-1';observedSid='S-1-5-21-1';reportedSid='S-1-5-21-1';expectedPid=123;reportedPid=123;tokenNonAdmin=$true;tokenObserved=$true;createdAt='2026-01-01T00:00:00Z';observedCreatedAt='2026-01-01T00:00:00Z';expectedNonce='synthetic-nonce';reportedNonce='synthetic-nonce';exitCode=20;outcome='denied';contained=$true;terminated=$true}
  $account=@{role='legacy';sid='S-1-5-21-1'}; $token=@{sid='S-1-5-21-1'}
  $cases=@{}
  $positive=@{Run={ param($a,$t,$op,$target) $base }.GetNewClosure()}
  try { $null=Invoke-PhaseAActorOperation $account $token $positive 'Read' 'synthetic' 'denied'; $baseline=$true } catch { $baseline=$false }
  $cases.sameSid= -not (Test-DistinctActorSids $account.sid $account.sid)
  foreach ($name in @('wrongSid','wrongPid','wrongCreationTime','forgedObservation','malformedObservation','missingObservation','wrongJob','unexpectedSuccess','wrongDenial','missingDenial')) {
    $sample=$base.Clone()
    switch ($name) {
      'wrongSid' { $sample.reportedSid='S-1-5-21-2' }
      'wrongPid' { $sample.reportedPid=124 }
      'wrongCreationTime' { $sample.createdAt='2026-01-01T00:00:01Z' }
      'forgedObservation' { $sample.reportedNonce='forged' }
      'malformedObservation' { $sample.Remove('reportedNonce') }
      'missingObservation' { $sample=$null }
      'wrongJob' { $sample.contained=$false }
      'unexpectedSuccess' { $sample.outcome='allowed'; $sample.exitCode=0 }
      'wrongDenial' { $sample.exitCode=21 }
      'missingDenial' { $sample.Remove('exitCode') }
    }
    $backend=@{Run={ param($a,$t,$op,$target) $sample }.GetNewClosure()}
    $rejected=$false
    try { $null=Invoke-PhaseAActorOperation $account $token $backend 'Read' 'synthetic' 'denied' }
    catch { $rejected=$_.Exception.GetBaseException().Message -cin @('STAGE2_OBSERVATION_REJECTED','STAGE2_CHILD_UNCONFIRMED') }
    $cases[$name]=$rejected
  }
  if (-not $baseline) { foreach ($key in @($cases.Keys)) { $cases[$key]=$false } }
  return @{kind='injected';cases=$cases}
}
function Get-PhaseAAdversarialStatus($Result) {
  $keys=@('wrongSid','sameSid','wrongPid','wrongCreationTime','forgedObservation','malformedObservation','missingObservation','wrongJob','unexpectedSuccess','wrongDenial','missingDenial')
  if ($Result -isnot [hashtable] -or -not $Result.ContainsKey('kind') -or $Result.kind -cne 'injected' -or -not $Result.ContainsKey('cases') -or $Result.cases -isnot [hashtable] -or $Result.cases.Count -ne $keys.Count) { return 'FAIL' }
  foreach ($key in $keys) { if (-not $Result.cases.ContainsKey($key) -or $Result.cases[$key] -isnot [bool] -or -not $Result.cases[$key]) { return 'FAIL' } }
  return 'SIMULATED_PASS'
}
function Invoke-PhaseASupervisorEvidence([scriptblock]$SameIdentityProbe) {
  $result=@{injected='FAIL';sameIdentity='NOT_RUN';reason='SUPERVISOR_INJECTED_FAILED'}
  $accounts=@(@{role='broker';sid='S-1-5-21-1'},@{role='legacy';sid='S-1-5-21-2'})
  $tokens=@(@{sid='S-1-5-21-1'},@{sid='S-1-5-21-2'})
  $positive=@{Run={param($a,$t) @{role=$a.role;expectedSid=$a.sid;observedSid=$a.sid;reportedSid=$a.sid;expectedPid=123;reportedPid=123;tokenNonAdmin=$true;tokenObserved=$true;createdAt='2026-01-01T00:00:00Z';observedCreatedAt='2026-01-01T00:00:00Z';expectedNonce='n';reportedNonce='n';exitCode=0;outcome='allowed';contained=$true;terminated=$true}}}
  try {
    if ((Invoke-PhaseAStage2 $accounts $tokens $positive) -cne 'STAGE2_COMPLETE') { return $result }
    foreach ($reason in @('STAGE2_TIMEOUT','STAGE2_CLEANUP_FAILED','STAGE2_CHILD_UNCONFIRMED')) {
      $backend=@{Run={param($a,$t) throw $reason}.GetNewClosure()}
      $observed=''
      try { $observed=Invoke-PhaseAStage2 $accounts $tokens $backend } catch { $observed=$_.Exception.GetBaseException().Message }
      $expected=if($reason -ceq 'STAGE2_CLEANUP_FAILED'){'STAGE2_RESOURCE_UNCONFIRMED'}else{$reason}
      if ($observed -cne $expected) { return $result }
    }
    $result.injected='SIMULATED_PASS'; $result.sameIdentity='FAIL'; $result.reason='SUPERVISOR_PROBE_FAILED'
    $probeResult=& $SameIdentityProbe
    if ($probeResult -is [bool] -and $probeResult) { $result.sameIdentity='SAME_IDENTITY_PASS'; $result.reason='NONE' }
  } catch { $message=$_.Exception.GetBaseException().Message; if ($message -cin @('SUPERVISOR_JOB_PROBE_FAILED','SUPERVISOR_DEATH_PROBE_FAILED')) { $result.reason=$message } }
  return $result
}
