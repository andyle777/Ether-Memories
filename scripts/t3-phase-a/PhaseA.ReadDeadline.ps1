# Internal elapsed-tick decision logic. Production supplies its own Stopwatch and native waits.
# Connection is bounded at eight seconds; all stages share ten seconds.
# Completion at the deadline is rejected, intentionally tightening the earlier inclusive check.
# Cancellation and cleanup retain their separate existing completion checks.
function New-PhaseAWitnessDeadline([scriptblock]$Clock) {
 if($null -eq $Clock){throw 'WITNESS_CLOCK_UNVERIFIED'}
 $initial=& $Clock
 if($initial -isnot [long] -or $initial -lt 0){throw 'WITNESS_CLOCK_UNVERIFIED'}
 return @{clock=$Clock;start=$initial;last=$initial}
}
function Get-PhaseAWitnessDeadlineElapsed([hashtable]$Deadline) {
 $value=& $Deadline.clock
 if($value -isnot [long] -or $value -lt $Deadline.last -or $value -lt $Deadline.start){throw 'WITNESS_CLOCK_UNVERIFIED'}
 $Deadline.last=$value
 return [long]($value-$Deadline.start)
}
function Invoke-PhaseAWitnessDeadlineWait([hashtable]$Deadline,[long]$LimitTicks,[scriptblock]$Wait) {
 if($LimitTicks -le 0 -or $LimitTicks -gt 100000000 -or $null -eq $Wait){throw 'WITNESS_CLOCK_UNVERIFIED'}
 $elapsed=Get-PhaseAWitnessDeadlineElapsed $Deadline
 if($elapsed -ge $LimitTicks){return $false}
 $remaining=$LimitTicks-$elapsed
 $milliseconds=[int][Math]::Ceiling(([double]$remaining)/10000.0)
 $completed=& $Wait $milliseconds
 if($completed -isnot [bool]){throw 'WITNESS_WAIT_UNVERIFIED'}
 $after=Get-PhaseAWitnessDeadlineElapsed $Deadline
 return ($completed -and $after -lt $LimitTicks)
}
function Test-PhaseAWitnessDeadline([hashtable]$Deadline,[long]$LimitTicks) {
 if($LimitTicks -le 0 -or $LimitTicks -gt 100000000){throw 'WITNESS_CLOCK_UNVERIFIED'}
 return ((Get-PhaseAWitnessDeadlineElapsed $Deadline) -lt $LimitTicks)
}