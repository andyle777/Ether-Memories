# Synthetic-only integration. Callbacks are trusted test seams, not a security boundary.
. "$PSScriptRoot/PhaseA.AggregateSupervisor.ps1"
. "$PSScriptRoot/PhaseA.DurableAdmission.ps1"
function Invoke-PhaseAStateOnlyAttempt([string]$Directory,[string]$SessionId,[int]$BudgetMs,[hashtable]$Backend,[scriptblock]$Clock,[scriptblock]$Fault=$null,[scriptblock]$Flush=$null) {
 $out=@{source='LOCAL_UNTRUSTED';status='UNVERIFIED';reason='ADMISSION_DENIED';record='NOT_PUBLISHED'}
 if($Backend.ContainsKey('NativeGate') -and $Backend.NativeGate -ceq $true){$out.reason='PROTOTYPE_INCIDENT_UNRESOLVED';return $out}
 $lease=$null;$owner=$null
 try {
  $owner=Initialize-PhaseAAdmissionStore $Directory $Fault $Flush
  $lease=Open-PhaseAAdmissionLease $owner $SessionId $Fault $Flush
  $s=New-PhaseAAggregateSession $BudgetMs $Backend $Clock
  $r=Invoke-PhaseAAggregateAttempt $s $BudgetMs 1000 'NORMAL'
  if($r.source -cne 'LOCAL_UNTRUSTED' -or $r.classification -cne 'OBSERVED' -or $r.cleanup -cne 'CONFIRMED'){$out.reason='SYNTHETIC_ATTEMPT_UNRESOLVED';return $out}
  Publish-PhaseAStateOnlyClean $lease $r $Fault $Flush
  $out.status='SIMULATED_COMPLETE';$out.reason='SYNTHETIC_ONLY';$out.record='CLEAN'
 } catch {$out.reason='ADMISSION_OR_PUBLICATION_FAILED'}
 finally {if($null -ne $lease){Close-PhaseAAdmissionLease $lease}elseif($null -ne $owner){Close-PhaseAAdmissionLease $owner}}
 return $out
}