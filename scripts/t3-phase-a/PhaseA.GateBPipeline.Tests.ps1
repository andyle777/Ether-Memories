$ErrorActionPreference='Stop'
. "$PSScriptRoot/PhaseA.GateBPipeline.ps1"
function Assert($v,$m){if(-not $v){throw $m}}
function Reject([scriptblock]$b,[string]$name){$bad=$false;try{& $b | Out-Null}catch{$bad=$true};Assert $bad ('ACCEPTED_'+$name)}
$id='d'*32
$parser=@{Source='CAPTURED_UNTRUSTED';Status='UNVERIFIED';Experiment=$id;Reason='UNTRUSTED_CAPTURE';EventsLost=0;BufferLoss='UNKNOWN';DynamicDecodedEvents=1;PendingOperations=0;Events=@()}
$json=$parser | ConvertTo-Json -Compress -Depth 10
$p=Get-GateBParserProjection $json $id
Assert (-not $p.readPresent -and -not $p.createPresent -and -not $p.completionPresent) 'EMPTY_TRACE_FALSE_FILEIO'
$withPath=$parser.Clone();$withPath.Events=@(
 @{Kind='READ';ProcessId=1;ThreadId=2;TimeStampQpc=3;Version=2;Operation=9;FileObject=5;FileKey=1;Path='C:\Users\Private\secret';RequestedBytes=4;NativeStatus=0;ExtraInfo=0;Matched=$false},
 @{Kind='OP_END';ProcessId=1;ThreadId=2;TimeStampQpc=4;Version=2;Operation=9;FileObject=5;FileKey=1;Path='C:\Users\Private\secret';RequestedBytes=0;NativeStatus=0;ExtraInfo=4;Matched=$true}
)
$projection=Get-GateBParserProjection ($withPath | ConvertTo-Json -Compress -Depth 10) $id
Assert ($projection.readPresent -and $projection.completionPresent -and (($projection | ConvertTo-Json -Compress) -notmatch 'Private|secret|C:\\')) 'RAW_PATH_LEAKED'
foreach($name in @('LIVE','MISSING_COMPLETION','LOST','BAD_REASON','WRONG_EXPERIMENT')){
 $x=$parser.Clone();switch($name){'LIVE'{$x.Source='LIVE'} 'LOST'{$x.EventsLost=1} 'BAD_REASON'{$x.Reason='COMPLETION_MISSING'} 'WRONG_EXPERIMENT'{$x.Experiment='f'*32} 'MISSING_COMPLETION'{$x.Events=@(@{Kind='READ';ProcessId=1;ThreadId=2;TimeStampQpc=3;Version=2;Operation=9;FileObject=5;FileKey=1;Path='C:\Users\Private\secret';RequestedBytes=4;NativeStatus=0;ExtraInfo=0;Matched=$false})}}
 $s=$x | ConvertTo-Json -Compress -Depth 10;Reject {Get-GateBParserProjection $s $id} $name
}
Reject {Get-GateBParserProjection ($json -replace '"Source":','"Source":"LIVE","Source":') $id} 'DUPLICATE_PARSER_FIELD'
$outer=[pscustomobject]@{classification='UNVERIFIED';worker='COMPLETE';workerCleanup='CONFIRMED';source='CAPTURED_UNTRUSTED';experiment=$id;vmDisposalRequired=$false;vmDisposalConfirmed=$false}
$hand=[pscustomobject]@{experiment=$id;receiptValidation='VALID';workerClassification='COMPLETE';workerCleanup='CONFIRMED';experimental=$false}
$worker=[pscustomobject]@{Source='CAPTURED_UNTRUSTED';Status='UNVERIFIED';Experiment=$id;nativeCalls=0}
$summary=New-GateBPipelineSummary $outer $hand $worker $p ('a'*40) ('b'*64) ('c'*64) $true
$validated=ConvertTo-GateBValidatedSummary $summary
Assert ($validated -notmatch 'C:\\Users|S-1-5|"securityStatus":"PASS"') 'PRIVACY_OR_PROMOTION'
$bad=($summary | ConvertFrom-Json);$bad.summary | Add-Member -NotePropertyName personalPath -NotePropertyValue 'C:\Users\Private\secret'
Reject {ConvertTo-GateBValidatedSummary ($bad | ConvertTo-Json -Compress -Depth 10)} 'SUMMARY_UNEXPECTED_FIELD'
$bad=($summary | ConvertFrom-Json);$bad.summary.securityStatus='LIVE';Reject {ConvertTo-GateBValidatedSummary ($bad | ConvertTo-Json -Compress -Depth 10)} 'SUMMARY_LIVE'
$bad=($summary | ConvertFrom-Json);$bad.summary.eventsLost=0;Reject {ConvertTo-GateBValidatedSummary ($bad | ConvertTo-Json -Compress -Depth 10)} 'UNKNOWN_LOSS_ZERO'
$bad=($summary | ConvertFrom-Json);$bad.summary.readPresent=$true;Reject {ConvertTo-GateBValidatedSummary ($bad | ConvertTo-Json -Compress -Depth 10)} 'FIXTURE_CLAIMED_FILEIO'
$bad=($summary | ConvertFrom-Json);$bad.summary.sourceSha='C:\Users\Private\secret';Reject {ConvertTo-GateBValidatedSummary ($bad | ConvertTo-Json -Compress -Depth 10)} 'PATH_LEAK'
$validRecord=@{sourceSha=('a'*40);controllerSha256=('b'*64);decoderSha256=('c'*64);experiment=$id;requestedBytes=1;actualBytes=1;fixtureDigestMatch=$true;stop='SESSION_STOPPED';statisticsValid=$true;eventsLost=[uint32]0;logBuffersLost=[uint32]0;realTimeBuffersLost=[uint32]0;createPresent=$true;readPresent=$true;completionPresent=$true}
$hostSummary=ConvertTo-PhaseAGateBPublicSummary $validRecord | ConvertFrom-Json
$hostSummary.eventsLost=$true
$hostEnvelope=@{classification='UNVERIFIED';inputProvenance='UNTRUSTED_CAPTURE';summary=$hostSummary} | ConvertTo-Json -Compress -Depth 10
Reject {ConvertTo-GateBValidatedSummary $hostEnvelope} 'BOOLEAN_LOSS_COERCED'
$hostSummary.eventsLost=0;$hostSummary.stop='STOP_UNCONFIRMED'
$hostEnvelope=@{classification='UNVERIFIED';inputProvenance='UNTRUSTED_CAPTURE';summary=$hostSummary} | ConvertTo-Json -Compress -Depth 10
Reject {ConvertTo-GateBValidatedSummary $hostEnvelope} 'HOSTED_SUMMARY_CONTRADICTION'
Reject {ConvertTo-GateBValidatedSummary ($summary -replace '"classification":','"classification":"LIVE","classification":')} 'SUMMARY_DUPLICATE'
$badWorker=[pscustomobject]@{Source='LIVE';Status='PASS';Experiment=$id;nativeCalls=0};Reject {New-GateBPipelineSummary $outer $hand $badWorker $p ('a'*40) ('b'*64) ('c'*64) $true} 'WORKER_LIVE'
$badOuter=[pscustomobject]@{classification='UNVERIFIED';worker='COMPLETE';workerCleanup='CONFIRMED';source='CAPTURED_UNTRUSTED';experiment=('e'*32);vmDisposalRequired=$false};Reject {New-GateBPipelineSummary $badOuter $hand $worker $p ('a'*40) ('b'*64) ('c'*64) $true} 'MISMATCHED_WORKER'
$bytes=[Text.Encoding]::UTF8.GetBytes("ORION Gate B synthetic fixture v1`n");$sha=[Security.Cryptography.SHA256]::Create();try{$fixtureSha=([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose()}
$hostOuter=[pscustomobject]@{classification='UNVERIFIED';worker='COMPLETE';workerCleanup='CONFIRMED';source='CAPTURED_UNTRUSTED';experiment=$id;vmDisposalRequired=$true;vmDisposalConfirmed=$false}
$hostHand=[pscustomobject]@{experiment=$id;receiptValidation='VALID';workerClassification='COMPLETE';workerCleanup='CONFIRMED';experimental=$true}
$hostWorker=[pscustomobject]@{Source='CAPTURED_UNTRUSTED';Status='UNVERIFIED';Experiment=$id;state='FINALIZATION_UNVERIFIED';stop='SESSION_STOPPED';code=0;operationFailure=$null;workloadFailure=$null;controllerException=$null;cleanupFailure='STOP_EXCEPTION';cleanupException=$null;workload=[pscustomobject]@{Outcome='READ_COMPLETE';RequestedBytes=$bytes.Length;ActualBytes=$bytes.Length;ExpectedSha256=$fixtureSha;ActualSha256=$fixtureSha};statistics=[pscustomobject]@{StatisticsValid=$false;EventsLost=$null;LogBuffersLost=$null;RealTimeBuffersLost=$null}}
Reject {New-GateBPipelineSummary $hostOuter $hostHand $hostWorker $p ('a'*40) ('b'*64) ('c'*64) $false} 'WORKER_CLEANUP_CONTRADICTION'
Write-Output 'PASS strict projection rejects missing completion, loss, duplicate, contradiction, path and LIVE promotion'
$fixture=Join-Path $PSScriptRoot 'external-fixtures/SelfDescribingSingleEvent.etl'
$exe=Join-Path $PSScriptRoot 'etl-decoder/bin/Debug/net10.0/EtLDecoder.exe';$hash=(Get-FileHash $exe -Algorithm SHA256).Hash
$dir=Join-Path ([IO.Path]::GetTempPath()) ('orion-pipeline-'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($dir)
$r=Invoke-PhaseAEtlWorker -Executable $exe -ExecutableHash $hash -ExperimentDirectory $dir -TimeoutMs 10000
Assert ($r.classification -ceq 'INPUT_MISSING') 'MISSING_ETL_ACCEPTED'
$dir=Join-Path ([IO.Path]::GetTempPath()) ('orion-pipeline-'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($dir)
[IO.File]::WriteAllText((Join-Path $dir 'input.etl'),'not an ETL')
$r=Invoke-PhaseAEtlWorker -Executable $exe -ExecutableHash $hash -ExperimentDirectory $dir -TimeoutMs 10000
Assert ($r.classification -ceq 'WORKER_FAILED' -and $r.cleanup -ceq 'CONFIRMED') 'CORRUPT_ETL_ACCEPTED'
$workerExe=Join-Path $PSScriptRoot 'etl-decoder/test-worker/bin/Debug/net10.0/TestWorker.exe';$workerHash=(Get-FileHash $workerExe -Algorithm SHA256).Hash
foreach($case in @('CRASH','HANG')) {
 $tmp=Join-Path ([IO.Path]::GetTempPath()) ('orion-pipeline-'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($tmp);[IO.File]::WriteAllText((Join-Path $tmp 'input.etl'),$case)
 $r=Invoke-PhaseAEtlWorker -Executable $workerExe -ExecutableHash $workerHash -ExperimentDirectory $tmp -TimeoutMs 1500
 Assert ($r.classification -ceq $(if($case -ceq 'CRASH'){'WORKER_FAILED'}else{'TIMEOUT'}) -and $r.terminationConfirmed -and $r.cleanup -ceq 'CONFIRMED') ('DECODER_FAILURE_'+$case)
}
$real=Join-Path ([IO.Path]::GetTempPath()) ('orion-pipeline-'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($real);[IO.File]::Copy($fixture,(Join-Path $real 'input.etl'))
$r=Invoke-PhaseAEtlWorker -Executable $exe -ExecutableHash $hash -ExperimentDirectory $real -TimeoutMs 10000
Assert ($r.classification -ceq 'COMPLETE' -and $r.cleanup -ceq 'CONFIRMED') 'REAL_ETL_FAILED'
$p=Get-GateBParserProjection $r.outputJson $r.experiment
Assert (-not $p.readPresent -and -not $p.createPresent -and -not $p.completionPresent) 'REAL_FIXTURE_MISLABELED'
Write-Output 'PASS real self-describing ETL decoded; missing/corrupt input, crash and timeout fail closed'
$controller=Join-Path $PSScriptRoot 'gate-b-controller/bin/Debug/net10.0/GateBController.exe'
$controllerHash=(Get-FileHash -LiteralPath $controller -Algorithm SHA256).Hash.ToLowerInvariant();$decoderHash=$hash.ToLowerInvariant()
$out=Join-Path ([IO.Path]::GetTempPath()) ('orion-summary-'+[guid]::NewGuid().ToString('N')+'.json')
$cli=Join-Path $PSScriptRoot 'Invoke-GateBPipeline.ps1'
$response=& powershell.exe -NoProfile -File $cli -Mode OfflineFixture -ParentDirectory ([IO.Path]::GetTempPath()) -FixturePath $fixture -SourceSha ('a'*40) -ExpectedControllerSha256 $controllerHash -ExpectedDecoderSha256 $decoderHash -SummaryPath $out
Assert ($LASTEXITCODE -eq 0 -and $response -ceq '{"classification":"UNVERIFIED","diagnostic":"SUMMARY_WRITTEN"}') 'WRAPPER_PARSER_SUMMARY_FAILED'
$s=Get-Content -LiteralPath $out -Raw | ConvertFrom-Json
Assert ($s.inputProvenance -ceq 'SELF_DESCRIBING_OFFLINE_FIXTURE' -and -not $s.summary.readPresent -and -not $s.summary.createPresent -and $s.summary.securityStatus -ceq 'UNVERIFIED' -and $null -eq $s.summary.eventsLost) 'FULL_PIPELINE_PROVENANCE_FAILED'
$verified=Join-Path ([IO.Path]::GetTempPath()) ('orion-validated-'+[guid]::NewGuid().ToString('N')+'.json')
$response=& powershell.exe -NoProfile -File $cli -Mode ValidateSummary -SummaryPath $out -ValidatedSummaryPath $verified
Assert ($LASTEXITCODE -eq 0 -and $response -ceq '{"classification":"UNVERIFIED","diagnostic":"SUMMARY_WRITTEN"}' -and [IO.File]::Exists($verified)) 'SUMMARY_RECONSTRUCTION_FAILED'
$response=& powershell.exe -NoProfile -File $cli -Mode ValidateSummary -SummaryPath $out -ValidatedSummaryPath $verified
Assert ($LASTEXITCODE -eq 2 -and $response -ceq '{"classification":"UNVERIFIED","diagnostic":"PIPELINE_INCOMPLETE"}') 'SUMMARY_OVERWRITE_ACCEPTED'
$missing=Join-Path ([IO.Path]::GetTempPath()) ('orion-missing-'+[guid]::NewGuid().ToString('N')+'.json')
$response=& powershell.exe -NoProfile -File $cli -Mode HostedCapture -SummaryPath $missing
Assert ($LASTEXITCODE -eq 2 -and $response -ceq '{"classification":"UNVERIFIED","diagnostic":"PIPELINE_INCOMPLETE"}' -and -not [IO.File]::Exists($missing)) 'HOSTED_CAPTURE_NOT_DISABLED'
Write-Output 'PASS full offline wrapper to decoder to reconstructed summary; hosted capture remains disabled'
