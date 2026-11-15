$ErrorActionPreference='Stop'
. "$PSScriptRoot/PhaseA.PrimaryTokenBridge.Tests.ps1"
# The existing substitution regression uses a shallow actor copy and mutates
# the shared broker lineage. Build fresh values for this separate regression.
foreach($probe in @($journal.ToArray()|Where-Object {$_.operation -ceq 'probe'})) {
  $probe.observation.lineage=$probe.observation.lineage.Clone()
  $probe.observation.lineage.launchTokenId=if($probe.role -ceq 'broker'){'0000000000000001'}else{'0000000000000002'}
}

foreach ($role in @('broker','legacy')) {
  $sid=if($role -ceq 'broker'){'S-1-5-21-1'}else{'S-1-5-21-2'}
  $entry=New-TestTokenRecord $role $sid
  $entry.closed=$false
  $record=@{source='INJECTED';role=$role;accountSid=$sid;launchTokenId=$entry.first.tokenId;launchAuthenticationId=$entry.first.authenticationId;launchModifiedId=$entry.first.modifiedId;postTokenId=$entry.first.tokenId;postAuthenticationId=$entry.first.authenticationId;postModifiedId=$entry.first.modifiedId;pid=123;createdAt='2026-01-01T00:00:00Z';contained=$true;first=@{pid=123;createdAt='2026-01-01T00:00:00Z';sid='S-1-5-21-9';primary=$true;admin=$false;elevated=$false;standard=$true;tokenId='0000000000000021';authenticationId='0000000000000010';modifiedId='0000000000000022'};second=@{pid=123;createdAt='2026-01-01T00:00:00Z';sid='S-1-5-21-9';primary=$true;admin=$false;elevated=$false;standard=$true;tokenId='0000000000000021';authenticationId='0000000000000010';modifiedId='0000000000000022'}}
  $record.launchAttempted=$true;$record.launchResult='CREATED';$record.inspectionAttempted=$true;$record.inspectionResult='OBSERVED';$record.cleanup='CHILD_UNCONFIRMED'
  $entry.processObservation=$record
  $v=New-PhaseAManagerVerdictInput ('1'*40) '123'
  Add-PhaseAPrimaryTokenEvidence $v @($entry) @() 'SIMULATED_PASS'
  if($v.cases[$role+'PrimaryToken'].state -cne 'FAIL'){throw 'PROCESS_VIOLATION_LOST_AFTER_ABORT'}
  $verify=New-PhaseAEvidenceVerifier @() $v '1' $true $true 'SIMULATED_PASS' @($entry)
  if(-not (& $verify ($role+'PrimaryToken') $v.cases[$role+'PrimaryToken'] $v)){throw 'PROCESS_VIOLATION_PROOF_NOT_RECHECKED'}
  foreach($problem in @('wrongRole','wrongAccount','wrongLaunch','modifiedSource','wrongPid','wrongCreation','contradiction','missingSecond','missingLaunch','notCreated','failedQuery','uncontained','relabeled')) {
    $bad=$record.Clone();$bad.first=$record.first.Clone();$bad.second=$record.second.Clone()
    switch($problem){
      'wrongRole' {$bad.role='other'} 'wrongAccount' {$bad.accountSid='S-1-5-21-7'}
      'wrongLaunch' {$bad.launchTokenId='00000000000000ff'} 'modifiedSource' {$bad.postModifiedId='00000000000000ff'}
      'wrongPid' {$bad.pid=999} 'wrongCreation' {$bad.createdAt='2025-01-01T00:00:00Z'}
      'contradiction' {$bad.second.sid=$sid} 'missingSecond' {$bad.Remove('second')}
      'missingLaunch' {$bad.Remove('launchTokenId')} 'notCreated' {$bad.launchResult='CREATE_FAILED'}
      'failedQuery' {$bad.inspectionResult='PROCESS_TOKEN_QUERY_FAILED'} 'uncontained' {$bad.contained=$false} 'relabeled' {$bad.source='LIVE'}
    }
    $entry.processObservation=$bad;$fresh=New-PhaseAManagerVerdictInput ('1'*40) '123';Add-PhaseAPrimaryTokenEvidence $fresh @($entry) @() 'SIMULATED_PASS'
    if($fresh.cases[$role+'PrimaryToken'].state -cne 'NOT_RUN'){throw ('INSUFFICIENT_PROCESS_EVIDENCE_ACCEPTED_'+$problem)}
    if(& $verify ($role+'PrimaryToken') $v.cases[$role+'PrimaryToken'] $v){throw ('TAMPERED_PROCESS_PROOF_ACCEPTED_'+$problem)}
  }
  $entry.processObservation=$record
  $live=New-PhaseAManagerVerdictInput ('1'*40) '123';Add-PhaseAPrimaryTokenEvidence $live @($entry) @() 'LIVE_OBSERVED'
  if($live.cases[$role+'PrimaryToken'].state -cne 'NOT_RUN'){throw 'SIMULATED_PROCESS_EVIDENCE_PROMOTED'}
  $good=$record.Clone();$good.first=$record.first.Clone();$good.second=$record.second.Clone();$good.first.sid=$sid;$good.second.sid=$sid
  $entry.processObservation=$good
  if((Get-PhaseAProcessTokenObservation $entry $good 'INJECTED') -cne 'PASS'){throw 'PROCESS_SUCCESS_NOT_CORROBORATED'}
  $good.second.pid=456
  if((Get-PhaseAProcessTokenObservation $entry $good 'INJECTED') -cne 'UNVERIFIED'){throw 'CONTRADICTORY_SUCCESS_ACCEPTED'}
  $good.second.pid=123;$good.first.tokenId='0000000000000030';$good.second.tokenId='0000000000000030';$good.first.modifiedId='0000000000000020';$good.second.modifiedId='0000000000000020';$good.cleanup='PROCESS_CONFIRMED'
  $entry.closed=$true;$entry.processObservations=New-Object 'System.Collections.Generic.List[object]';$entry.processObservations.Add($good)
  $success=New-PhaseAManagerVerdictInput ('1'*40) '123';Add-PhaseAPrimaryTokenEvidence $success @($entry) $journal.ToArray() 'SIMULATED_PASS'
  if($success.cases[$role+'PrimaryToken'].state -cne 'PASS'){throw 'PROCESS_SUCCESS_NOT_MAPPED'}
  $successVerifier=New-PhaseAEvidenceVerifier $journal.ToArray() $success '1' $true $true 'SIMULATED_PASS' @($entry)
  if(-not (& $successVerifier ($role+'PrimaryToken') $success.cases[$role+'PrimaryToken'] $success)){throw 'PROCESS_SUCCESS_NOT_RECHECKED'}
  $good.cleanup='RESOURCE_FAILED'
  if(& $successVerifier ($role+'PrimaryToken') $success.cases[$role+'PrimaryToken'] $success){throw 'PROCESS_CLEANUP_FAILURE_ACCEPTED'}
  $entry.closed=$false;$entry.closeResult='FAILED';$entry.processObservations=@($record,@{source='INJECTED';launchResult='CREATE_FAILED'})
  $retained=New-PhaseAManagerVerdictInput ('1'*40) '123';Add-PhaseAPrimaryTokenEvidence $retained @($entry) @() 'SIMULATED_PASS'
  if($retained.cases[$role+'PrimaryToken'].state -cne 'FAIL'){throw 'EARLIER_PROCESS_VIOLATION_LOST'}
  $null=$entry.Remove('processObservations');$entry.closeResult='CLOSED'
  foreach($field in @('primary','admin','elevated','standard')) {
    $bad=$record.Clone();$bad.first=$record.first.Clone();$bad.second=$record.second.Clone();$bad.first.sid=$sid;$bad.second.sid=$sid
    $value=$field -cin @('admin','elevated');$bad.first[$field]=$value;$bad.second[$field]=$value
    $entry.processObservation=$bad;$fresh=New-PhaseAManagerVerdictInput ('1'*40) '123';Add-PhaseAPrimaryTokenEvidence $fresh @($entry) @() 'SIMULATED_PASS'
    if($fresh.cases[$role+'PrimaryToken'].state -cne 'FAIL'){throw ('OBSERVED_PROCESS_PROPERTY_NOT_RETAINED_'+$field)}
  }
}
Write-Output 'PASS independently observed child-token violations retained and 13 malformed cases rejected for both roles'
$template=[pscustomobject]@{pid=123;createdAt='2026-01-01T00:00:00Z';sid='S-1-5-21-1';primary=$true;admin=$false;elevated=$false;standard=$true;tokenId='0000000000000030';authenticationId='0000000000000010';modifiedId='0000000000000020'}
foreach($kind in @('PROCESS_TOKEN_OPEN_FAILED','PROCESS_TOKEN_OPEN_DENIED','PROCESS_TOKEN_QUERY_FAILED','TOKEN_INSPECTION_CLOSE_FAILED')) {
  $r=@{inspectionAttempted=$false;inspectionResult='NOT_ATTEMPTED'};$owner=@{launchFailure='NONE'}
  try{$null=Invoke-PhaseAProcessTokenPair $null $r $owner {param($p) throw $kind}.GetNewClosure();throw 'QUERY_FAILURE_ACCEPTED'}catch{$caught=$_.Exception.GetBaseException().Message}
  $expected=if($kind -ceq 'TOKEN_INSPECTION_CLOSE_FAILED'){'STAGE2_CLEANUP_FAILED'}else{'STAGE2_OBSERVATION_REJECTED'}
  $result=if($kind -ceq 'TOKEN_INSPECTION_CLOSE_FAILED'){'TOKEN_CLOSE_FAILED'}else{$kind}
  if($caught -cne $expected -or $r.inspectionResult -cne $result -or -not $r.inspectionAttempted){throw ('QUERY_FAILURE_NOT_RETAINED_'+$kind)}
  if($kind -ceq 'TOKEN_INSPECTION_CLOSE_FAILED' -and (-not $r.ContainsKey('cleanup') -or $r.cleanup -cne 'RESOURCE_FAILED')){throw 'TOKEN_QUERY_CLEANUP_RECORDED_AS_CONFIRMED'}
}
$r=@{inspectionAttempted=$false;inspectionResult='NOT_ATTEMPTED'};$owner=@{launchFailure='NONE'};$script:pairCalls=0
try{$null=Invoke-PhaseAProcessTokenPair $null $r $owner {param($p) $script:pairCalls++;if($script:pairCalls -eq 1){return $template};throw 'PROCESS_TOKEN_QUERY_FAILED'}.GetNewClosure()}catch{}
if(-not $r.ContainsKey('first') -or $r.ContainsKey('second') -or $r.inspectionResult -cne 'PROCESS_TOKEN_QUERY_FAILED'){throw 'FIRST_OBSERVATION_LOST_AFTER_SECOND_QUERY_FAILURE'}
Write-Output 'PASS injected producer retains native query failures and partial observations'
$self=Get-Process -Id $PID;$selfRecord=@{inspectionAttempted=$false;inspectionResult='NOT_ATTEMPTED'};$selfOwner=@{launchFailure='NONE'}
try {
  $selfObserved=Invoke-PhaseAProcessTokenPair $self $selfRecord $selfOwner {param($p) Get-PhaseAProcessToken $p $true}
  if($selfRecord.inspectionResult -cne 'OBSERVED' -or $selfObserved.pid -ne $PID -or $selfRecord.first.pid -ne $PID -or $selfRecord.second.pid -ne $PID -or $selfRecord.first.tokenId -cne $selfRecord.second.tokenId){throw 'SELF_TOKEN_PAIR_NOT_CORROBORATED'}
} finally {$self.Dispose()}
Write-Output 'PASS actual same-identity double process-token observation'
$launchRecord=@{launchAttempted=$false;launchResult='NOT_ATTEMPTED'}
try{$null=Invoke-PhaseABoundProcessLaunch $launchRecord {throw 'synthetic launch failure'};throw 'LAUNCH_FAILURE_ACCEPTED'}catch{$launchError=$_.Exception.GetBaseException().Message}
if($launchError -cne 'synthetic launch failure' -or -not $launchRecord.launchAttempted -or $launchRecord.launchResult -cne 'CREATE_FAILED'){throw 'LAUNCH_FAILURE_NOT_RETAINED'}
Write-Output 'PASS process creation failure retained without invented child observation'
