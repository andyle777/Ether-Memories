$ErrorActionPreference='Stop'
. "$PSScriptRoot/PhaseA.RecoveryJournal.ps1"
$root=Join-Path ([IO.Path]::GetTempPath()) ('orion-interrupt-'+[Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($root)
[IO.File]::WriteAllText((Join-Path $root 'input.etl'),'HANG')
$exe=Join-Path $PSScriptRoot 'etl-decoder/test-worker/bin/Debug/net10.0/TestWorker.exe'
$hash=(Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash
$marker=Join-Path $root 'identified.marker'
$module=(Join-Path $PSScriptRoot 'PhaseA.EtlSupervisor.ps1').Replace("'","''")
$rootQuoted=$root.Replace("'","''");$exeQuoted=$exe.Replace("'","''");$markerQuoted=$marker.Replace("'","''")
$code=@'
$ErrorActionPreference='Stop'
. '__MODULE__'
$script:OriginalJournalWriter=${function:Write-PhaseARecoveryJournal}
function Write-PhaseARecoveryJournal($Journal,[string]$Phase,[int]$WorkerPid,[string]$CreatedAt,[string]$Operation,[string]$Cleanup,[bool]$Unresolved,[string]$Resources,[string]$CleanupAttempt) {
 & $script:OriginalJournalWriter $Journal $Phase $WorkerPid $CreatedAt $Operation $Cleanup $Unresolved $Resources $CleanupAttempt
 if($Phase -ceq 'PROCESS_IDENTIFIED'){[IO.File]::WriteAllText('__MARKER__',($Journal.experiment+'|'+$WorkerPid+'|'+$CreatedAt))}
}
$null=Invoke-PhaseAEtlWorker -Executable '__EXE__' -ExecutableHash '__HASH__' -ExperimentDirectory '__ROOT__' -TimeoutMs 60000
'@
$code=$code.Replace('__MODULE__',$module).Replace('__MARKER__',$markerQuoted).Replace('__EXE__',$exeQuoted).Replace('__HASH__',$hash).Replace('__ROOT__',$rootQuoted)
$encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($code))
$manager=$null;$worker=$null
try {
 $errorPath=Join-Path $root 'manager-error.txt';$outPath=Join-Path $root 'manager-out.txt'
 $manager=Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') -ArgumentList @('-NoProfile','-NonInteractive','-EncodedCommand',$encoded) -PassThru -WindowStyle Hidden -RedirectStandardError $errorPath -RedirectStandardOutput $outPath
 $clock=[Diagnostics.Stopwatch]::StartNew()
 while(-not [IO.File]::Exists($marker)) {
  if($manager.HasExited -or $clock.ElapsedMilliseconds -gt 30000){if([IO.File]::Exists($errorPath)){Get-Content -LiteralPath $errorPath | Write-Output};throw 'MANAGER_READINESS_FAILED'}
  Start-Sleep -Milliseconds 25
 }
 $parts=[IO.File]::ReadAllText($marker).Split('|')
 if($parts.Count -ne 3){throw 'MARKER_INVALID'}
 $worker=Get-Process -Id ([int]$parts[1]) -ErrorAction Stop
 if($worker.StartTime.ToUniversalTime().ToString('o') -cne $parts[2]){throw 'WORKER_IDENTITY_MISMATCH'}
 $null=$worker.Handle
 $manager.Kill();if(-not $manager.WaitForExit(10000)){throw 'MANAGER_TERMINATION_UNCONFIRMED'}
 if(-not $worker.WaitForExit(10000)){throw 'WORKER_TERMINATION_UNCONFIRMED'}
 $recovered=Read-PhaseARecoveryJournal (Join-Path $root 'recovery.journal') $parts[0]
 if($recovered.status -cne 'UNVERIFIED' -or $recovered.integrity -cne 'VALID' -or $recovered.lastTransition -cne 'PROCESS_IDENTIFIED' -or -not $recovered.unresolved -or $recovered.pid -ne [int]$parts[1] -or $recovered.createdAt -cne $parts[2]){throw 'INTERRUPTION_RECOVERY_INVALID'}
 Write-Output 'PASS actual manager interruption; owned worker terminated; journal remains UNVERIFIED'
} finally {
 if($manager -and -not $manager.HasExited){$manager.Kill();[void]$manager.WaitForExit(5000)}
 if($worker -and -not $worker.HasExited){$worker.Kill();[void]$worker.WaitForExit(5000)}
 if($worker){$worker.Dispose()};if($manager){$manager.Dispose()}
}
