# Bounded same-identity verification only. Results are not LIVE security evidence.
. "$PSScriptRoot/PhaseA.ReadDeadline.ps1"
. "$PSScriptRoot/PhaseA.Native.ps1"
. "$PSScriptRoot/PhaseA.Atomic.ps1"
function New-PhaseAAggregateSession([int]$BudgetMs,[hashtable]$Backend,[scriptblock]$Clock) {
 if($BudgetMs -lt 1 -or $BudgetMs -gt 60000 -or $null -eq $Backend -or $null -eq $Clock){throw 'AGGREGATE_INVALID'}
 $d=New-PhaseAWitnessDeadline $Clock
 return @{budgetTicks=[long]$BudgetMs*10000;deadline=$d;backend=$Backend;halted=$false;retained=$null;active=$false}
}
function Invoke-PhaseAAggregateAttempt([hashtable]$Session,[int]$AttemptMs,[int]$CleanupMs,[string]$Mode) {
 $r=@{classification='UNVERIFIED';reason='NONE';source='LOCAL_UNTRUSTED';pid=$null;createdAt=$null;termination='NOT_REQUESTED';wait='NOT_OBSERVED';cleanup='NOT_CONFIRMED';descendants='UNVERIFIED'}
 if($Session.halted -or $Session.active){$r.reason='RESOURCE_UNRESOLVED';return $r}
 if($AttemptMs -lt 1 -or $AttemptMs -gt 60000 -or $CleanupMs -lt 1 -or $CleanupMs -gt 5000 -or $Mode -cnotin @('NORMAL','STALL')){$r.reason='INVALID_LIMIT';return $r}
 try{$start=Get-PhaseAWitnessDeadlineElapsed $Session.deadline}catch{$Session.halted=$true;$r.reason='CLOCK_UNVERIFIED';return $r}
 if($start -ge $Session.budgetTicks){$r.reason='AGGREGATE_EXPIRED';return $r}
 $attemptEnd=[Math]::Min([long]$Session.budgetTicks,[long]($start+([long]$AttemptMs*10000)))
 $domain=[AppDomain]::CurrentDomain;$gateKey='EtherPhaseAAggregateNativeGate'
 $nativeGate=($Session.backend.ContainsKey('NativeGate') -and $Session.backend.NativeGate -ceq $true)
 if($nativeGate){$r.reason='PROTOTYPE_INCIDENT_UNRESOLVED';return $r}
 if($nativeGate){
  [Threading.Monitor]::Enter($domain)
  try {if($null -ne $domain.GetData($gateKey)){$r.reason='RESOURCE_UNRESOLVED';return $r};$domain.SetData($gateKey,@{state='IN_FLIGHT'})}
  finally {[Threading.Monitor]::Exit($domain)}
 }
 $Session.active=$true;$a=@{job=$null;child=$null;created=$false;contained=$false;identity=$false;io='NOT_USED';cleanup='NOT_CONFIRMED'}
 try {
  $null=& $Session.backend.Start $a $Mode
  if($a.contained -isnot [bool] -or -not $a.contained -or $a.identity -isnot [bool] -or -not $a.identity -or $a.pid -isnot [int] -or $a.pid -le 0 -or [string]::IsNullOrWhiteSpace($a.createdAt)){throw 'START_UNVERIFIED'}
  $r.pid=$a.pid;$r.createdAt=$a.createdAt
  $elapsed=Get-PhaseAWitnessDeadlineElapsed $Session.deadline
  $ms=[int][Math]::Floor([Math]::Max([long]0,($attemptEnd-$elapsed))/10000.0)
  $signaled=& $Session.backend.Wait $a $ms
  if($signaled -isnot [bool]){throw 'WAIT_UNVERIFIED'}
  $after=Get-PhaseAWitnessDeadlineElapsed $Session.deadline
  if($signaled -and $after -lt $attemptEnd){$r.wait='SIGNALED';$r.classification='OBSERVED';$r.reason='NORMAL'}
  else {$r.classification='UNVERIFIED';$r.reason=if($after -ge $Session.budgetTicks){'AGGREGATE_EXPIRED'}else{'ATTEMPT_TIMEOUT'}}
  if(-not $signaled){
   $r.termination='REQUESTED';$null=& $Session.backend.Terminate $a
   $confirm=& $Session.backend.Wait $a $CleanupMs
   if($confirm -isnot [bool] -or -not $confirm){throw 'TERMINATION_UNCONFIRMED'}
   $r.wait='SIGNALED'
  }
  if($a.io -cne 'NOT_USED'){throw 'IO_UNCONFIRMED'}
  $closed=& $Session.backend.Close $a
  if($closed -isnot [bool] -or -not $closed){throw 'CLEANUP_UNCONFIRMED'}
  $r.cleanup='CONFIRMED'
 } catch {
  $r.classification='UNVERIFIED'
  $r.reason=if($_.Exception.GetBaseException().Message -cin @('TERMINATION_UNCONFIRMED','IO_UNCONFIRMED','CLEANUP_UNCONFIRMED','START_UNVERIFIED','WAIT_UNVERIFIED')){$_.Exception.GetBaseException().Message}else{'SUPERVISOR_FAILURE'}
  $Session.halted=$true;$Session.retained=$a;$r.cleanup='RESOURCE_RETAINED'
 } finally {
  $Session.active=$false
  if($nativeGate){[Threading.Monitor]::Enter($domain);try{if($Session.halted){$domain.SetData($gateKey,@{state='UNRESOLVED';resources=$a})}else{$domain.SetData($gateKey,$null)}}finally{[Threading.Monitor]::Exit($domain)}}
 }
 return $r
}
function New-PhaseAAggregateNativeBackend {
 . "$PSScriptRoot/PhaseA.Native.ps1"
 . "$PSScriptRoot/PhaseA.Atomic.ps1"
 return @{
  NativeGate=$true
  Start={param($a,$mode)
   $a.job=[EtherPhaseAJob]::Create()
   $flags=[EtherPhaseAJob]::QueryLimitFlags($a.job)
   if(($flags -band 0x2000) -eq 0 -or ($flags -band 0x1800) -ne 0){throw 'job flags'}
   $exe=Join-Path $PSHOME 'powershell.exe'
   $command=if($mode -ceq 'NORMAL'){'"'+$exe+'" -NoProfile -NonInteractive -Command "exit 0"'}else{'"'+$exe+'" -NoProfile -NonInteractive -Command "Start-Sleep -Seconds 30"'}
   $a.child=[EtherPhaseAAtomic]::CreateSelfInDirectory($a.job,$exe,$command,[IO.Path]::GetTempPath());$a.created=$true
   if(-not $a.child.InJob() -or $a.child.Exited()){throw 'containment'}
   $a.contained=$true;$p=Get-Process -Id $a.child.Pid -ErrorAction Stop
   try{$i=Get-PhaseAProcessToken $p $true;if($i.pid -ne $a.child.Pid -or $i.sid -cne [Security.Principal.WindowsIdentity]::GetCurrent().User.Value){throw 'identity'};$a.pid=[int]$i.pid;$a.createdAt=$i.createdAt;$a.identity=$true}finally{$p.Dispose()}
   $a.child.Resume()
  }
  Wait={param($a,$ms) $a.child.Wait([uint32]$ms)}
  Terminate={param($a) $a.child.Terminate()}
  Close={param($a) $c=$a.child.CloseObserved();if($c.ProcessClose -cne 'CLOSED' -or $c.ThreadClose -cne 'CLOSED'){return $false};[EtherPhaseAJob]::Close($a.job);$a.job=$null;return $true}
 }
}