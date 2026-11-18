Set-StrictMode -Version Latest
. "$PSScriptRoot/PhaseA.Stage2.ps1"
. "$PSScriptRoot/PhaseA.Inventory.ps1"
. "$PSScriptRoot/PhaseA.ReadProcess.ps1"
function Get-PhaseAOriginalReadCorrelation($Expected,$Candidate,$SeenRecordIds) {
  # Diagnostic only: these normalized fields are not authenticated Windows events.
  # In particular, nonce and file identity are manager-context fields, not 4663 fields.
  $out=@{kind='ORIGINAL_ACTOR_READ';status='UNVERIFIED';reason='INDEPENDENT_OBSERVATION_MISSING'}
  if($null -eq $Candidate){return $out}
  try {
    if($Candidate -isnot [hashtable] -or -not $Candidate.ContainsKey('source')){$out.reason='MALFORMED_OBSERVATION';return $out}
    if($Candidate.source -ceq 'LIVE'){$out.reason='TRUSTED_COLLECTOR_NOT_CONNECTED';return $out}
    if($Candidate.source -cne 'INJECTED' -or $Expected -isnot [hashtable]){$out.reason='MALFORMED_OBSERVATION';return $out}
    $keys=@('experiment','nonce','pid','createdAt','sid','authenticationId','targetId','fileId')
    foreach($key in $keys){if(-not $Expected.ContainsKey($key) -or -not $Candidate.ContainsKey($key)){$out.reason='MALFORMED_OBSERVATION';return $out}}
    foreach($key in @('recordId','completed','eventLoss','nativeOutcome')){if(-not $Candidate.ContainsKey($key)){$out.reason='MALFORMED_OBSERVATION';return $out}}
    if(-not $Expected.ContainsKey('actorOutcome') -or $Candidate.recordId -isnot [int] -or $Candidate.recordId -le 0 -or $Candidate.completed -isnot [bool] -or $Candidate.eventLoss -isnot [bool]){$out.reason='MALFORMED_OBSERVATION';return $out}
    if($Candidate.experiment -cne $Expected.experiment){$out.reason='EXPERIMENT_MISMATCH';return $out}
    if($Candidate.nonce -cne $Expected.nonce){$out.reason='NONCE_MISMATCH';return $out}
    if($Candidate.pid -cne $Expected.pid -or $Candidate.createdAt -cne $Expected.createdAt){$out.reason='PROCESS_MISMATCH';return $out}
    if($Candidate.sid -cne $Expected.sid -or $Candidate.authenticationId -cne $Expected.authenticationId){$out.reason='TOKEN_MISMATCH';return $out}
    if($Candidate.targetId -cne $Expected.targetId -or $Candidate.fileId -cne $Expected.fileId){$out.reason='TARGET_MISMATCH';return $out}
    if(@($SeenRecordIds) -contains $Candidate.recordId){$out.reason='REPLAYED_EVENT';return $out}
    if($Candidate.eventLoss){$out.reason='EVENT_LOSS';return $out}
    if(-not $Candidate.completed){$out.reason='COMPLETION_MISSING';return $out}
    if($Candidate.nativeOutcome -cne $Expected.actorOutcome){$out.reason='CONTRADICTORY_OBSERVATION';return $out}
    # A synthetic open or an absent read event cannot establish a read or denial.
    if($Candidate.nativeOutcome -ceq 'DENIED'){$out.reason='DENIAL_NOT_INDEPENDENTLY_OBSERVED';return $out}
    if(-not $Candidate.ContainsKey('eventKind') -or $Candidate.eventKind -cne 'READ'){$out.reason='READ_OPERATION_MISSING';return $out}
    if(-not $Candidate.ContainsKey('requestedBytes') -or -not $Candidate.ContainsKey('completedBytes') -or $Candidate.requestedBytes -isnot [int] -or $Candidate.completedBytes -isnot [int] -or $Candidate.requestedBytes -le 0 -or $Candidate.completedBytes -lt 0 -or $Candidate.completedBytes -gt $Candidate.requestedBytes){$out.reason='INVALID_READ_COMPLETION';return $out}
    $out.reason='INJECTED_MATCH_NOT_PROOF';return $out
  } catch {$out.reason='MALFORMED_OBSERVATION';return $out}
}
function Invoke-PhaseATrustedAccess([hashtable]$Backend,[hashtable]$Fixture,$Token,[string]$ExpectedSid,[string]$Operation,[string]$TargetId,[string]$EvidenceClass) {
  $failure=@{status='UNVERIFIED';reason='WITNESS_UNAVAILABLE';evidence=$EvidenceClass}
  # LIVE results cannot be accepted until the original actor operation is
  # independently corroborated; do not invoke an unverified witness probe.
  if ($EvidenceClass -ceq 'LIVE') {
    return @{status='UNVERIFIED';reason='ORIGINAL_OPERATION_UNCORROBORATED';evidence='LIVE'}
  }
  try {
    if ($EvidenceClass -cnotin @('LIVE','INJECTED') -or $Token.sid -cne $ExpectedSid -or [string]::IsNullOrWhiteSpace($ExpectedSid) -or $Operation -cnotin @('Read','Overwrite','Create') -or $TargetId -cnotin @('protectedFile','deniedFile','controlFile','authorizedProbeFile','controlProbeFile')) { return $failure }
    if (($Operation -ceq 'Create' -and $TargetId -cnotin @('deniedFile','authorizedProbeFile','controlProbeFile')) -or ($Operation -ceq 'Overwrite' -and $TargetId -cnotin @('protectedFile','controlFile')) -or ($Operation -ceq 'Read' -and $TargetId -cnotin @('protectedFile','controlFile'))) { return $failure }
    $path=$Fixture[$TargetId]; if ([string]::IsNullOrWhiteSpace([string]$path)) { return $failure }
    if ($Operation -ceq 'Create') { $parent=if ($TargetId -ceq 'controlProbeFile') { $Fixture.controlDir } else { $Fixture.protectedDir }; if (-not (& $Backend.DirectoryExists $parent) -or (& $Backend.Exists $path)) { return $failure } }
    elseif (-not (& $Backend.Exists $path)) { return $failure }
    $root=if ($Fixture.ContainsKey('root')) { $Fixture.root } else { '' }
    $raw=& $Backend.Probe $Token $ExpectedSid $Operation $path $root
    if ($raw -isnot [hashtable] -or $raw.sid -cne $ExpectedSid -or $raw.operation -cne $Operation -or $raw.attempted -isnot [bool] -or -not $raw.attempted -or $raw.allowed -isnot [bool] -or $raw.error -isnot [int] -or $raw.handlesClosed -isnot [bool] -or -not $raw.handlesClosed) { return $failure }
    $processEvidence=($raw.ContainsKey('execution') -and $raw.execution -ceq 'PROCESS')
    if($processEvidence) {if($raw.processVerified -isnot [bool] -or -not $raw.processVerified -or $raw.terminated -isnot [bool] -or -not $raw.terminated){return $failure}}
    elseif($raw.impersonated -isnot [bool] -or -not $raw.impersonated -or $raw.reverted -isnot [bool] -or -not $raw.reverted){return $failure}
    if($EvidenceClass -ceq 'LIVE' -and -not $processEvidence){return $failure}
    $outcome=if ($raw.allowed -and $raw.error -eq 0) {'ALLOWED'} elseif (-not $raw.allowed -and $raw.error -eq 5) {'ACCESS_DENIED'} elseif (-not $raw.allowed -and $raw.error -in @(2,3,6,32,80,87,123,183)) { return @{status='UNVERIFIED';reason='NATIVE_ERROR';evidence=$EvidenceClass;operation=$Operation;target=$TargetId;nativeError=$raw.error} } else { return $failure }
    $result=@{status='OBSERVED';reason='NONE';evidence=$EvidenceClass;sid=$raw.sid;operation=$Operation;target=$TargetId;outcome=$outcome;nativeError=$raw.error;handlesClosed=$raw.handlesClosed}; if($processEvidence){$result.execution='PROCESS';$result.processVerified=$raw.processVerified;$result.terminated=$raw.terminated;$result.pid=$raw.pid;$result.createdAt=$raw.createdAt;$result.pipeClientPid=$raw.pipeClientPid;$result.nonce=$raw.nonce}else{$result.reverted=$raw.reverted};return $result
  } catch { $code=$_.Exception.GetBaseException().Message; if ($code -ceq 'STAGE2_CHILD_UNCONFIRMED') { throw }; if($code -ceq 'WITNESS_CLEANUP_FAILED'){throw}; if($code -ceq 'WITNESS_TIMEOUT') {return @{status='UNVERIFIED';reason=$code;evidence=$EvidenceClass}}; return $failure }
}
function Get-PhaseAInventorySnapshot($Backend,$Fixture,$Account,[string]$Control,[string]$Phase) {
  $positions=@{unauthorizedRead=0;unauthorizedWrite=1;unauthorizedCreate=2;unauthorizedRename=3;unauthorizedDelete=4}
  $failed=@{status='ERROR';reason='COLLECTION_FAILED';control=$Control;phase=$Phase}
  try {
    if(-not $positions.ContainsKey($Control) -or $Phase -cnotin @('BEFORE','AFTER') -or $Fixture -isnot [hashtable] -or -not $Fixture.ContainsKey('root') -or -not $Fixture.ContainsKey('protectedDir') -or $Account.sid -isnot [string]){return $failed}
    $root=[IO.Path]::GetFullPath($Fixture.root);$parent=[IO.Path]::GetFullPath($Fixture.parent).TrimEnd('\');$fixtureId=[IO.Path]::GetFileName($root)
    if($fixtureId -cnotmatch '^ether-phase-a-store-[0-9a-f]{32}$' -or -not $root.StartsWith($parent+'\',[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFullPath($Fixture.protectedDir) -cne [IO.Path]::Combine($root,'protected')){return $failed}
    $source=if($Backend.ContainsKey('WitnessEvidence') -and $Backend.WitnessEvidence -ceq 'LIVE'){'LIVE'}else{'INJECTED'}
    if($source -ceq 'LIVE') {foreach($path in @($root,$Fixture.protectedDir)){if(-not [IO.Directory]::Exists($path) -or (((Get-Item -LiteralPath $path -Force -ErrorAction Stop).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)){return $failed}}}
    $snapshot=& $Backend.InventoryDetailed $Fixture
    if($snapshot -isnot [hashtable] -or $snapshot.digest -cnotmatch '^[0-9a-f]{64}$' -or (Get-PhaseAInventoryEntriesDigest $snapshot.entries) -cne $snapshot.digest){return $failed}
    if($source -ceq 'LIVE' -and $parent -cne [IO.Path]::GetFullPath([Environment]::GetFolderPath([Environment+SpecialFolder]::CommonApplicationData)).TrimEnd('\')){return $failed}
    return @{status='OBSERVED';reason='NONE';source=$source;rootIdentity=$root;fixtureId=$fixtureId;control=$Control;position=$positions[$Control];phase=$Phase;actorSid=$Account.sid;digest=$snapshot.digest;entries=$snapshot.entries}
  } catch {return $failed}
}
function Invoke-PhaseATrackedDeniedOperation($Account,$Token,[hashtable]$ActorBackend,[hashtable]$FixtureBackend,$Fixture,[hashtable]$Journal,[string]$Control,[string]$Operation,[string]$Target,[string]$TargetId) {
  $entry=@{control=$Control;operation=$Operation;target=$TargetId;accountSid=$Account.sid;tokenSid=$Token.sid;beforeExists=$null;parentExists=$null;beforeInventory=$null;beforeDigest=$null;afterExists=$null;afterInventory=$null;observation=$null;witness=$null}
  $Journal[$Control]=$entry
  # The actor's self-report and a separate access witness do not establish the
  # original read. Retain the gap even if a later actor or witness aborts.
  if($Control -ceq 'unauthorizedRead' -and $Operation -ceq 'Read'){
    $entry.originalReadEvidence=Get-PhaseAOriginalReadCorrelation $null $null @()
  }
  $entry.beforeExists=& $FixtureBackend.Exists $Target
  if ($FixtureBackend.ContainsKey('DirectoryExists') -and $Fixture.ContainsKey('protectedDir')) { $entry.parentExists=& $FixtureBackend.DirectoryExists $Fixture.protectedDir }
  try { $entry.beforeInventory=& $FixtureBackend.Inventory $Fixture } catch { $entry['beforeDetails']=@{status='ERROR';reason='COLLECTION_FAILED';control=$Control;phase='BEFORE'}; throw 'INVENTORY_COLLECTION_FAILED' }
  if($FixtureBackend.ContainsKey('InventoryDetailed')){$entry['beforeDetails']=Get-PhaseAInventorySnapshot $FixtureBackend $Fixture $Account $Control 'BEFORE'}
  if ($Operation -ceq 'Read' -and $entry.beforeExists -ceq $true) { $entry.beforeDigest=& $FixtureBackend.Digest $Target }
  $original=$ActorBackend.Run
  $capture={param($a,$t,$op,$path) $value=& $original $a $t $op $path; if($value -is [hashtable]){$entry.observation=$value}; return $value}.GetNewClosure()
  try {
    $value=Invoke-PhaseAActorOperation $Account $Token @{Run=$capture} $Operation $Target 'denied'
    if ($Operation -cin @('Read','Overwrite','Create') -and $FixtureBackend.ContainsKey('Probe')) {
      $class=if ($FixtureBackend.ContainsKey('WitnessEvidence') -and $FixtureBackend.WitnessEvidence -ceq 'LIVE') {'LIVE'} else {'INJECTED'}
      try{$entry.witness=Invoke-PhaseATrustedAccess $FixtureBackend $Fixture $Token $Account.sid $Operation $TargetId $class}
      catch {
        $ex=$_.Exception.GetBaseException();$prior=$ex.Data['PhaseAWitnessOutcome']
        if($ex.Message -cin @('WITNESS_CLEANUP_FAILED','STAGE2_CHILD_UNCONFIRMED') -and $prior -is [hashtable] -and $prior.ContainsKey('operation') -and $prior.ContainsKey('target') -and $prior.ContainsKey('allowed') -and $prior.ContainsKey('nativeError') -and $prior.operation -ceq $Operation -and $prior.target -ceq $TargetId -and $prior.allowed -is [bool] -and $prior.nativeError -is [int]){
          $entry.witness=@{status='UNVERIFIED';reason=$(if($ex.Message -ceq 'STAGE2_CHILD_UNCONFIRMED'){'CHILD_UNCONFIRMED'}else{'CLEANUP_FAILED'});evidence=$class;operation=$Operation;target=$TargetId;provisionalOutcome=$(if($prior.allowed){'ALLOWED'}else{'DENIED'});nativeError=$prior.nativeError}
        }
        throw
      }
      if ($entry.witness.status -cne 'OBSERVED' -or $entry.witness.outcome -cne 'ACCESS_DENIED') { throw 'STAGE3_WITNESS_UNVERIFIED' }
    }
    return $value
  }
  finally {
    try { $entry.afterExists=& $FixtureBackend.Exists $Target; $entry.afterInventory=& $FixtureBackend.Inventory $Fixture; if($FixtureBackend.ContainsKey('InventoryDetailed')){$entry['afterDetails']=Get-PhaseAInventorySnapshot $FixtureBackend $Fixture $Account $Control 'AFTER'} } catch { $entry['afterDetails']=@{status='ERROR';reason='COLLECTION_FAILED';control=$Control;phase='AFTER'} }
  }
}
function Get-PhaseAManagerAclObservation($Fixture,[string]$Role,$Record,[string]$Source) {
  $out=@{status='UNVERIFIED';reason='OBSERVATION_FAILED';fixtureId='';role=$Role;relative='';sequence=-1;descriptor='';protected=$false;source=$Source}
  try {
    if($Source -cnotin @('LIVE','INJECTED') -or $Fixture -isnot [hashtable] -or $Record -isnot [hashtable]) { return $out }
    $roles=@{root=@('.',0);protected=@('protected',1);control=@('control',2)}; if(-not $roles.ContainsKey($Role)){return $out}
    $root=[IO.Path]::GetFullPath($Fixture.root).TrimEnd('\');$id=[IO.Path]::GetFileName($root);$relative=$roles[$Role][0];$position=$roles[$Role][1]
    if($id -cnotmatch '^ether-phase-a-store-[0-9a-f]{32}$' -or $Record.fixtureId -cne $id -or $Record.role -cne $Role -or $Record.relative -cne $relative -or $Record.sequence -ne $position){return $out}
    if($Source -ceq 'LIVE' -and [IO.Path]::GetDirectoryName($root) -cne [IO.Path]::GetFullPath([Environment]::GetFolderPath([Environment+SpecialFolder]::CommonApplicationData)).TrimEnd('\')){return $out}
    $out.fixtureId=$id;$out.relative=$relative;$out.sequence=$position
    $path=if($relative -ceq '.'){$root}else{[IO.Path]::Combine($root,$relative)}
    foreach($p in @($root,$path)){ $item=Get-Item -LiteralPath $p -Force -ErrorAction Stop; if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or -not $item.PSIsContainer){return $out} }
    $acl=Get-Acl -LiteralPath $path -ErrorAction Stop;$out.descriptor=$acl.GetSecurityDescriptorSddlForm([Security.AccessControl.AccessControlSections]::Access);$out.protected=[bool]$acl.AreAccessRulesProtected;$out.status='OBSERVED';$out.reason='NONE';return $out
  } catch { return $out }
}
function Invoke-PhaseAStage3($Accounts,$Tokens,[hashtable]$FixtureBackend,[hashtable]$ActorBackend,[hashtable]$EvidenceSink=@{}) {
  $cases=@{acl=$false;authorizedRead=$false;authorizedCreate=$false;authorizedReadback=$false;
    unauthorizedRead=$false;unauthorizedWrite=$false;unauthorizedCreate=$false;proposedDelete=$false;proposedRename=$false;inventory=$false;insecureRejected=$false;fixtureCleanup=$false}
  $evidence=@{cleanupVerified=$false}; $EvidenceSink['evidence']=$evidence; $EvidenceSink['cases']=$cases; $fixture=$null; $status='STAGE3_SETUP_FAILED'; $unconfirmed=$false; $cleanupBlocked=$false
  try {
    $observer={param($f,$record) if($FixtureBackend.ContainsKey('ObserveAcl')) { try {$o=& $FixtureBackend.ObserveAcl $f $record.role $record; if(-not $evidence.ContainsKey('aclCorroboration')){$evidence['aclCorroboration']=New-Object 'System.Collections.Generic.List[object]'};$evidence.aclCorroboration.Add($o);if($o.status -ceq 'OBSERVED' -and -not $evidence.ContainsKey('aclFixtureBinding')){$evidence['aclFixtureBinding']=@{fixtureId=$o.fixtureId;rootIdentity=[IO.Path]::GetFullPath($f.root).TrimEnd('\');brokerSid=$Accounts[0].sid;legacySid=$Accounts[1].sid;source=$o.source}}}catch{} }}.GetNewClosure()
    $cleanupObserver={param($f,$phase) if(-not $FixtureBackend.ContainsKey('CleanupObservation')){return $null};$o=& $FixtureBackend.CleanupObservation $f $phase;if($o -is [hashtable] -and $o.status -ceq 'OBSERVED' -and -not $evidence.ContainsKey('setupFixtureBinding')){$evidence['setupFixtureBinding']=@{fixtureId=$o.fixtureId;rootIdentity=$o.rootIdentity;brokerSid=$Accounts[0].sid;legacySid=$Accounts[1].sid;source=$o.source}};return $o}.GetNewClosure()
    $fixture=& $FixtureBackend.Setup $Accounts $evidence $observer $cleanupObserver
    if ($null -eq $fixture -or ($fixture.aclInspected -isnot [bool] -or -not $fixture.aclInspected)) { throw 'STAGE3_ACL_REJECTED' }
    if ($fixture -is [hashtable] -and $fixture.ContainsKey('aclEvidence')) { $evidence['aclInspection']=$fixture.aclEvidence }
    $cases.acl=$true; $status='STAGE3_CASE_FAILED'
    if (-not (& $FixtureBackend.Exists $fixture.protectedFile) -or -not (& $FixtureBackend.Exists $fixture.controlFile) -or
        (& $FixtureBackend.Exists $fixture.newFile)) { throw 'fixture paths invalid' }
    if ((& $FixtureBackend.Digest $fixture.protectedFile) -cne $fixture.initialDigest) { throw 'initial digest mismatch' }
    if ($FixtureBackend.ContainsKey('Probe')) {
      $class=if ($FixtureBackend.ContainsKey('WitnessEvidence') -and $FixtureBackend.WitnessEvidence -ceq 'LIVE') {'LIVE'} else {'INJECTED'}
      $controls=@{}; $evidence['witnessControls']=$controls
      foreach ($spec in @(@('authorizedRead',0,'Read','protectedFile'),@('permissiveRead',1,'Read','controlFile'),@('authorizedWrite',0,'Overwrite','protectedFile'),@('permissiveWrite',1,'Overwrite','controlFile'),@('authorizedCreate',0,'Create','authorizedProbeFile'),@('permissiveCreate',1,'Create','controlProbeFile'))) {
        $name=$spec[0];$index=[int]$spec[1];$op=$spec[2];$targetId=$spec[3]
        $control=Invoke-PhaseATrustedAccess $FixtureBackend $fixture $Tokens[$index] $Accounts[$index].sid $op $targetId $class
        $controls[$name]=$control
        if ($control.status -cne 'OBSERVED' -or $control.outcome -cne 'ALLOWED') { throw 'STAGE3_WITNESS_UNVERIFIED' }
        if ($op -ceq 'Create') {
          if (-not $FixtureBackend.ContainsKey('RemoveProbe')) { throw 'STAGE3_WITNESS_UNVERIFIED' }
          $null=& $FixtureBackend.RemoveProbe $fixture $targetId
          if (& $FixtureBackend.Exists $fixture[$targetId]) { throw 'STAGE3_WITNESS_UNVERIFIED' }
          $control['removed']=$true
        }
      }
    }
    $read=Invoke-PhaseAActorOperation $Accounts[0] $Tokens[0] $ActorBackend 'Read' $fixture.protectedFile 'allowed'
    if ($read.digest -cne $fixture.initialDigest) { throw 'authorized read mismatch' }; $cases.authorizedRead=$true
    $null=Invoke-PhaseAActorOperation $Accounts[0] $Tokens[0] $ActorBackend 'Create' $fixture.newFile 'allowed'
    if (-not (& $FixtureBackend.Exists $fixture.newFile) -or (& $FixtureBackend.Digest $fixture.newFile) -cne $fixture.writeDigest) { throw 'authorized create mismatch' }
    $cases.authorizedCreate=$true
    $readback=Invoke-PhaseAActorOperation $Accounts[0] $Tokens[0] $ActorBackend 'Read' $fixture.newFile 'allowed'
    if ($readback.digest -cne $fixture.writeDigest) { throw 'authorized readback mismatch' }; $cases.authorizedReadback=$true
    try { $before=& $FixtureBackend.Inventory $fixture } catch { $evidence['inventoryBaseline']=@{status='ERROR';reason='COLLECTION_FAILED';control='unauthorizedRead';phase='BEFORE'}; throw 'INVENTORY_COLLECTION_FAILED' }
    if($FixtureBackend.ContainsKey('InventoryDetailed')){$evidence['inventoryBaseline']=Get-PhaseAInventorySnapshot $FixtureBackend $fixture $Accounts[1] 'unauthorizedRead' 'BEFORE'}
    if ([string]::IsNullOrWhiteSpace([string]$before)) { throw 'inventory missing' }
    if (-not (& $FixtureBackend.Exists $fixture.protectedFile)) { throw 'protected file missing' }
    $null=Invoke-PhaseATrackedDeniedOperation $Accounts[1] $Tokens[1] $ActorBackend $FixtureBackend $fixture $evidence 'unauthorizedRead' 'Read' $fixture.protectedFile 'protectedFile'; $cases.unauthorizedRead=$true
    if (-not (& $FixtureBackend.Exists $fixture.protectedFile)) { throw 'protected file missing' }
    $null=Invoke-PhaseATrackedDeniedOperation $Accounts[1] $Tokens[1] $ActorBackend $FixtureBackend $fixture $evidence 'unauthorizedWrite' 'Overwrite' $fixture.protectedFile 'protectedFile'; $cases.unauthorizedWrite=$true
    if ((& $FixtureBackend.Inventory $fixture) -cne $before) { throw 'inventory changed after write' }
    $deniedPath=$fixture.deniedFile
    if ([string]::IsNullOrWhiteSpace([string]$deniedPath) -or (& $FixtureBackend.Exists $deniedPath)) { throw 'create control invalid' }
    $null=Invoke-PhaseATrackedDeniedOperation $Accounts[1] $Tokens[1] $ActorBackend $FixtureBackend $fixture $evidence 'unauthorizedCreate' 'Create' $deniedPath 'deniedFile'; $cases.unauthorizedCreate=$true
    if ((& $FixtureBackend.Inventory $fixture) -cne $before) { throw 'inventory changed after create' }; $cases.inventory=$true
    if (-not (& $FixtureBackend.Exists $fixture.protectedFile) -or (& $FixtureBackend.Exists ($fixture.protectedFile+'.renamed'))) { throw 'rename fixture invalid' }
    $null=Invoke-PhaseATrackedDeniedOperation $Accounts[1] $Tokens[1] $ActorBackend $FixtureBackend $fixture $evidence 'unauthorizedRename' 'Rename' $fixture.protectedFile 'protectedFile'
    if ((& $FixtureBackend.Inventory $fixture) -cne $before) { throw 'inventory changed after rename' }; $cases.proposedRename=$true
    if (-not (& $FixtureBackend.Exists $fixture.protectedFile)) { throw 'delete fixture invalid' }
    $null=Invoke-PhaseATrackedDeniedOperation $Accounts[1] $Tokens[1] $ActorBackend $FixtureBackend $fixture $evidence 'unauthorizedDelete' 'Delete' $fixture.protectedFile 'protectedFile'
    if ((& $FixtureBackend.Inventory $fixture) -cne $before) { throw 'inventory changed after delete' }; $cases.proposedDelete=$true
    $insecure=Invoke-PhaseAActorOperation $Accounts[1] $Tokens[1] $ActorBackend 'Read' $fixture.controlFile 'allowed'
    if (Test-ActorObservation $insecure $Accounts[1].role 'denied') { throw 'insecure control accepted' }; $cases.insecureRejected=$true
    $status='STAGE3_COMPLETE'
  } catch {
    $base=$_.Exception.GetBaseException().Message
    if ($base -ceq 'STAGE2_CHILD_UNCONFIRMED') { $unconfirmed=$true }
    elseif ($base -cin @('STAGE2_CLEANUP_FAILED','WITNESS_CLEANUP_FAILED')) { $cleanupBlocked=$true; $status='STAGE3_CLEANUP_FAILED' }
    elseif ($base -ceq 'STAGE3_ACL_REJECTED') { $status='STAGE3_ACL_REJECTED' }
    elseif ($base -ceq 'STAGE3_CLEANUP_FAILED') { $status='STAGE3_CLEANUP_FAILED' }
  } finally {
    if ($null -ne $fixture -and $FixtureBackend.ContainsKey('CleanupObservation')) {
      $evidence['fixtureCleanup']=@{fixtureId='';rootIdentity='';parentIdentity='';identityAssurance='PATH_ONLY';expected=@('.','protected','control','protected/original.bin','protected/committed.bin','protected/rejected.bin','protected/original.bin.renamed','control/original.bin','protected/witness-authorized.bin','control/witness-permissive.bin');authorized=(-not ($unconfirmed -or $cleanupBlocked));attempted=$false;returned=$false;reason=$(if($unconfirmed){'CHILD_UNCONFIRMED'}elseif($cleanupBlocked){'PROCESS_CLEANUP_FAILED'}else{'NOT_ATTEMPTED'});before=$null;after=$null}
      try {$evidence.fixtureCleanup.rootIdentity=[IO.Path]::GetFullPath($fixture.root).TrimEnd('\');$evidence.fixtureCleanup.parentIdentity=[IO.Path]::GetFullPath($fixture.parent).TrimEnd('\');$evidence.fixtureCleanup.fixtureId=[IO.Path]::GetFileName($evidence.fixtureCleanup.rootIdentity)} catch {}
    }
    if ($null -ne $fixture -and -not $unconfirmed -and -not $cleanupBlocked) {
      try {
        if ($evidence.ContainsKey('fixtureCleanup')) {
          $cleanup=$evidence.fixtureCleanup;$cleanup.before=& $FixtureBackend.CleanupObservation $fixture 'BEFORE'
          if ($cleanup.before.status -cne 'OBSERVED' -or -not $cleanup.before.rootExists) { $cleanup.reason='PRECHECK_FAILED'; throw 'STAGE3_CLEANUP_FAILED' }
          $cleanup.attempted=$true
        }
        $null=& $FixtureBackend.Cleanup $fixture
        if ($evidence.ContainsKey('fixtureCleanup')) { $cleanup.returned=$true;$cleanup.reason='NONE' }
        $cases.fixtureCleanup=$true
        if ($FixtureBackend.ContainsKey('CleanupVerified')) { $evidence.cleanupVerified=(& $FixtureBackend.CleanupVerified $fixture) -ceq $true }
      } catch { if($evidence.ContainsKey('fixtureCleanup') -and $cleanup.attempted){$cleanup.reason='CLEANUP_FAILED'}; $status='STAGE3_CLEANUP_FAILED' }
      finally {
        if ($evidence.ContainsKey('fixtureCleanup') -and $cleanup.attempted) {
          try { $cleanup.after=& $FixtureBackend.CleanupObservation $fixture 'AFTER';if($cleanup.after.status -cne 'OBSERVED' -or $cleanup.after.rootExists -or $cleanup.after.existing.Count -ne 0){$evidence.cleanupVerified=$false;$cases.fixtureCleanup=$false;$status='STAGE3_CLEANUP_FAILED'} } catch { $cleanup.after=$null;$evidence.cleanupVerified=$false;$cases.fixtureCleanup=$false;$status='STAGE3_CLEANUP_FAILED' }
        }
      }
    }
  }
  if ($unconfirmed) { throw 'STAGE2_CHILD_UNCONFIRMED' }
  if ($cleanupBlocked) { throw 'STAGE2_RESOURCE_UNCONFIRMED' }
  if ($status -ceq 'STAGE3_COMPLETE' -and @($cases.Values | Where-Object { $_ -isnot [bool] -or -not $_ }).Count -ne 0) { $status='STAGE3_CASE_FAILED' }
  return @{status=$status;cases=$cases;evidence=$evidence}
}
function Get-PhaseAFixtureCleanupObservation($Fixture,[string]$Phase,[string]$Source) {
  $result=@{status='UNVERIFIED';reason='OBSERVATION_FAILED';phase=$Phase;source=$Source;fixtureId='';rootIdentity='';parentIdentity='';identityAssurance='PATH_ONLY';rootExists=$false;existing=@();unexpected=0}
  try {
    if($Fixture -isnot [hashtable] -or $Phase -cnotin @('BEFORE','AFTER') -or $Source -cnotin @('LIVE','INJECTED')){return $result}
    $root=[IO.Path]::GetFullPath($Fixture.root).TrimEnd('\');$parent=[IO.Path]::GetFullPath($Fixture.parent).TrimEnd('\');$id=[IO.Path]::GetFileName($root)
    if($id -cnotmatch '^ether-phase-a-store-[0-9a-f]{32}$' -or [IO.Path]::GetDirectoryName($root) -cne $parent){return $result}
    if($Source -ceq 'LIVE' -and $parent -cne [IO.Path]::GetFullPath([Environment]::GetFolderPath([Environment+SpecialFolder]::CommonApplicationData)).TrimEnd('\')){return $result}
    $expected=[ordered]@{root='.';protectedDir='protected';controlDir='control';protectedFile='protected/original.bin';newFile='protected/committed.bin';deniedFile='protected/rejected.bin';controlFile='control/original.bin';authorizedProbeFile='protected/witness-authorized.bin';controlProbeFile='control/witness-permissive.bin'}
    foreach($key in $expected.Keys){if($key -ceq 'root'){continue};$path=[IO.Path]::GetFullPath($Fixture[$key]);$want=[IO.Path]::GetFullPath((Join-Path $root $expected[$key].Replace('/','\')));if($path -cne $want){return $result}}
    $result.fixtureId=$id;$result.rootIdentity=$root;$result.parentIdentity=$parent;$existing=New-Object 'System.Collections.Generic.List[string]'
    foreach($relative in @('.','protected','control','protected/original.bin','protected/committed.bin','protected/rejected.bin','protected/original.bin.renamed','control/original.bin','protected/witness-authorized.bin','control/witness-permissive.bin')) {
      $path=if($relative -ceq '.'){$root}else{Join-Path $root $relative.Replace('/','\')};$item=$null
      try {$item=Get-Item -LiteralPath $path -Force -ErrorAction Stop} catch [System.Management.Automation.ItemNotFoundException] {continue}
      if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){$result.reason='REPARSE_REJECTED';return $result}
      $existing.Add($relative)
    }
    $result.existing=$existing.ToArray();$result.rootExists=($result.existing -ccontains '.')
    if($result.rootExists){foreach($relative in @('.','protected','control')){$dir=if($relative -ceq '.'){$root}else{Join-Path $root $relative};if([IO.Directory]::Exists($dir)){foreach($entry in [IO.Directory]::EnumerateFileSystemEntries($dir)){$name=[IO.Path]::GetFileName($entry);$rel=if($relative -ceq '.') {$name}else{$relative+'/'+$name};if($rel -cnotin @('protected','control','protected/original.bin','protected/committed.bin','protected/rejected.bin','protected/original.bin.renamed','control/original.bin','protected/witness-authorized.bin','control/witness-permissive.bin')){$result.unexpected++};if($result.unexpected -gt 128){$result.reason='ENTRY_LIMIT';return $result}}}}}
    $result.status='OBSERVED';$result.reason='NONE';return $result
  }catch{return $result}
}
function Set-PhaseAFixtureAcl([string]$Path,[string[]]$FullSids,[string[]]$ReadSids,[hashtable]$Record=@{},[hashtable]$Io=@{}) {
  $acl=New-Object Security.AccessControl.DirectorySecurity
  $acl.SetAccessRuleProtection($true,$false)
  foreach ($item in @(@{sids=$FullSids;rights='FullControl'},@{sids=$ReadSids;rights='ReadAndExecute'})) {
    foreach ($sidText in $item.sids) {
      $sid=New-Object Security.Principal.SecurityIdentifier($sidText)
      $rule=New-Object Security.AccessControl.FileSystemAccessRule($sid,$item.rights,'ContainerInherit,ObjectInherit','None','Allow')
      $acl.AddAccessRule($rule)
    }
  }
  $section=[Security.AccessControl.AccessControlSections]::Access
  $expectedSddl=$acl.GetSecurityDescriptorSddlForm($section)
  $Record.expected=$expectedSddl; $Record.expectedProtected=$true
  $Record.attempted=$true
  try { if($Io.ContainsKey('Apply')) { $null=& $Io.Apply $Path $acl } else { Set-Acl -LiteralPath $Path -AclObject $acl -ErrorAction Stop }; $Record.applied=$true }
  catch { $Record.reason='APPLY_FAILED'; throw 'STAGE3_ACL_REJECTED' }
  try { $actual=if($Io.ContainsKey('Read')) { & $Io.Read $Path } else { Get-Acl -LiteralPath $Path -ErrorAction Stop }; $actualSddl=$actual.GetSecurityDescriptorSddlForm($section); $Record.actual=$actualSddl; $Record.actualProtected=[bool]$actual.AreAccessRulesProtected }
  catch { $Record.reason='READ_FAILED'; throw 'STAGE3_ACL_REJECTED' }
  if (-not $actual.AreAccessRulesProtected -or $actualSddl -cne $expectedSddl) { $Record.reason='DESCRIPTOR_MISMATCH' }
  if (-not $actual.AreAccessRulesProtected -or $actualSddl -cne $expectedSddl) { throw 'STAGE3_ACL_REJECTED' }
  return @{expected=$expectedSddl;actual=$actualSddl;protected=[bool]$actual.AreAccessRulesProtected}
}
function Invoke-PhaseARecordedFixtureAcl($Records,$Fixture,[string]$Role,[string]$Path,[int]$Sequence,[string[]]$FullSids,[string[]]$ReadSids,[string]$Source,[hashtable]$Io=@{},[scriptblock]$Observe=$null) {
  $roles=@{root=@('.',0);protected=@('protected',1);control=@('control',2)}
  if (-not $roles.ContainsKey($Role) -or $Sequence -ne $roles[$Role][1] -or $Source -cnotin @('LIVE','INJECTED')) { throw 'STAGE3_ACL_REJECTED' }
  $root=[IO.Path]::GetFullPath($Fixture.root).TrimEnd('\'); $id=[IO.Path]::GetFileName($root); $relative=$roles[$Role][0]
  if ($id -cnotmatch '^ether-phase-a-store-[0-9a-f]{32}$' -or [IO.Path]::GetFullPath($Path).TrimEnd('\') -cne $(if($relative -ceq '.'){$root}else{[IO.Path]::Combine($root,$relative)})) { throw 'STAGE3_ACL_REJECTED' }
  $record=@{fixtureId=$id;role=$Role;relative=$relative;sequence=$Sequence;targetExists=$false;expected='';expectedProtected=$false;attempted=$false;applied=$false;actual='';actualProtected=$false;reason='NONE';source=$Source}
  $Records.Add($record)
  try { $exists=if($Io.ContainsKey('Exists')) { & $Io.Exists $Path } else { [IO.Directory]::Exists($Path) }; if($exists -isnot [bool] -or -not $exists) { $record.reason='TARGET_MISSING'; throw 'STAGE3_ACL_REJECTED' }; $record.targetExists=$true; return Set-PhaseAFixtureAcl $Path $FullSids $ReadSids $record $Io }
  catch { if($record.reason -ceq 'NONE'){$record.reason='SETUP_FAILED'}; throw 'STAGE3_ACL_REJECTED' }
  finally { if($null -ne $Observe){& $Observe $Fixture $record} }
}
function Remove-PhaseAFixture($Fixture) {
  $root=[IO.Path]::GetFullPath($Fixture.root); $parent=[IO.Path]::GetFullPath($Fixture.parent).TrimEnd('\')
  if (-not $root.StartsWith($parent+'\',[StringComparison]::OrdinalIgnoreCase) -or
      -not [IO.Path]::GetFileName($root).StartsWith('ether-phase-a-store-')) { throw 'fixture cleanup path rejected' }
  if (-not [IO.Directory]::Exists($root)) { return }
  foreach ($dir in @($root,$Fixture.protectedDir,$Fixture.controlDir)) {
    if ([IO.Directory]::Exists($dir) -and ((Get-Item -LiteralPath $dir -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'fixture reparse point rejected' }
  }
  foreach ($file in @($Fixture.protectedFile,$Fixture.newFile,$Fixture.deniedFile,($Fixture.protectedFile+'.renamed'),$Fixture.controlFile,$Fixture.authorizedProbeFile,$Fixture.controlProbeFile)) {
    if (Test-Path -LiteralPath $file) {
      $entry=Get-Item -LiteralPath $file -Force -ErrorAction Stop
      if (($entry.Attributes -band ([IO.FileAttributes]::Directory -bor [IO.FileAttributes]::ReparsePoint)) -ne 0) { throw 'unexpected fixture entry' }
      [IO.File]::Delete($file)
    }
  }
  foreach ($dir in @($Fixture.protectedDir,$Fixture.controlDir,$root)) { if ([IO.Directory]::Exists($dir)) { [IO.Directory]::Delete($dir,$false) } }
}
function Invoke-PhaseASetupCreation($Records,[string]$Role,[scriptblock]$Operation) {
  if($Role -cnotin @('root','protected','control','protectedFile','controlFile')){throw 'STAGE3_SETUP_FAILED'}
  $record=@{role=$Role;sequence=$Records.Count;attempted=$true;result='UNCONFIRMED'};$Records.Add($record)
  try {$null=& $Operation;$record.result='CREATED'} catch {throw}
}
function Invoke-PhaseAEarlyFixtureCleanup($Fixture,[hashtable]$Evidence,$Creation,[bool]$RootCreated,[bool]$ChildUnconfirmed,[string]$SetupReason,[scriptblock]$Observe,[scriptblock]$Cleanup) {
  $root=[IO.Path]::GetFullPath($Fixture.root).TrimEnd('\');$parent=[IO.Path]::GetFullPath($Fixture.parent).TrimEnd('\')
  $c=@{route='SETUP_FAILURE';fixtureId=[IO.Path]::GetFileName($root);rootIdentity=$root;parentIdentity=$parent;identityAssurance='PATH_ONLY';expected=@('.','protected','control','protected/original.bin','protected/committed.bin','protected/rejected.bin','protected/original.bin.renamed','control/original.bin','protected/witness-authorized.bin','control/witness-permissive.bin');authorized=($RootCreated -and -not $ChildUnconfirmed);attempted=$false;returned=$false;reason=$(if($ChildUnconfirmed){'CHILD_UNCONFIRMED'}elseif(-not $RootCreated){'ROOT_UNCONFIRMED'}else{'NOT_ATTEMPTED'});setupReason=$SetupReason;creation=$Creation;before=$null;after=$null}
  $Evidence['fixtureCleanup']=$c;$Evidence.cleanupVerified=$false
  if($ChildUnconfirmed){return}
  if(-not $RootCreated){if($Creation.Count -gt 0 -and $null -ne $Observe){try{$c.after=& $Observe $Fixture 'AFTER'}catch{$c.after=$null}};return}
  try {
    if($null -eq $Observe){$c.reason='PRECHECK_FAILED';return};$c.before=& $Observe $Fixture 'BEFORE'
    if($c.before -isnot [hashtable] -or $c.before.status -cne 'OBSERVED' -or -not $c.before.rootExists){$c.reason='PRECHECK_FAILED';return}
    $c.attempted=$true;$null=& $Cleanup $Fixture;$c.returned=$true;$c.reason='NONE'
  } catch {$c.reason=if($c.attempted){'CLEANUP_FAILED'}else{'PRECHECK_FAILED'}}
  finally {if($c.attempted){try{$c.after=& $Observe $Fixture 'AFTER'}catch{$c.after=$null}}}
}
function New-PhaseAStage3Backend {
  return @{
    ObserveAcl={param($fixture,$role,$record) Get-PhaseAManagerAclObservation $fixture $role $record 'LIVE'}
    Setup={ param($accounts,$evidence,$observe,$cleanupObserve)
      $common=[Environment]::GetFolderPath([Environment+SpecialFolder]::CommonApplicationData)
      if ([string]::IsNullOrWhiteSpace($common)) { throw 'STAGE3_SETUP_FAILED' }
      $parent=[IO.Path]::GetFullPath($common).TrimEnd('\')
      $root=Join-Path $parent ('ether-phase-a-store-'+[Guid]::NewGuid().ToString('N'))
      $protectedDir=Join-Path $root 'protected'; $controlDir=Join-Path $root 'control'
      $f=@{parent=$parent;root=$root;protectedDir=$protectedDir;controlDir=$controlDir;
        protectedFile=(Join-Path $protectedDir 'original.bin');newFile=(Join-Path $protectedDir 'committed.bin');
        deniedFile=(Join-Path $protectedDir 'rejected.bin');controlFile=(Join-Path $controlDir 'original.bin');authorizedProbeFile=(Join-Path $protectedDir 'witness-authorized.bin');controlProbeFile=(Join-Path $controlDir 'witness-permissive.bin');aclInspected=$false}
      $aclRecords=New-Object 'System.Collections.Generic.List[object]'; $evidence['aclEstablishment']=$aclRecords
      $creation=New-Object 'System.Collections.Generic.List[object]';$evidence['fixtureSetupCreation']=$creation
      $created=$false
      try {
        $manager=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
        if ($accounts[0].sid -ceq $accounts[1].sid -or $accounts[0].sid -ceq $manager -or $accounts[1].sid -ceq $manager -or
            $accounts[0].sid -ceq 'S-1-5-18' -or $accounts[1].sid -ceq 'S-1-5-18') { throw 'identity overlap' }
        $drive=New-Object IO.DriveInfo([IO.Path]::GetPathRoot($root))
        if ($drive.DriveFormat -cne 'NTFS') { throw 'NTFS required' }
        Invoke-PhaseASetupCreation $creation 'root' {New-Item -ItemType Directory -Path $root -ErrorAction Stop}; $created=$true
        if (((Get-Item -LiteralPath $root -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'fixture reparse point rejected' }
        try { $null=Invoke-PhaseARecordedFixtureAcl $aclRecords $f 'root' $root 0 @($manager,'S-1-5-18') @($accounts[0].sid,$accounts[1].sid) 'LIVE' @{} $observe } catch { throw 'STAGE3_ACL_REJECTED' }
        Invoke-PhaseASetupCreation $creation 'protected' {New-Item -ItemType Directory -Path $protectedDir -ErrorAction Stop}
        Invoke-PhaseASetupCreation $creation 'control' {New-Item -ItemType Directory -Path $controlDir -ErrorAction Stop}
        try {
          $protectedAcl=Invoke-PhaseARecordedFixtureAcl $aclRecords $f 'protected' $protectedDir 1 @($manager,'S-1-5-18',$accounts[0].sid) @() 'LIVE' @{} $observe
          $null=Invoke-PhaseARecordedFixtureAcl $aclRecords $f 'control' $controlDir 2 @($manager,'S-1-5-18',$accounts[0].sid,$accounts[1].sid) @() 'LIVE' @{} $observe
        } catch { throw 'STAGE3_ACL_REJECTED' }
        Invoke-PhaseASetupCreation $creation 'protectedFile' {[IO.File]::WriteAllText($f.protectedFile,'ether-phase-a-synthetic',[Text.Encoding]::ASCII)}
        Invoke-PhaseASetupCreation $creation 'controlFile' {[IO.File]::WriteAllText($f.controlFile,'ether-phase-a-control',[Text.Encoding]::ASCII)}
        $sha=[Security.Cryptography.SHA256]::Create()
        try {
          $f.initialDigest=[BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::ASCII.GetBytes('ether-phase-a-synthetic'))).Replace('-','').ToLowerInvariant()
          $f.writeDigest=[BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::ASCII.GetBytes('A'))).Replace('-','').ToLowerInvariant()
        } finally { $sha.Dispose() }
        $f.aclEvidence=$protectedAcl; $f.aclInspected=$true; return $f
      } catch {
        $original=$_;$base=$original.Exception.GetBaseException().Message;$reason=if($base -ceq 'STAGE3_ACL_REJECTED'){'ACL_REJECTED'}elseif($base -ceq 'STAGE2_CHILD_UNCONFIRMED'){'CHILD_UNCONFIRMED'}else{'SETUP_FAILED'}
        try {Invoke-PhaseAEarlyFixtureCleanup $f $evidence $creation $created ($base -ceq 'STAGE2_CHILD_UNCONFIRMED') $reason $cleanupObserve {param($fixture) Remove-PhaseAFixture $fixture}}catch{}
        throw $original
      }
    }
    Exists={ param($path) [IO.File]::Exists($path) }
    DirectoryExists={ param($path) [IO.Directory]::Exists($path) }
    RemoveProbe={ param($f,$id)
      if ($id -cnotin @('authorizedProbeFile','controlProbeFile')) { throw 'probe id rejected' }
      $path=$f[$id]; if (Test-Path -LiteralPath $path) {
        $item=Get-Item -LiteralPath $path -Force -ErrorAction Stop
        if (($item.Attributes -band ([IO.FileAttributes]::Directory -bor [IO.FileAttributes]::ReparsePoint)) -ne 0) { throw 'probe entry rejected' }
        [IO.File]::Delete($path)
      }
    }
    WitnessEvidence='LIVE'
    Probe={ param($token,$sid,$operation,$path,$root)
      $name=[IO.Path]::GetFileName($path);$directory=[IO.Path]::GetFileName([IO.Path]::GetDirectoryName($path));$targetId=switch($name){'original.bin' {if($directory -ceq 'protected'){'protectedFile'}else{'controlFile'}} 'rejected.bin' {'deniedFile'} 'witness-authorized.bin' {'authorizedProbeFile'} 'witness-permissive.bin' {'controlProbeFile'} default {throw 'WITNESS_ARGUMENT_REJECTED'}}
      return Invoke-PhaseAReadPipeProcess $token $sid $path $targetId $root $false $false $operation
    }
    CleanupVerified={ param($f) -not (Test-Path -LiteralPath $f.root -ErrorAction Stop) }
    CleanupObservation={ param($f,$phase) Get-PhaseAFixtureCleanupObservation $f $phase 'LIVE' }
    Digest={ param($path) (Get-FileHash -LiteralPath $path -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant() }
    Inventory={ param($f) (Get-PhaseAInventory $f.protectedDir -Detailed).digest }
    InventoryDetailed={ param($f) Get-PhaseAInventory $f.protectedDir -Detailed }
    Cleanup={ param($f) Remove-PhaseAFixture $f }
  }
}
