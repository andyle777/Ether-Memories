$ErrorActionPreference='Stop'
$module=Join-Path $PSScriptRoot 'PhaseA.EtlSupervisor.ps1'
if (!(Test-Path -LiteralPath $module)) { throw 'SUPERVISOR_IMPLEMENTATION_MISSING' }
. $module
. "$PSScriptRoot/PhaseA.RecoveryJournal.ps1"
if ((Get-PhaseAEtlNativeCategory (New-Object ComponentModel.Win32Exception 4551)) -cne 'APPLICATION_CONTROL_BLOCKED') {throw 'NATIVE_POLICY_ERROR_NOT_PRESERVED'}
Write-Output 'PASS native application-control error classification'
$root=Join-Path ([IO.Path]::GetTempPath()) ('orion-etl-supervisor-'+[Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($root)
$exe=Join-Path $PSScriptRoot 'etl-decoder/test-worker/bin/Debug/net10.0/TestWorker.exe'
if (-not [IO.File]::Exists($exe)) {throw 'TEST_WORKER_NOT_BUILT'}
$hash=(Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash
foreach($test in @(@('OK','COMPLETE'),@('HANG','TIMEOUT'),@('CRASH','WORKER_FAILED'),@('MISSING','OUTPUT_MISSING'),@('OVERSIZE','OUTPUT_TOO_LARGE'),@('BOTH_FLOOD','OUTPUT_TOO_LARGE'),@('FORGED','OUTPUT_INVALID'),@('REPLAY','OUTPUT_INVALID'))) {
 $dir=Join-Path $root ([Guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($dir)
 [IO.File]::WriteAllText((Join-Path $dir 'input.etl'),$test[0])
 $r=Invoke-PhaseAEtlWorker -Executable $exe -ExecutableHash $hash -ExperimentDirectory $dir -TimeoutMs 2000 -TerminationMs 5000 -MaximumOutputBytes 65536
 if($r.transfer -cne 'ANONYMOUS_PIPE'){throw 'MUTABLE_OUTPUT_TRANSFER_REACHABLE'}
 if ($r.classification -cne $test[1] -or -not $r.terminationConfirmed -or $r.cleanup -cne 'CONFIRMED') {throw ("WORKER_{0}: {1}" -f $test[0],($r|ConvertTo-Json -Compress))}
 if ($test[0] -ceq 'CRASH' -and $r.exitCode -ne 9) {throw 'WORKER_EXIT_STATUS_LOST'}
 if (-not $r.tokenProperties.primary -or $r.tokenProperties.source -cne 'PROCESS_TOKEN_ONLY') {throw 'TOKEN_OBSERVATION_LOST'}
 $journal=Read-PhaseARecoveryJournal (Join-Path $dir 'recovery.journal') $r.experiment
 if($journal.integrity -cne 'VALID' -or $journal.lastTransition -cne 'CLEANUP_OBSERVED' -or $journal.status -cne 'UNVERIFIED'){throw 'MANAGER_RECOVERY_JOURNAL_MISSING'}
 Write-Output ("PASS real child {0}: {1} pid={2} termination={3}" -f $test[0],$r.classification,$r.pid,$r.terminationConfirmed)
}
$dir=Join-Path $root ([Guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($dir)
[IO.File]::WriteAllText((Join-Path $dir 'input.etl'),'HANG')
$cts=New-Object Threading.CancellationTokenSource
$cts.Cancel()
$r=Invoke-PhaseAEtlWorker -Executable $exe -ExecutableHash $hash -ExperimentDirectory $dir -Cancellation $cts.Token
if ($r.classification -cne 'CANCELLED' -or -not $r.terminationConfirmed -or $r.cleanup -cne 'CONFIRMED') {throw 'CANCELLATION_FAILED'}
Write-Output 'PASS real child cancellation and confirmed termination'
$dir=Join-Path $root ([Guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($dir)
[IO.File]::WriteAllText((Join-Path $dir 'input.etl'),'OK')
$r=Invoke-PhaseAEtlWorker -Executable (Join-Path $root 'absent.exe') -ExecutableHash $hash -ExperimentDirectory $dir
if($r.classification -cne 'EXECUTABLE_MISSING') {throw 'MISSING_EXECUTABLE_ACCEPTED'}
Write-Output 'PASS missing executable rejected'
$dir=Join-Path $root ([Guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($dir)
[IO.File]::WriteAllText((Join-Path $dir 'input.etl'),'MUTATE_INPUT')
$r=Invoke-PhaseAEtlWorker -Executable $exe -ExecutableHash $hash -ExperimentDirectory $dir -TimeoutMs 5000
if ([IO.File]::ReadAllText((Join-Path $dir 'input.etl')) -cne 'MUTATE_INPUT') {throw 'INPUT_CHANGED_DURING_WORKER'}
if ($r.classification -cne 'COMPLETE' -or -not $r.terminationConfirmed) {throw 'INPUT_LOCK_TEST_INCOMPLETE'}
Write-Output 'PASS open input handle prevents concurrent write by child'
$dir=Join-Path $root ([Guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($dir)
[IO.File]::WriteAllText((Join-Path $dir 'input.etl'),'OK')
[IO.File]::WriteAllText((Join-Path $dir 'result.json'),'preserve')
$r=Invoke-PhaseAEtlWorker -Executable $exe -ExecutableHash $hash -ExperimentDirectory $dir
if ($r.classification -cne 'OUTPUT_EXISTS' -or $r.pid -ne 0 -or [IO.File]::ReadAllText((Join-Path $dir 'result.json')) -cne 'preserve') {throw 'OUTPUT_COLLISION_ACCEPTED'}
Write-Output 'PASS existing output preserved without starting child'
$dir=Join-Path $root ([Guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($dir)
[IO.File]::WriteAllText((Join-Path $dir 'input.etl'),'ATTACK_INPUT')
$r=Invoke-PhaseAEtlWorker -Executable $exe -ExecutableHash $hash -ExperimentDirectory $dir -TimeoutMs 5000
$o=$r.outputJson | ConvertFrom-Json
if ($r.classification -cne 'COMPLETE' -or $o.modify -or $o.rename -or $o.delete -or $o.replace -or [IO.File]::ReadAllText((Join-Path $dir 'input.etl')) -cne 'ATTACK_INPUT') {throw 'INPUT_HANDLE_ATTACK_SUCCEEDED'}
Write-Output 'PASS same-identity child could not modify, rename, delete or replace held input'
$dir=Join-Path $root ([Guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($dir)
[IO.File]::WriteAllText((Join-Path $dir 'input.etl'),'SUBSTITUTE_OUTPUT')
$r=Invoke-PhaseAEtlWorker -Executable $exe -ExecutableHash $hash -ExperimentDirectory $dir -TimeoutMs 5000
$o=$r.outputJson | ConvertFrom-Json
if ($r.classification -cne 'COMPLETE' -or $r.transfer -cne 'ANONYMOUS_PIPE' -or -not $o.substituted -or -not $o.deleted) {throw 'OUTPUT_PATH_SUBSTITUTED'}
Write-Output 'PASS same-identity output-path substitution did not replace pipe output'
$clone=Join-Path $root 'worker-clone';[void][IO.Directory]::CreateDirectory($clone)
Get-ChildItem -File -LiteralPath ([IO.Path]::GetDirectoryName($exe)) | ForEach-Object {[IO.File]::Copy($_.FullName,(Join-Path $clone $_.Name))}
$cloneExe=Join-Path $clone 'TestWorker.exe';$cloneHash=(Get-FileHash -LiteralPath $cloneExe -Algorithm SHA256).Hash
foreach($mode in @('ATTACK_EXECUTABLE','ATTACK_DEPENDENCY')) {
 $dir=Join-Path $root ([Guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($dir)
 [IO.File]::WriteAllText((Join-Path $dir 'input.etl'),$mode)
 $r=Invoke-PhaseAEtlWorker -Executable $cloneExe -ExecutableHash $cloneHash -ExperimentDirectory $dir -TimeoutMs 5000
 $o=$r.outputJson | ConvertFrom-Json
 if ($r.classification -cne 'COMPLETE') {throw 'CLONED_WORKER_FAILED'}
 if ($mode -ceq 'ATTACK_EXECUTABLE' -and ($o.modify -or $o.rename -or $o.delete -or $o.replace)) {throw 'EXECUTABLE_HANDLE_ATTACK_SUCCEEDED'}
 if ($mode -ceq 'ATTACK_DEPENDENCY' -and $o.modified) {throw 'DEPENDENCY_MUTATED_DURING_RUN'}
 Write-Output ('PASS same-identity child could not change '+$mode)
}
