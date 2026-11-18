$ErrorActionPreference='Stop'
$path=Join-Path $PSScriptRoot 'PhaseA.RecoveryJournal.ps1'
if (-not (Test-Path -LiteralPath $path)) {throw 'RECOVERY_JOURNAL_MISSING'}
. $path
$root=Join-Path ([IO.Path]::GetTempPath()) ('orion-journal-test-'+[Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($root)
$id=[Guid]::NewGuid().ToString('N');$file=Join-Path $root 'recovery.jsonl'
$j=New-PhaseARecoveryJournal $file $id
Write-PhaseARecoveryJournal $j 'STARTED' 0 '' 'UNVERIFIED' 'NOT_STARTED' $false
Write-PhaseARecoveryJournal $j 'PROCESS_IDENTIFIED' 42 '2026-01-01T00:00:00.0000000Z' 'UNVERIFIED' 'NOT_STARTED' $true
Write-PhaseARecoveryJournal $j 'PRE_CLEANUP' 42 '2026-01-01T00:00:00.0000000Z' 'TIMEOUT' 'NOT_CONFIRMED' $true
$j.stream.Dispose()
$r=Read-PhaseARecoveryJournal $file $id
if($r.status -cne 'UNVERIFIED' -or $r.integrity -cne 'VALID' -or $r.lastTransition -cne 'PRE_CLEANUP' -or -not $r.unresolved) {throw 'RECOVERY_INCOMPLETE_ACCEPTED'}
Write-Output 'PASS durable incomplete journal remains UNVERIFIED'
$bytes=[IO.File]::ReadAllBytes($file)
$bad=Join-Path $root 'truncated.jsonl';[IO.File]::WriteAllBytes($bad,$bytes[0..($bytes.Length-2)])
if((Read-PhaseARecoveryJournal $bad $id).integrity -cne 'INVALID'){throw 'TRUNCATION_ACCEPTED'}
$bad=Join-Path $root 'replayed.jsonl';[IO.File]::WriteAllBytes($bad,$bytes+$bytes)
if((Read-PhaseARecoveryJournal $bad $id).integrity -cne 'INVALID'){throw 'REPLAY_ACCEPTED'}
$bad=Join-Path $root 'corrupt.jsonl';$copy=[byte[]]$bytes.Clone();$copy[30]=$copy[30] -bxor 1;[IO.File]::WriteAllBytes($bad,$copy)
if((Read-PhaseARecoveryJournal $bad $id).integrity -cne 'INVALID'){throw 'CORRUPTION_ACCEPTED'}
if((Read-PhaseARecoveryJournal $file ([Guid]::NewGuid().ToString('N'))).integrity -cne 'INVALID'){throw 'WRONG_EXPERIMENT_ACCEPTED'}
Write-Output 'PASS truncation, replay, corruption and wrong experiment rejected'
