$ErrorActionPreference='Stop'
. "$PSScriptRoot/PhaseA.AggregateSupervisor.ps1"
function Need($v,$m){if(-not $v){throw $m}}
function Run([string]$mode){
 $script:t=[long]0;$script:mode=$mode;$script:waits=New-Object 'System.Collections.Generic.List[int]';$script:starts=0;$script:terms=0
 $clock={if($script:mode -ceq 'BAD_CLOCK'){return 'bad'};if($script:mode -ceq 'BACKWARD' -and $script:waits.Count -gt 0){return [long]-1};return $script:t}
 $b=@{
  Start={param($a,$m) $script:starts++;$a.created=$true;$a.pid=[int]123;$a.createdAt='2026-01-01T00:00:00Z';$a.contained=$true;$a.identity=$true;if($script:mode -ceq 'CONTAIN'){$a.contained=$false};if($script:mode -ceq 'EXCEPTION'){throw 'failure'}}
  Wait={param($a,$ms) $script:waits.Add([int]$ms);if($script:waits.Count -eq 1){if($script:mode -cin @('TIMEOUT','AGGREGATE','UNCONFIRMED','TERM_FAIL','CLEANUP_LIMIT')){$script:t+=([long]$ms*10000);return $false};if($script:mode -ceq 'LATE'){$script:t+=100000000};if($script:mode -ceq 'IO'){$a.io='UNCONFIRMED'};return $true};if($script:mode -cin @('UNCONFIRMED','CLEANUP_LIMIT')){return $false};return $true}
  Terminate={param($a) $script:terms++;if($script:mode -ceq 'TERM_FAIL'){throw 'failure'}}
  Close={param($a) return ($script:mode -cne 'CLOSE_FAIL')}
 }
 $s=New-PhaseAAggregateSession 10000 $b $clock
 if($mode -ceq 'BETWEEN'){$script:t=[long]100000000}
 $out=Invoke-PhaseAAggregateAttempt $s $(if($mode -ceq 'TIMEOUT'){500}else{20000}) 1000 'NORMAL'
 switch($mode){
  'NORMAL' {Need ($out.classification -ceq 'OBSERVED' -and $out.cleanup -ceq 'CONFIRMED' -and $script:waits[0] -eq 10000) 'NORMAL'}
  'TIMEOUT' {Need ($out.reason -ceq 'ATTEMPT_TIMEOUT' -and $script:terms -eq 1 -and $out.cleanup -ceq 'CONFIRMED' -and $script:waits[0] -eq 500) 'TIMEOUT'}
  'BETWEEN' {Need ($out.reason -ceq 'AGGREGATE_EXPIRED' -and $script:starts -eq 0) 'BETWEEN'}
  'AGGREGATE' {Need ($out.reason -ceq 'AGGREGATE_EXPIRED' -and $script:terms -eq 1 -and $out.cleanup -ceq 'CONFIRMED') 'AGGREGATE'}
  'LATE' {Need ($out.classification -ceq 'UNVERIFIED' -and $out.reason -ceq 'AGGREGATE_EXPIRED') 'LATE'}
  {$_ -cin @('UNCONFIRMED','TERM_FAIL','CONTAIN','IO','CLOSE_FAIL','EXCEPTION','BACKWARD','CLEANUP_LIMIT')} {
   Need ($out.classification -ceq 'UNVERIFIED' -and $s.halted -and $out.cleanup -ceq 'RESOURCE_RETAINED') ('RETAIN_'+$mode)
   $later=Invoke-PhaseAAggregateAttempt $s 100 100 'NORMAL';Need ($later.reason -ceq 'RESOURCE_UNRESOLVED' -and $script:starts -eq 1) ('STICKY_'+$mode)
  }
 }
 "PASS $mode"
}
foreach($mode in @('NORMAL','TIMEOUT','BETWEEN','AGGREGATE','LATE','UNCONFIRMED','TERM_FAIL','CONTAIN','IO','CLOSE_FAIL','EXCEPTION','BACKWARD','CLEANUP_LIMIT')){Run $mode}
$script:t=[long]0;$c={return $script:t};$b=New-PhaseAAggregateNativeBackend;$sw=[Diagnostics.Stopwatch]::StartNew();$realClock={return [long]$sw.Elapsed.Ticks}.GetNewClosure()
$s=New-PhaseAAggregateSession 10000 $b $realClock
$r=Invoke-PhaseAAggregateAttempt $s 5000 3000 'NORMAL'
Need ($r.classification -ceq 'OBSERVED' -and $r.cleanup -ceq 'CONFIRMED' -and $r.pid -gt 0) ('NATIVE_NORMAL_'+$r.reason)
"PASS native normal pid=$($r.pid)"
$s=New-PhaseAAggregateSession 3000 $b $realClock
$r=Invoke-PhaseAAggregateAttempt $s 300 3000 'STALL'
Need ($r.reason -ceq 'ATTEMPT_TIMEOUT' -and $r.termination -ceq 'REQUESTED' -and $r.wait -ceq 'SIGNALED' -and $r.cleanup -ceq 'CONFIRMED') ('NATIVE_TIMEOUT_'+$r.reason)
"PASS native timeout pid=$($r.pid) termination=$($r.wait)"
# Native aggregate expiry blocks a later attempt, using a real monotonic stopwatch.
$sw2=[Diagnostics.Stopwatch]::StartNew();$clock2={return [long]$sw2.Elapsed.Ticks}.GetNewClosure()
$s=New-PhaseAAggregateSession 3000 $b $clock2
$r=Invoke-PhaseAAggregateAttempt $s 2500 3000 'NORMAL'
Need ($r.classification -ceq 'OBSERVED' -and $r.cleanup -ceq 'CONFIRMED') 'NATIVE_AGGREGATE_POSITIVE'
while($sw2.ElapsedMilliseconds -lt 3100){Start-Sleep -Milliseconds 25}
$r2=Invoke-PhaseAAggregateAttempt $s 2500 3000 'NORMAL'
Need ($r2.reason -ceq 'AGGREGATE_EXPIRED' -and $null -eq $r2.pid) 'NATIVE_AGGREGATE_ADMITTED'
'PASS native aggregate expiration prevents another attempt'
$bad={return 'bad'};$rejected=$false
try{$null=New-PhaseAAggregateSession 1000 @{} $bad}catch{$rejected=$true}
Need $rejected 'MALFORMED_INITIAL_CLOCK'
'PASS malformed initial clock'
# Run last: this intentionally leaves the process-local gate sticky.
$t=[long]0;$testClock={return $t}.GetNewClosure()
$gateBackend=@{NativeGate=$true;Start={param($a,$m) $a.contained=$false};Wait={param($a,$ms) $false};Terminate={param($a)};Close={param($a) $false}}
$s1=New-PhaseAAggregateSession 1000 $gateBackend $testClock;$r1=Invoke-PhaseAAggregateAttempt $s1 100 100 'NORMAL'
$s2=New-PhaseAAggregateSession 1000 $gateBackend $testClock;$r2=Invoke-PhaseAAggregateAttempt $s2 100 100 'NORMAL'
Need ($r1.cleanup -ceq 'RESOURCE_RETAINED' -and $r2.reason -ceq 'RESOURCE_UNRESOLVED') 'CROSS_SESSION_GATE'
'PASS cross-session unresolved ownership gate'