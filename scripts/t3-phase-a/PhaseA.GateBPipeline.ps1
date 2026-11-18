# Bounded Gate B evidence projection. Neither the controller nor ETL output is
# authenticated; successful offline decoding never supplies security acceptance.
. "$PSScriptRoot/PhaseA.GateBSummary.ps1"
. "$PSScriptRoot/PhaseA.EtlSupervisor.ps1"
. "$PSScriptRoot/PhaseA.GateBReceiptValidation.ps1"
if(-not ('GateBStrictJson' -as [type])) { Add-Type -Path "$PSScriptRoot/PhaseA.GateBStrictJson.cs" -ReferencedAssemblies System.Web.Extensions }
function ConvertFrom-GateBStrictJson([string]$Json) {
 if([string]::IsNullOrEmpty($Json) -or -not [GateBStrictJson]::Validate($Json)){throw 'JSON_INVALID'}
 return ($Json | ConvertFrom-Json -ErrorAction Stop)
}
function Assert-GateBProperties($Object,[string[]]$Names) {
 if($null -eq $Object -or $Object -is [array] -or $Object -is [string]){throw 'OBJECT_INVALID'}
 $actual=@($Object.PSObject.Properties.Name)
 if($actual.Count -ne $Names.Count -or @($actual | Where-Object {$_ -cnotin $Names}).Count){throw 'OBJECT_SCHEMA_INVALID'}
}
function Get-GateBParserProjection([string]$Json,[string]$Experiment) {
 $p=ConvertFrom-GateBStrictJson $Json
 Assert-GateBProperties $p @('Source','Status','Experiment','Reason','EventsLost','BufferLoss','DynamicDecodedEvents','PendingOperations','Events')
 if($p.Source -cne 'CAPTURED_UNTRUSTED' -or $p.Status -cne 'UNVERIFIED' -or $p.Experiment -cne $Experiment){throw 'PARSER_BINDING_INVALID'}
 if($p.Reason -cne 'UNTRUSTED_CAPTURE' -or $p.EventsLost -isnot [int] -or $p.EventsLost -ne 0 -or $p.BufferLoss -cne 'UNKNOWN' -or $p.PendingOperations -isnot [int] -or $p.PendingOperations -ne 0 -or $p.DynamicDecodedEvents -isnot [int] -or $p.DynamicDecodedEvents -lt 0 -or $p.Events -isnot [array]){throw 'PARSER_INCOMPLETE'}
 $create=$false;$read=$false;$completion=$false;$pending=@{};$seen=@{}
 foreach($e in $p.Events) {
  Assert-GateBProperties $e @('Kind','ProcessId','ThreadId','TimeStampQpc','Version','Operation','FileObject','FileKey','Path','RequestedBytes','NativeStatus','ExtraInfo','Matched')
  if($e.Kind -cnotin @('PROCESS_START','PROCESS_END','THREAD_START','THREAD_END','FILE_NAME','CREATE','READ','OP_END')){throw 'PARSER_EVENT_INVALID'}
  if($e.Kind -in @('CREATE','READ')){
   if(($e.Operation -isnot [int] -and $e.Operation -isnot [long] -and $e.Operation -isnot [uint32] -and $e.Operation -isnot [uint64] -and $e.Operation -isnot [decimal]) -or [decimal]$e.Operation -le 0 -or [decimal]::Truncate([decimal]$e.Operation) -ne [decimal]$e.Operation){throw 'PARSER_OPERATION_INVALID'}
   $id=[string]$e.Operation;if($seen.ContainsKey($id)){throw 'PARSER_REPLAY'};$seen[$id]=$true;$pending[$id]=$true
   if($e.Kind -ceq 'CREATE'){$create=$true}else{$read=$true}
  }
  if($e.Kind -ceq 'OP_END'){
   if($e.Matched -isnot [bool] -or ($e.Operation -isnot [int] -and $e.Operation -isnot [long] -and $e.Operation -isnot [uint32] -and $e.Operation -isnot [uint64] -and $e.Operation -isnot [decimal]) -or [decimal]$e.Operation -le 0 -or [decimal]::Truncate([decimal]$e.Operation) -ne [decimal]$e.Operation){throw 'PARSER_COMPLETION_INVALID'}
   $id=[string]$e.Operation
   if($e.Matched){if(-not $pending.ContainsKey($id)){throw 'PARSER_COMPLETION_INVALID'};$pending.Remove($id);$completion=$true}
   elseif($pending.ContainsKey($id)){throw 'PARSER_COMPLETION_CONTRADICTION'}
  }
 }
 if($pending.Count -ne 0){throw 'PARSER_COMPLETION_MISSING'}
 # Merely seeing events does not establish same-operation correlation.
 return @{createPresent=$create;readPresent=$read;completionPresent=$completion;eventsLost=$p.EventsLost}
}
function New-GateBPipelineSummary($Outer,$Handoff,$Worker,$Projection,[string]$SourceSha,[string]$ControllerSha,[string]$DecoderSha,[bool]$Offline) {
 if($Outer.classification -cne 'UNVERIFIED' -or $Outer.worker -cne 'COMPLETE' -or $Outer.workerCleanup -cne 'CONFIRMED' -or $Outer.source -cne 'CAPTURED_UNTRUSTED' -or $Outer.experiment -cne $Handoff.experiment -or $Handoff.receiptValidation -cne 'VALID' -or $Handoff.workerClassification -cne 'COMPLETE' -or $Handoff.workerCleanup -cne 'CONFIRMED' -or $Worker.Source -cne 'CAPTURED_UNTRUSTED' -or $Worker.Status -cne 'UNVERIFIED' -or $Worker.Experiment -cne $Outer.experiment){throw 'WORKER_BINDING_INVALID'}
 $record=@{sourceSha=$SourceSha;controllerSha256=$ControllerSha;decoderSha256=$DecoderSha;experiment=$Outer.experiment;requestedBytes=0;actualBytes=0;fixtureDigestMatch=$false;stop='NOT_OBSERVED';statisticsValid=$false;eventsLost=$null;logBuffersLost=$null;realTimeBuffersLost=$null;createPresent=$Projection.createPresent;readPresent=$Projection.readPresent;completionPresent=$Projection.completionPresent}
 if($Offline) {
  if($Worker.nativeCalls -ne 0 -or $Outer.vmDisposalRequired -ne $false -or $Handoff.experimental -ne $false -or $record.createPresent -or $record.readPresent -or $record.completionPresent){throw 'OFFLINE_CONTRADICTION'}
 } else {
  if($Outer.vmDisposalRequired -ne $true -or $Outer.vmDisposalConfirmed -ne $false -or $Handoff.experimental -ne $true){throw 'DISPOSAL_INVALID'}
  if($Worker.state -cne 'FINALIZATION_UNVERIFIED' -or $Worker.stop -cne 'SESSION_STOPPED' -or $Worker.code -ne 0){throw 'WORKER_STATE_INCOMPLETE'}
  foreach($name in @('operationFailure','workloadFailure','controllerException','cleanupFailure','cleanupException')) {
   if(-not $Worker.PSObject.Properties[$name] -or $null -ne $Worker.$name){throw 'WORKER_FAILURE_CONTRADICTION'}
  }
  if($Worker.workload.Outcome -cne 'READ_COMPLETE'){throw 'WORKLOAD_INCOMPLETE'}
  $content=[Text.Encoding]::UTF8.GetBytes("ORION Gate B synthetic fixture v1`n")
  $hasher=[Security.Cryptography.SHA256]::Create();try{$fixtureHash=([BitConverter]::ToString($hasher.ComputeHash($content))).Replace('-','').ToLowerInvariant()}finally{$hasher.Dispose()}
  if($Worker.workload.RequestedBytes -isnot [int] -or $Worker.workload.ActualBytes -isnot [int] -or $Worker.workload.RequestedBytes -ne $content.Length -or $Worker.workload.ActualBytes -ne $content.Length -or $Worker.workload.ExpectedSha256 -cne $fixtureHash -or $Worker.workload.ActualSha256 -cne $fixtureHash){throw 'WORKLOAD_CONTRADICTION'}
  $record.requestedBytes=$Worker.workload.RequestedBytes;$record.actualBytes=$Worker.workload.ActualBytes;$record.fixtureDigestMatch=$true
  $record.stop=$Worker.stop;$record.statisticsValid=$Worker.statistics.StatisticsValid -ceq $true
  if($record.statisticsValid){
   foreach($pair in @(@('eventsLost','EventsLost'),@('logBuffersLost','LogBuffersLost'),@('realTimeBuffersLost','RealTimeBuffersLost'))) {
    $v=$Worker.statistics.($pair[1]);if(($v -isnot [int] -and $v -isnot [long] -and $v -isnot [uint32]) -or [decimal]$v -lt 0 -or [decimal]$v -gt [uint32]::MaxValue){throw 'STATISTICS_INVALID'}
    $record[$pair[0]]=[uint32]$v
   }
   if($record.eventsLost -ne $Projection.eventsLost){throw 'LOSS_CONTRADICTION'}
  } elseif($null -ne $Worker.statistics.EventsLost -or $null -ne $Worker.statistics.LogBuffersLost -or $null -ne $Worker.statistics.RealTimeBuffersLost){throw 'UNKNOWN_LOSS_CONTRADICTION'}
 }
 $summary=ConvertFrom-GateBStrictJson (ConvertTo-PhaseAGateBPublicSummary $record)
 return @{classification='UNVERIFIED';inputProvenance=$(if($Offline){'SELF_DESCRIBING_OFFLINE_FIXTURE'}else{'UNTRUSTED_CAPTURE'});summary=$summary} | ConvertTo-Json -Compress -Depth 8
}
function ConvertTo-GateBValidatedSummary([string]$Json) {
 $v=ConvertFrom-GateBStrictJson $Json
 Assert-GateBProperties $v @('classification','inputProvenance','summary')
 if($v.classification -cne 'UNVERIFIED' -or $v.inputProvenance -cnotin @('SELF_DESCRIBING_OFFLINE_FIXTURE','UNTRUSTED_CAPTURE')){throw 'SUMMARY_PROVENANCE_INVALID'}
 $names=@('sourceSha','controllerSha256','decoderSha256','experiment','requestedBytes','actualBytes','fixtureDigestMatch','stop','statisticsValid','eventsLost','logBuffersLost','realTimeBuffersLost','createPresent','readPresent','completionPresent')
 Assert-GateBProperties $v.summary ($names+@('provenance','securityStatus','correlation','limitations'))
 if($v.summary.provenance -cne 'CAPTURED_UNTRUSTED' -or $v.summary.securityStatus -cne 'UNVERIFIED' -or $v.summary.correlation -cne 'UNVERIFIED' -or $v.summary.limitations -isnot [array] -or ($v.summary.limitations -join '|') -cne 'RAW_TRACE_NOT_PUBLIC|EFFECTIVE_THREAD_IDENTITY_UNVERIFIED|NO_SECURITY_ACCEPTANCE'){throw 'SUMMARY_PROMOTION_INVALID'}
 $r=@{};foreach($name in $names){$r[$name]=$v.summary.$name}
 if($r.statisticsValid -ceq $true){foreach($k in @('eventsLost','logBuffersLost','realTimeBuffersLost')){if(($r[$k] -isnot [int] -and $r[$k] -isnot [long] -and $r[$k] -isnot [uint32]) -or [decimal]$r[$k] -lt 0 -or [decimal]$r[$k] -gt [uint32]::MaxValue){throw 'SUMMARY_LOSS_INVALID'};$r[$k]=[uint32]$r[$k]}}
 if($v.inputProvenance -ceq 'SELF_DESCRIBING_OFFLINE_FIXTURE' -and ($r.createPresent -or $r.readPresent -or $r.completionPresent -or $r.statisticsValid -or $r.fixtureDigestMatch -or $r.requestedBytes -ne 0 -or $r.actualBytes -ne 0 -or $r.stop -cne 'NOT_OBSERVED')){throw 'OFFLINE_PROVENANCE_INVALID'}
 if($v.inputProvenance -ceq 'UNTRUSTED_CAPTURE' -and ($r.stop -cne 'SESSION_STOPPED' -or $r.fixtureDigestMatch -ne $true -or $r.requestedBytes -le 0 -or $r.actualBytes -ne $r.requestedBytes)){throw 'CAPTURE_SUMMARY_CONTRADICTION'}
 $s=ConvertFrom-GateBStrictJson (ConvertTo-PhaseAGateBPublicSummary $r)
 return @{classification='UNVERIFIED';inputProvenance=$v.inputProvenance;summary=$s} | ConvertTo-Json -Compress -Depth 8
}
function Write-GateBNewJson([string]$Path,[string]$Json) {
 $f=New-Object IO.FileStream($Path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
 try{$b=[Text.Encoding]::UTF8.GetBytes($Json);$f.Write($b,0,$b.Length);$f.Flush($true)}finally{$f.Dispose()}
}
function Invoke-PhaseAGateBPipelineCore {
 param([string]$Mode,[string]$ParentDirectory,[string]$FixturePath,[string]$SourceSha,[string]$ControllerSha,[string]$DecoderSha)
 # This constant deliberately prevents any hosted capture in this revision.
 $hostedEnabled=$false
 if($Mode -ceq 'HostedCapture' -and -not $hostedEnabled){throw 'HOSTED_CAPTURE_DISABLED'}
 if($Mode -cnotin @('HostedCapture','OfflineFixture')){throw 'MODE_INVALID'}
 foreach($v in @($SourceSha,$ControllerSha,$DecoderSha)){if($v -cnotmatch '^[a-f0-9]+$'){throw 'SOURCE_ID_INVALID'}}
 if($SourceSha.Length -ne 40 -or $ControllerSha.Length -ne 64 -or $DecoderSha.Length -ne 64){throw 'SOURCE_ID_INVALID'}
 $parent=(Get-Item -LiteralPath $ParentDirectory -Force -ErrorAction Stop)
 if(-not $parent.PSIsContainer -or ($parent.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'PARENT_INVALID'}
 $handoffPath=Join-Path $parent.FullName ('orion-handoff-'+[guid]::NewGuid().ToString('N')+'.private.json')
 $wrapper=Join-Path $PSScriptRoot 'Invoke-GateBFeasibility.ps1'
 $args=@('-NoProfile','-File',$wrapper,'-ParentDirectory',$parent.FullName,'-ExpectedExecutableSha256',$ControllerSha,'-InternalResultPath',$handoffPath)
 if($Mode -ceq 'HostedCapture'){$args+=@('-ExperimentalDisposableVM','-OwnerApproval','SEPARATELY_AUTHORIZED')}
 # Capture both child streams privately; neither raw diagnostics nor paths may escape.
 $outerText=(& powershell.exe @args 2>&1 | Out-String);$exit=$LASTEXITCODE
 if($exit -ne 0 -or -not [IO.File]::Exists($handoffPath)){throw 'CONTROLLER_INCOMPLETE'}
 $outer=ConvertFrom-GateBStrictJson $outerText
 $h=ConvertFrom-GateBStrictJson ([IO.File]::ReadAllText($handoffPath))
 Assert-GateBProperties $h @('version','experimentRoot','experiment','receiptJson','workerClassification','workerExitCode','workerCleanup','receiptValidation','experimental')
 if($h.version -ne 1 -or $h.experiment -cnotmatch '^[a-f0-9]{32}$'){throw 'HANDOFF_INVALID'}
 $root=[IO.Path]::GetFullPath($h.experimentRoot);$expectedParent=[IO.Path]::GetFullPath($parent.FullName).TrimEnd('\')
 if([IO.Path]::GetDirectoryName($root) -ine $expectedParent -or [IO.Path]::GetFileName($root) -cnotmatch '^orion-gate-b-[a-f0-9]{32}$'){throw 'HANDOFF_PATH_INVALID'}
 $rootItem=Get-Item -LiteralPath $root -Force -ErrorAction Stop
 if(-not $rootItem.PSIsContainer -or ($rootItem.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'HANDOFF_PATH_INVALID'}
 if(-not (Test-GateBWorkerReceipt -Json $h.receiptJson -Experiment $h.experiment -Root $root -Experimental ([bool]$h.experimental))){throw 'WORKER_SCHEMA_INVALID'}
 $worker=ConvertFrom-GateBStrictJson $h.receiptJson
 if($Mode -ceq 'OfflineFixture') {
  $inputItem=Get-Item -LiteralPath $FixturePath -Force -ErrorAction Stop
  if($inputItem.PSIsContainer -or ($inputItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -or (Get-FileHash -LiteralPath $inputItem.FullName -Algorithm SHA256).Hash -cne '4C312C63C7D366E12B908C49769943886C017497183733BC2C93B8D80E932C7C'){throw 'OFFLINE_FIXTURE_INVALID'}
 } else {
  $input=[IO.Path]::GetFullPath($worker.etl)
  if([IO.Path]::GetDirectoryName($input) -ine $root -or [IO.Path]::GetFileName($input) -cne ('orion-'+$worker.attempt+'.etl') -or $worker.attempt -cnotmatch '^[a-f0-9]{32}$'){throw 'TRACE_PATH_INVALID'}
  $inputItem=Get-Item -LiteralPath $input -Force -ErrorAction Stop
  if($inputItem.PSIsContainer -or ($inputItem.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'TRACE_PATH_INVALID'}
 }
 if($inputItem.Length -gt 64MB){throw 'TRACE_TOO_LARGE'}
 $decodeDir=Join-Path $parent.FullName ('orion-decode-'+[guid]::NewGuid().ToString('N'));[void](New-Item -ItemType Directory -Path $decodeDir -ErrorAction Stop)
 $source=New-Object IO.FileStream($inputItem.FullName,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
 try{
  if($source.Length -gt 64MB){throw 'TRACE_TOO_LARGE'}
  if($Mode -ceq 'OfflineFixture' -and (Get-FileHash -InputStream $source -Algorithm SHA256).Hash -cne '4C312C63C7D366E12B908C49769943886C017497183733BC2C93B8D80E932C7C'){throw 'OFFLINE_FIXTURE_INVALID'}
  $source.Position=0
  $dest=New-Object IO.FileStream((Join-Path $decodeDir 'input.etl'),[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None);try{$source.CopyTo($dest);$dest.Flush($true)}finally{$dest.Dispose()}
 }finally{$source.Dispose()}
 $exe=Join-Path $PSScriptRoot 'etl-decoder/bin/Debug/net10.0/EtLDecoder.exe'
 $parser=Invoke-PhaseAEtlWorker -Executable $exe -ExecutableHash $DecoderSha -ExperimentDirectory $decodeDir -TimeoutMs 10000 -TerminationMs 5000
 if($parser.classification -cne 'COMPLETE' -or $parser.cleanup -cne 'CONFIRMED' -or -not $parser.terminationConfirmed){throw 'DECODER_INCOMPLETE'}
 $projection=Get-GateBParserProjection $parser.outputJson $parser.experiment
 return New-GateBPipelineSummary $outer $h $worker $projection $SourceSha $ControllerSha $DecoderSha ($Mode -ceq 'OfflineFixture')
}
