$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'PhaseA.StateOnlyAdmission.ps1')
. (Join-Path $PSScriptRoot 'PhaseA.RestartProbeValidation.ps1')
$probe=Join-Path $PSScriptRoot 'PhaseA.RestartProbe.ps1';$source=Join-Path $PSScriptRoot 'PhaseA.DurableAdmission.ps1'
function NewRoot{$d=Join-Path $env:TEMP ('orion-r6-probe-'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($d);$d}
function Need($v,$m){if(-not $v){throw $m}}
function Run([string]$root,[string]$nonce,[string]$sourcePath=$source){
 $p=New-Object Diagnostics.ProcessStartInfo;$p.FileName=Join-Path $PSHOME 'powershell.exe'
 $p.Arguments='-NoProfile -NonInteractive -File "'+$probe+'" -Root "'+$root+'" -Nonce '+$nonce+' -Source "'+$sourcePath+'"'
 $p.UseShellExecute=$false;$p.CreateNoWindow=$true;$p.RedirectStandardOutput=$true;$p.RedirectStandardError=$true
 $c=[Diagnostics.Process]::Start($p)
 try{if(-not $c.WaitForExit(15000)){try{$c.Kill()}catch{throw 'PROBE_TERMINATION_UNCONFIRMED'};if(-not $c.WaitForExit(5000)){throw 'PROBE_TERMINATION_UNCONFIRMED'};throw 'PROBE_TIMEOUT'};return @{code=$c.ExitCode;output=$c.StandardOutput.ReadToEnd();errors=$c.StandardError.ReadToEnd()}}finally{$c.Dispose()}
}
$n=[guid]::NewGuid().ToString('N');$d=NewRoot;$script:p01Callbacks=0
$backend=@{Start={param($a,$m) $script:p01Callbacks++;$a.pid=123;$a.createdAt='2026-01-01T00:00:00Z';$a.contained=$true;$a.identity=$true};Wait={param($a,$ms) $true};Terminate={param($a)};Close={param($a) $true}}
$completed=Invoke-PhaseAStateOnlyAttempt $d ('a'*32) 1000 $backend {return [long]0}
Need ($completed.status -ceq 'SIMULATED_COMPLETE' -and $script:p01Callbacks -eq 1) 'P01_NO_COMPLETED_ATTEMPT'
$r=Run $d $n;Need (Test-PhaseARestartProbeResult $r.output $r.code $n) 'P01_SEALED';'PASS P01 completed synthetic attempt stays sealed'
$d=NewRoot;$o=Initialize-PhaseAAdmissionStore $d
try{
 $r=Run $d $n;Need (Test-PhaseARestartProbeResult $r.output $r.code $n) 'P02_ACTIVE'
 $conflict=$false;try{$h=[IO.File]::Open((Join-Path $d 'admission.lock'),[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None);$h.Dispose()}catch{$e=$_.Exception.GetBaseException();$conflict=($e -is [IO.IOException] -and ([long]$e.HResult -band 0xffffffffL) -eq 2147942432)}
 Need $conflict 'P02_NO_SHARING_VIOLATION'
}finally{Close-PhaseAAdmissionLease $o}
$h=[IO.File]::Open((Join-Path $d 'admission.lock'),[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None);$h.Dispose();$r=Run $d $n;Need (Test-PhaseARestartProbeResult $r.output $r.code $n) 'P02_RELEASED';'PASS P02 active and released observations'
$d=NewRoot;$r=Run $d $n;Need (Test-PhaseAClaimCreatedProbeResult $r.output $r.code $n) 'P03_FRESH';'PASS P03 fresh claim'
$r=Run (Join-Path $env:TEMP ('missing-'+$n)) $n;Need ($r.code -eq 8 -and ($r.output|ConvertFrom-Json).reason -ceq 'DOMAIN_MISSING_OR_INACCESSIBLE' -and -not (Test-PhaseARestartProbeResult $r.output $r.code $n)) 'P04_MISSING';'PASS P04 missing directory'
$r=Run 'invalid-relative-path' $n;Need ($r.code -eq 8 -and ($r.output|ConvertFrom-Json).reason -ceq 'INVALID_DOMAIN_BINDING' -and -not (Test-PhaseARestartProbeResult $r.output $r.code $n)) 'P05_INVALID';'PASS P05 invalid binding'
$d=NewRoot;$o=Initialize-PhaseAAdmissionStore $d;Close-PhaseAAdmissionLease $o
$original=[IO.File]::ReadAllText($source);$sourceDir=Join-Path $env:TEMP ('orion-r6-fake-'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($sourceDir);$fake=Join-Path $sourceDir 'PhaseA.DurableAdmission.ps1'
$insert="  Invoke-AdmissionFault `$Fault 'INIT_LOCK_BEFORE_CREATE'"
$replacement=$insert+"`r`n  throw [UnauthorizedAccessException]::new('INJECTED_UNRELATED')"
Need ($original.Contains($insert)) 'P06_FIXTURE_BOUNDARY';[IO.File]::WriteAllText($fake,$original.Replace($insert,$replacement),[Text.UTF8Encoding]::new($false))
$r=Run $d $n $fake;Need ($r.code -eq 7 -and ($r.output|ConvertFrom-Json).reason -ceq 'UNRELATED_OR_UNVERIFIED_ERROR' -and -not (Test-PhaseARestartProbeResult $r.output $r.code $n)) 'P06_UNRELATED_ACCESS';'PASS P06 unrelated access failure'
$r=Run $d $n (Join-Path $sourceDir 'missing.ps1');Need ($r.code -eq 8 -and ($r.output|ConvertFrom-Json).reason -ceq 'SOURCE_UNAVAILABLE_OR_INVALID' -and -not (Test-PhaseARestartProbeResult $r.output $r.code $n)) 'P07_MISSING_SOURCE';'PASS P07 missing source'
$replacement=$insert+"`r`n  throw 'INJECTED_UNEXPECTED'";[IO.File]::WriteAllText($fake,$original.Replace($insert,$replacement),[Text.UTF8Encoding]::new($false))
$r=Run $d $n $fake;Need ($r.code -eq 7 -and ($r.output|ConvertFrom-Json).reason -ceq 'UNRELATED_OR_UNVERIFIED_ERROR' -and -not (Test-PhaseARestartProbeResult $r.output $r.code $n)) 'P08_UNEXPECTED';'PASS P08 unexpected exception'
foreach($bad in @('','{}','garbage','[]')){Need (-not (Test-PhaseARestartProbeResult $bad 0 $n)) 'P09_MALFORMED'};'PASS P09 malformed records'
$d=NewRoot;$o=Initialize-PhaseAAdmissionStore $d;$jp=Join-Path $d 'admission.journal';$old=[IO.File]::ReadAllBytes($jp);$lease=Open-PhaseAAdmissionLease $o ('a'*32);Close-PhaseAAdmissionLease $lease;[IO.File]::WriteAllBytes($jp,$old)
$r=Run $d $n;Need (Test-PhaseARestartProbeResult $r.output $r.code $n) 'P11_ROLLBACK';'PASS P11 rollback with claim'
$d=NewRoot;$o=Initialize-PhaseAAdmissionStore $d;Close-PhaseAAdmissionLease $o;Need (-not [IO.File]::Exists((Join-Path $d 'admission.init-failed'))) 'P12_MARKER';$r=Run $d $n;Need (Test-PhaseARestartProbeResult $r.output $r.code $n) 'P12_MARKER';'PASS P12 no failure marker'
$d=NewRoot;$o=Initialize-PhaseAAdmissionStore $d;Close-PhaseAAdmissionLease $o;[IO.File]::WriteAllText((Join-Path $d 'other.lock'),'x')
$replacement=$insert+"`r`n  `$other=New-Object IO.FileStream((Join-Path `$root 'other.lock'),[IO.FileMode]::CreateNew,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)"
[IO.File]::WriteAllText($fake,$original.Replace($insert,$replacement),[Text.UTF8Encoding]::new($false));$r=Run $d $n $fake;$j=$r.output|ConvertFrom-Json
Need ($j.observedError -ceq '80070050' -and -not (Test-PhaseARestartProbeResult $r.output $r.code $n)) 'P13_WRONG_OPERATION';'PASS P13 same HRESULT unrelated operation'
$r=Run $d $n;Need (-not (Test-PhaseARestartProbeResult $r.output $r.code ([guid]::NewGuid().ToString('N')))) 'P14_NONCE';'PASS P14 wrong nonce'
foreach($change in @('VERSION','LEASES','CALLBACKS','REACHED','CLAIM','ERROR','REASON','EXTRA','EXIT')){
 $v=$r.output|ConvertFrom-Json;$code=$r.code
 switch($change){'VERSION'{$v.schemaVersion=2} 'LEASES'{$v.leaseCount=1} 'CALLBACKS'{$v.callbackCount=1} 'REACHED'{$v.operationReached=$false} 'CLAIM'{$v.claimRetained=$false} 'ERROR'{$v.observedError='80070005'} 'REASON'{$v.reason='OTHER'} 'EXTRA'{$v|Add-Member -NotePropertyName unexpected -NotePropertyValue 1} 'EXIT'{$code=9}}
 Need (-not (Test-PhaseARestartProbeResult ($v|ConvertTo-Json -Compress) $code $n)) ('CONTRADICTORY_ACCEPTED_'+$change)
}
'PASS contradictory and unexpected records rejected'
