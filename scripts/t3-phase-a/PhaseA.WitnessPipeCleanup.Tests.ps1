$ErrorActionPreference='Stop'
. "$PSScriptRoot/PhaseA.Stage3.ps1"
$script:trace=New-Object 'System.Collections.Generic.List[string]';$script:signals=$true
$io=@{Cancel={param($p) $script:trace.Add('cancel');return 'REQUESTED'};Wait={param($w) $script:trace.Add('wait');return $script:signals};EndConnection={param($p,$a) $script:trace.Add('end');return 'ENDED'};EndRead={param($p,$a) $script:trace.Add('endread');return 'ENDED'};DisposeWait={param($w) $script:trace.Add('disposeWait')};DisposePipe={param($p) $script:trace.Add('disposePipe')}}
$record=@{};$ok=Complete-PhaseAWitnessPipeCleanup 'pipe' 'pending' $null 'wait' $null $false $false $record $io
if(-not $ok -or ($script:trace -join ',') -cne 'cancel,wait,end,disposeWait,disposePipe'){throw 'PIPE_COMPLETION_ORDER_WRONG'}
$script:trace.Clear();$script:signals=$false;$record=@{};$ok=Complete-PhaseAWitnessPipeCleanup 'pipe' 'pending' $null 'wait' $null $false $false $record $io
if($ok -or $script:trace.Contains('disposePipe') -or $script:trace.Contains('disposeWait') -or $record.connectionWaitCleanup -cne 'UNCONFIRMED'){throw 'UNFINISHED_WAIT_CLOSED'}
$script:signals=$true
foreach($endState in @('CANCELED')){
 $script:endState=$endState;$io.EndConnection={param($p,$a) $script:trace.Add('end');return $script:endState}
 $script:trace.Clear();$record=@{};$ok=Complete-PhaseAWitnessPipeCleanup 'pipe' 'pending' $null 'wait' $null $false $false $record $io
 if(-not $ok -or $record.connectionEnd -cne $endState -or -not $script:trace.Contains('disposePipe')){throw ('PIPE_COMPLETION_STATUS_LOST_'+$endState)}
}
$io.Cancel={param($p) $script:trace.Add('cancel');return 'NOT_FOUND'}
$io.EndConnection={param($p,$a) $script:trace.Add('end');return 'ENDED'}
$script:trace.Clear();$record=@{};$ok=Complete-PhaseAWitnessPipeCleanup 'pipe' 'pending' $null 'wait' $null $false $false $record $io
if(-not $ok -or $record.pipeCancel -cne 'NOT_FOUND' -or $record.connectionEnd -cne 'ENDED' -or -not $script:trace.Contains('wait')){throw 'NOT_FOUND_COMPLETION_NOT_OBSERVED'}
$io.Wait={param($w) $script:trace.Add('wait');throw 'injected wait failure'}
$script:trace.Clear();$record=@{};$ok=Complete-PhaseAWitnessPipeCleanup 'pipe' 'pending' $null 'wait' $null $false $false $record $io
if($ok -or $record.connectionWaitCleanup -cne 'UNCONFIRMED' -or $script:trace.Contains('disposePipe') -or $script:trace.Contains('disposeWait')){throw 'WAIT_FAILURE_DID_NOT_RETAIN_RESOURCES'}
foreach($mode in @('ERROR','THROW','INVALID')) {
 $script:trace.Clear();$script:signals=$true;$io.Wait={param($w) $script:trace.Add('wait');return $true}
 $script:mode=$mode;$io.EndConnection={param($p,$a) $script:trace.Add('end');switch($script:mode){'ERROR' {return 'ERROR'} 'THROW' {throw 'INJECTED_END_FAILURE'} 'INVALID' {return 'UNRECOGNIZED'}}}
 $record=@{};$ok=Complete-PhaseAWitnessPipeCleanup 'pipe' 'pending' $null 'wait' $null $false $false $record $io
 if($ok -or $script:trace.Contains('disposePipe') -or $script:trace.Contains('disposeWait') -or $record.pipeDispose -cne 'RETAINED'){throw ('UNCONFIRMED_END_RELEASED_'+$mode)}
}
foreach($alreadyEnded in @($false,$true)) {
 $io.Wait={param($w) return $true};$io.EndConnection={param($p,$a) return 'ENDED'}
 $io.DisposeWait={param($w) throw [ObjectDisposedException]::new('injected')};$io.DisposePipe={param($p)}
 $record=@{};$ok=Complete-PhaseAWitnessPipeCleanup 'pipe' 'pending' $null 'wait' $null $alreadyEnded $false $record $io
 if($ok -or $record.connectionWaitCleanup -cne 'FAILED'){throw ('WAIT_DISPOSAL_EXCEPTION_ACCEPTED_'+$alreadyEnded)}
}
Write-Output 'PASS pending pipe operations finish before handle disposal'
