$ErrorActionPreference='Stop'
. "$PSScriptRoot/PhaseA.ReadProcess.ps1"
function Need($v,$msg){if(-not $v){throw $msg}}
function RunCase([string]$mode) {
 $script:mode=$mode;$script:t=[long]0;$script:waits=New-Object 'System.Collections.Generic.List[int]';$script:ends=0;$script:disposed=$false
 $io=@{
  Clock={if($script:mode -ceq 'BAD_INITIAL'){return 'bad'};if($script:mode -ceq 'BACKWARD' -and $script:waits.Count -gt 0){return [long]-1};return $script:t}
  Cancel={param($p) if($script:mode -ceq 'CANCEL_TIME'){$script:t+=30000000};if($script:mode -ceq 'CANCEL_THROW'){throw 'injected'};if($script:mode -ceq 'NOT_FOUND'){return 'NOT_FOUND'};'REQUESTED'}
  Wait={param($w,$ms)
   $script:waits.Add([int]$ms)
   if($script:mode -ceq 'INVALID_WAIT'){return 'bad'}
   if($script:mode -ceq 'FULL' -and $w -ceq 'first'){$script:t+=50000000;return $false}
   if($script:mode -ceq 'PARTIAL' -and $w -ceq 'first'){$script:t+=30000000;return $true}
   if($script:mode -ceq 'PARTIAL' -and $w -ceq 'second'){$script:t+=20000000;return $false}
   if($script:mode -ceq 'BOUNDARY'){$script:t+=50000000;return $true}
   if($script:mode -ceq 'EXPIRED_ZERO'){return $false}
   return $true
  }
  EndConnection={param($p,$a) $script:ends++;if($script:mode -ceq 'END_THROW'){throw 'injected'};'CANCELED'}
  EndRead={param($p,$a) $script:ends++;'CANCELED'}
  DisposeWait={param($w) if($script:mode -ceq 'DISPOSE_THROW'){throw 'injected'}}
  DisposePipe={param($p) $script:disposed=$true}
 }
 $r=@{};$pend='pending';$read='read';$first='first';$second='second';$ended=$false
 if($mode -ceq 'MISSING_WAIT'){$second=$null}
 if($mode -ceq 'ENDED'){$ended=$true}
 $ok=Complete-PhaseAWitnessPipeCleanup 'pipe' $pend $read $first $second $ended $false $r $io
 switch($mode){
  'FULL' {Need (-not $ok -and $r.pipeDispose -ceq 'RETAINED' -and $script:waits.Count -eq 2 -and $script:waits[0] -eq 5000 -and $script:waits[1] -eq 0) 'FULL_BUDGET'}
  'PARTIAL' {Need (-not $ok -and $r.pipeDispose -ceq 'RETAINED' -and $script:waits.Count -eq 2 -and $script:waits[0] -eq 5000 -and $script:waits[1] -eq 2000) ('PARTIAL_BUDGET '+($script:waits -join ','))}
  'BOTH' {Need ($ok -and $script:ends -eq 2 -and $script:disposed) 'BOTH_COMPLETE'}
  'CANCEL_TIME' {Need ($ok -and $script:waits[0] -eq 2000) 'CANCEL_BUDGET'}
  'CANCEL_THROW' {Need (-not $ok -and $r.pipeCancel -ceq 'FAILED') 'CANCEL_FAILURE'}
  'NOT_FOUND' {Need ($ok -and $r.pipeCancel -ceq 'NOT_FOUND' -and $script:ends -eq 2) 'NOT_FOUND_NO_COMPLETION'}
  'BOUNDARY' {Need ($ok -and $script:waits[0] -eq 5000 -and $script:waits[1] -eq 0 -and $script:ends -eq 2) 'BOUNDARY_POLL'}
  'END_THROW' {Need (-not $ok -and $r.pipeDispose -ceq 'RETAINED') 'END_FAILURE'}
  'DISPOSE_THROW' {Need (-not $ok -and $r.connectionWaitCleanup -ceq 'FAILED') 'DISPOSE_FAILURE'}
  'MISSING_WAIT' {Need (-not $ok -and $r.pipeDispose -ceq 'RETAINED') 'MISSING_WAIT'}
  'BAD_INITIAL' {Need (-not $ok -and $r.pipeDispose -ceq 'RETAINED' -and $script:waits.Count -eq 0) 'BAD_INITIAL_CLOCK'}
  'BACKWARD' {Need (-not $ok -and $r.pipeDispose -ceq 'RETAINED') 'BACKWARD_CLOCK'}
  'INVALID_WAIT' {Need (-not $ok -and $r.pipeDispose -ceq 'RETAINED') 'INVALID_WAIT'}
  'ENDED' {Need ($ok -and $script:waits.Count -eq 1 -and $script:ends -eq 1) 'ENDED_OPERATION'}
 }
 Write-Output ("PASS $mode")
}
foreach($mode in @('FULL','PARTIAL','BOTH','CANCEL_TIME','CANCEL_THROW','NOT_FOUND','BOUNDARY','END_THROW','DISPOSE_THROW','MISSING_WAIT','BAD_INITIAL','BACKWARD','INVALID_WAIT','ENDED')){RunCase $mode}