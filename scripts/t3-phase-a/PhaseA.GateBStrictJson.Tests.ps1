$ErrorActionPreference='Stop'
. "$PSScriptRoot/PhaseA.GateBReceiptValidation.ps1"
$valid='{"Source":"CAPTURED_UNTRUSTED","Status":"UNVERIFIED","nested":{"a":1},"arr":[true,false,null]}'
if(-not [GateBStrictJson]::Validate($valid)){throw 'VALID_JSON_REJECTED'}
foreach($bad in @(
 '{"a":1,"a":2}',
 '{"a":1,"\u0061":2}',
 '{"A":1,"a":2}',
 '{"outer":{"x":1,"x":2}}',
 '{"a":"\q"}',
 '{"a":1,}',
 '{"a":1} trailing',
 '{"a":01}'
)) {if([GateBStrictJson]::Validate($bad)){throw 'MALFORMED_OR_DUPLICATE_JSON_ACCEPTED'}}
Write-Output 'PASS strict JSON rejects duplicate, escaped, nested and malformed properties'
$root=[IO.Path]::GetTempPath().TrimEnd('\')
$id=[Guid]::NewGuid().ToString('N')
$dry=@{Source='CAPTURED_UNTRUSTED';Status='UNVERIFIED';Experiment=$id;nativeCalls=0;session='Orion-T3-GateB-Feasibility';maxMiB=64;captureSeconds=15}
if(-not (Test-GateBWorkerReceipt ($dry | ConvertTo-Json -Compress) $id $root $false)){throw 'VALID_DRY_RECEIPT_REJECTED'}
$dry['extra']='UNTRUSTED'
if(Test-GateBWorkerReceipt ($dry | ConvertTo-Json -Compress) $id $root $false){throw 'DRY_UNKNOWN_FIELD_ACCEPTED'}
$dry.Remove('extra');$dry.captureSeconds='15'
if(Test-GateBWorkerReceipt ($dry | ConvertTo-Json -Compress) $id $root $false){throw 'DRY_WRONG_TYPE_ACCEPTED'}
Write-Output 'PASS dry-run receipt requires exact fields and typed values'
$receipt=@{Source='CAPTURED_UNTRUSTED';Status='UNVERIFIED';Experiment=$id;state='FINALIZATION_UNVERIFIED';stop='SESSION_STOPPED';statistics=@{FinalStatistics='INCOMPLETE';StatisticsValid=$false;EventsLost=$null;LogBuffersLost=$null;RealTimeBuffersLost=$null};code=0;attempt=[guid]::NewGuid().ToString('N');session='Orion-T3-GateB-Feasibility';etl=(Join-Path $root 'fixture.etl');vmDisposalRequired=$true;vmDisposalConfirmed=$false;operationFailure=$null;workloadFailure=$null;controllerException=$null;cleanupFailure=$null;cleanupException=$null;initial=$null;final=@{Code=0};workload=@{Outcome='READ_COMPLETE';ExpectedSha256='a';ActualSha256='a';StartedUtc='x';CompletedUtc='x';RequestedBytes=1;ActualBytes=1;ProcessId=1;ThreadId=1;StartTicks=1;EndTicks=2}}
$json=$receipt | ConvertTo-Json -Compress -Depth 6
if(-not (Test-GateBWorkerReceipt $json $id $root $true)){throw 'VALID_RECEIPT_REJECTED'}
$receipt.statistics['unexpected']='not-allowed'
if(Test-GateBWorkerReceipt ($receipt | ConvertTo-Json -Compress -Depth 6) $id $root $true){throw 'UNEXPECTED_NESTED_FIELD_ACCEPTED'}
$receipt.statistics.Remove('unexpected')
$receipt.statistics.EventsLost=0
if(Test-GateBWorkerReceipt ($receipt | ConvertTo-Json -Compress -Depth 6) $id $root $true){throw 'UNKNOWN_STATISTICS_PROMOTED'}
$receipt.statistics.EventsLost=$null;$receipt.vmDisposalRequired=$false
if(Test-GateBWorkerReceipt ($receipt | ConvertTo-Json -Compress -Depth 6) $id $root $true){throw 'DISPOSAL_CONTRADICTION_ACCEPTED'}
$receipt.vmDisposalRequired=$true;$receipt.Status='PASS'
if(Test-GateBWorkerReceipt ($receipt | ConvertTo-Json -Compress -Depth 6) $id $root $true){throw 'LIVE_PROMOTION_ACCEPTED'}
Write-Output 'PASS receipt schema rejects unknown-as-zero, disposal contradiction and LIVE promotion'
