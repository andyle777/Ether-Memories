$ErrorActionPreference='Stop'
. "$PSScriptRoot/PhaseA.Stage2.ps1"
function Need($v,$m){if(-not $v){throw $m}}
function RunCase([string]$mode){
 $script:mode=$mode;$script:t=[long]0;$script:waits=New-Object 'System.Collections.Generic.List[int]';$script:terms=0;$script:closes=0
 $io=@{
  Clock={if($script:mode -ceq 'BAD_CLOCK'){return 'bad'};if($script:mode -ceq 'BACK_CLOCK' -and $script:waits.Count -gt 0){return [long]-1};return $script:t}
  Wait={param($c,$ms) $script:waits.Add([int]$ms)
   if($script:mode -ceq 'WAIT_THROW'){throw 'WAIT_THROW'}
   if($script:mode -ceq 'WAIT_INVALID'){return 'bad'}
   if($script:mode -cin @('ALREADY_EXITED','DURING_INITIAL','CONTRADICT','EXITCODE','PROC_CLOSE','THREAD_CLOSE')){return $true}
   if($script:waits.Count -eq 1){$script:t+=10000000;return $false}
   if($script:mode -cin @('NO_CONFIRM','EXHAUSTED_NO')){return $false}
   return $true
  }
  Terminate={param($c) $script:terms++;if($script:mode -ceq 'TERM_THROW'){throw 'TERM_THROW'};if($script:mode -ceq 'TERM_COST'){$script:t+=20000000};if($script:mode -cin @('EXHAUSTED_YES','EXHAUSTED_NO')){$script:t+=40000000}}
  Exited={param($c) return ($script:mode -cnotin @('NO_CONFIRM','EXHAUSTED_NO','CONTRADICT'))}
  ExitCode={param($c) if($script:mode -ceq 'EXITCODE'){throw 'EXITCODE'};return 0}
  Dispose={param($c) $script:closes++;return @{ProcessClose=$(if($script:mode -ceq 'PROC_CLOSE'){'FAILED'}else{'CLOSED'});ProcessError=$(if($script:mode -ceq 'PROC_CLOSE'){'WIN32_INVALID_HANDLE'}else{'NONE'});ThreadClose=$(if($script:mode -ceq 'THREAD_CLOSE'){'FAILED'}else{'CLOSED'});ThreadError=$(if($script:mode -ceq 'THREAD_CLOSE'){'WIN32_INVALID_HANDLE'}else{'NONE'})}}
 }
 $r=@{};$out=Invoke-PhaseAActorChildCleanup @{} $r $io
 switch($mode){
  {$_ -cin @('ALREADY_EXITED','DURING_INITIAL')} {Need ($out.confirmed -and -not $out.cleanupFailed -and $script:terms -eq 0 -and $script:waits[0] -eq 1000) 'INITIAL_SIGNAL'}
  'NORMAL' {Need ($out.confirmed -and $script:terms -eq 1 -and ($script:waits -join ',') -ceq '1000,4000' -and $r.termination -ceq 'REQUESTED') ('BUDGET '+($script:waits -join ','))}
  'TERM_COST' {Need ($out.confirmed -and ($script:waits -join ',') -ceq '1000,2000') 'TERM_COST'}
  'EXHAUSTED_YES' {Need ($out.confirmed -and ($script:waits -join ',') -ceq '1000,0') 'ZERO_YES'}
  'EXHAUSTED_NO' {Need (-not $out.confirmed -and ($script:waits -join ',') -ceq '1000,0' -and $script:closes -eq 0) 'ZERO_NO'}
  'NO_CONFIRM' {Need (-not $out.confirmed -and $r.finalWait -ceq 'TIMEOUT' -and $script:closes -eq 0) 'SURVIVOR'}
  {$_ -cin @('TERM_THROW','WAIT_THROW','WAIT_INVALID','BAD_CLOCK','BACK_CLOCK')} {Need (-not $out.confirmed -and $r.finalWait -ceq 'FAILED' -and $script:closes -eq 0) ('FAIL_CLOSED_'+$mode)}
  'CONTRADICT' {Need (-not $out.confirmed -and $r.error -ceq 'EXIT_UNCONFIRMED' -and $script:closes -eq 0) 'CONTRADICTION'}
  'EXITCODE' {Need ($out.confirmed -and $out.cleanupFailed -and $r.exitState -ceq 'EXITED') 'EXITCODE'}
  'PROC_CLOSE' {Need ($out.confirmed -and $out.cleanupFailed -and $r.processClose -ceq 'FAILED') 'PROC_CLOSE'}
  'THREAD_CLOSE' {Need ($out.confirmed -and $out.cleanupFailed -and $r.threadClose -ceq 'FAILED') 'THREAD_CLOSE'}
 }
 "PASS $mode"
}
foreach($mode in @('ALREADY_EXITED','DURING_INITIAL','NORMAL','TERM_COST','EXHAUSTED_YES','EXHAUSTED_NO','NO_CONFIRM','TERM_THROW','WAIT_THROW','WAIT_INVALID','CONTRADICT','EXITCODE','PROC_CLOSE','THREAD_CLOSE','BAD_CLOCK','BACK_CLOCK')){RunCase $mode}