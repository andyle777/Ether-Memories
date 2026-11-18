$ErrorActionPreference='Stop'
. "$PSScriptRoot/PhaseA.Stage3.ps1"
$prior=@{marker='retained';child=[object]::new()}
$script:PhaseAUnconfirmedWitnessResources=$prior
$failure=''
try { Invoke-PhaseAReadPipeProcess $null '' '' '' '' | Out-Null } catch { $failure=$_.Exception.GetBaseException().Message }
if($failure -cne 'WITNESS_CLEANUP_FAILED'){throw 'UNRESOLVED_WITNESS_NOT_REJECTED'}
if(-not [object]::ReferenceEquals($prior,$script:PhaseAUnconfirmedWitnessResources)){throw 'UNRESOLVED_WITNESS_OVERWRITTEN'}
Write-Output 'PASS unresolved witness blocks new invocation and retains original resources'