$ErrorActionPreference='Stop'
. "$PSScriptRoot/PhaseA.EtlSupervisor.ps1"
if (-not (Get-Command Invoke-PhaseAEtlWait -ErrorAction SilentlyContinue) -or -not (Get-Command Close-PhaseAEtlJob -ErrorAction SilentlyContinue)) {throw 'CLEANUP_SEAM_MISSING'}
$exe=Join-Path $PSScriptRoot 'etl-decoder/test-worker/bin/Debug/net10.0/TestWorker.exe'
$hash=(Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash
$root=Join-Path ([IO.Path]::GetTempPath()) ('orion-etl-failure-'+[Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($root)
function New-Input([string]$mode) {
 $dir=Join-Path $root ([Guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($dir)
 [IO.File]::WriteAllText((Join-Path $dir 'input.etl'),$mode);return $dir
}
function Invoke-PhaseAEtlWait($Child,[uint32]$Milliseconds) {return $false}
$r=Invoke-PhaseAEtlWorker -Executable $exe -ExecutableHash $hash -ExperimentDirectory (New-Input 'HANG') -TimeoutMs 100 -TerminationMs 200
function Invoke-PhaseAEtlWait($Child,[uint32]$Milliseconds) {return $Child.Wait($Milliseconds)}
if ($r.classification -cne 'TIMEOUT' -or $r.terminationConfirmed -or $r.cleanup -cne 'RESOURCE_RETAINED') {throw 'UNCONFIRMED_NOT_RETAINED'}
$modulePath=(Join-Path $PSScriptRoot 'PhaseA.EtlSupervisor.ps1').Replace("'","''")
$restartCode=". '$modulePath'; Write-Output ('RETAINED_COUNT='+`$script:EtlUnconfirmed.Count)"
$encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($restartCode))
$restart=& powershell.exe -NoProfile -NonInteractive -EncodedCommand $encoded
if ($LASTEXITCODE -ne 0 -or ($restart -join '') -cne 'RETAINED_COUNT=0') {throw 'RESTART_OBSERVATION_INVALID'}
Write-Output 'PASS restart cannot recover process-local handles; durable journal remains separate'
$owner=$script:EtlUnconfirmed[$script:EtlUnconfirmed.Count-1]
if (-not $owner.child.Wait(5000)) {throw 'TEST_CHILD_STILL_RUNNING'}
[void]$owner.child.CloseObserved();[EtherPhaseAJob]::Close($owner.job);$owner.process.Dispose();$owner.inputHandle.Dispose();$owner.exeHandle.Dispose();if($owner.outputHandle){$owner.outputHandle.Dispose()};if($owner.pipes){if(-not $owner.pipes.WaitReaders(5000)){throw 'TEST_PIPE_STILL_ACTIVE'};$owner.pipes.Dispose()};foreach($h in $owner.dependencyHandles){$h.Dispose()}
$script:EtlUnconfirmed.RemoveAt($script:EtlUnconfirmed.Count-1)
Write-Output 'PASS injected unconfirmed observation retains resources after real termination'
function Close-PhaseAEtlJob($Job) {throw 'INJECTED_CLOSE_FAILURE'}
$r=Invoke-PhaseAEtlWorker -Executable $exe -ExecutableHash $hash -ExperimentDirectory (New-Input 'CRASH') -TimeoutMs 5000
function Close-PhaseAEtlJob($Job) {[EtherPhaseAJob]::Close($Job)}
if ($r.classification -cne 'WORKER_FAILED' -or $r.exitCode -ne 9 -or $r.cleanup -cne 'FAILED') {throw 'EARLIER_FAILURE_LOST_AFTER_CLEANUP_FAILURE'}
$owner=$script:EtlUnconfirmed[$script:EtlUnconfirmed.Count-1]
[EtherPhaseAJob]::Close($owner.job)
if($owner.inputHandle){$owner.inputHandle.Dispose()};if($owner.exeHandle){$owner.exeHandle.Dispose()};if($owner.outputHandle){$owner.outputHandle.Dispose()};if($owner.pipes){$owner.pipes.Dispose()};foreach($h in $owner.dependencyHandles){$h.Dispose()}
$script:EtlUnconfirmed.RemoveAt($script:EtlUnconfirmed.Count-1)
Write-Output 'PASS injected job-close failure preserves earlier real worker failure'
function Close-PhaseAEtlChildHandles($Child) {return @{ThreadClose='CLOSED';ProcessClose='FAILED';ProcessError='INJECTED'}}
$r=Invoke-PhaseAEtlWorker -Executable $exe -ExecutableHash $hash -ExperimentDirectory (New-Input 'CRASH') -TimeoutMs 5000
function Close-PhaseAEtlChildHandles($Child) {return $Child.CloseObserved()}
if ($r.classification -cne 'WORKER_FAILED' -or $r.exitCode -ne 9 -or $r.cleanup -cne 'FAILED' -or $r.close.ProcessClose -cne 'FAILED') {throw 'HANDLE_CLOSE_FAILURE_NOT_RETAINED'}
$owner=$script:EtlUnconfirmed[$script:EtlUnconfirmed.Count-1]
# The injected callback did not touch the real handles; close them only after
# the manager reported and retained the failure.
$actual=$owner.child.CloseObserved()
if ($actual.ProcessClose -cne 'CLOSED' -or $actual.ThreadClose -cne 'CLOSED') {throw 'TEST_HANDLE_RELEASE_FAILED'}
if($owner.inputHandle){$owner.inputHandle.Dispose()};if($owner.exeHandle){$owner.exeHandle.Dispose()};if($owner.outputHandle){$owner.outputHandle.Dispose()};if($owner.pipes){$owner.pipes.Dispose()};foreach($h in $owner.dependencyHandles){$h.Dispose()}
$script:EtlUnconfirmed.RemoveAt($script:EtlUnconfirmed.Count-1)
Write-Output 'PASS injected process-handle close failure retains earlier real worker failure'
function Close-PhaseAEtlJob($Job) {throw 'INJECTED_CLOSE_FAILURE'}
$r=Invoke-PhaseAEtlWorker -Executable $exe -ExecutableHash $hash -ExperimentDirectory (New-Input 'OK') -TimeoutMs 5000
function Close-PhaseAEtlJob($Job) {[EtherPhaseAJob]::Close($Job)}
if ($r.classification -cne 'CLEANUP_UNCONFIRMED' -or $r.operationClassification -cne 'COMPLETE' -or $r.cleanup -cne 'FAILED') {throw 'CLEANUP_FAILURE_PROMOTED_TO_COMPLETE'}
$owner=$script:EtlUnconfirmed[$script:EtlUnconfirmed.Count-1]
[EtherPhaseAJob]::Close($owner.job)
if($owner.inputHandle){$owner.inputHandle.Dispose()};if($owner.exeHandle){$owner.exeHandle.Dispose()};if($owner.outputHandle){$owner.outputHandle.Dispose()};if($owner.pipes){$owner.pipes.Dispose()};foreach($h in $owner.dependencyHandles){$h.Dispose()}
$script:EtlUnconfirmed.RemoveAt($script:EtlUnconfirmed.Count-1)
Write-Output 'PASS cleanup failure cannot be presented as completed run'
