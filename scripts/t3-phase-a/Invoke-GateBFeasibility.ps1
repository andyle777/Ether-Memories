[CmdletBinding()]
param(
 [Parameter(Mandatory=$true)][string]$ParentDirectory,
 [Parameter(Mandatory=$true)][string]$ExpectedExecutableSha256,
 [switch]$ExperimentalDisposableVM,
 [string]$OwnerApproval='',
 [string]$InternalResultPath='',
 [ValidateSet('','VALID','NONZERO','CRASH','ABRUPT','HANG','MISSING','MALFORMED','DUPLICATE','CONTRADICT','REPLAY','OVERSIZE')][string]$OfflineTestCase=''
)
$ErrorActionPreference='Stop'
$disposalRequired=[bool]$ExperimentalDisposableVM
$disposalConfirmed=$false
trap {
 # Do not leak exception text or local paths; uncertainty never removes the VM requirement.
 @{classification='UNVERIFIED';worker='WRAPPER_FAILED';receipt='NOT_VALIDATED';vmDisposalRequired=$disposalRequired;vmDisposalConfirmed=$disposalConfirmed;source='CAPTURED_UNTRUSTED'} | ConvertTo-Json -Compress
 exit 2
}
. "$PSScriptRoot/PhaseA.EtlSupervisor.ps1"
. "$PSScriptRoot/PhaseA.GateBReceiptValidation.ps1"
if($ExperimentalDisposableVM -and $OwnerApproval -cne 'SEPARATELY_AUTHORIZED'){throw 'EXPERIMENT_NOT_AUTHORIZED'}
if($OfflineTestCase -and -not $ExperimentalDisposableVM){throw 'OFFLINE_TEST_MODE_INVALID'}
$parent=Get-Item -LiteralPath $ParentDirectory -Force
if(-not $parent.PSIsContainer -or ($parent.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'PARENT_INVALID'}
$root=Join-Path $parent.FullName ('orion-gate-b-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path $root -ErrorAction Stop
$inputPath=Join-Path $root 'input.etl'
$config=if($OfflineTestCase){$OfflineTestCase}elseif($ExperimentalDisposableVM){'{"mode":"experimental-disposable-vm","ownerApproval":"separately-authorized"}'}else{'{"mode":"dry-run"}'}
$file=New-Object IO.FileStream($inputPath,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
try {$bytes=[Text.Encoding]::UTF8.GetBytes($config);$file.Write($bytes,0,$bytes.Length);$file.Flush($true)} finally {$file.Dispose()}
$exe=Join-Path $PSScriptRoot 'gate-b-controller/bin/Debug/net10.0/GateBController.exe'
if($OfflineTestCase){$exe=Join-Path $PSScriptRoot 'etl-decoder/test-worker/bin/Debug/net10.0/TestWorker.exe'}
$binaryDir=[IO.Path]::GetDirectoryName($exe)
# These are review pins, not a trust root: the script itself and runtime must
# also be reviewed. Held read-only handles prevent replacement during launch.
$pins=@{
 'GateBController.dll'='5aca8c2888518fe12fbf5474d6bfc6f3f25c74d5d727b3dfd1b12283d7189597'
 'GateBController.deps.json'='e59c0531a3596f5b478aea28f149f9775de5eba55c0b0ca7772406bd0211bfb4'
 'GateBController.runtimeconfig.json'='256dda2706e1151bb95987b6b5be610bf68d64e058285b19e7e958222fc90414'
}
$held=New-Object 'System.Collections.Generic.List[System.IO.FileStream]'
try {
 foreach($name in $(if($OfflineTestCase){@()}else{$pins.Keys})) {
  $h=New-Object IO.FileStream((Join-Path $binaryDir $name),[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
  $held.Add($h)
  if((Get-FileHash -InputStream $h -Algorithm SHA256).Hash -ine $pins[$name]){throw 'CONTROLLER_DEPENDENCY_HASH_MISMATCH'}
 }
 $timeout=if($OfflineTestCase -ceq 'HANG'){1500}else{45000}
 $r=Invoke-PhaseAEtlWorker -Executable $exe -ExecutableHash $ExpectedExecutableSha256 -ExperimentDirectory $root -TimeoutMs $timeout -TerminationMs 5000
} finally {foreach($h in $held){$h.Dispose()}}
$evidence='NOT_WRITTEN'
$receipt='NOT_VALIDATED'
if($r.classification -ceq 'COMPLETE') {
 $receipt=if(Test-GateBWorkerReceipt -Json $r.stdout -Experiment $r.experiment -Root $root -Experimental $disposalRequired){'VALID'}else{'INVALID'}
}
if($r.stdout -cne 'NOT_CAPTURED') {
 try {
  $out=New-Object IO.FileStream((Join-Path $root 'worker-output.private.json'),[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
  try {$bytes=[Text.Encoding]::UTF8.GetBytes($r.stdout);$out.Write($bytes,0,$bytes.Length);$out.Flush($true)} finally {$out.Dispose()}
  $evidence='DURABLE_UNTRUSTED'
 } catch {$evidence='WRITE_FAILED'}
}
if($InternalResultPath){
 # Private handoff is local untrusted data, not an authenticated receipt. The
 # caller must independently validate it and must not publish its contents.
 $private=@{version=1;experimentRoot=$root;experiment=$r.experiment;receiptJson=if($receipt -ceq 'VALID'){$r.stdout}else{$null};workerClassification=$r.classification;workerExitCode=$r.exitCode;workerCleanup=$r.cleanup;receiptValidation=$receipt;experimental=$disposalRequired} | ConvertTo-Json -Compress -Depth 8
 $handoff=New-Object IO.FileStream($InternalResultPath,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
 try {$privateBytes=[Text.Encoding]::UTF8.GetBytes($private);$handoff.Write($privateBytes,0,$privateBytes.Length);$handoff.Flush($true)} finally {$handoff.Dispose()}
}
# Process termination is not an ETW-session stop. The disposable VM must be
# discarded after the experimental job, including when the worker times out.
@{classification='UNVERIFIED';worker=$r.classification;workerTerminated=$r.terminationConfirmed;workerCleanup=$r.cleanup;workerExitCode=$r.exitCode;experiment=$r.experiment;journal=$r.journal;evidence=$evidence;receipt=$receipt;vmDisposalRequired=$disposalRequired;vmDisposalConfirmed=$disposalConfirmed;source='CAPTURED_UNTRUSTED'} | ConvertTo-Json -Compress -Depth 5
if($r.classification -cne 'COMPLETE' -or $r.cleanup -cne 'CONFIRMED' -or $evidence -cne 'DURABLE_UNTRUSTED' -or $receipt -cne 'VALID'){exit 2}
exit 0
