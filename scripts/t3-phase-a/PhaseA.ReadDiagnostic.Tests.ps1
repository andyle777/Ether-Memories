param([string]$Helper=(Join-Path $PSScriptRoot "PhaseA.ReadDiagnostic.ps1"))
$ErrorActionPreference='Stop'
. $Helper
function Get-Err($exception){try {throw $exception} catch {return $_}}
function Assert-Outcome($actual,$want){if($actual.outcome -cne $want){throw ("expected="+$want+" actual="+$actual.outcome)}}
$released=@{operationFailure='WITNESS_TIMEOUT';cleanupDependency='RELEASE_ELIGIBLE';launch='CREATED';jobClose='CLOSED';pipeRetention='RELEASED';child=@{finalWait='SIGNALED';exitState='EXITED';processClose='CLOSED';threadClose='CLOSED'}}
Assert-Outcome (Get-PhaseAStallDiagnostic $true $null $released) 'STALL_ACCEPTED'
Assert-Outcome (Get-PhaseAStallDiagnostic $false (Get-Err ([InvalidOperationException]::new('WITNESS_TIMEOUT'))) $released) 'EXPECTED_TIMEOUT'
Assert-Outcome (Get-PhaseAStallDiagnostic $false (Get-Err ([ComponentModel.Win32Exception]::new(4551))) @{operationFailure='WITNESS_OPERATION_FAILED';cleanupDependency='RELEASE_ELIGIBLE'}) 'EXECUTION_POLICY_BLOCKED'
Assert-Outcome (Get-PhaseAStallDiagnostic $false (Get-Err ([ComponentModel.Win32Exception]::new(4551))) $released) 'UNEXPECTED_FAILURE'
Assert-Outcome (Get-PhaseAStallDiagnostic $false (Get-Err ([ComponentModel.Win32Exception]::new(5))) $released) 'LAUNCH_OR_SETUP_FAILED'
Assert-Outcome (Get-PhaseAStallDiagnostic $false (Get-Err ([InvalidOperationException]::new('WITNESS_CLEANUP_FAILED',[ComponentModel.Win32Exception]::new(4551)))) @{cleanupDependency='RETAIN'}) 'CLEANUP_FAILED'
Assert-Outcome (Get-PhaseAStallDiagnostic $false (Get-Err ([InvalidOperationException]::new('STAGE2_CHILD_UNCONFIRMED'))) @{cleanupDependency='RETAIN'}) 'CHILD_TERMINATION_UNCONFIRMED'
Assert-Outcome (Get-PhaseAStallDiagnostic $false (Get-Err ([InvalidOperationException]::new('other'))) $released) 'UNEXPECTED_FAILURE'
Assert-Outcome (Get-PhaseAStallDiagnostic $false (Get-Err ([InvalidOperationException]::new('WITNESS_TIMEOUT'))) @{cleanupDependency='RETAIN'}) 'CLEANUP_FAILED'
Assert-Outcome (Get-PhaseAStallDiagnostic $true (Get-Err ([InvalidOperationException]::new('contradiction'))) $released) 'UNEXPECTED_FAILURE'
Write-Output 'PASS nine bounded diagnostic classifications and cleanup precedence'
$err=Get-Err ([InvalidOperationException]::new('WITNESS_TIMEOUT'))
$bad=@{operationFailure='WITNESS_TIMEOUT';cleanupDependency='RELEASE_ELIGIBLE';launch='CREATED';jobClose='CLOSED';pipeRetention='RELEASED';child=@{finalWait='TIMEOUT';exitState='ALIVE';processClose='CLOSED';threadClose='CLOSED'}}
Assert-Outcome (Get-PhaseAStallDiagnostic $false $err $bad) 'CHILD_TERMINATION_UNCONFIRMED'
$bad.child.finalWait='SIGNALED';$bad.child.exitState='EXITED';$bad.jobClose='FAILED'
Assert-Outcome (Get-PhaseAStallDiagnostic $false $err $bad) 'CLEANUP_FAILED'
$bad.jobClose='CLOSED';$bad.child.processClose='FAILED'
Assert-Outcome (Get-PhaseAStallDiagnostic $false $err $bad) 'CLEANUP_FAILED'
Assert-Outcome (Get-PhaseAStallDiagnostic $false $err @{cleanupDependency='RELEASE_ELIGIBLE'}) 'UNEXPECTED_FAILURE'
Write-Output 'PASS contradictory and missing lifecycle evidence rejected'

function Err($e){try{throw $e}catch{return $_}}
function Need($actual,$expect,$label){if($actual.outcome -cne $expect){throw ('RED_'+$label+'_'+$actual.outcome)}}
$r=@{cleanupDependency='RELEASE_ELIGIBLE';launch='CREATED';jobClose='CLOSED';pipeRetention='RELEASED';operationFailure='WITNESS_IDENTITY_REJECTED';child=@{finalWait='SIGNALED';exitState='EXITED';processClose='CLOSED';threadClose='CLOSED'}}
$t=Err ([InvalidOperationException]::new('WITNESS_TIMEOUT'))
Need (Get-PhaseAStallDiagnostic $false $t $r) 'UNEXPECTED_FAILURE' 'CONTRADICTION'
$r.operationFailure='WITNESS_TIMEOUT'
$wrapped=Err ([InvalidOperationException]::new('UNRELATED_FAILURE',[InvalidOperationException]::new('WITNESS_TIMEOUT')))
Need (Get-PhaseAStallDiagnostic $false $wrapped $r) 'UNEXPECTED_FAILURE' 'WRAPPED'
Need (Get-PhaseAStallDiagnostic $false $t $null) 'UNEXPECTED_FAILURE' 'NULL'
Write-Output 'PASS contradiction, unrelated wrapper and missing lifecycle'
$r=@{operationFailure='WITNESS_TIMEOUT';cleanupDependency='RELEASE_ELIGIBLE';launch=$true;jobClose='CLOSED';pipeRetention='RELEASED';child=@{finalWait='SIGNALED';exitState='EXITED';processClose='CLOSED';threadClose='CLOSED'}}
Need (Get-PhaseAStallDiagnostic $false (Err ([InvalidOperationException]::new('WITNESS_TIMEOUT'))) $r) 'UNEXPECTED_FAILURE' 'MALFORMED_LAUNCH'
$wrapped=Err ([InvalidOperationException]::new('wrapper',[ComponentModel.Win32Exception]::new(4551)))
$out=Get-PhaseAStallDiagnostic $false $wrapped @{operationFailure='WITNESS_OPERATION_FAILED';cleanupDependency='RELEASE_ELIGIBLE'}
if($out.outcome -cne 'EXECUTION_POLICY_BLOCKED' -or $out.nativeError -ne 4551 -or -not [object]::ReferenceEquals($out.exception,$wrapped.Exception)){throw 'WRAPPED_POLICY_OR_EXCEPTION_LOST'}
Write-Output 'PASS strict field types and wrapped native exception'

$r=@{operationFailure='WITNESS_TIMEOUT';cleanupDependency='RELEASE_ELIGIBLE';launch='CREATED';jobClose='CLOSED';pipeRetention='RELEASED';child=@{finalWait='SIGNALED';exitState='EXITED';processClose='CLOSED';threadClose='CLOSED'}}
$nested=Err ([InvalidOperationException]::new('WITNESS_TIMEOUT',[InvalidOperationException]::new('UNRELATED_FAILURE')))
Need (Get-PhaseAStallDiagnostic $false $nested $r) 'UNEXPECTED_FAILURE' 'TIMEOUT_WITH_UNRELATED_CAUSE'
Write-Output 'PASS timeout wrapping unrelated cause rejected'

$policy=Err ([ComponentModel.Win32Exception]::new(4551))
Need (Get-PhaseAStallDiagnostic $false $policy @{operationFailure='WITNESS_OPERATION_FAILED';cleanupDependency='RELEASE_ELIGIBLE';jobClose='INVALID_STATE'}) 'UNEXPECTED_FAILURE' 'MALFORMED_POLICY_CLEANUP'
Need (Get-PhaseAStallDiagnostic $false (Err ([InvalidOperationException]::new('STAGE2_CHILD_UNCONFIRMED'))) $null) 'CHILD_TERMINATION_UNCONFIRMED' 'NULL_CHILD_FAILURE'
Need (Get-PhaseAStallDiagnostic $false (Err ([InvalidOperationException]::new('WITNESS_CLEANUP_FAILED'))) $null) 'CLEANUP_FAILED' 'NULL_CLEANUP_FAILURE'
Write-Output 'PASS malformed cleanup and missing-lifecycle exception precedence'
