$ErrorActionPreference='Stop'
. "$PSScriptRoot/PhaseA.Core.ps1"
. "$PSScriptRoot/PhaseA.Accounts.ps1"
. "$PSScriptRoot/PhaseA.Stage2.ps1"
$config=@{repository='andyle777/Ether-Memories';event='push';ref='refs/heads/test/t3-windows-enforcement-run';runner='github-hosted';sha=('a'*40);base='42f9b5bdf94e47c4c69c0f87127eb545dff13ed1'}
$env:GITHUB_REPOSITORY=$config.repository;$env:GITHUB_EVENT_NAME=$config.event;$env:GITHUB_REF=$config.ref;$env:RUNNER_ENVIRONMENT=$config.runner;$env:GITHUB_SHA=$config.sha
$global:PhaseAGateTestScenario='';$global:PhaseAGateTestCalls=@{account=0;authenticate=0;actor=0;supervisor=0;fixtureCreate=0;fixtureDelete=0}
$accounts=@{Create={param($role) $global:PhaseAGateTestCalls.account++;throw 'stop before account creation'};Authenticate={param($a) $global:PhaseAGateTestCalls.authenticate++};Close={param($t)};Remove={param($a)}}
$actors=@{Run={param($a,$t) $global:PhaseAGateTestCalls.actor++}}
$supervisor=@{Run={param($a,$t,$mode) $global:PhaseAGateTestCalls.supervisor++}}
$fixture=@{Setup={param($a) $global:PhaseAGateTestCalls.fixtureCreate++};Cleanup={param($f) $global:PhaseAGateTestCalls.fixtureDelete++}}
$after={ Invoke-PhaseAStages $true $true $accounts $actors $true $fixture @{} $true $supervisor @{} $false }
$checkout={param($repository,$sha,$base,$journal)
 $attempt='aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';$stream=New-Object psobject;$stream|Add-Member ScriptMethod ReadToEndAsync {[Threading.Tasks.Task]::FromResult('')}
 foreach($i in 0..2){
  $fake=[pscustomobject]@{StartInfo=$null;Id=(100+$i);StartTime=[datetime]::UtcNow;ExitCode=0;StandardOutput=$stream;StandardError=$stream;waitCount=0}
  $fake|Add-Member ScriptMethod Start {if($global:PhaseAGateTestScenario -ceq 'launch' -and $this.Id -eq 100){throw 'start'};$true}
  $fake|Add-Member ScriptMethod WaitForExit {param($ms) $this.waitCount++;if($this.Id -eq 100 -and $global:PhaseAGateTestScenario -in @('timeout','unconfirmed')){if($global:PhaseAGateTestScenario -ceq 'timeout' -and $this.waitCount -gt 1){return $true};return $false};if($this.Id -eq 100 -and $global:PhaseAGateTestScenario -ceq 'wait'){throw 'wait'};return $true}
  $fake|Add-Member ScriptMethod Kill {}
  $fake|Add-Member ScriptMethod Dispose {if($global:PhaseAGateTestScenario -ceq 'dispose'){throw 'dispose'}}
  $factory={return $fake}.GetNewClosure();$observer={param($id) @{pid=$id;createdAt=$fake.StartTime.ToUniversalTime().ToString('o')}}.GetNewClosure()
  $op=@('HEAD','ANCESTOR','CLEAN')[$i];$null=Invoke-PhaseAGit $PSScriptRoot 'status' $journal $factory $attempt $op $i $observer
  if($global:PhaseAGateTestScenario -ceq 'exception' -and $i -eq 1){throw 'later exception'}
 }
 switch($global:PhaseAGateTestScenario){'identity'{$journal[0].observedPid=999} 'duplicate'{$journal[1].attempt=$journal[0].attempt} 'stale'{$journal[1].experiment=('b'*32)} 'contradiction'{$journal[0].wait='UNCONFIRMED'}}
 return $true
}
foreach($kind in @('launch','timeout','wait','unconfirmed','identity','duplicate','stale','contradiction','dispose','exception','success')){
 $global:PhaseAGateTestScenario=$kind;foreach($key in @($global:PhaseAGateTestCalls.Keys)){$global:PhaseAGateTestCalls[$key]=0};$journal=New-Object 'System.Collections.Generic.List[object]'
 $result=& "$PSScriptRoot/Invoke-PhaseA.ps1" -RequiredBase $config.base -OutputFile 'unused-test-output' -EnableAccountStage -EnableActorStage -EnableFilesystemStage -EnableSupervisorProbe -TestHooks @{Checkout=$checkout;AfterCheckout=$after}
 $journal=$result.journal
 if($kind -ceq 'success'){if($result.reason -cne 'ACCOUNT_CREATION_FAILED' -or $global:PhaseAGateTestCalls.account -ne 1){throw 'POSITIVE_GATE_FAILED'}}
 else {if($result.reason -cne 'CHECKOUT_REJECTED' -or $global:PhaseAGateTestCalls.account -ne 0){throw ('GATE_ACCEPTED_'+$kind)}}
 foreach($key in @('authenticate','actor','supervisor','fixtureCreate','fixtureDelete')){if($global:PhaseAGateTestCalls[$key] -ne 0){throw ('UNEXPECTED_CALLBACK_'+$key)}}
 if($journal.Count -lt 1){throw ('EVIDENCE_MISSING_'+$kind)}
 if($kind -ceq 'unconfirmed' -and ($journal[0].wait -cne 'UNCONFIRMED' -or $journal[0].managedDispose -cne 'RETAINED' -or $journal[0].error -cne 'TERMINATION_UNCONFIRMED')){throw 'UNCONFIRMED_NOT_RETAINED'}
 if($kind -ceq 'exception' -and ($journal.Count -ne 2 -or $journal[0].identity -cne 'MATCHED' -or $journal[0].wait -cne 'SIGNALED')){throw 'EARLIER_OBSERVATION_NOT_RETAINED'}
}
Write-Output 'PASS manager preflight gate negative and positive controls'
