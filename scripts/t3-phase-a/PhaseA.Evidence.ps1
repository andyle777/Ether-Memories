function Test-PhaseAReadWitnessCleanup($Record,[string]$Source) {
 if($Record -isnot [hashtable]){return $false}
 # LIVE witness provenance and retained lifecycle correlation are not yet connected.
 # Until the producer-to-verifier bridge exists, no relabeled object is live proof.
 if($Source -ceq 'LIVE'){return $false}
 $parsed=[DateTimeOffset]::MinValue
 if($Record.ContainsKey('execution') -and $Record.execution -ceq 'PROCESS'){return ($Record.ContainsKey('processVerified') -and $Record.processVerified -is [bool] -and $Record.processVerified -and $Record.ContainsKey('terminated') -and $Record.terminated -is [bool] -and $Record.terminated -and $Record.ContainsKey('pid') -and $Record.pid -is [int] -and $Record.pid -gt 0 -and $Record.ContainsKey('pipeClientPid') -and $Record.pipeClientPid -is [int] -and $Record.pipeClientPid -eq $Record.pid -and $Record.ContainsKey('createdAt') -and $Record.createdAt -is [string] -and [DateTimeOffset]::TryParse($Record.createdAt,[ref]$parsed) -and $Record.ContainsKey('nonce') -and $Record.nonce -cmatch '^[0-9a-f]{32}$')}
 if($Source -ceq 'LIVE'){return $false}
 return ($Record.ContainsKey('reverted') -and $Record.reverted -is [bool] -and $Record.reverted)
}
Set-StrictMode -Version Latest
if(-not (Get-Variable -Name PhaseATrustedAccountBackends -Scope Script -ErrorAction SilentlyContinue)){$script:PhaseATrustedAccountBackends=New-Object 'System.Collections.Generic.Dictionary[object,object]'}
if(-not (Get-Variable -Name PhaseATrustedTokenRecords -Scope Script -ErrorAction SilentlyContinue)){$script:PhaseATrustedTokenRecords=New-Object 'System.Collections.Generic.HashSet[object]'}
if(-not (Get-Variable -Name PhaseATokenOwners -Scope Script -ErrorAction SilentlyContinue)){$script:PhaseATokenOwners=New-Object 'System.Collections.Generic.Dictionary[object,object]'}
if(-not (Get-Variable -Name PhaseATrustedActorBackends -Scope Script -ErrorAction SilentlyContinue)){$script:PhaseATrustedActorBackends=New-Object 'System.Collections.Generic.Dictionary[object,object]'}
if(-not (Get-Variable -Name PhaseATrustedActorRecords -Scope Script -ErrorAction SilentlyContinue)){$script:PhaseATrustedActorRecords=New-Object 'System.Collections.Generic.HashSet[object]'}
if(-not (Get-Variable -Name PhaseATrustedProcessTokenRecords -Scope Script -ErrorAction SilentlyContinue)){$script:PhaseATrustedProcessTokenRecords=New-Object 'System.Collections.Generic.HashSet[object]'}
function Get-PhaseAProcessTokenObservation($item,$r,[string]$source) {
  try {
    if($r -isnot [hashtable] -or $r.source -cne $source -or $r.role -cne $item.role -or $r.accountSid -cne $item.accountSid){return 'UNVERIFIED'}
    if($source -ceq 'LIVE' -and -not $script:PhaseATrustedProcessTokenRecords.Contains($r)){return 'UNVERIFIED'}
    if($r.launchAttempted -isnot [bool] -or -not $r.launchAttempted -or $r.launchResult -cne 'CREATED' -or $r.inspectionAttempted -isnot [bool] -or -not $r.inspectionAttempted -or $r.inspectionResult -cne 'OBSERVED'){return 'UNVERIFIED'}
    if($r.contained -isnot [bool] -or -not $r.contained -or $r.pid -isnot [int] -or $r.pid -le 0){return 'UNVERIFIED'}
    $t=[DateTimeOffset]::MinValue;if(-not [DateTimeOffset]::TryParse($r.createdAt,[ref]$t)){return 'UNVERIFIED'}
    foreach($pair in @(@('launchTokenId','tokenId'),@('launchAuthenticationId','authenticationId'),@('launchModifiedId','modifiedId'),@('postTokenId','tokenId'),@('postAuthenticationId','authenticationId'),@('postModifiedId','modifiedId'))){if($r[$pair[0]] -cne $item.first[$pair[1]]){return 'UNVERIFIED'}}
    $a=$r.first;$b=$r.second;if($a -isnot [hashtable] -or $b -isnot [hashtable]){return 'UNVERIFIED'}
    foreach($k in @('pid','createdAt','sid','primary','admin','elevated','standard','tokenId','authenticationId','modifiedId')){if(-not $a.ContainsKey($k) -or -not $b.ContainsKey($k) -or $a[$k] -cne $b[$k]){return 'UNVERIFIED'}}
    if($a.pid -ne $r.pid -or $a.createdAt -cne $r.createdAt){return 'UNVERIFIED'}
    foreach($k in @('primary','admin','elevated','standard')){if($a[$k] -isnot [bool]){return 'UNVERIFIED'}}
    foreach($k in @('tokenId','authenticationId','modifiedId')){if($a[$k] -isnot [string] -or $a[$k] -cnotmatch '^[0-9a-f]{16}$'){return 'UNVERIFIED'}}
    $observedSid=New-Object Security.Principal.SecurityIdentifier($a.sid);if($observedSid.Value -cne $a.sid){return 'UNVERIFIED'}
    if($a.sid -cne $item.accountSid -or -not $a.primary -or $a.admin -or $a.elevated -or -not $a.standard){return 'FAIL'}
    if($a.authenticationId -cne $item.first.authenticationId){return 'UNVERIFIED'}
    return 'PASS'
  } catch {return 'UNVERIFIED'}
}
# A journal item is recorded only after the real Stage 2 backend has returned.
# Raw identity data remains in manager memory and is not written to the report.
function Add-PhaseAActorEvidence($VerdictInput,$Journal,[string]$EvidenceClass) {
  if ($EvidenceClass -cnotin @('LIVE_OBSERVED','SIMULATED_PASS') -or $VerdictInput -isnot [Collections.IDictionary] -or $VerdictInput.cases -isnot [Collections.IDictionary]) { return }
  # Actor journal operation results are not independent LIVE observations.
  if ($EvidenceClass -ceq 'LIVE_OBSERVED') { return }
  $events=@($Journal)
  if ($events.Count -notin @(9,11)) { return }
  $sequence=@(@('broker','probe','allowed'),@('legacy','probe','allowed'),@('broker','Read','allowed'),@('broker','Create','allowed'),@('broker','Read','allowed'),@('legacy','Read','denied'),@('legacy','Overwrite','denied'),@('legacy','Create','denied'))
  if ($events.Count -eq 11) { $sequence+=@(@('legacy','Rename','denied'),@('legacy','Delete','denied')) }
  $sequence+=,@('legacy','Read','allowed')
  $roleSids=@{}; $canonical=New-Object 'System.Collections.Generic.List[object]'
  for ($i=0; $i -lt $sequence.Count; $i++) {
    $item=$events[$i]; $expected=$sequence[$i]
    if ($item -isnot [hashtable] -or $item.Count -ne 5) { return }
    foreach ($key in @('role','operation','accountSid','tokenSid','observation')) { if (-not $item.ContainsKey($key)) { return } }
    if ($item.role -cne $expected[0] -or $item.operation -cne $expected[1] -or $item.accountSid -isnot [string] -or
        [string]::IsNullOrWhiteSpace($item.accountSid) -or $item.tokenSid -cne $item.accountSid -or $item.observation -isnot [hashtable]) { return }
    if ($roleSids.ContainsKey($item.role) -and $roleSids[$item.role] -cne $item.accountSid) { return }; $roleSids[$item.role]=$item.accountSid
    $o=$item.observation
    if (-not $o.ContainsKey('expectedSid') -or $o.expectedSid -cne $item.accountSid -or
        -not $o.ContainsKey('contained') -or $o.contained -isnot [bool] -or -not $o.contained -or
        -not $o.ContainsKey('terminated') -or $o.terminated -isnot [bool] -or -not $o.terminated -or
        -not (Test-ActorObservation $o $item.role $expected[2])) { return }
    $canonical.Add([ordered]@{role=$item.role;operation=$item.operation;accountSid=$item.accountSid;tokenSid=$item.tokenSid;
      expectedSid=$o.expectedSid;observedSid=$o.observedSid;reportedSid=$o.reportedSid;expectedPid=$o.expectedPid;reportedPid=$o.reportedPid;
      createdAt=$o.createdAt;observedCreatedAt=$o.observedCreatedAt;expectedNonce=$o.expectedNonce;reportedNonce=$o.reportedNonce;
      tokenNonAdmin=$o.tokenNonAdmin;tokenObserved=$o.tokenObserved;outcome=$o.outcome;exitCode=$o.exitCode;contained=$o.contained;terminated=$o.terminated})
  }
  if (-not (Test-DistinctActorSids $roleSids.broker $roleSids.legacy)) { return }
  $controls=@('identityDistinct','brokerNonAdmin','legacyNonAdmin','brokerActorBinding','legacyActorBinding','actorPidBinding','actorCreationTimeBinding','actorSidBinding')
  foreach ($key in $controls) { if (-not $VerdictInput.cases.Contains($key) -or $VerdictInput.cases[$key].state -cne 'NOT_RUN') { return } }
  $json=ConvertTo-Json -InputObject @($canonical.ToArray()) -Compress -Depth 5
  $sha=[Security.Cryptography.SHA256]::Create()
  try {
    foreach ($key in $controls) {
      $bytes=[Text.Encoding]::UTF8.GetBytes($key+"`n"+$json)
      $proof=[BitConverter]::ToString($sha.ComputeHash($bytes)).Replace('-','').ToLowerInvariant()
      $VerdictInput.cases[$key]=@{state='PASS';evidence=$EvidenceClass;reason='NONE';proof=$proof}
    }
  } finally { $sha.Dispose() }
}
function New-PhaseAActorJournalBackend([hashtable]$Backend,[Collections.Generic.List[object]]$Journal,[ValidateSet('LIVE','INJECTED')][string]$Source='INJECTED') {
  if (-not $Backend.ContainsKey('Run') -or $Backend.Run -isnot [scriptblock] -or $null -eq $Journal) { throw 'ACTOR_JOURNAL_INVALID' }
  if($Source -ceq 'LIVE' -and (-not $script:PhaseATrustedActorBackends.ContainsKey($Backend) -or -not [object]::ReferenceEquals($script:PhaseATrustedActorBackends[$Backend],$Backend.Run))){throw 'ACTOR_SOURCE_REJECTED'}
  $run=$Backend.Run
  $wrapped={
    param($account,$token,$operation,$target)
    $value=& $run $account $token $operation $target
    if ($value -is [hashtable]) {
      $kind=if ([string]::IsNullOrEmpty($operation)) {'probe'} else {$operation}
      $item=@{role=$account.role;operation=$kind;accountSid=$account.sid;tokenSid=$token.sid;observation=$value};$Journal.Add($item)
      if($Source -ceq 'LIVE'){$null=$script:PhaseATrustedActorRecords.Add($item)}
    }
    return $value
  }.GetNewClosure()
  return @{Run=$wrapped}
}
function New-PhaseAEvidenceVerifier($Journal,$BoundRecord,[string]$RunAttempt,[bool]$ProvenanceVerified,[bool]$LiveAuthorized,[string]$EvidenceClass,$TokenJournal=@(),$HostedJournal=@{},$FilesystemJournal=@{}) {
  $boundAudience=Get-PhaseAEvidenceAudience $BoundRecord $RunAttempt
  $items=@($Journal)
  return {
    param($kind,$entry,$context)
    try {
      if ($context -isnot [Collections.IDictionary]) { return $false }
      if ($context.schema -ceq 'ether.t3.phase-a.final.v1') {
        if ($context.repository -cne 'andyle777/Ether-Memories' -or $context.workflowRef -cne 'andyle777/Ether-Memories/.github/workflows/t3-windows-phase-a.yml@refs/heads/test/t3-windows-enforcement-run' -or $context.ref -cne 'refs/heads/test/t3-windows-enforcement-run' -or $context.event -cne 'push' -or $context.runner -cne 'github-hosted' -or $context.runAttempt -cne $RunAttempt) { return $false }
        $candidate=@{schema='ether.t3.phase-a.verdict-input.v1';policy=$context.policy;commit=$context.commit;runId=$context.runId;cases=$context.cases}
      } else { $candidate=$context }
      if ([string]::IsNullOrEmpty($boundAudience) -or (Get-PhaseAEvidenceAudience $candidate $RunAttempt) -cne $boundAudience) { return $false }
      if ($kind -ceq 'authorization') { return ($ProvenanceVerified -and $LiveAuthorized) }
      if ($kind -ceq 'workflow_provenance') { return $ProvenanceVerified }
      if ($kind -cnotin @('identityDistinct','brokerNonAdmin','legacyNonAdmin','brokerActorBinding','legacyActorBinding','actorPidBinding','actorCreationTimeBinding','actorSidBinding','brokerPrimaryToken','legacyPrimaryToken','jobContainment','jobClosure','aclEstablishment','aclInspection','protectedInventory','fixtureCleanup','unauthorizedRead','unauthorizedWrite','unauthorizedCreate')) { return $false }
      $fresh=New-PhaseAManagerVerdictInput $candidate.commit $candidate.runId
      Add-PhaseAActorEvidence $fresh $items $EvidenceClass
      Add-PhaseAPrimaryTokenEvidence $fresh $TokenJournal $items $EvidenceClass
      Add-PhaseAInnerJobEvidence $fresh $HostedJournal $items $EvidenceClass
      Add-PhaseAStage3Evidence $fresh $FilesystemJournal $EvidenceClass $items
      $expected=$fresh.cases[$kind]
      return ($entry -is [Collections.IDictionary] -and $expected.state -cin @('PASS','FAIL') -and $entry.state -ceq $expected.state -and $entry.evidence -ceq $EvidenceClass -and $entry.reason -ceq $expected.reason -and $entry.proof -ceq $expected.proof)
    } catch { return $false }
  }.GetNewClosure()
}
function Add-PhaseAPrimaryTokenEvidence($VerdictInput,$TokenJournal,$ActorJournal,[string]$EvidenceClass) {
  if ($EvidenceClass -cnotin @('LIVE_OBSERVED','SIMULATED_PASS')) { return }
  $source=if($EvidenceClass -ceq 'LIVE_OBSERVED'){'LIVE'}else{'INJECTED'}
  $items=@($TokenJournal);if($items.Count -gt 2){return}
  $actor=New-PhaseAManagerVerdictInput $VerdictInput.commit $VerdictInput.runId;Add-PhaseAActorEvidence $actor $ActorJournal $EvidenceClass
  foreach($role in @('broker','legacy')) {
    $name=$role+'PrimaryToken';if($VerdictInput.cases[$name].state -cne 'NOT_RUN'){continue}
    $matched=@($items | Where-Object {$_ -is [hashtable] -and $_.ContainsKey('role') -and $_.role -ceq $role});if($matched.Count -ne 1){continue};$item=$matched[0]
    if($source -ceq 'LIVE' -and -not $script:PhaseATrustedTokenRecords.Contains($item)){continue}
    if($item.ContainsKey('source')){if($item.source -cne $source){continue}}elseif($source -ceq 'LIVE'){continue}
    $present=$true;foreach($key in @('accountSid','first','second','closed')){if(-not $item.ContainsKey($key)){$present=$false}};if(-not $present){continue}
    if($item.accountSid -isnot [string] -or [string]::IsNullOrWhiteSpace($item.accountSid) -or $item.first -isnot [hashtable] -or $item.second -isnot [hashtable] -or $item.closed -isnot [bool]){continue}
    if($item.ContainsKey('inspection') -and $item.inspection -cne 'OBSERVED'){continue}
    $first=$item.first;$second=$item.second;$keys=@('sid','primary','admin','elevated','standard');$valid=$true
    foreach($key in $keys){if(-not $first.ContainsKey($key) -or -not $second.ContainsKey($key) -or $first[$key] -cne $second[$key]){$valid=$false}}
    if(-not $valid -or $first.sid -isnot [string] -or [string]::IsNullOrWhiteSpace($first.sid) -or -not $second.ContainsKey('handleOpen') -or $second.handleOpen -isnot [bool] -or -not $second.handleOpen){continue}
    try{$expectedSid=New-Object Security.Principal.SecurityIdentifier($item.accountSid);$observedSid=New-Object Security.Principal.SecurityIdentifier($first.sid);if($expectedSid.Value -cne $item.accountSid -or $observedSid.Value -cne $first.sid){continue}}catch{continue}
    foreach($key in @('primary','admin','elevated','standard')){if($first[$key] -isnot [bool] -or $second[$key] -isnot [bool]){$valid=$false}};if(-not $valid){continue}
    foreach($key in @('tokenId','authenticationId','modifiedId')){if(-not $first.ContainsKey($key) -or -not $second.ContainsKey($key) -or $first[$key] -isnot [string] -or $first[$key] -cnotmatch '^[0-9a-f]{16}$' -or $first[$key] -cne $second[$key]){$valid=$false}}
    if(-not $first.ContainsKey('statisticsPrimary') -or -not $second.ContainsKey('statisticsPrimary') -or $first.statisticsPrimary -isnot [bool] -or $second.statisticsPrimary -isnot [bool] -or $first.statisticsPrimary -ne $second.statisticsPrimary -or $first.primary -ne $first.statisticsPrimary){$valid=$false};if(-not $valid){continue}
    $violation=($first.sid -cne $item.accountSid -or -not $first.primary -or $first.admin -or $first.elevated -or -not $first.standard)
    $state='FAIL';$reason='VIOLATION';$actorProof=''
    $processViolation=$false;$processViolationRecord=$null
    if(-not $violation){
      $records=if($item.ContainsKey('processObservations')){@($item.processObservations | ForEach-Object {$_})}elseif($item.ContainsKey('processObservation')){@($item.processObservation)}else{@()}
      foreach($candidate in $records){if((Get-PhaseAProcessTokenObservation $item $candidate $source) -ceq 'FAIL'){$processViolation=$true;$processViolationRecord=$candidate;break}}
    }
    if(-not $violation -and -not $processViolation){
      if($item.closed -isnot [bool] -or -not $item.closed -or ($item.ContainsKey('closeResult') -and $item.closeResult -cne 'CLOSED')){continue}
      if($source -ceq 'LIVE'){foreach($event in @($ActorJournal)){if(-not $script:PhaseATrustedActorRecords.Contains($event)){$valid=$false}};if(-not $valid){continue}}
      if($actor.cases.actorSidBinding.state -cne 'PASS'){continue};$probe=@($ActorJournal|Where-Object {$_.role -ceq $role -and $_.operation -ceq 'probe'})
      if($probe.Count -ne 1 -or $probe[0].accountSid -cne $item.accountSid -or $probe[0].tokenSid -cne $item.accountSid){continue}
      if($source -ceq 'LIVE' -and -not $script:PhaseATrustedActorRecords.Contains($probe[0])){continue}
      $observation=$probe[0].observation;if(-not $observation.ContainsKey('lineage') -or $observation.lineage -isnot [hashtable]){continue};$lineage=$observation.lineage
      foreach($key in @('source','role','launchTokenId','launchAuthenticationId','launchModifiedId','processTokenId','processAuthenticationId','processModifiedId','processPrimary','pid','createdAt','contained')){if(-not $lineage.ContainsKey($key)){$valid=$false}};if(-not $valid){continue}
      if($lineage.source -cne $source -or $lineage.role -cne $role -or $lineage.launchTokenId -cne $first.tokenId -or $lineage.launchAuthenticationId -cne $first.authenticationId -or $lineage.launchModifiedId -cne $first.modifiedId -or $lineage.processAuthenticationId -cne $first.authenticationId -or $lineage.processTokenId -cnotmatch '^[0-9a-f]{16}$' -or $lineage.processModifiedId -cnotmatch '^[0-9a-f]{16}$' -or $lineage.processPrimary -isnot [bool] -or -not $lineage.processPrimary -or $lineage.contained -isnot [bool] -or -not $lineage.contained -or $lineage.pid -ne $observation.expectedPid -or $lineage.createdAt -cne $observation.observedCreatedAt){continue}
      $successProcess=$null
      if($source -ceq 'LIVE' -or $item.ContainsKey('processObservations')){
        if(-not $item.ContainsKey('processObservations')){continue}
        $matching=@($item.processObservations | Where-Object {$_ -is [hashtable] -and $_.ContainsKey('pid') -and $_.ContainsKey('createdAt') -and $_.pid -eq $lineage.pid -and $_.createdAt -ceq $lineage.createdAt})
        if($matching.Count -ne 1){continue};$successProcess=$matching[0]
        if((Get-PhaseAProcessTokenObservation $item $successProcess $source) -cne 'PASS' -or $successProcess.first.tokenId -cne $lineage.processTokenId -or $successProcess.first.authenticationId -cne $lineage.processAuthenticationId -or $successProcess.first.modifiedId -cne $lineage.processModifiedId -or $successProcess.cleanup -cne 'PROCESS_CONFIRMED'){continue}
      }
      $state='PASS';$reason='NONE';$actorProof=$actor.cases.actorSidBinding.proof
    }
    $canonical=[ordered]@{control=$name;source=$source;role=$role;accountSid=$item.accountSid;observedSid=$first.sid;primary=$first.primary;admin=$first.admin;elevated=$first.elevated;standard=$first.standard;tokenId=$first.tokenId;authenticationId=$first.authenticationId;modifiedId=$first.modifiedId;handleOpen=$second.handleOpen;closed=$item.closed;actorProof=$actorProof;lineage=$(if($state -ceq 'PASS'){$lineage}else{$null});processObservation=$(if($processViolation){$processViolationRecord}elseif($state -ceq 'PASS'){$successProcess}else{$null});state=$state}
    $sha=[Security.Cryptography.SHA256]::Create();try{$json=ConvertTo-Json -InputObject $canonical -Compress -Depth 5;$proof=[BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($json))).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose()}
    $VerdictInput.cases[$name]=@{state=$state;evidence=$EvidenceClass;reason=$reason;proof=$proof}
  }
}
function New-PhaseATokenJournalBackend([hashtable]$Backend,[Collections.Generic.List[object]]$Journal,[scriptblock]$Inspect,[ValidateSet('LIVE','INJECTED')][string]$Source='INJECTED') {
  if ($null -eq $Inspect -or $null -eq $Journal) { throw 'TOKEN_JOURNAL_INVALID' }
  if($Source -ceq 'LIVE'){
    if(-not $script:PhaseATrustedAccountBackends.ContainsKey($Backend)){throw 'TOKEN_SOURCE_REJECTED'}
    $origin=$script:PhaseATrustedAccountBackends[$Backend]
    if(-not [object]::ReferenceEquals($origin.authenticate,$Backend.Authenticate) -or -not [object]::ReferenceEquals($origin.close,$Backend.Close) -or -not [object]::ReferenceEquals($origin.inspect,$Backend.InspectToken) -or -not [object]::ReferenceEquals($origin.inspect,$Inspect)){throw 'TOKEN_SOURCE_REJECTED'}
  }
  $wrapped=$Backend.Clone(); $authenticate=$Backend.Authenticate; $close=$Backend.Close;$owners=New-Object 'System.Collections.Generic.List[object]'
  $wrapped.Authenticate={ param($account)
    $token=& $authenticate $account
    $entry=$null
    try {
      $first=@{sid=$token.sid;primary=$token.primary;admin=$token.admin;elevated=$token.elevated;standard=$token.standard}
      if($Source -ceq 'INJECTED' -and $token -is [hashtable]){foreach($key in @('tokenId','authenticationId','modifiedId','statisticsPrimary')){if($token.ContainsKey($key)){$first[$key]=$token[$key]}}}
      $entry=@{role=$account.role;accountSid=$account.sid;source=$Source;first=$first;second=$null;inspection='FAILED';failure='STATISTICS_QUERY_FAILED';launchFailure='NONE';closed=$false;closeResult='NOT_ATTEMPTED'};$Journal.Add($entry);$owners.Add(@{token=$token;entry=$entry})
      if($Source -ceq 'LIVE'){$null=$script:PhaseATrustedTokenRecords.Add($entry);$script:PhaseATokenOwners.Add($token,$entry)}
      if($Source -ceq 'LIVE'){$stats=[EtherPhaseANative]::InspectTokenHandle($token.handle.DangerousGetHandle());$first.tokenId=$stats.tokenId;$first.authenticationId=$stats.authenticationId;$first.modifiedId=$stats.modifiedId;$first.statisticsPrimary=$stats.primary}
      $entry.failure='INSPECTION_FAILED'
      $observation=& $Inspect $token
      if ($observation -isnot [hashtable]) { throw 'TOKEN_INSPECTION_FAILED' }
      $required=@('sid','primary','admin','elevated','standard','handleOpen');if($Source -ceq 'LIVE'){$required+=@('tokenId','authenticationId','modifiedId','statisticsPrimary')}
      if($Source -ceq 'INJECTED'){foreach($key in @('tokenId','authenticationId','modifiedId','statisticsPrimary')){if($observation.ContainsKey($key)){$required+=$key}}}
      $bounded=@{};foreach($key in $required){if(-not $observation.ContainsKey($key)){throw 'TOKEN_INSPECTION_FAILED'};$bounded[$key]=$observation[$key]}
      $entry.second=$bounded;$entry.inspection='OBSERVED';$entry.failure='NONE'
      return $token
    } catch { try { $null=& $close $token; if($entry){$entry.closed=$true;$entry.closeResult='CLOSED'} } catch { if($entry){$entry.closeResult='FAILED'};throw 'ACCOUNT_CLEANUP_FAILED' } finally {if($Source -ceq 'LIVE'){$null=$script:PhaseATokenOwners.Remove($token)}}; throw }
  }.GetNewClosure()
  $wrapped.Close={ param($token)
    $matches=@($owners | Where-Object { [object]::ReferenceEquals($_.token,$token) })
    if ($matches.Count -ne 1) { throw 'ACCOUNT_CLEANUP_FAILED' }
    try{$null=& $close $token;$matches[0].entry.closed=$true;$matches[0].entry.closeResult='CLOSED'}catch{$matches[0].entry.closeResult='FAILED';throw}finally{if($Source -ceq 'LIVE'){$null=$script:PhaseATokenOwners.Remove($token)}}
  }.GetNewClosure()
  return $wrapped
}
function Test-PhaseACloseReceipt($Receipt,$Expected) {
  try {
    $fields=@('schema','mode','attempt','supervisorPid','supervisorCreatedAt','childPid','childCreatedAt','attempted','succeeded','error')
    if ($Receipt -isnot [Collections.IDictionary] -or $Expected -isnot [Collections.IDictionary] -or $Receipt.Count -ne $fields.Count) { return $false }
    foreach ($field in $fields) { if (-not (@($Receipt.Keys) -ccontains $field)) { return $false } }
    if ($Receipt.schema -cne 'ether.phase-a.close-receipt.v1' -or $Receipt.mode -cne 'jobClosure' -or $Expected.mode -cne 'jobClosure' -or $Receipt.attempt -isnot [string] -or $Receipt.attempt -cnotmatch '^[0-9a-f]{32}$' -or $Receipt.attempt -cne $Expected.attempt -or $Receipt.attempted -isnot [bool] -or -not $Receipt.attempted -or $Receipt.succeeded -isnot [bool]) { return $false }
    foreach ($field in @('supervisorPid','childPid')) { if ($Receipt[$field] -isnot [int] -or $Receipt[$field] -le 0 -or $Receipt[$field] -ne $Expected[$field]) { return $false } }
    foreach ($field in @('supervisorCreatedAt','childCreatedAt')) { $a=[DateTimeOffset]::MinValue; $b=[DateTimeOffset]::MinValue; if (-not [DateTimeOffset]::TryParse([string]$Receipt[$field],[ref]$a) -or -not [DateTimeOffset]::TryParse([string]$Expected[$field],[ref]$b) -or $a -ne $b) { return $false } }
    if ($Receipt.succeeded) { return ($Receipt.error -ceq 'NONE') }
    return ($Receipt.error -cin @('WIN32_ACCESS_DENIED','WIN32_INVALID_HANDLE','WIN32_OTHER','NON_WIN32'))
  } catch { return $false }
}
function Add-PhaseAInnerJobEvidence($VerdictInput,$HostedJournal,$ActorJournal,[string]$EvidenceClass) {
  try {
    if ($EvidenceClass -cnotin @('LIVE_OBSERVED','SIMULATED_PASS') -or $HostedJournal -isnot [hashtable]) { return }
    $source=if ($EvidenceClass -ceq 'LIVE_OBSERVED') {'LIVE'} else {'INJECTED'}
    $probes=@($ActorJournal | Where-Object { $_.role -ceq 'broker' -and $_.operation -ceq 'probe' })
    if ($probes.Count -ne 1) { return }
    $probe=$probes[0]; $obs=$probe.observation
    if ($probe.accountSid -cne $probe.tokenSid -or $obs.expectedSid -cne $probe.accountSid -or $obs.contained -isnot [bool] -or -not $obs.contained -or $obs.terminated -isnot [bool] -or -not $obs.terminated -or -not (Test-ActorObservation $obs 'broker' 'allowed')) { return }
    foreach ($mode in @('supervisorDeath','jobClosure')) {
      if (-not $HostedJournal.ContainsKey($mode)) { continue }
      $record=$HostedJournal[$mode]
      if ($record -isnot [hashtable] -or $record.source -cne $source -or $record.mode -cne $mode -or $record.innerJobObservation -isnot [hashtable] -or $record.cleanupSucceeded -isnot [bool]) { continue }
      $inner=$record.innerJobObservation
      if ($record.supervisorSid -cne $probe.accountSid -or $record.supervisorPid -isnot [int] -or $record.supervisorPid -le 0 -or $record.childPid -isnot [int] -or $record.childPid -le 0 -or $record.supervisorPid -eq $record.childPid -or $record.childSid -cne $probe.accountSid -or $inner.pid -isnot [int] -or $inner.sid -isnot [string] -or $inner.createdAt -isnot [string]) { continue }
      $identityMismatch=($inner.pid -ne $record.childPid -or $inner.sid -cne $record.childSid -or $inner.createdAt -cne $record.childCreatedAt)
      $supervisorTime=[DateTimeOffset]::MinValue; if (-not [DateTimeOffset]::TryParse([string]$record.supervisorCreatedAt,[ref]$supervisorTime)) { continue }
      $outcome='NOT_RUN'; $reason='NOT_RUN'; $control=if ($mode -ceq 'supervisorDeath') {'jobContainment'} else {'jobClosure'}
      $limitsValid=(($inner.limitFlags -is [int] -or $inner.limitFlags -is [uint32]) -and (($inner.limitFlags -band 0x2000) -ne 0))
      $memberValid=($inner.member -is [bool] -and $inner.member -and $inner.supervisorMember -is [bool] -and -not $inner.supervisorMember)
      $released=($inner.released -is [bool] -and $inner.released)
      $innerValid=($inner.status -ceq 'OBSERVED' -and $inner.reason -ceq 'NONE' -and $limitsValid -and $memberValid -and $released)
      if ($mode -ceq 'supervisorDeath') {
        if ($identityMismatch) { $outcome='FAIL';$reason='SETUP_FAILED' }
        elseif ($innerValid) { $outcome='PASS';$reason='NONE' }
        elseif ($inner.status -ceq 'FAILED' -and $released -and (($inner.reason -ceq 'LIMIT_MISMATCH' -and -not $limitsValid -and ($inner.limitFlags -is [int] -or $inner.limitFlags -is [uint32])) -or ($inner.reason -ceq 'JOB_MISMATCH' -and $limitsValid -and $inner.member -is [bool] -and $inner.supervisorMember -is [bool] -and -not $memberValid))) { $outcome='FAIL';$reason='CONTROL_FAILED' }
        elseif ($inner.status -ceq 'FAILED' -and $inner.reason -cin @('INSPECTION_FAILED','INSPECTION_RELEASE_FAILED','PID_MISMATCH','TIME_MISMATCH','EARLY_EXIT')) { $outcome='FAIL';$reason='SETUP_FAILED' }
      } elseif (-not $identityMismatch -and $innerValid -and $record.childRunningBeforeAction -is [bool] -and $record.childRunningBeforeAction -and $record.action -ceq 'CLOSE_REQUESTED' -and $record.supervisorWaitSucceeded -is [bool] -and $record.supervisorWaitSucceeded -and $record.supervisorExitCode -is [int] -and (Test-PhaseACloseReceipt $record.closeReceipt $record)) {
        if (-not $record.closeReceipt.succeeded) { $outcome='FAIL';$reason='SETUP_FAILED' }
        elseif ($record.childWaitOutcome -ceq 'SIGNALED' -and $record.supervisorExitCode -eq 0 -and $record.childAliveAfterWait -is [bool] -and -not $record.childAliveAfterWait -and $record.childExitCode -is [int] -and $record.childExitCode -ne 259) { $outcome='PASS';$reason='NONE' }
        elseif ($record.childWaitOutcome -ceq 'TIMEOUT' -and $record.childAliveAfterWait -is [bool] -and $record.childAliveAfterWait -and $null -eq $record.childExitCode) { $outcome='FAIL';$reason='CONTROL_FAILED' }
        elseif ($record.childWaitOutcome -ceq 'FAILED') { $outcome='FAIL';$reason='SETUP_FAILED' }
      }
      if ($outcome -ceq 'NOT_RUN') { continue }
      if (-not $record.cleanupSucceeded -and $outcome -ceq 'PASS') { $outcome='FAIL';$reason='CLEANUP_UNCONFIRMED' }
      if ($VerdictInput.cases[$control].state -cne 'NOT_RUN') { continue }
      $canonical=[ordered]@{control=$control;mode=$mode;state=$outcome;reason=$reason;supervisorPid=$record.supervisorPid;supervisorSid=$record.supervisorSid;supervisorCreatedAt=$record.supervisorCreatedAt;reportedChildPid=$record.childPid;reportedChildSid=$record.childSid;reportedChildCreatedAt=$record.childCreatedAt;pid=$inner.pid;sid=$inner.sid;createdAt=$inner.createdAt;innerStatus=$inner.status;innerReason=$inner.reason;limitFlags=$inner.limitFlags;member=$inner.member;supervisorMember=$inner.supervisorMember;released=$inner.released;cleanup=$record.cleanupSucceeded;actorPid=$obs.expectedPid;actorCreatedAt=$obs.observedCreatedAt}
      if ($mode -ceq 'jobClosure') {
        foreach ($key in @('childRunningBeforeAction','action','supervisorWaitSucceeded','supervisorExitCode','childWaitOutcome','childExitCode','childAliveAfterWait','attempt')) { $canonical[$key]=$record[$key] }
        $r=$record.closeReceipt; $canonical['closeReceipt']=[ordered]@{schema=$r.schema;mode=$r.mode;attempt=$r.attempt;supervisorPid=$r.supervisorPid;supervisorCreatedAt=$r.supervisorCreatedAt;childPid=$r.childPid;childCreatedAt=$r.childCreatedAt;attempted=$r.attempted;succeeded=$r.succeeded;error=$r.error}
      }
      $sha=[Security.Cryptography.SHA256]::Create()
      try { $json=ConvertTo-Json -InputObject $canonical -Compress; $proof=[BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($json))).Replace('-','').ToLowerInvariant() } finally { $sha.Dispose() }
      $VerdictInput.cases[$control]=@{state=$outcome;evidence=$EvidenceClass;reason=$reason;proof=$proof}
    }
  } catch { return }
}
function Add-PhaseAProtectedInventoryEvidence($VerdictInput,$Evidence,[string]$EvidenceClass,$Journal) {
 try {
  if($EvidenceClass -cnotin @('LIVE_OBSERVED','SIMULATED_PASS') -or $Evidence -isnot [hashtable] -or $Evidence.cleanupVerified -isnot [bool] -or -not $Evidence.ContainsKey('inventoryBaseline')){return}
  $source=if($EvidenceClass -ceq 'LIVE_OBSERVED'){'LIVE'}else{'INJECTED'}
  $baseline=$Evidence.inventoryBaseline
  if($baseline -isnot [hashtable] -or $baseline.status -cne 'OBSERVED' -or $baseline.source -cne $source -or $baseline.reason -cne 'NONE' -or $baseline.control -cne 'unauthorizedRead' -or $baseline.position -ne 0 -or $baseline.phase -cne 'BEFORE' -or $baseline.fixtureId -cnotmatch '^ether-phase-a-store-[0-9a-f]{32}$' -or $baseline.digest -cnotmatch '^[0-9a-f]{64}$' -or (Get-PhaseAInventoryEntriesDigest $baseline.entries) -cne $baseline.digest){return}
  if($baseline.rootIdentity -isnot [string] -or $baseline.rootIdentity -cne [IO.Path]::GetFullPath($baseline.rootIdentity) -or [IO.Path]::GetFileName([IO.Path]::GetFullPath($baseline.rootIdentity)) -cne $baseline.fixtureId){return}
  if($source -ceq 'LIVE' -and [IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($baseline.rootIdentity)) -cne [IO.Path]::GetFullPath([Environment]::GetFolderPath([Environment+SpecialFolder]::CommonApplicationData)).TrimEnd('\')){return}
  $items=@($Journal);$proofs=New-Object 'System.Collections.Generic.List[object]';$violated=$false
  if($items.Count -lt 5){return};$expectedPrelude=@(@('broker','probe'),@('legacy','probe'),@('broker','Read'),@('broker','Create'),@('broker','Read'))
  for($p=0;$p -lt 5;$p++){$item=$items[$p];$expected=$expectedPrelude[$p];if($item -isnot [hashtable] -or $item.role -cne $expected[0] -or $item.operation -cne $expected[1] -or $item.accountSid -cne $item.tokenSid -or $item.observation.expectedSid -cne $item.accountSid -or $item.observation.contained -isnot [bool] -or -not $item.observation.contained -or $item.observation.terminated -isnot [bool] -or -not $item.observation.terminated -or -not (Test-ActorObservation $item.observation $expected[0] 'allowed')){return}}
  if($items[1].accountSid -cne $baseline.actorSid -or $items[0].accountSid -ceq $baseline.actorSid -or $items[2].accountSid -cne $items[0].accountSid -or $items[3].accountSid -cne $items[0].accountSid -or $items[4].accountSid -cne $items[0].accountSid){return}
  $sha=[Security.Cryptography.SHA256]::Create();try{$original=[BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::ASCII.GetBytes('ether-phase-a-synthetic'))).Replace('-','').ToLowerInvariant();$committed=[BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::ASCII.GetBytes('A'))).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose()}
  if($items[2].observation.digest -cne $original -or $items[4].observation.digest -cne $committed -or $baseline.entries.Count -ne 3){return}
  $initial=@($baseline.entries|Where-Object {$_.name -ceq 'original.bin' -and $_.type -ceq 'file' -and $_.sha256 -ceq $original -and $_.size -eq 23});$created=@($baseline.entries|Where-Object {$_.name -ceq 'committed.bin' -and $_.type -ceq 'file' -and $_.sha256 -ceq $committed -and $_.size -eq 1})
  if($initial.Count -ne 1 -or $created.Count -ne 1){return}
  for($i=0;$i -lt 5;$i++) {
   $control=@('unauthorizedRead','unauthorizedWrite','unauthorizedCreate','unauthorizedRename','unauthorizedDelete')[$i];$operation=@('Read','Overwrite','Create','Rename','Delete')[$i]
   if(-not $Evidence.ContainsKey($control) -or $items.Count -le (5+$i)){return};$entry=$Evidence[$control];$actor=$items[5+$i]
   if($entry -isnot [hashtable] -or $entry.control -cne $control -or $entry.operation -cne $operation -or $entry.target -cne $(if($i -eq 2){'deniedFile'}else{'protectedFile'}) -or $entry.accountSid -cne $baseline.actorSid -or $entry.tokenSid -cne $baseline.actorSid -or $actor.role -cne 'legacy' -or $actor.operation -cne $operation -or $actor.accountSid -cne $baseline.actorSid -or $actor.tokenSid -cne $baseline.actorSid){return}
   $o=$entry.observation;$j=$actor.observation
   if($o -isnot [hashtable] -or $j -isnot [hashtable] -or $o.expectedPid -ne $j.expectedPid -or $o.expectedNonce -cne $j.expectedNonce -or $o.observedCreatedAt -cne $j.observedCreatedAt -or $o.expectedSid -cne $baseline.actorSid -or $o.contained -isnot [bool] -or -not $o.contained -or $o.terminated -isnot [bool] -or -not $o.terminated -or $o.outcome -cnotin @('allowed','denied') -or -not (Test-ActorObservation $o 'legacy' $o.outcome) -or -not (Test-ActorObservation $j 'legacy' $j.outcome) -or $o.outcome -cne $j.outcome){return}
   $violationBefore=$false
   foreach($phase in @('BEFORE','AFTER')) {
    $snap=if($phase -ceq 'BEFORE'){$entry.beforeDetails}else{$entry.afterDetails};$original=if($phase -ceq 'BEFORE'){$entry.beforeInventory}else{$entry.afterInventory}
    if($snap -isnot [hashtable] -or $snap.status -cne 'OBSERVED' -or $snap.source -cne $source -or $snap.reason -cne 'NONE' -or $snap.fixtureId -cne $baseline.fixtureId -or $snap.rootIdentity -cne $baseline.rootIdentity -or $snap.control -cne $control -or $snap.position -ne $i -or $snap.phase -cne $phase -or $snap.actorSid -cne $baseline.actorSid -or $snap.digest -cnotmatch '^[0-9a-f]{64}$' -or $snap.digest -cne $original -or (Get-PhaseAInventoryEntriesDigest $snap.entries) -cne $snap.digest){return}
    if($phase -ceq 'BEFORE' -and $snap.digest -cne $baseline.digest){$violationBefore=$true;break}
   }
   if($violationBefore){$proofs.Add([ordered]@{control=$control;position=$i;before=$entry.beforeDetails.digest;after='';pid=$o.expectedPid;createdAt=$o.observedCreatedAt;nonce=$o.expectedNonce;outcome=$o.outcome});$violated=$true;break}
   $proofs.Add([ordered]@{control=$control;position=$i;before=$entry.beforeDetails.digest;after=$entry.afterDetails.digest;pid=$o.expectedPid;createdAt=$o.observedCreatedAt;nonce=$o.expectedNonce;outcome=$o.outcome})
   if($entry.afterDetails.digest -cne $baseline.digest){$violated=$true;break}
  }
  if(-not $violated -and (-not $Evidence.cleanupVerified -or $proofs.Count -ne 5)){return}
  $state=if($violated){'FAIL'}else{'PASS'};$reason=if($violated){'VIOLATION'}else{'NONE'}
  $canonical=[ordered]@{control='protectedInventory';fixture=$baseline.fixtureId;rootIdentity=$baseline.rootIdentity;actorSid=$baseline.actorSid;baseline=$baseline.digest;operations=$proofs.ToArray();cleanup=$Evidence.cleanupVerified;state=$state}
  $sha=[Security.Cryptography.SHA256]::Create();try{$json=ConvertTo-Json -InputObject $canonical -Compress -Depth 8;$proof=[BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($json))).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose()}
  if($VerdictInput.cases.protectedInventory.state -ceq 'NOT_RUN'){$VerdictInput.cases.protectedInventory=@{state=$state;evidence=$EvidenceClass;reason=$reason;proof=$proof}}
 } catch {return}
}
function Add-PhaseAAclEstablishmentEvidence($VerdictInput,$Evidence,[string]$EvidenceClass,$ActorJournal) {
 try {
  if($EvidenceClass -cnotin @('LIVE_OBSERVED','SIMULATED_PASS') -or $Evidence.cleanupVerified -isnot [bool] -or -not $Evidence.ContainsKey('aclEstablishment') -or -not $Evidence.ContainsKey('aclCorroboration') -or -not $Evidence.ContainsKey('aclFixtureBinding')){return}
  $src=if($EvidenceClass -ceq 'LIVE_OBSERVED'){'LIVE'}else{'INJECTED'};$actors=@($ActorJournal);if($actors.Count -lt 2){return}
  foreach($i in 0,1){$a=$actors[$i];$role=@('broker','legacy')[$i];if($a.role -cne $role -or $a.operation -cne 'probe' -or $a.accountSid -cne $a.tokenSid -or $a.observation.expectedSid -cne $a.accountSid -or $a.observation.contained -isnot [bool] -or -not $a.observation.contained -or $a.observation.terminated -isnot [bool] -or -not $a.observation.terminated -or -not (Test-ActorObservation $a.observation $role 'allowed')){return}}
  $broker=$actors[0].accountSid;$legacy=$actors[1].accountSid;$manager=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
  $binding=$Evidence.aclFixtureBinding;if($binding -isnot [hashtable] -or $binding.source -cne $src -or $binding.brokerSid -cne $broker -or $binding.legacySid -cne $legacy -or $binding.fixtureId -cnotmatch '^ether-phase-a-store-[0-9a-f]{32}$'){return}
  if($binding.rootIdentity -isnot [string] -or $binding.rootIdentity -cne [IO.Path]::GetFullPath($binding.rootIdentity).TrimEnd('\') -or [IO.Path]::GetFileName($binding.rootIdentity) -cne $binding.fixtureId){return};if($src -ceq 'LIVE' -and [IO.Path]::GetDirectoryName($binding.rootIdentity) -cne [IO.Path]::GetFullPath([Environment]::GetFolderPath([Environment+SpecialFolder]::CommonApplicationData)).TrimEnd('\')){return}
  if($broker -ceq $legacy -or $broker -ceq $manager -or $legacy -ceq $manager -or $broker -ceq 'S-1-5-18' -or $legacy -ceq 'S-1-5-18'){return}
  $records=@($Evidence.aclEstablishment | ForEach-Object {$_});$observed=@($Evidence.aclCorroboration | ForEach-Object {$_});if($records.Count -lt 1 -or $records.Count -gt 3 -or $records.Count -ne $observed.Count){return}
  $id='';$proofs=New-Object 'System.Collections.Generic.List[object]';$violated=$false
  for($i=0;$i -lt $records.Count;$i++){
   $r=$records[$i];$o=$observed[$i];$role=@('root','protected','control')[$i];$relative=@('.','protected','control')[$i]
   if($r -isnot [hashtable] -or $o -isnot [hashtable] -or $r.fixtureId -cnotmatch '^ether-phase-a-store-[0-9a-f]{32}$' -or ($i -gt 0 -and $r.fixtureId -cne $id) -or $o.fixtureId -cne $r.fixtureId -or $r.role -cne $role -or $o.role -cne $role -or $r.relative -cne $relative -or $o.relative -cne $relative -or $r.sequence -ne $i -or $o.sequence -ne $i -or $r.source -cne $src -or $o.source -cne $src){return};$id=$r.fixtureId;if($id -cne $binding.fixtureId){return}
   if($r.targetExists -isnot [bool] -or -not $r.targetExists -or $r.attempted -isnot [bool] -or -not $r.attempted -or $r.applied -isnot [bool] -or -not $r.applied -or $r.expectedProtected -isnot [bool] -or -not $r.expectedProtected -or $r.actualProtected -isnot [bool] -or $o.protected -isnot [bool] -or $o.status -cne 'OBSERVED' -or $o.reason -cne 'NONE'){return}
   $acl=New-Object Security.AccessControl.DirectorySecurity;$acl.SetAccessRuleProtection($true,$false)
   $full=if($i -eq 0){@($manager,'S-1-5-18')}elseif($i -eq 1){@($manager,'S-1-5-18',$broker)}else{@($manager,'S-1-5-18',$broker,$legacy)};$read=if($i -eq 0){@($broker,$legacy)}else{@()}
   foreach($spec in @(@{sids=$full;rights='FullControl'},@{sids=$read;rights='ReadAndExecute'})){foreach($sidText in $spec.sids){$sid=New-Object Security.Principal.SecurityIdentifier($sidText);$rule=New-Object Security.AccessControl.FileSystemAccessRule($sid,$spec.rights,'ContainerInherit,ObjectInherit','None','Allow');$acl.AddAccessRule($rule)}}
   $expected=$acl.GetSecurityDescriptorSddlForm([Security.AccessControl.AccessControlSections]::Access)
   if($r.expected -cne $expected -or $r.actual -isnot [string] -or [string]::IsNullOrEmpty($r.actual) -or $r.actual -cne $o.descriptor -or $r.actualProtected -cne $o.protected){return}
   $raw=New-Object Security.AccessControl.RawSecurityDescriptor($o.descriptor);$protectedFlag=($raw.ControlFlags -band [Security.AccessControl.ControlFlags]::DiscretionaryAclProtected) -ne 0;if($protectedFlag -cne $o.protected){return}
   $mismatch=($o.descriptor -cne $expected -or -not $o.protected)
   if(($mismatch -and $r.reason -cne 'DESCRIPTOR_MISMATCH') -or (-not $mismatch -and $r.reason -cne 'NONE')){return}
   $proofs.Add([ordered]@{fixture=$id;role=$role;relative=$relative;sequence=$i;expected=$expected;actual=$r.actual;manager=$o.descriptor;protected=$o.protected});if($mismatch){if($records.Count -ne ($i+1)){return};$violated=$true;break}
  }
  if(-not $violated -and ($records.Count -ne 3 -or -not $Evidence.cleanupVerified)){return}
  $state=if($violated){'FAIL'}else{'PASS'};$reason=if($violated){'VIOLATION'}else{'NONE'};$canonical=[ordered]@{control='aclEstablishment';broker=$broker;legacy=$legacy;manager=$manager;records=$proofs.ToArray();cleanup=$Evidence.cleanupVerified;state=$state};$sha=[Security.Cryptography.SHA256]::Create();try{$json=ConvertTo-Json -InputObject $canonical -Compress -Depth 8;$proof=[BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($json))).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose()};if($VerdictInput.cases.aclEstablishment.state -ceq 'NOT_RUN'){$VerdictInput.cases.aclEstablishment=@{state=$state;evidence=$EvidenceClass;reason=$reason;proof=$proof}}
 }catch{return}
}
function Add-PhaseAFixtureCleanupEvidence($VerdictInput,$Evidence,[string]$EvidenceClass,$ActorJournal) {
 try {
  if($EvidenceClass -cnotin @('LIVE_OBSERVED','SIMULATED_PASS') -or $Evidence -isnot [hashtable] -or $Evidence.cleanupVerified -isnot [bool] -or -not $Evidence.ContainsKey('fixtureCleanup')){return}
  $source=if($EvidenceClass -ceq 'LIVE_OBSERVED'){'LIVE'}else{'INJECTED'};$c=$Evidence.fixtureCleanup;if($c -isnot [hashtable] -or ($c.ContainsKey('route') -and $c.route -cne 'SETUP_FAILURE')){return};$early=($c.ContainsKey('route') -and $c.route -ceq 'SETUP_FAILURE');$key=if($early){'setupFixtureBinding'}else{'aclFixtureBinding'};if(-not $Evidence.ContainsKey($key)){return};$b=$Evidence[$key];$actors=@($ActorJournal)
  if($c -isnot [hashtable] -or $b -isnot [hashtable] -or $actors.Count -lt 2 -or $b.source -cne $source -or $b.fixtureId -cnotmatch '^ether-phase-a-store-[0-9a-f]{32}$'){return}
  foreach($i in 0,1){$a=$actors[$i];$role=@('broker','legacy')[$i];if($a.role -cne $role -or $a.operation -cne 'probe' -or $a.accountSid -cne $a.tokenSid -or $a.accountSid -cne $(if($i -eq 0){$b.brokerSid}else{$b.legacySid}) -or $a.observation.expectedSid -cne $a.accountSid -or $a.observation.contained -isnot [bool] -or -not $a.observation.contained -or $a.observation.terminated -isnot [bool] -or -not $a.observation.terminated -or -not (Test-ActorObservation $a.observation $role 'allowed')){return}}
  if($b.brokerSid -ceq $b.legacySid -or $b.rootIdentity -isnot [string] -or $b.rootIdentity -cne [IO.Path]::GetFullPath($b.rootIdentity).TrimEnd('\') -or [IO.Path]::GetFileName($b.rootIdentity) -cne $b.fixtureId){return}
  $parent=[IO.Path]::GetDirectoryName($b.rootIdentity);if($source -ceq 'LIVE' -and $parent -cne [IO.Path]::GetFullPath([Environment]::GetFolderPath([Environment+SpecialFolder]::CommonApplicationData)).TrimEnd('\')){return}
  if($c.authorized -isnot [bool] -or -not $c.authorized -or $c.attempted -isnot [bool] -or -not $c.attempted -or $c.returned -isnot [bool] -or $c.reason -cnotin @('NONE','CLEANUP_FAILED')){return}
  $allowed=@('.','protected','control','protected/original.bin','protected/committed.bin','protected/rejected.bin','protected/original.bin.renamed','control/original.bin','protected/witness-authorized.bin','control/witness-permissive.bin')
  $creationProof=@();if($early){if($c.setupReason -cnotin @('ACL_REJECTED','SETUP_FAILED') -or -not $c.ContainsKey('creation') -or ($c.returned -and $c.reason -cne 'NONE') -or (-not $c.returned -and $c.reason -cne 'CLEANUP_FAILED')){return};$creation=@($c.creation | ForEach-Object {$_});if($creation.Count -lt 1 -or $creation.Count -gt 5){return};$roles=@('root','protected','control','protectedFile','controlFile');for($i=0;$i -lt $creation.Count;$i++){$item=$creation[$i];if($item -isnot [hashtable] -or $item.role -cne $roles[$i] -or $item.sequence -ne $i -or $item.attempted -isnot [bool] -or -not $item.attempted -or $item.result -cnotin @('CREATED','UNCONFIRMED') -or ($item.result -ceq 'UNCONFIRMED' -and $i -ne ($creation.Count-1))){return};$creationProof+=,[ordered]@{role=$item.role;sequence=$i;result=$item.result}};if($creation[0].result -cne 'CREATED'){return}}
  if($c.fixtureId -cne $b.fixtureId -or $c.rootIdentity -cne $b.rootIdentity -or $c.parentIdentity -cne $parent -or $c.identityAssurance -cne 'PATH_ONLY' -or $c.expected -isnot [array] -or $c.expected.Count -ne $allowed.Count){return};for($i=0;$i -lt $allowed.Count;$i++){if($c.expected[$i] -cne $allowed[$i]){return}}
  foreach($phase in @('BEFORE','AFTER')){$o=if($phase -ceq 'BEFORE'){$c.before}else{$c.after};if($o -isnot [hashtable] -or $o.status -cne 'OBSERVED' -or $o.reason -cne 'NONE' -or $o.phase -cne $phase -or $o.source -cne $source -or $o.fixtureId -cne $b.fixtureId -or $o.rootIdentity -cne $b.rootIdentity -or $o.parentIdentity -cne $parent -or $o.identityAssurance -cne 'PATH_ONLY' -or $o.rootExists -isnot [bool] -or $o.existing -isnot [array] -or $o.unexpected -isnot [int] -or $o.unexpected -lt 0 -or $o.unexpected -gt 128){return};$seen=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase);foreach($x in $o.existing){if($x -isnot [string] -or $x -cnotin $allowed -or -not $seen.Add($x)){return}};if(($o.existing -ccontains '.') -cne $o.rootExists){return};if(-not $o.rootExists -and ($o.existing.Count -ne 0 -or $o.unexpected -ne 0)){return}}
  if(-not $c.before.rootExists){return};$survived=$c.after.rootExists -or $c.after.existing.Count -gt 0 -or $c.after.unexpected -gt 0
  # Path absence cannot prove that the original directory was not renamed or replaced.
  # Until file identity and deletion continuity are observed, absence cannot produce PASS.
  if(-not $survived){return}
  if($survived -and $Evidence.cleanupVerified){return}
  $state=if($survived){'FAIL'}else{'PASS'};$reason=if($survived){'CLEANUP_UNCONFIRMED'}else{'NONE'}
  $canonical=[ordered]@{control='fixtureCleanup';route=$(if($early){'SETUP_FAILURE'}else{'NORMAL'});setupReason=$(if($early){$c.setupReason}else{''});creation=$creationProof;fixture=$b.fixtureId;root=$b.rootIdentity;before=@($c.before.existing);attempted=$c.attempted;returned=$c.returned;operation=$c.reason;after=@($c.after.existing);unexpected=$c.after.unexpected;state=$state};$sha=[Security.Cryptography.SHA256]::Create();try{$json=ConvertTo-Json -InputObject $canonical -Compress -Depth 6;$proof=[BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($json))).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose()};if($VerdictInput.cases.fixtureCleanup.state -ceq 'NOT_RUN'){$VerdictInput.cases.fixtureCleanup=@{state=$state;evidence=$EvidenceClass;reason=$reason;proof=$proof}}
 }catch{return}
}
function Add-PhaseAStage3Evidence($VerdictInput,$Evidence,[string]$EvidenceClass,$ActorJournal=@()) {
  try {
    if ($EvidenceClass -cnotin @('LIVE_OBSERVED','SIMULATED_PASS') -or $Evidence -isnot [hashtable] -or $Evidence.cleanupVerified -isnot [bool]) { return }
    Add-PhaseAFixtureCleanupEvidence $VerdictInput $Evidence $EvidenceClass $ActorJournal
    Add-PhaseAAclEstablishmentEvidence $VerdictInput $Evidence $EvidenceClass $ActorJournal
    Add-PhaseAProtectedInventoryEvidence $VerdictInput $Evidence $EvidenceClass $ActorJournal
    # Recompute establishment independently; a preexisting verdict entry is not proof.
    $aclProof=New-PhaseAManagerVerdictInput $VerdictInput.commit $VerdictInput.runId
    Add-PhaseAAclEstablishmentEvidence $aclProof $Evidence $EvidenceClass $ActorJournal
    $est=$aclProof.cases.aclEstablishment
    if ($VerdictInput.cases.aclInspection.state -ceq 'NOT_RUN' -and $est.state -cin @('PASS','FAIL') -and $Evidence.ContainsKey('aclEstablishment') -and $Evidence.ContainsKey('aclCorroboration')) {
      $operations=@($Evidence.aclEstablishment | ForEach-Object {$_});$checks=@($Evidence.aclCorroboration | ForEach-Object {$_})
      if ($operations.Count -ge 2 -and $checks.Count -ge 2 -and $operations[1].role -ceq 'protected' -and $checks[1].role -ceq 'protected' -and ($est.state -ceq 'PASS' -or ($est.state -ceq 'FAIL' -and $operations.Count -eq 2 -and $operations[1].reason -ceq 'DESCRIPTOR_MISMATCH'))) {
        $payload=[ordered]@{control='aclInspection';target='protected';sequence=1;establishmentProof=$est.proof;state=$est.state}
        $sha=[Security.Cryptography.SHA256]::Create();try {$json=ConvertTo-Json -Compress -InputObject $payload;$hash=[BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($json))).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose()}
        $VerdictInput.cases.aclInspection=@{state=$est.state;evidence=$EvidenceClass;reason=$est.reason;proof=$hash}
      }
    }
    # Original access operations lack independent corroboration. Preserve the
    # separate fixture, ACL and inventory evidence already processed above.
    if($EvidenceClass -ceq 'LIVE_OBSERVED'){return}
    $probes=@($ActorJournal | Where-Object { $_.role -ceq 'legacy' -and $_.operation -ceq 'probe' })
    if ($probes.Count -ne 1) { return }
    $probe=$probes[0]; $probeObs=$probe.observation
    if ($probe.accountSid -cne $probe.tokenSid -or $probeObs.expectedSid -cne $probe.accountSid -or $probeObs.contained -isnot [bool] -or -not $probeObs.contained -or $probeObs.terminated -isnot [bool] -or -not $probeObs.terminated -or -not (Test-ActorObservation $probeObs 'legacy' 'allowed')) { return }
    if ($Evidence.ContainsKey('unauthorizedRead') -and $Evidence.ContainsKey('witnessControls') -and $Evidence.ContainsKey('aclInspection')) {
      $entry=$Evidence.unauthorizedRead; $controls=$Evidence.witnessControls; $acl=$Evidence.aclInspection
      $brokers=@($ActorJournal | Where-Object { $_.role -ceq 'broker' -and $_.operation -ceq 'probe' })
      if ($entry -is [hashtable] -and $controls -is [hashtable] -and $acl -is [hashtable] -and $brokers.Count -eq 1) {
        $broker=$brokers[0]; $bo=$broker.observation; $o=$entry.observation; $w=$entry.witness
        $source=if ($EvidenceClass -ceq 'LIVE_OBSERVED') {'LIVE'} else {'INJECTED'}
        $validBroker=($broker.accountSid -ceq $broker.tokenSid -and $broker.accountSid -cne $probe.accountSid -and $bo.expectedSid -ceq $broker.accountSid -and $bo.contained -is [bool] -and $bo.contained -and $bo.terminated -is [bool] -and $bo.terminated -and (Test-ActorObservation $bo 'broker' 'allowed'))
        $validAcl=($acl.protected -is [bool] -and $acl.protected -and $acl.expected -is [string] -and $acl.expected.Length -gt 0 -and $acl.expected -ceq $acl.actual)
        $goodControls=$true
        foreach ($spec in @(@('authorizedRead',$broker.accountSid,'protectedFile'),@('permissiveRead',$probe.accountSid,'controlFile'))) {
          if (-not $controls.ContainsKey($spec[0])) { $goodControls=$false; break }
          $c=$controls[$spec[0]]
          if ($c -isnot [hashtable] -or $c.status -cne 'OBSERVED' -or $c.reason -cne 'NONE' -or $c.evidence -cne $source -or $c.sid -cne $spec[1] -or $c.operation -cne 'Read' -or $c.target -cne $spec[2] -or $c.outcome -cne 'ALLOWED' -or $c.nativeError -isnot [int] -or $c.nativeError -ne 0 -or -not (Test-PhaseAReadWitnessCleanup $c $source) -or $c.handlesClosed -isnot [bool] -or -not $c.handlesClosed) { $goodControls=$false; break }
        }
        $goodWitness=($w -is [hashtable] -and $w.status -ceq 'OBSERVED' -and $w.reason -ceq 'NONE' -and $w.evidence -ceq $source -and $w.sid -ceq $probe.accountSid -and $w.operation -ceq 'Read' -and $w.target -ceq 'protectedFile' -and $w.nativeError -is [int] -and (($w.outcome -ceq 'ACCESS_DENIED' -and $w.nativeError -eq 5) -or ($w.outcome -ceq 'ALLOWED' -and $w.nativeError -eq 0)) -and (Test-PhaseAReadWitnessCleanup $w $source) -and $w.handlesClosed -is [bool] -and $w.handlesClosed)
        $goodActor=($o -is [hashtable] -and $o.errorCategory -ceq 'ACCESS_DENIED' -and $o.errorCode -is [int] -and $o.errorCode -eq 5 -and $o.expectedSid -ceq $probe.accountSid -and $o.contained -is [bool] -and $o.contained -and $o.terminated -is [bool] -and $o.terminated -and (Test-ActorObservation $o 'legacy' 'denied'))
        $goodResource=($entry.control -ceq 'unauthorizedRead' -and $entry.operation -ceq 'Read' -and $entry.target -ceq 'protectedFile' -and $entry.accountSid -ceq $probe.accountSid -and $entry.tokenSid -ceq $probe.accountSid -and $entry.beforeExists -is [bool] -and $entry.beforeExists -and $entry.parentExists -is [bool] -and $entry.parentExists -and $entry.afterExists -is [bool] -and $entry.afterExists -and $entry.beforeInventory -cmatch '^[0-9a-f]{64}$' -and $entry.beforeInventory -ceq $entry.afterInventory -and $entry.beforeDigest -cmatch '^[0-9a-f]{64}$')
        if($goodWitness -and $w.ContainsKey('execution') -and $w.execution -ceq 'PROCESS' -and $goodControls){$allNonces=@($w.nonce,$controls.authorizedRead.nonce,$controls.permissiveRead.nonce);if(@($allNonces | Select-Object -Unique).Count -ne 3){$goodControls=$false}}
        if ($validBroker -and $validAcl -and $goodControls -and $goodWitness -and $goodActor -and $goodResource -and $VerdictInput.cases.unauthorizedRead.state -ceq 'NOT_RUN') {
          $state=if($w.outcome -ceq 'ALLOWED'){'FAIL'}elseif($Evidence.cleanupVerified){'PASS'}else{'NOT_RUN'}
          if ($state -cne 'NOT_RUN') {
            $reason=if($state -ceq 'FAIL'){'VIOLATION'}else{'NONE'}
            $canonical=[ordered]@{control='unauthorizedRead';brokerSid=$broker.accountSid;legacySid=$probe.accountSid;pid=$o.expectedPid;createdAt=$o.observedCreatedAt;nonce=$o.expectedNonce;actorOutcome=$o.outcome;actorError=$o.errorCode;witnessOutcome=$w.outcome;witnessError=$w.nativeError;authorized=$controls.authorizedRead.outcome;permissive=$controls.permissiveRead.outcome;inventory=$entry.beforeInventory;digest=$entry.beforeDigest;acl=$acl.actual;cleanup=$Evidence.cleanupVerified;state=$state}
            if($w.ContainsKey('execution') -and $w.execution -ceq 'PROCESS'){$canonical['witnessProcess']=[ordered]@{pid=$w.pid;pipeClientPid=$w.pipeClientPid;createdAt=$w.createdAt;nonce=$w.nonce};$canonical['authorizedProcess']=[ordered]@{pid=$controls.authorizedRead.pid;pipeClientPid=$controls.authorizedRead.pipeClientPid;createdAt=$controls.authorizedRead.createdAt;nonce=$controls.authorizedRead.nonce};$canonical['permissiveProcess']=[ordered]@{pid=$controls.permissiveRead.pid;pipeClientPid=$controls.permissiveRead.pipeClientPid;createdAt=$controls.permissiveRead.createdAt;nonce=$controls.permissiveRead.nonce}}
            $sha=[Security.Cryptography.SHA256]::Create(); try {$json=ConvertTo-Json -Compress -InputObject $canonical;$hash=[BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($json))).Replace('-','').ToLowerInvariant()} finally {$sha.Dispose()}
            $VerdictInput.cases.unauthorizedRead=@{state=$state;evidence=$EvidenceClass;reason=$reason;proof=$hash}
          }
        }
      }
    }
    if ($Evidence.ContainsKey('witnessControls') -and $Evidence.ContainsKey('aclInspection')) {
      $controls=$Evidence.witnessControls; $acl=$Evidence.aclInspection
      $brokers=@($ActorJournal | Where-Object { $_.role -ceq 'broker' -and $_.operation -ceq 'probe' })
      if ($controls -is [hashtable] -and $acl -is [hashtable] -and $brokers.Count -eq 1) {
        $broker=$brokers[0];$bo=$broker.observation;$source=if($EvidenceClass -ceq 'LIVE_OBSERVED'){'LIVE'}else{'INJECTED'}
        $baseOk=($acl.protected -is [bool] -and $acl.protected -and $acl.expected -is [string] -and $acl.expected.Length -gt 0 -and $acl.expected -ceq $acl.actual -and $broker.accountSid -ceq $broker.tokenSid -and $broker.accountSid -cne $probe.accountSid -and $bo.expectedSid -ceq $broker.accountSid -and $bo.contained -is [bool] -and $bo.contained -and $bo.terminated -is [bool] -and $bo.terminated -and (Test-ActorObservation $bo 'broker' 'allowed'))
        foreach($spec in @(@('unauthorizedWrite','Overwrite','protectedFile','authorizedWrite','permissiveWrite','protectedFile','controlFile'),@('unauthorizedCreate','Create','deniedFile','authorizedCreate','permissiveCreate','authorizedProbeFile','controlProbeFile'))) {
          $key=$spec[0];if(-not $baseOk -or -not $Evidence.ContainsKey($key) -or -not $controls.ContainsKey($spec[3]) -or -not $controls.ContainsKey($spec[4])){continue}
          $entry=$Evidence[$key];if($entry -isnot [hashtable] -or $entry.control -cne $key -or $entry.operation -cne $spec[1] -or $entry.target -cne $spec[2] -or $entry.accountSid -cne $probe.accountSid -or $entry.tokenSid -cne $probe.accountSid -or $entry.beforeExists -isnot [bool] -or $entry.parentExists -isnot [bool] -or -not $entry.parentExists -or $entry.afterExists -isnot [bool] -or $entry.beforeInventory -cnotmatch '^[0-9a-f]{64}$' -or $entry.afterInventory -cnotmatch '^[0-9a-f]{64}$'){continue}
          if (($key -ceq 'unauthorizedWrite' -and -not $entry.beforeExists) -or ($key -ceq 'unauthorizedCreate' -and $entry.beforeExists)){continue}
          $controlsOk=$true
          foreach($cs in @(@($spec[3],$broker.accountSid,$spec[5]),@($spec[4],$probe.accountSid,$spec[6]))) {
            $c=$controls[$cs[0]]
            if($c -isnot [hashtable] -or $c.status -cne 'OBSERVED' -or $c.reason -cne 'NONE' -or $c.evidence -cne $source -or $c.sid -cne $cs[1] -or $c.operation -cne $spec[1] -or $c.target -cne $cs[2] -or $c.outcome -cne 'ALLOWED' -or $c.nativeError -isnot [int] -or $c.nativeError -ne 0 -or -not (Test-PhaseAReadWitnessCleanup $c $source) -or $c.handlesClosed -isnot [bool] -or -not $c.handlesClosed -or ($spec[1] -ceq 'Create' -and ($c.removed -isnot [bool] -or -not $c.removed))) {$controlsOk=$false;break}
          }
          if(-not $controlsOk){continue}
          $o=$entry.observation;$w=$entry.witness
          if($o -isnot [hashtable] -or $o.expectedSid -cne $probe.accountSid -or $o.errorCategory -cne 'ACCESS_DENIED' -or $o.errorCode -isnot [int] -or $o.errorCode -ne 5 -or $o.contained -isnot [bool] -or -not $o.contained -or $o.terminated -isnot [bool] -or -not $o.terminated -or -not (Test-ActorObservation $o 'legacy' 'denied')){continue}
          if($w -isnot [hashtable] -or $w.status -cne 'OBSERVED' -or $w.reason -cne 'NONE' -or $w.evidence -cne $source -or $w.sid -cne $probe.accountSid -or $w.operation -cne $spec[1] -or $w.target -cne $spec[2] -or -not (Test-PhaseAReadWitnessCleanup $w $source) -or $w.handlesClosed -isnot [bool] -or -not $w.handlesClosed -or $w.nativeError -isnot [int]){continue}
          if($w.ContainsKey('execution') -and $w.execution -ceq 'PROCESS'){
            $nonces=@($w.nonce,$controls[$spec[3]].nonce,$controls[$spec[4]].nonce)
            if(@($nonces | Select-Object -Unique).Count -ne 3){continue}
          }
          $state='NOT_RUN';$reason='NOT_RUN'
          if($w.outcome -ceq 'ACCESS_DENIED' -and $w.nativeError -eq 5 -and $Evidence.cleanupVerified -and $entry.beforeInventory -ceq $entry.afterInventory -and $entry.afterExists -eq $entry.beforeExists){$state='PASS';$reason='NONE'}
          elseif($w.outcome -ceq 'ALLOWED' -and $w.nativeError -eq 0 -and ($key -cne 'unauthorizedCreate' -or ($entry.afterExists -and $entry.beforeInventory -cne $entry.afterInventory))){$state='FAIL';$reason='VIOLATION'}
          if($state -ceq 'NOT_RUN' -or $VerdictInput.cases[$key].state -cne 'NOT_RUN'){continue}
          $canonical=[ordered]@{control=$key;operation=$entry.operation;target=$entry.target;brokerSid=$broker.accountSid;legacySid=$probe.accountSid;pid=$o.expectedPid;createdAt=$o.observedCreatedAt;nonce=$o.expectedNonce;actorOutcome=$o.outcome;actorError=$o.errorCode;witnessOutcome=$w.outcome;witnessError=$w.nativeError;beforeExists=$entry.beforeExists;afterExists=$entry.afterExists;beforeInventory=$entry.beforeInventory;afterInventory=$entry.afterInventory;acl=$acl.actual;cleanup=$Evidence.cleanupVerified;state=$state}
          if($w.ContainsKey('execution') -and $w.execution -ceq 'PROCESS'){
            $canonical['witnessProcess']=[ordered]@{pid=$w.pid;pipeClientPid=$w.pipeClientPid;createdAt=$w.createdAt;nonce=$w.nonce}
            $a=$controls[$spec[3]];$b=$controls[$spec[4]]
            $canonical['authorizedProcess']=[ordered]@{pid=$a.pid;pipeClientPid=$a.pipeClientPid;createdAt=$a.createdAt;nonce=$a.nonce}
            $canonical['permissiveProcess']=[ordered]@{pid=$b.pid;pipeClientPid=$b.pipeClientPid;createdAt=$b.createdAt;nonce=$b.nonce}
          }
          $sha=[Security.Cryptography.SHA256]::Create();try{$json=ConvertTo-Json -Compress -InputObject $canonical;$hash=[BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($json))).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose()}
          $VerdictInput.cases[$key]=@{state=$state;evidence=$EvidenceClass;reason=$reason;proof=$hash}
        }
      }
    }
    foreach($spec in @(@('unauthorizedWrite','Overwrite','protectedFile'),@('unauthorizedCreate','Create','deniedFile'))) {
      $key=$spec[0];if(-not $Evidence.ContainsKey($key)){continue};$entry=$Evidence[$key];if($entry -isnot [hashtable] -or $entry.control -cne $key -or $entry.operation -cne $spec[1] -or $entry.target -cne $spec[2] -or $entry.accountSid -cne $entry.tokenSid -or $entry.accountSid -cne $probe.accountSid -or $entry.parentExists -isnot [bool] -or -not $entry.parentExists -or $entry.beforeExists -isnot [bool] -or $entry.afterExists -isnot [bool] -or -not $entry.afterExists -or $entry.beforeInventory -cnotmatch '^[0-9a-f]{64}$' -or $entry.afterInventory -cnotmatch '^[0-9a-f]{64}$' -or $entry.beforeInventory -ceq $entry.afterInventory){continue}
      if (($key -ceq 'unauthorizedWrite' -and -not $entry.beforeExists) -or ($key -ceq 'unauthorizedCreate' -and $entry.beforeExists)){continue}
      $o=$entry.observation;if($o -isnot [hashtable] -or -not $o.ContainsKey('errorCategory') -or $o.errorCategory -cne 'NONE' -or -not $o.ContainsKey('errorCode') -or $o.errorCode -isnot [int] -or $o.errorCode -ne 0 -or $o.expectedSid -cne $entry.accountSid -or $o.contained -isnot [bool] -or -not $o.contained -or $o.terminated -isnot [bool] -or -not $o.terminated -or -not (Test-ActorObservation $o 'legacy' 'allowed')){continue}
      if($VerdictInput.cases[$key].state -cne 'NOT_RUN'){continue}
      $canonical=[ordered]@{control=$key;operation=$entry.operation;target=$entry.target;accountSid=$entry.accountSid;beforeExists=$entry.beforeExists;parentExists=$entry.parentExists;beforeInventory=$entry.beforeInventory;afterExists=$entry.afterExists;afterInventory=$entry.afterInventory;pid=$o.expectedPid;sid=$o.observedSid;createdAt=$o.observedCreatedAt;nonce=$o.expectedNonce;result=$o.outcome;error=$o.errorCategory;errorCode=$o.errorCode;cleanup=$Evidence.cleanupVerified}
      $sha=[Security.Cryptography.SHA256]::Create();try {$json=ConvertTo-Json -Compress -InputObject $canonical;$hash=[BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($json))).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose()}
      $VerdictInput.cases[$key]=@{state='FAIL';evidence=$EvidenceClass;reason='VIOLATION';proof=$hash}
    }
  } catch { return }
}
