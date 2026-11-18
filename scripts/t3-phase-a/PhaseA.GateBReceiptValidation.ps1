# Schema and duplicate-key checks validate structure, not witness authority.
if(-not ('GateBStrictJson' -as [type])) {
 Add-Type -Path "$PSScriptRoot/PhaseA.GateBStrictJson.cs" -ReferencedAssemblies System.Web.Extensions
}
function Test-GateBWorkerReceipt {
 param([string]$Json,[string]$Experiment,[string]$Root,[bool]$Experimental)
 try {
  if(-not [GateBStrictJson]::Validate($Json)){return $false}
  $d=$Json | ConvertFrom-Json -ErrorAction Stop
  if($null -eq $d -or $d -is [array] -or $d.Source -cne 'CAPTURED_UNTRUSTED' -or $d.Status -cne 'UNVERIFIED' -or $d.Experiment -cne $Experiment){return $false}
  if(-not $Experimental){
   $dryNames=@('Source','Status','Experiment','nativeCalls','session','maxMiB','captureSeconds')
   $properties=@($d.PSObject.Properties)
   if($properties.Count -ne $dryNames.Count){return $false}
   foreach($property in $properties){if($dryNames -cnotcontains $property.Name){return $false}}
   return ($d.nativeCalls -is [int] -and $d.nativeCalls -eq 0 -and $d.session -is [string] -and $d.session -ceq 'Orion-T3-GateB-Feasibility' -and $d.maxMiB -is [int] -and $d.maxMiB -eq 64 -and $d.captureSeconds -is [int] -and $d.captureSeconds -eq 15)
  }
  $allowed=@('Source','Status','Experiment','state','stop','statistics','code','operationFailure','workloadFailure','controllerException','cleanupFailure','cleanupException','attempt','session','etl','vmDisposalRequired','vmDisposalConfirmed','workload','initial','final')
  if(@($d.PSObject.Properties).Count -ne $allowed.Count){return $false}
  foreach($property in $d.PSObject.Properties){if($allowed -cnotcontains $property.Name){return $false}}
  foreach($name in @('state','stop','statistics','code','attempt','session','etl','vmDisposalRequired','vmDisposalConfirmed','workload')){if(-not $d.PSObject.Properties[$name]){return $false}}
  if($d.vmDisposalRequired -isnot [bool] -or $d.vmDisposalRequired -ne $true -or $d.vmDisposalConfirmed -isnot [bool] -or $d.vmDisposalConfirmed -ne $false){return $false}
  if($d.state -isnot [string] -or $d.stop -isnot [string] -or $d.session -cne 'Orion-T3-GateB-Feasibility' -or $d.attempt -cnotmatch '^[0-9a-f]{32}$'){return $false}
  if($d.etl -isnot [string] -or [IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($d.etl)) -ine [IO.Path]::GetFullPath($Root) -or [IO.Path]::GetExtension($d.etl) -ine '.etl'){return $false}
  if($null -eq $d.statistics -or $d.statistics.StatisticsValid -isnot [bool] -or $d.statistics.FinalStatistics -cnotin @('VALID','INCOMPLETE')){return $false}
  $statNames=@('FinalStatistics','StatisticsValid','EventsLost','LogBuffersLost','RealTimeBuffersLost')
  if(@($d.statistics.PSObject.Properties).Count -ne $statNames.Count){return $false}
  foreach($property in $d.statistics.PSObject.Properties){if($statNames -cnotcontains $property.Name){return $false}}
  if($d.statistics.StatisticsValid -ne ($d.statistics.FinalStatistics -ceq 'VALID')){return $false}
  foreach($name in @('EventsLost','LogBuffersLost','RealTimeBuffersLost')){
   if(-not $d.statistics.PSObject.Properties[$name]){return $false};$v=$d.statistics.$name
   if($d.statistics.StatisticsValid){if($v -isnot [int] -and $v -isnot [long]){return $false};if($v -lt 0 -or $v -gt [uint32]::MaxValue){return $false}}elseif($null -ne $v){return $false}
  }
  $workNames=@('Outcome','ExpectedSha256','ActualSha256','StartedUtc','CompletedUtc','RequestedBytes','ActualBytes','ProcessId','ThreadId','StartTicks','EndTicks')
  if($null -eq $d.workload -or $d.workload.Outcome -isnot [string] -or @($d.workload.PSObject.Properties).Count -ne $workNames.Count){return $false}
  foreach($property in $d.workload.PSObject.Properties){if($workNames -cnotcontains $property.Name){return $false}}
  if($null -ne $d.initial){$names=@('Code','Mode','EnableFlags','BufferSize','MinimumBuffers','MaximumBuffers','MaximumFileSize','FlushTimer');if(@($d.initial.PSObject.Properties).Count -ne $names.Count){return $false};foreach($property in $d.initial.PSObject.Properties){if($names -cnotcontains $property.Name){return $false}}}
  if($null -ne $d.final -and (@($d.final.PSObject.Properties).Count -ne 1 -or -not $d.final.PSObject.Properties['Code'])){return $false}
  return $true
 } catch {return $false}
}
