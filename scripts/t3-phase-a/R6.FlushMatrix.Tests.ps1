$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'PhaseA.StateOnlyAdmission.ps1')
. (Join-Path $PSScriptRoot 'PhaseA.RestartProbeValidation.ps1')
function Need($v,$m){if(-not $v){throw $m}}
$script:originalOpen=(Get-Item Function:\Open-PhaseAAdmissionLease).ScriptBlock
function Open-PhaseAAdmissionLease($owner,[string]$session,[scriptblock]$Fault=$null,[scriptblock]$Flush=$null){$lease=& $script:originalOpen $owner $session $Fault $Flush;$script:leases++;return $lease}
foreach($stage in @('INIT_EMPTY','INIT_JOURNAL','RECEIPT','MARKER','INTENT_JOURNAL','CLEAN_JOURNAL')){
 foreach($kind in @('NORMAL','THROW','ERROR','CONTINUE','ERROR_OUTPUT','OUTPUT','VISIBLE')){
  $root=Join-Path $env:TEMP ('orion-r6-test-'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($root)
  $script:stage=$stage;$script:kind=$kind;$script:called=0;$script:reached=0;$script:leases=0
  $backend=@{Start={param($a,$m) $script:called++;$a.pid=123;$a.createdAt='2026-01-01T00:00:00Z';$a.contained=$true;$a.identity=$true};Wait={param($a,$n) $true};Terminate={param($a)};Close={param($a) $true}}
  $flush={param($s,$op) if($op -cne $script:stage){$s.Flush($true);return};$script:reached++;switch($script:kind){'NORMAL'{$s.Flush($true)} 'THROW'{throw [IO.IOException]::new('R6_THROW')} 'ERROR'{Write-Error 'R6_ERROR'} 'CONTINUE'{Write-Error 'R6_ERROR' -ErrorAction Continue} 'ERROR_OUTPUT'{Write-Error 'R6_ERROR' -ErrorAction Continue; 'unexpected'} 'OUTPUT'{'unexpected'} 'VISIBLE'{$s.Flush($true);Write-Error 'R6_ERROR' -ErrorAction Continue}}}
  $ErrorActionPreference='Continue';$r=Invoke-PhaseAStateOnlyAttempt $root ('a'*32) 1000 $backend {return [long]0} $null $flush
  Need ($ErrorActionPreference -ceq 'Continue') 'PREFERENCE_CHANGED'
  Need ($script:reached -eq 1) ('NOT_REACHED '+$stage+' '+$kind)
  if($kind -ceq 'NORMAL'){Need ($r.status -ceq 'SIMULATED_COMPLETE' -and $script:called -eq 1 -and $script:leases -eq 1) 'NORMAL_REJECTED'}else{$expected=if($stage -ceq 'CLEAN_JOURNAL'){1}else{0};Need ($r.status -ceq 'UNVERIFIED' -and $script:called -eq $expected -and $script:leases -eq $expected -and [IO.File]::Exists((Join-Path $root 'admission.lock'))) ('FAIL_OPEN '+$stage+' '+$kind)}
  $nonce=[guid]::NewGuid().ToString('N')
  $start=New-Object Diagnostics.ProcessStartInfo;$start.FileName=Join-Path $PSHOME 'powershell.exe'
  $probe=Join-Path $PSScriptRoot 'PhaseA.RestartProbe.ps1';$source=Join-Path $PSScriptRoot 'PhaseA.DurableAdmission.ps1'
  $start.Arguments='-NoProfile -NonInteractive -File "'+$probe+'" -Root "'+$root+'" -Nonce '+$nonce+' -Source "'+$source+'"'
  $start.UseShellExecute=$false;$start.CreateNoWindow=$true;$start.RedirectStandardOutput=$true;$start.RedirectStandardError=$true
  $process=[Diagnostics.Process]::Start($start)
  try{
   if(-not $process.WaitForExit(15000)){try{$process.Kill()}catch{throw 'PROBE_TERMINATION_UNCONFIRMED'};if(-not $process.WaitForExit(5000)){throw 'PROBE_TERMINATION_UNCONFIRMED'};throw 'PROBE_TIMEOUT'}
   $output=$process.StandardOutput.ReadToEnd();$errors=$process.StandardError.ReadToEnd()
   Need ($errors.Length -eq 0 -and (Test-PhaseARestartProbeResult $output $process.ExitCode $nonce)) ('FRESH_PROCESS_NOT_SEALED '+$stage+' '+$kind)
  }finally{$process.Dispose()}
  Write-Output ('PASS '+$stage+' '+$kind)
 }
}
$path=Join-Path $env:TEMP ('orion-r6-error-record-'+[guid]::NewGuid().ToString('N'));$s=[IO.File]::Open($path,[IO.FileMode]::CreateNew)
try{
 $caught=$false
 try{Invoke-AdmissionFlush $s 'TEST' {param($s,$op) Write-Error 'R6ERROR' -ErrorId 'R6OriginalId' -Category InvalidData -ErrorAction Continue}}catch{$caught=($_.FullyQualifiedErrorId -ceq 'R6OriginalId' -and $_.CategoryInfo.Category -eq [Management.Automation.ErrorCategory]::InvalidData)}
 Need $caught 'ERROR_RECORD_METADATA_LOST'
 $caught=$false
 try{Invoke-AdmissionFlush $s 'TEST' {param($s,$op) throw [IO.IOException]::new('R6_IO')}}catch{$caught=($_.Exception.GetBaseException() -is [IO.IOException])}
 Need $caught 'IO_EXCEPTION_TYPE_LOST'
}finally{$s.Dispose()}
'PASS original error record and exception type preserved'
