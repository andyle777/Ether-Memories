$ErrorActionPreference='Stop'
. "$PSScriptRoot/PhaseA.Tests.ps1"
function New-TestTokenRecord([string]$role,[string]$sid) {
 $id=if($role -ceq 'broker'){'0000000000000001'}else{'0000000000000002'}
 return @{role=$role;accountSid=$sid;source='INJECTED';first=@{sid=$sid;primary=$true;admin=$false;elevated=$false;standard=$true;tokenId=$id;authenticationId='0000000000000010';modifiedId='0000000000000020';statisticsPrimary=$true};second=@{sid=$sid;primary=$true;admin=$false;elevated=$false;standard=$true;handleOpen=$true;tokenId=$id;authenticationId='0000000000000010';modifiedId='0000000000000020';statisticsPrimary=$true};closed=$true;inspection='OBSERVED';closeResult='CLOSED'}
}
foreach($role in @('broker','legacy')) {
 $control=$role+'PrimaryToken';$idx=if($role -ceq 'broker'){0}else{1}
 foreach($field in @('sid','primary','admin','elevated','standard')) {
  $items=@((New-TestTokenRecord 'broker' 'S-1-5-21-1'),(New-TestTokenRecord 'legacy' 'S-1-5-21-2'))
  $value=switch($field){'sid' {'S-1-5-21-9'} 'primary' {$false} 'admin' {$true} 'elevated' {$true} 'standard' {$false}}
  $items[$idx].first[$field]=$value;$items[$idx].second[$field]=$value;if($field -ceq 'primary'){$items[$idx].first.statisticsPrimary=$value;$items[$idx].second.statisticsPrimary=$value}
  $v=New-PhaseAManagerVerdictInput ('1'*40) '123';Add-PhaseAPrimaryTokenEvidence $v $items @() 'SIMULATED_PASS'
  if($v.cases[$control].state -cne 'FAIL'){throw "TOKEN_VIOLATION_NOT_RETAINED_${role}_${field}"}
 }
 foreach($problem in @('inspection','close','contradiction','source','malformedClose')) {
  $items=@((New-TestTokenRecord 'broker' 'S-1-5-21-1'),(New-TestTokenRecord 'legacy' 'S-1-5-21-2'))
  switch($problem){'inspection' {$items[$idx].inspection='FAILED';$items[$idx].second=$null} 'close' {$items[$idx].closed=$false;$items[$idx].closeResult='FAILED'} 'contradiction' {$items[$idx].second.primary=$false} 'source' {$items[$idx].source='LIVE'} 'malformedClose' {$items[$idx].closed='true'}}
  $v=New-PhaseAManagerVerdictInput ('1'*40) '123';Add-PhaseAPrimaryTokenEvidence $v $items $journal.ToArray() 'SIMULATED_PASS'
  if($v.cases[$control].state -cne 'NOT_RUN'){throw "TOKEN_INSUFFICIENT_EVIDENCE_ACCEPTED_${role}_${problem}"}
 }
}
Write-Output 'PASS token violation, ambiguity and evidence-source controls'
foreach($role in @('broker','legacy')) {
 $sid=if($role -ceq 'broker'){'S-1-5-21-1'}else{'S-1-5-21-2'};$log=New-Object 'System.Collections.Generic.List[object]'
 $b=@{Authenticate={param($a) @{sid=$a.sid;primary=$false;admin=$false;elevated=$false;standard=$true;tokenId='0000000000000001';authenticationId='0000000000000010';modifiedId='0000000000000020';statisticsPrimary=$false}};Close={param($token) throw 'synthetic close failure'}}
 $wrapped=New-PhaseATokenJournalBackend $b $log {param($t) @{sid=$t.sid;primary=$t.primary;admin=$t.admin;elevated=$t.elevated;standard=$t.standard;handleOpen=$true;tokenId=$t.tokenId;authenticationId=$t.authenticationId;modifiedId=$t.modifiedId;statisticsPrimary=$t.statisticsPrimary}}
 $token=& $wrapped.Authenticate @{role=$role;sid=$sid};try{& $wrapped.Close $token}catch{}
 if($log.Count -ne 1 -or $log[0].closeResult -cne 'FAILED' -or $log[0].closed){throw 'TOKEN_CLOSE_FAILURE_NOT_RETAINED'}
 $v=New-PhaseAManagerVerdictInput ('1'*40) '123';Add-PhaseAPrimaryTokenEvidence $v $log.ToArray() @() 'SIMULATED_PASS';$name=$role+'PrimaryToken'
 if($v.cases[$name].state -cne 'FAIL'){throw 'TOKEN_VIOLATION_LOST_AFTER_CLOSE_FAILURE'}
 $verify=New-PhaseAEvidenceVerifier @() $v '1' $true $true 'SIMULATED_PASS' $log.ToArray()
 if(-not (& $verify $name $v.cases[$name] $v)){throw 'TOKEN_FAILURE_PROOF_NOT_RECHECKED'}
 $log[0].second.primary=$true;if(& $verify $name $v.cases[$name] $v){throw 'TAMPERED_TOKEN_FAILURE_ACCEPTED'}
}
Write-Output 'PASS retained close failure and rechecked prior token violation'
$items=@((New-TestTokenRecord 'broker' 'S-1-5-21-1'),(New-TestTokenRecord 'legacy' 'S-1-5-21-2'))
$valid=New-PhaseAManagerVerdictInput ('1'*40) '123';Add-PhaseAPrimaryTokenEvidence $valid $items $journal.ToArray() 'SIMULATED_PASS';$check=New-PhaseAEvidenceVerifier $journal.ToArray() $valid '1' $true $true 'SIMULATED_PASS' $items
foreach($name in @('brokerPrimaryToken','legacyPrimaryToken')){if($valid.cases[$name].state -cne 'PASS' -or -not (& $check $name $valid.cases[$name] $valid)){throw 'TOKEN_SUCCESS_PROOF_NOT_RECHECKED'}}
$v=New-PhaseAManagerVerdictInput ('1'*40) '123';Add-PhaseAPrimaryTokenEvidence $v $items $journal.ToArray() 'LIVE_OBSERVED'
if($v.cases.brokerPrimaryToken.state -cne 'NOT_RUN' -or $v.cases.legacyPrimaryToken.state -cne 'NOT_RUN'){throw 'INJECTED_SOURCE_RELABELLED_LIVE'}
$actorCopy=Copy-ActorJournal $journal.ToArray();$actorCopy[0].tokenSid='S-1-5-21-9'
$v=New-PhaseAManagerVerdictInput ('1'*40) '123';Add-PhaseAPrimaryTokenEvidence $v $items $actorCopy 'SIMULATED_PASS'
if($v.cases.brokerPrimaryToken.state -cne 'NOT_RUN'){throw 'WRONG_ACTOR_TOKEN_BINDING_ACCEPTED'}
$bad=@{Authenticate={param($a) @{sid=$a.sid;primary=$true;admin=$false;elevated=$false;standard=$true}};Close={param($t)}};$j=New-Object 'System.Collections.Generic.List[object]'
$w=New-PhaseATokenJournalBackend $bad $j {param($t) throw 'synthetic failure'};try{& $w.Authenticate @{role='broker';sid='S-1-5-21-1'}}catch{}
if($j.Count -ne 1 -or $j[0].inspection -cne 'FAILED' -or $j[0].failure -cne 'INSPECTION_FAILED' -or -not $j[0].closed){throw 'FAILED_INSPECTION_NOT_RETAINED'}
Write-Output 'PASS injected provenance, wrong actor binding and failed inspection controls'
$items=@((New-TestTokenRecord 'broker' 'S-1-5-21-1'),(New-TestTokenRecord 'legacy' 'S-1-5-21-2'));$items[0].first.sid='malformed';$items[0].second.sid='malformed'
$v=New-PhaseAManagerVerdictInput ('1'*40) '123';Add-PhaseAPrimaryTokenEvidence $v $items @() 'SIMULATED_PASS';if($v.cases.brokerPrimaryToken.state -cne 'NOT_RUN'){throw 'MALFORMED_SID_ACCEPTED'}
$j=New-Object 'System.Collections.Generic.List[object]';$w=New-PhaseATokenJournalBackend $bad $j {param($t) @{sid=$t.sid;primary=$true;admin=$false;elevated=$false;standard=$true;handleOpen=$true;secret='do-not-retain'}}
$token=& $w.Authenticate @{role='broker';sid='S-1-5-21-1'};& $w.Close $token;if($j[0].second.ContainsKey('secret')){throw 'UNBOUNDED_INSPECTION_RETAINED'}
Write-Output 'PASS malformed SID and bounded observation controls'
$relabel=@((New-TestTokenRecord 'broker' 'S-1-5-21-1'),(New-TestTokenRecord 'legacy' 'S-1-5-21-2'));$relabel[0].source='LIVE';$relabel[1].source='LIVE'
$forged=New-PhaseAManagerVerdictInput ('1'*40) '123';Add-PhaseAPrimaryTokenEvidence $forged $relabel $journal.ToArray() 'LIVE_OBSERVED'
if($forged.cases.brokerPrimaryToken.state -ceq 'PASS' -or $forged.cases.legacyPrimaryToken.state -ceq 'PASS'){throw 'RELABELLED_INJECTED_RECORDS_ACCEPTED_AS_LIVE'}
$rejected=$false;try{$null=New-PhaseATokenJournalBackend $bad (New-Object 'System.Collections.Generic.List[object]') {param($t) @{}} 'LIVE'}catch{$rejected=$_.Exception.GetBaseException().Message -ceq 'TOKEN_SOURCE_REJECTED'};if(-not $rejected){throw 'INJECTED_BACKEND_ACCEPTED_AS_LIVE'}
Write-Output 'PASS manager-owned live origin binding'
. "$PSScriptRoot/PhaseA.Accounts.ps1"
$live=New-PhaseAWindowsAccountBackend;$live.Authenticate={param($a) @{sid=$a.sid;primary=$true;admin=$false;elevated=$false;standard=$true}}
$rejected=$false;try{$null=New-PhaseATokenJournalBackend $live (New-Object 'System.Collections.Generic.List[object]') {param($t) @{}} 'LIVE'}catch{$rejected=$_.Exception.GetBaseException().Message -ceq 'TOKEN_SOURCE_REJECTED'};if(-not $rejected){throw 'MODIFIED_LIVE_BACKEND_ACCEPTED'}
Write-Output 'PASS substituted live backend rejected'
$live=New-PhaseAWindowsAccountBackend;$rejected=$false;try{$null=New-PhaseATokenJournalBackend $live (New-Object 'System.Collections.Generic.List[object]') {param($t) @{}} 'LIVE'}catch{$rejected=$_.Exception.GetBaseException().Message -ceq 'TOKEN_SOURCE_REJECTED'};if(-not $rejected){throw 'SUBSTITUTED_LIVE_INSPECTION_ACCEPTED'}
$null=New-PhaseATokenJournalBackend $live (New-Object 'System.Collections.Generic.List[object]') $live.InspectToken 'LIVE'
Write-Output 'PASS substituted live inspection rejected'
$items=@((New-TestTokenRecord 'broker' 'S-1-5-21-1'),(New-TestTokenRecord 'legacy' 'S-1-5-21-2'));$items[0].first.tokenId='000000000000000a';$items[0].second.tokenId='000000000000000a'
$different=Copy-ActorJournal $journal.ToArray();$different[0].observation.lineage.launchTokenId='000000000000000b'
$v=New-PhaseAManagerVerdictInput ('1'*40) '123';Add-PhaseAPrimaryTokenEvidence $v $items $different 'SIMULATED_PASS';if($v.cases.brokerPrimaryToken.state -ceq 'PASS'){throw 'SAME_SID_WRONG_TOKEN_BINDING_ACCEPTED'}
Write-Output 'PASS same-SID substituted launch token rejected'
$records=New-Object 'System.Collections.Generic.List[object]';$b=@{Authenticate={param($a) @{sid=$a.sid;primary=$true;admin=$false;elevated=$false;standard=$true}};Close={param($t)}}
$w=New-PhaseATokenJournalBackend $b $records {param($t) @{sid=$t.sid;primary=$true;admin=$false;elevated=$false;standard=$true;handleOpen=$true}}
$t1=& $w.Authenticate @{role='broker';sid='S-1-5-21-1'};$t2=& $w.Authenticate @{role='legacy';sid='S-1-5-21-1'};& $w.Close $t1
if(-not $records[0].closed -or $records[1].closed){throw 'SAME_SID_WRONG_JOURNAL_ENTRY_CLOSED'};& $w.Close $t2;if(-not $records[1].closed){throw 'SECOND_TOKEN_NOT_CLOSED'}
Write-Output 'PASS same-SID close ownership by object reference'
. "$PSScriptRoot/PhaseA.Stage2.ps1"
$owner=New-TestTokenRecord 'broker' 'S-1-5-21-1';$account=@{role='broker';sid='S-1-5-21-1'};$owner.closed=$false
$stats=[pscustomobject]@{tokenId=$owner.first.tokenId;authenticationId=$owner.first.authenticationId;modifiedId=$owner.first.modifiedId;primary=$true}
if(-not (Test-PhaseAOwnedLaunchToken $owner $account $stats)){throw 'CORRECT_PRELAUNCH_TOKEN_REJECTED'}
foreach($property in @('tokenId','authenticationId','modifiedId','primary')){$wrong=$stats.PSObject.Copy();if($property -ceq 'primary'){$wrong.primary=$false}else{$wrong.$property='00000000000000ff'};if(Test-PhaseAOwnedLaunchToken $owner $account $wrong){throw ('PRELAUNCH_MISMATCH_ACCEPTED_'+$property)}}
$wrongAccount=@{role='legacy';sid='S-1-5-21-1'};if(Test-PhaseAOwnedLaunchToken $owner $wrongAccount $stats){throw 'SAME_SID_WRONG_ROLE_ACCEPTED'}
if(Test-PhaseAOwnedLaunchToken $owner $account $null){throw 'MISSING_STATISTICS_ACCEPTED'}
$nativeFailed=$false;try{$null=[EtherPhaseANative]::InspectTokenHandle([IntPtr]::Zero)}catch{$nativeFailed=$true};if(-not $nativeFailed){throw 'FAILED_NATIVE_STATISTICS_QUERY_ACCEPTED'}
Write-Output 'PASS prelaunch token, modification, role and missing-statistics controls'
$rejected=$false;try{$null=New-PhaseAActorJournalBackend @{Run={param($a,$t) @{}}} (New-Object 'System.Collections.Generic.List[object]') 'LIVE'}catch{$rejected=$_.Exception.GetBaseException().Message -ceq 'ACTOR_SOURCE_REJECTED'};if(-not $rejected){throw 'INJECTED_ACTOR_BACKEND_ACCEPTED_AS_LIVE'}
Write-Output 'PASS injected actor cannot be classified as live'
foreach($problem in @('wrongLaunch','wrongSession','wrongType','wrongPid','wrongCreation','missing','relabeled')){
 $badActors=Copy-ActorJournal $journal.ToArray();$badActors[0].observation.lineage=$badActors[0].observation.lineage.Clone();$l=$badActors[0].observation.lineage
 switch($problem){'wrongLaunch' {$l.launchTokenId='00000000000000ff'} 'wrongSession' {$l.processAuthenticationId='00000000000000ff'} 'wrongType' {$l.processPrimary=$false} 'wrongPid' {$l.pid=999} 'wrongCreation' {$l.createdAt='2020-01-01T00:00:00Z'} 'missing' {$badActors[0].observation.Remove('lineage')} 'relabeled' {$l.source='LIVE'}}
 $items=@((New-TestTokenRecord 'broker' 'S-1-5-21-1'),(New-TestTokenRecord 'legacy' 'S-1-5-21-2'));$v=New-PhaseAManagerVerdictInput ('1'*40) '123';Add-PhaseAPrimaryTokenEvidence $v $items $badActors 'SIMULATED_PASS'
 if($v.cases.brokerPrimaryToken.state -cne 'NOT_RUN'){throw ('INVALID_PROCESS_LINEAGE_ACCEPTED_'+$problem)}
}
Write-Output 'PASS mismatched or missing process lineage controls'
$realActor=New-PhaseAStage2Backend;$null=New-PhaseAActorJournalBackend $realActor (New-Object 'System.Collections.Generic.List[object]') 'LIVE'
$realActor.Run={param($a,$t) @{}};$rejected=$false;try{$null=New-PhaseAActorJournalBackend $realActor (New-Object 'System.Collections.Generic.List[object]') 'LIVE'}catch{$rejected=$_.Exception.GetBaseException().Message -ceq 'ACTOR_SOURCE_REJECTED'};if(-not $rejected){throw 'SUBSTITUTED_ACTOR_BACKEND_ACCEPTED'}
Write-Output 'PASS real actor origin and substituted callback controls'
