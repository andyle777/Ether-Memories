$ErrorActionPreference='Stop'
$wrapper=Join-Path $PSScriptRoot 'Invoke-GateBFeasibility.ps1'
$exe=Join-Path $PSScriptRoot 'etl-decoder/test-worker/bin/Debug/net10.0/TestWorker.exe'
if(-not [IO.File]::Exists($exe)){throw 'TEST_WORKER_NOT_BUILT'}
$hash=(Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash
$cases=@(
 @{mode='VALID'; worker='COMPLETE'; receipt='VALID'; exit=0},
 @{mode='NONZERO'; worker='WORKER_FAILED'; receipt='NOT_VALIDATED'; exit=2},
 @{mode='ABRUPT'; worker='WORKER_FAILED'; receipt='NOT_VALIDATED'; exit=2},
 @{mode='HANG'; worker='TIMEOUT'; receipt='NOT_VALIDATED'; exit=2},
 @{mode='MISSING'; worker='OUTPUT_MISSING'; receipt='NOT_VALIDATED'; exit=2},
 @{mode='MALFORMED'; worker='OUTPUT_INVALID'; receipt='NOT_VALIDATED'; exit=2},
 @{mode='DUPLICATE'; worker='COMPLETE'; receipt='INVALID'; exit=2},
 @{mode='CONTRADICT'; worker='COMPLETE'; receipt='INVALID'; exit=2},
 @{mode='REPLAY'; worker='OUTPUT_INVALID'; receipt='NOT_VALIDATED'; exit=2},
 @{mode='OVERSIZE'; worker='OUTPUT_TOO_LARGE'; receipt='NOT_VALIDATED'; exit=2}
)
foreach($case in $cases){
 $text=@(& powershell.exe -NoProfile -File $wrapper -ParentDirectory ([IO.Path]::GetTempPath()) -ExpectedExecutableSha256 $hash -ExperimentalDisposableVM -OwnerApproval 'SEPARATELY_AUTHORIZED' -OfflineTestCase $case.mode)
 $exitCode=$LASTEXITCODE
 if($exitCode -ne $case.exit){throw ("$($case.mode): EXIT_$exitCode EXPECTED_$($case.exit)")}
 try {$result=($text -join "`n") | ConvertFrom-Json -ErrorAction Stop} catch {throw ("$($case.mode): WRAPPER_OUTPUT_INVALID")}
 if($result.vmDisposalRequired -ne $true -or $result.vmDisposalConfirmed -ne $false){throw ("$($case.mode): VM_DISPOSAL_UNSAFE")}
 if($result.worker -cne $case.worker -or $result.receipt -cne $case.receipt){throw ("$($case.mode): WRONG_CLASSIFICATION worker=$($result.worker) receipt=$($result.receipt)")}
 if($result.workerTerminated -ne $true -or $result.workerCleanup -cne 'CONFIRMED'){throw ("$($case.mode): CHILD_TERMINATION_OR_HANDLE_CLEANUP_UNCONFIRMED")}
 if($case.mode -in @('NONZERO','ABRUPT') -and ($null -eq $result.workerExitCode -or $result.workerExitCode -eq 0)){throw ("$($case.mode): CHILD_EXIT_STATUS_LOST")}
 if($result.classification -cne 'UNVERIFIED'){throw ("$($case.mode): IMPROPER_SECURITY_VERDICT")}
 Write-Output ("PASS {0}: worker={1}, receipt={2}, exit={3}" -f $case.mode,$result.worker,$result.receipt,$exitCode)
}
