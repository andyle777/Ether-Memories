$ErrorActionPreference='Stop'
. "$PSScriptRoot/PhaseA.Stage3.ps1"
$script:PhaseAUnconfirmedWitnessResources=@{marker='prior'}
try { Invoke-PhaseAReadPipeProcess $null '' '' '' '' | Out-Null } catch {}
$gate=[AppDomain]::CurrentDomain.GetData('EtherPhaseAWitnessResourceGate')
if($gate.state -cne 'UNRESOLVED' -or -not [object]::ReferenceEquals($gate.resources,$script:PhaseAUnconfirmedWitnessResources)){throw 'PROCESS_GATE_DID_NOT_RETAIN_RESOURCES'}
$path=Join-Path $PSScriptRoot 'PhaseA.Stage3.ps1'
$ps=[PowerShell]::Create()
try {
 $null=$ps.AddScript('param($p) . $p; try { Invoke-PhaseAReadPipeProcess $null "" "" "" "" | Out-Null; "ACCEPTED" } catch { $_.Exception.GetBaseException().Message }').AddArgument($path)
 $result=@($ps.Invoke())
 if($result.Count -ne 1 -or $result[0] -cne 'WITNESS_CLEANUP_FAILED'){throw ('CROSS_RUNSPACE_RESOURCE_GATE_BYPASSED_'+($result -join ','))}
 if($script:PhaseAUnconfirmedWitnessResources.marker -cne 'prior'){throw 'PRIOR_RESOURCE_RECORD_REPLACED'}
} finally {$ps.Dispose()}
Write-Output 'PASS unresolved witness blocks a different runspace'