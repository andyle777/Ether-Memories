$ErrorActionPreference='Stop'
. "$PSScriptRoot/PhaseA.Tests.ps1"
$forged=$processRead.Clone();$forged.unauthorizedRead=$processRead.unauthorizedRead.Clone();$forged.unauthorizedRead.witness=$processRead.unauthorizedRead.witness.Clone();$forged.unauthorizedRead.witness.evidence='LIVE'
$forged.witnessControls=$processRead.witnessControls.Clone()
foreach($k in @('authorizedRead','permissiveRead')){$forged.witnessControls[$k]=$processRead.witnessControls[$k].Clone();$forged.witnessControls[$k].evidence='LIVE'}
$v=New-PhaseAManagerVerdictInput ('1'*40) '123';Add-PhaseAStage3Evidence $v $forged 'LIVE_OBSERVED' $journal.ToArray()
if($v.cases.unauthorizedRead.state -cne 'NOT_RUN'){throw ('RELABELLED_INJECTED_WITNESS_ACCEPTED_'+$v.cases.unauthorizedRead.state)}
Write-Output 'PASS relabeled witness rejected as LIVE'
