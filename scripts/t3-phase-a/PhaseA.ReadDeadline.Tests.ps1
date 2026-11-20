param([string]$Helper=(Join-Path $PSScriptRoot 'PhaseA.ReadDeadline.ps1'),[string]$Core=(Join-Path $PSScriptRoot 'PhaseA.ReadProcess.ps1'))
$ErrorActionPreference='Stop'
. $Core
. $Helper
$script:t=[long]0;$script:advance=[long]0;$script:signal=$true;$script:waits=0;$script:lastMs=-1
$clock={return $script:t}
$wait={param($ms) $script:waits++;$script:lastMs=$ms;$script:t=[long]($script:t+$script:advance);return $script:signal}
function NewD {$script:t=[long]0;$script:waits=0;New-PhaseAWitnessDeadline $clock}
function Assert($truth,$label){if(-not $truth){throw $label}}
$d=NewD;$script:advance=[long]80000001;Assert (-not (Invoke-PhaseAWitnessDeadlineWait $d 80000000 $wait)) 'CONNECTION_LATE_ACCEPTED'
$d=NewD;$script:advance=[long]99999999;Assert (Invoke-PhaseAWitnessDeadlineWait $d 100000000 $wait) 'BEFORE_DEADLINE_REJECTED'
$d=NewD;$script:advance=[long]100000000;Assert (-not (Invoke-PhaseAWitnessDeadlineWait $d 100000000 $wait)) 'AT_DEADLINE_ACCEPTED'
$d=NewD;$script:advance=[long]100000001;Assert (-not (Invoke-PhaseAWitnessDeadlineWait $d 100000000 $wait)) 'AFTER_DEADLINE_ACCEPTED'
$d=NewD;$script:advance=[long]40000000;Assert (Invoke-PhaseAWitnessDeadlineWait $d 80000000 $wait) 'CONNECTION_FAILED';$script:advance=[long]60000000;Assert (-not (Invoke-PhaseAWitnessDeadlineWait $d 100000000 $wait)) 'SHARED_BUDGET_RESET'
$d=NewD;$script:t=[long]100000000;$script:advance=[long]0;Assert (-not (Invoke-PhaseAWitnessDeadlineWait $d 100000000 $wait)) 'EXPIRED_ACCEPTED';Assert ($script:waits -eq 0) 'EXPIRED_WAIT_EXECUTED'
$d=NewD;$script:t=[long]99999999;$script:advance=[long]0;Assert (Invoke-PhaseAWitnessDeadlineWait $d 100000000 $wait) 'ONE_TICK_REJECTED';Assert ($script:lastMs -eq 1) 'ROUNDING_UNSAFE'
$d=NewD;$script:t=[long]10;$null=Test-PhaseAWitnessDeadline $d 100000000;$script:t=[long]9;$caught=$false;try{$null=Test-PhaseAWitnessDeadline $d 100000000}catch{$caught=$_.Exception.GetBaseException().Message -ceq 'WITNESS_CLOCK_UNVERIFIED'};Assert $caught 'REGRESSION_ACCEPTED'
$d=NewD;$script:t=[long]::MaxValue;Assert (-not (Test-PhaseAWitnessDeadline $d 100000000)) 'EXTREME_ACCEPTED'
$d=NewD;$caught=$false;try{$null=Invoke-PhaseAWitnessDeadlineWait $d 0 $wait}catch{$caught=$true};Assert $caught 'ZERO_BUDGET_ACCEPTED'
$d=NewD;$caught=$false;try{$null=Invoke-PhaseAWitnessDeadlineWait $d 100000000 {param($ms) throw 'WAIT_FAIL'}}catch{$caught=$_.Exception.GetBaseException().Message -ceq 'WAIT_FAIL'};Assert $caught 'WAIT_EXCEPTION_LOST'
$caught=$false;try{$null=New-PhaseAWitnessDeadline {return 'malformed'}}catch{$caught=$true};Assert $caught 'MALFORMED_CLOCK_ACCEPTED'
$script:phase='';$io=@{Cancel={param($p) $script:phase='REQUESTED';return 'REQUESTED'};Wait={param($w,$ms) if($script:phase -cne 'REQUESTED'){throw 'WAIT_BEFORE_CANCEL'};$script:t=[long]($script:t+100);return $true};EndConnection={param($p,$a) return 'CANCELED'};EndRead={param($p,$a) return 'CANCELED'};DisposeWait={param($w)};DisposePipe={param($p)}}
$r=@{};Assert (Complete-PhaseAWitnessPipeCleanup 'pipe' 'pending' $null 'wait' $null $false $false $r $io) 'DELAYED_CLEANUP_REJECTED';Assert ($r.pipeCancel -ceq 'REQUESTED' -and $r.connectionEnd -ceq 'CANCELED') 'CANCEL_NOT_CONFIRMED'
Write-Output 'PASS production-shared deadline decisions, boundaries and delayed cancellation'
$d=NewD;$script:advance=[long]1;$script:signal=$false;Assert (-not (Invoke-PhaseAWitnessDeadlineWait $d 100000000 $wait)) 'UNSIGNALED_ACCEPTED';$script:signal=$true
$d=NewD;$caught=$false;try{$null=Invoke-PhaseAWitnessDeadlineWait $d 100000000 {param($ms) return 'true'}}catch{$caught=$_.Exception.GetBaseException().Message -ceq 'WITNESS_WAIT_UNVERIFIED'};Assert $caught 'MALFORMED_WAIT_ACCEPTED'
$script:count=0;$io.Cancel={param($p) $script:count++;return 'REQUESTED'};$io.Wait={param($w,$ms) return $false}
foreach($i in 1..2){$r=@{};$ok=Complete-PhaseAWitnessPipeCleanup 'pipe' 'pending' $null 'wait' $null $false $false $r $io;Assert (-not $ok -and $r.pipeDispose -ceq 'RETAINED') 'REPEATED_CANCEL_RELEASED'}
Assert ($script:count -eq 2) 'CANCELLATION_NOT_REQUESTED'
Write-Output 'PASS malformed waits and repeated unconfirmed cancellation'

$d=NewD;$script:t='malformed';$caught=$false;try{$null=Test-PhaseAWitnessDeadline $d 100000000}catch{$caught=$_.Exception.GetBaseException().Message -ceq 'WITNESS_CLOCK_UNVERIFIED'};Assert $caught 'MALFORMED_LATER_CLOCK_ACCEPTED'
$d=NewD;$script:advance=[long]60000000;Assert (Invoke-PhaseAWitnessDeadlineWait $d 80000000 $wait) 'CONNECTION_WITHIN_BUDGET_FAILED';$script:advance=[long]40000001;Assert (-not (Invoke-PhaseAWitnessDeadlineWait $d 100000000 $wait)) 'READ_AFTER_DEADLINE_ACCEPTED'
$raw=[IO.File]::ReadAllText($Core);Assert (([regex]::Matches($raw,'Invoke-PhaseAWitnessDeadlineWait \$deadline')).Count -eq 3) 'PRODUCTION_WAIT_WIRING_MISSING';Assert (([regex]::Matches($raw,'Test-PhaseAWitnessDeadline \$deadline')).Count -ge 2) 'RECEIPT_DEADLINE_WIRING_MISSING'
Write-Output 'PASS later clock failure, delayed read and production-wiring checks'