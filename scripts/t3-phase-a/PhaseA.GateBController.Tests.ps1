$ErrorActionPreference='Stop'
. "$PSScriptRoot/PhaseA.EtlSupervisor.ps1"
$exe=Join-Path $PSScriptRoot 'gate-b-controller/bin/Debug/net10.0/GateBController.exe'
$hash=(Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash
$root=Join-Path ([IO.Path]::GetTempPath()) ('orion-gate-b-test-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($root)
[IO.File]::WriteAllText((Join-Path $root 'input.etl'),'{"mode":"dry-run"}')
$r=Invoke-PhaseAEtlWorker -Executable $exe -ExecutableHash $hash -ExperimentDirectory $root -TimeoutMs 10000 -TerminationMs 5000
if($r.classification -cne 'COMPLETE' -or -not $r.terminationConfirmed -or $r.cleanup -cne 'CONFIRMED'){throw ('SUPERVISED_DRY_RUN_FAILED '+$r.classification)}
$out=$r.outputJson | ConvertFrom-Json
if($out.Status -cne 'UNVERIFIED' -or $out.Experiment -cne $r.experiment -or $out.nativeCalls -ne 0){throw 'DRY_RUN_SECURITY_BOUNDARY_FAILED'}
Write-Output 'PASS contained Gate B dry run, untrusted pipe receipt and no native calls'
$stall=Join-Path ([IO.Path]::GetTempPath()) ('orion-gate-b-test-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($stall)
[IO.File]::WriteAllText((Join-Path $stall 'input.etl'),'{"mode":"offline-stall-test"}')
$r=Invoke-PhaseAEtlWorker -Executable $exe -ExecutableHash $hash -ExperimentDirectory $stall -TimeoutMs 1500 -TerminationMs 5000
if($r.classification -cne 'TIMEOUT' -or -not $r.terminationConfirmed -or $r.cleanup -cne 'CONFIRMED'){throw 'CONTROLLER_TIMEOUT_NOT_CONTAINED'}
Write-Output 'PASS stalled harmless controller timed out and termination was independently confirmed'
$wrapper=Join-Path $PSScriptRoot 'Invoke-GateBFeasibility.ps1'
$wrapperResult=& powershell.exe -NoProfile -File $wrapper -ParentDirectory ([IO.Path]::GetTempPath()) -ExpectedExecutableSha256 $hash
if($LASTEXITCODE -ne 0){throw 'WRAPPER_DRY_RUN_FAILED'}
$wr=$wrapperResult | ConvertFrom-Json
if($wr.classification -cne 'UNVERIFIED' -or $wr.worker -cne 'COMPLETE' -or $wr.evidence -cne 'DURABLE_UNTRUSTED' -or $wr.vmDisposalRequired){throw 'WRAPPER_DRY_RUN_INVALID'}
Write-Output 'PASS pinned controller wrapper dry run remains UNVERIFIED'
