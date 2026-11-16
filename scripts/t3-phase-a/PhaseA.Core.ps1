Set-StrictMode -Version Latest
function Test-ActorObservation([hashtable]$Observation, [string]$Role, [string]$ExpectedOutcome) {
  $keys = @("role","expectedSid","observedSid","reportedSid","expectedPid","reportedPid","tokenNonAdmin","tokenObserved","createdAt","observedCreatedAt","reportedNonce","expectedNonce","exitCode","outcome")
  foreach ($key in $keys) { if (-not $Observation.ContainsKey($key) -or $null -eq $Observation[$key]) { return $false } }
  if ($Role -notin @("broker","legacy") -or $ExpectedOutcome -notin @("allowed","denied")) { return $false }
  if ($Observation.role -cne $Role -or $Observation.outcome -cne $ExpectedOutcome) { return $false }
  if ([string]::IsNullOrWhiteSpace([string]$Observation.expectedSid) -or
      $Observation.expectedSid -cne $Observation.observedSid -or
      $Observation.expectedSid -cne $Observation.reportedSid) { return $false }
  $expectedPid = 0; $reportedPid = 0
  if (-not [int]::TryParse([string]$Observation.expectedPid, [ref]$expectedPid) -or
      -not [int]::TryParse([string]$Observation.reportedPid, [ref]$reportedPid) -or
      $expectedPid -le 0 -or $expectedPid -ne $reportedPid) { return $false }
  if ($Observation.tokenNonAdmin -isnot [bool] -or -not $Observation.tokenNonAdmin -or
      $Observation.tokenObserved -isnot [bool] -or -not $Observation.tokenObserved) { return $false }
  $time = [DateTimeOffset]::MinValue
  if (-not [DateTimeOffset]::TryParse([string]$Observation.createdAt, [ref]$time)) { return $false }
  $observedTime = [DateTimeOffset]::MinValue
  if (-not [DateTimeOffset]::TryParse([string]$Observation.observedCreatedAt, [ref]$observedTime) -or $time -ne $observedTime) { return $false }
  if ([string]::IsNullOrWhiteSpace([string]$Observation.expectedNonce) -or
      $Observation.expectedNonce -cne $Observation.reportedNonce) { return $false }
  $expectedExit = if ($ExpectedOutcome -eq "allowed") { 0 } else { 20 }
  return ($Observation.exitCode -eq $expectedExit)
}
function Test-DistinctActorSids([string]$BrokerSid, [string]$LegacySid) {
  return (-not [string]::IsNullOrWhiteSpace($BrokerSid) -and
          -not [string]::IsNullOrWhiteSpace($LegacySid) -and $BrokerSid -cne $LegacySid)
}
function Test-RequiredCases([hashtable]$Cases) {
  $required = @("brokerCreate","brokerRead","legacyControl","legacyCreateDenied","legacyWriteDenied",
    "legacyReadDenied","protectedUnchanged","insecureRejected","sameSidRejected","wrongPidRejected",
    "spoofRejected","missingRejected","timeoutRejected","childTerminated","cleanupComplete")
  if ($Cases.Count -ne $required.Count) { return $false }
  foreach ($key in $required) {
    if (-not $Cases.ContainsKey($key) -or $Cases[$key] -isnot [bool] -or -not $Cases[$key]) { return $false }
  }
  return $true
}
function Get-PhaseAExitCode([string]$Status) {
  switch ($Status) { "GREEN" { return 0 } "RED" { return 1 } default { return 2 } }
}
function Test-SanitizedReport([hashtable]$Report) {
  $keys = @("schema","status","source","cases","cleanup")
  if ($Report.Count -ne $keys.Count) { return $false }
  foreach ($key in $keys) { if (-not $Report.ContainsKey($key)) { return $false } }
  if ($Report.schema -cne "ether.t3.phase-a.v1" -or $Report.status -cne "GREEN" -or
      $Report.source -cne "42f9b5bdf94e47c4c69c0f87127eb545dff13ed1" -or
      $Report.cleanup -cne "complete" -or $Report.cases -isnot [hashtable]) { return $false }
  return (Test-RequiredCases $Report.cases)
}
function Wait-PhaseAProcess($Process, [int]$TimeoutMilliseconds) {
  if ($TimeoutMilliseconds -lt 1 -or $TimeoutMilliseconds -gt 120000) {
    return @{completed=$false; timeout=$false; terminated=$false}
  }
  try {
    if ($Process.WaitForExit($TimeoutMilliseconds)) {
      return @{completed=$true; timeout=$false; terminated=$true}
    }
    try {
      $Process.Kill()
      $terminated = [bool]$Process.WaitForExit(5000)
      return @{completed=$false; timeout=$true; terminated=$terminated}
    } catch { return @{completed=$false; timeout=$true; terminated=$false} }
  } catch { return @{completed=$false; timeout=$false; terminated=$false} }
}
function Test-PhaseAReport([hashtable]$Report) {
  $keys = @("schema","status","source","commit","filesystem","cases","cleanup","brokerTag","legacyTag")
  if ($Report.Count -ne $keys.Count) { return $false }
  foreach ($key in $keys) { if (-not $Report.ContainsKey($key)) { return $false } }
  if ($Report.schema -cne "ether.t3.phase-a.v2" -or $Report.status -cne "GREEN" -or
      $Report.source -cne "42f9b5bdf94e47c4c69c0f87127eb545dff13ed1" -or
      $Report.commit -cnotmatch '^[0-9a-f]{40}$' -or $Report.filesystem -cne "NTFS" -or
      $Report.cleanup -cne "complete" -or $Report.brokerTag -cnotmatch '^[0-9a-f]{64}$' -or
      $Report.legacyTag -cnotmatch '^[0-9a-f]{64}$' -or $Report.brokerTag -ceq $Report.legacyTag -or
      $Report.cases -isnot [hashtable]) { return $false }
  return (Test-RequiredCases $Report.cases)
}
function Test-PhaseAObservationReport([Collections.IDictionary]$Report,[scriptblock]$Verify={param($kind,$entry,$record) return $false}) {
  $fields=@('schema','status','source','commit','reason','cases','supervisorCases','verdict')
  if ($Report.Count -ne $fields.Count) { return $false }
  foreach ($field in $fields) { if (-not $Report.Contains($field)) { return $false } }
  if ($Report.schema -cne 'ether.t3.phase-a.observations.v1' -or $Report.status -cnotin @('UNVERIFIED','GREEN','RED') -or
      $Report.source -cne '42f9b5bdf94e47c4c69c0f87127eb545dff13ed1' -or
      ($Report.commit -cne 'unknown' -and $Report.commit -cnotmatch '^[0-9a-f]{40}$')) { return $false }
  $reasons=@('CONFIGURATION_REJECTED','CHECKOUT_REJECTED','STAGE2_GUARD_REJECTED','STAGE3_GUARD_REJECTED',
    'IMPLEMENTATION_INCOMPLETE','VERDICT_GREEN','VERDICT_RED','SUPERVISOR_LIVE_FAILED','SUPERVISOR_INJECTED_FAILED','SUPERVISOR_PROBE_FAILED','SUPERVISOR_JOB_PROBE_FAILED','SUPERVISOR_DEATH_PROBE_FAILED','SUPERVISOR_PROBE_REQUIRED','ADVERSARIAL_CONTROL_FAILED','ACCOUNT_MANAGEMENT_UNAVAILABLE','ACCOUNT_CREATION_FAILED','ACCOUNT_IDENTITY_REJECTED',
    'ACCOUNT_AUTHENTICATION_FAILED','ACCOUNT_PRIVILEGE_UNAVAILABLE','ACCOUNT_LOGON_RIGHT_UNAVAILABLE','ACCOUNT_CONSUMER_FAILED',
    'ACCOUNT_CLEANUP_FAILED','STAGE2_OBSERVATION_REJECTED','STAGE2_LAUNCH_FAILED','STAGE2_TIMEOUT','STAGE2_CLEANUP_FAILED',
    'STAGE3_SETUP_FAILED','STAGE3_ACL_REJECTED','STAGE3_CASE_FAILED','STAGE3_CLEANUP_FAILED')
  if ($Report.reason -cnotin $reasons -or $Report.cases -isnot [Collections.IDictionary]) { return $false }
  $required=@('accountIdentity','brokerIdentity','legacyIdentity','actorIdentity','containment','acl','authorizedRead',
    'authorizedCreate','authorizedReadback','unauthorizedRead','unauthorizedWrite','unauthorizedCreate','proposedDelete','proposedRename','inventory',
    'insecureRejected','processCleanup','fixtureCleanup','accountCleanup','adversarialControls','supervisorInjected','supervisorFailure')
  if ($Report.cases.Count -ne $required.Count) { return $false }
  foreach ($case in $required) {
    if (-not $Report.cases.Contains($case)) { return $false }
    $allowed=@('PASS','FAIL','NOT_RUN'); if ($case -cin @('adversarialControls','supervisorInjected')) { $allowed+=@('SIMULATED_PASS') }; if ($case -ceq 'supervisorFailure') { $allowed+=@('SAME_IDENTITY_PASS') }
    if ($Report.cases[$case] -cnotin $allowed) { return $false }
  }
  if ($Report.supervisorCases -isnot [Collections.IDictionary] -or $Report.supervisorCases.Count -ne 3) { return $false }
  $allowedReasons=@('NOT_RUN','NONE','BACKEND_FAILURE','SETUP_FAILED','LAUNCH_FAILED','SUPERVISOR_IDENTITY_MISMATCH','READINESS_MISSING','EARLY_EXIT','TERMINATION_FAILED','MISSING_OBSERVATION','IDENTITY_MISMATCH','PID_MISMATCH','TIME_MISMATCH','JOB_MISMATCH','SUPERVISOR_SURVIVED','CHILD_SURVIVED','CHILD_UNCONFIRMED','CLEANUP_FAILED','TIMEOUT_NOT_OBSERVED')
  foreach ($mode in @('supervisorDeath','jobClosure','timeout')) {
    if (-not $Report.supervisorCases.Contains($mode)) { return $false }
    $entry=$Report.supervisorCases[$mode]
    if ($entry -isnot [Collections.IDictionary] -or $entry.Count -ne 3 -or -not $entry.Contains('status') -or -not $entry.Contains('reason') -or -not $entry.Contains('evidence') -or $entry.evidence -cne 'LIVE' -or $entry.status -cnotin @('NOT_RUN','LIVE_OBSERVED','FAIL') -or $entry.reason -cnotin $allowedReasons) { return $false }
    if (($entry.status -ceq 'NOT_RUN' -and $entry.reason -cne 'NOT_RUN') -or ($entry.status -ceq 'LIVE_OBSERVED' -and $entry.reason -cne 'NONE') -or ($entry.status -ceq 'FAIL' -and $entry.reason -cin @('NOT_RUN','NONE'))) { return $false }
  }
  if (-not (Test-PhaseAFinalReport $Report.verdict $Verify) -or $Report.status -cne $Report.verdict.status -or $Report.commit -cne $Report.verdict.commit) { return $false }
  if (($Report.status -ceq 'GREEN' -and $Report.reason -cne 'VERDICT_GREEN') -or ($Report.status -ceq 'RED' -and $Report.reason -cne 'VERDICT_RED')) { return $false }
  if ($Report.status -ceq 'GREEN') {
    foreach ($key in @('accountIdentity','brokerIdentity','legacyIdentity','actorIdentity','containment','acl','authorizedRead','authorizedCreate','authorizedReadback','unauthorizedRead','unauthorizedWrite','unauthorizedCreate','inventory','insecureRejected','processCleanup','fixtureCleanup','accountCleanup')) { if ($Report.cases[$key] -cne 'PASS') { return $false } }
    foreach ($mode in @('supervisorDeath','jobClosure','timeout')) { if ($Report.supervisorCases[$mode].status -cne 'LIVE_OBSERVED') { return $false } }
  }
  return $true
}
function Test-PhaseAConfig([hashtable]$Config) {
  $keys = @("repository","event","ref","runner","sha","base")
  if ($Config.Count -ne $keys.Count) { return $false }
  foreach ($key in $keys) { if (-not $Config.ContainsKey($key)) { return $false } }
  return ($Config.repository -ceq "andyle777/Ether-Memories" -and
    $Config.event -ceq "push" -and
    $Config.ref -ceq "refs/heads/test/t3-windows-enforcement-run" -and
    $Config.runner -ceq "github-hosted" -and
    $Config.sha -cmatch '^[0-9a-f]{40}$' -and
    $Config.base -ceq "42f9b5bdf94e47c4c69c0f87127eb545dff13ed1")
}
function Test-PhaseAPins([hashtable]$Pins) {
  $expected = @{
    ".t3-phase2-harness/Actor.ps1"="197e2198739c7b5267c7523af746757b74f78f9ba64ba2964941c73d8a02e7a1"
    ".t3-phase2-harness/Invoke-Phase2.ps1"="b7468536670a17d5a42c4eef0ea67bee54f632cba644941ad2e7b1e518cd5bf3"
    ".t3-phase2-harness/JobSupervisor.ps1"="1e975c73e04f04ef819cb4c11252932bfbb9a77367e5e7475d79919e33a98c07"
    ".t3-phase2-harness/Test-JobObject.ps1"="a4fa0aca1b4e9e5115024cc2ba3fe5f7a8a00375ccd688067e3caf2b94017e31"
    ".t3-phase2-harness/README.md"="125bf675e3d2d21f96ac10f5da597369537036f0edf77a3aeb7533759c1744a0"
    "src/persistence/productionOperations.ts"="51afc2951d2997892bd938d63bb77add0a55297b1e86c2cef2be17401dc1129f"
  }
  if ($Pins.Count -ne $expected.Count) { return $false }
  foreach ($key in $expected.Keys) {
    if (-not $Pins.ContainsKey($key) -or $Pins[$key] -cne $expected[$key]) { return $false }
  }
  return $true
}
function Get-PhaseARetainedProcessIdentity($Handle) {
  if(-not ('PhaseAPreflightIdentity' -as [type])){
    Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;
public static class PhaseAPreflightIdentity {
  [DllImport("kernel32.dll", SetLastError=true)] static extern uint GetProcessId(SafeProcessHandle process);
  [DllImport("kernel32.dll", SetLastError=true)] static extern bool GetProcessTimes(SafeProcessHandle process, out long creation, out long exit, out long kernel, out long user);
  public static object[] Observe(SafeProcessHandle process) {
    uint pid=GetProcessId(process); if(pid==0) throw new Win32Exception(Marshal.GetLastWin32Error());
    long creation,exit,kernel,user; if(!GetProcessTimes(process,out creation,out exit,out kernel,out user)) throw new Win32Exception(Marshal.GetLastWin32Error());
    return new object[] { checked((int)pid), DateTime.FromFileTimeUtc(creation).ToString("o") };
  }
}
'@ -ErrorAction Stop
  }
  $v=[PhaseAPreflightIdentity]::Observe($Handle);return @{pid=$v[0];createdAt=$v[1]}
}
function Invoke-PhaseAGit([string]$Repository, [string]$Arguments, $Journal=$null, [scriptblock]$ProcessFactory={New-Object Diagnostics.Process}, [string]$Experiment='', [string]$Operation='OTHER', [int]$Sequence=0, [scriptblock]$Observer=$null) {
  if($Experiment -ceq ''){$Experiment=[Guid]::NewGuid().ToString('N')}
  $record=@{role='CHECKOUT_PREFLIGHT';experiment=$Experiment;operation=$Operation;sequence=$Sequence;attempt=[Guid]::NewGuid().ToString('N');launch='ATTEMPTED';pid=$null;createdAt=$null;observedPid=$null;observedCreatedAt=$null;identity='NOT_OBSERVED';waitAttempted=$false;firstWait='NOT_RUN';wait='NOT_RUN';termination='NOT_REQUESTED';exitObserved=$false;exitCode=$null;managedDispose='NOT_ATTEMPTED';nativeClose='NOT_OBSERVED';error='NONE'}
  if($null -ne $Journal){$Journal.Add($record)}
  $start = New-Object Diagnostics.ProcessStartInfo
  $start.FileName = 'git.exe'; $start.Arguments = $Arguments; $start.WorkingDirectory = $Repository
  $start.UseShellExecute = $false; $start.CreateNoWindow = $true
  $start.RedirectStandardOutput = $true; $start.RedirectStandardError = $true
  $p=$null
  $result=$null;$keep=$false
  try {
    $p = & $ProcessFactory; $p.StartInfo = $start
    if (-not $p.Start()) { $record.launch='FAILED';$record.error='START_FAILED';throw 'start failed' }
    $record.launch='CREATED';$nativeHandle=$null
    if($null -eq $Observer){try{$nativeHandle=$p.SafeHandle}catch{$record.error='HANDLE_UNAVAILABLE'}}
    $record.pid=$p.Id
    try{$record.createdAt=$p.StartTime.ToUniversalTime().ToString('o')}catch{$record.error='CREATION_TIME_UNAVAILABLE'}
    try{if($null -eq $Observer){if($null -eq $nativeHandle){throw 'handle unavailable'};$independent=Get-PhaseARetainedProcessIdentity $nativeHandle}else{$independent=& $Observer $record.pid};if($independent -is [hashtable]){$record.observedPid=$independent.pid;$record.observedCreatedAt=$independent.createdAt;if($record.pid -eq $independent.pid -and $record.createdAt -and $record.createdAt -ceq $independent.createdAt){$record.identity='MATCHED'}else{$record.identity='MISMATCH';$record.error='IDENTITY_MISMATCH'}}else{$record.identity='UNAVAILABLE';$record.error='IDENTITY_UNAVAILABLE'}}catch{$record.identity='UNAVAILABLE';if($record.error -ceq 'NONE'){$record.error='IDENTITY_UNAVAILABLE'}}
    $out = $p.StandardOutput.ReadToEndAsync(); $err = $p.StandardError.ReadToEndAsync()
    $record.waitAttempted=$true
    if (-not $p.WaitForExit(10000)) { $record.firstWait='TIMEOUT';$record.wait='TIMEOUT';$record.termination='REQUESTED';$p.Kill();if($p.WaitForExit(5000)){$record.wait='SIGNALED';$record.exitObserved=$true;try{$record.exitCode=$p.ExitCode}catch{$record.error='EXIT_CODE_UNAVAILABLE'}}else{$record.wait='UNCONFIRMED';$record.error='TERMINATION_UNCONFIRMED';$keep=$true} }
    else {$record.firstWait='SIGNALED';$record.wait='SIGNALED';$record.exitObserved=$true;$record.exitCode=$p.ExitCode;$result=@{ code=$p.ExitCode; output=$out.Result.Trim(); error=$err.Result }}
  } catch { if($record.launch -ceq 'ATTEMPTED'){$record.launch='FAILED';$record.error='START_FAILED'}elseif($record.launch -ceq 'CREATED' -and $record.wait -cne 'SIGNALED'){if($record.waitAttempted -and $record.firstWait -ceq 'NOT_RUN'){$record.firstWait='FAILED'};$record.wait='UNCONFIRMED';$record.error='WAIT_UNCONFIRMED';$keep=$true}elseif($record.wait -ceq 'SIGNALED' -and $record.error -ceq 'NONE'){$record.error='EXIT_OR_OUTPUT_UNAVAILABLE'} } finally {
    if($keep){if(-not (Get-Variable -Name PhaseAUnconfirmedPreflightProcesses -Scope Script -ErrorAction SilentlyContinue)){$script:PhaseAUnconfirmedPreflightProcesses=New-Object 'System.Collections.Generic.List[object]'};$script:PhaseAUnconfirmedPreflightProcesses.Add($p);$record.managedDispose='RETAINED'}
    elseif($null -ne $p) {try{$p.Dispose();$record.managedDispose='DISPOSE_RETURNED'}catch{$record.managedDispose='FAILED';$record.error='DISPOSAL_FAILED';$result=$null}}
  }
  return $result
}
function Test-PhaseAPreflightJournal($Journal,[string]$Experiment,[string[]]$Operations) {
  try {
    if($Experiment -cnotmatch '^[0-9a-f]{32}$' -or $null -eq $Journal -or $Journal.Count -ne $Operations.Count){return $false}
    $seen=@{}
    for($i=0;$i -lt $Operations.Count;$i++){
      $r=$Journal[$i]
      if($r -isnot [hashtable] -or $r.role -cne 'CHECKOUT_PREFLIGHT' -or $r.experiment -cne $Experiment -or $r.operation -cne $Operations[$i] -or $r.sequence -ne $i -or $r.attempt -cnotmatch '^[0-9a-f]{32}$' -or $seen.ContainsKey($r.attempt)){return $false}
      $seen[$r.attempt]=$true
      $stamp=[DateTimeOffset]::MinValue
      if($r.launch -cne 'CREATED' -or $r.pid -isnot [int] -or $r.pid -le 0 -or $r.identity -cne 'MATCHED' -or $r.observedPid -ne $r.pid -or -not [DateTimeOffset]::TryParse([string]$r.createdAt,[ref]$stamp) -or $r.createdAt -cne $r.observedCreatedAt -or $r.waitAttempted -isnot [bool] -or -not $r.waitAttempted -or $r.firstWait -cne 'SIGNALED' -or $r.wait -cne 'SIGNALED' -or $r.termination -cne 'NOT_REQUESTED' -or $r.exitObserved -isnot [bool] -or -not $r.exitObserved -or $r.exitCode -isnot [int] -or $r.managedDispose -cne 'DISPOSE_RETURNED' -or $r.nativeClose -cne 'NOT_OBSERVED' -or $r.error -cne 'NONE'){return $false}
    }
    return $true
  } catch { return $false }
}
function Test-PhaseACheckout([string]$Repository, [string]$ExpectedHead, [string]$Base, $Journal=$null, [scriptblock]$ProcessFactory={New-Object Diagnostics.Process}, [scriptblock]$Observer=$null) {
  if ($ExpectedHead -cnotmatch '^[0-9a-f]{40}$' -or $Base -cnotmatch '^[0-9a-f]{40}$') { return $false }
  if($null -eq $Journal){$Journal=New-Object 'System.Collections.Generic.List[object]'}
  if($Journal.Count -ne 0){return $false};$experiment=[Guid]::NewGuid().ToString('N')
  $head = Invoke-PhaseAGit $Repository 'rev-parse HEAD' $Journal $ProcessFactory $experiment 'HEAD' 0 $Observer
  if ($null -eq $head -or $head.code -ne 0 -or $head.output -cne $ExpectedHead -or -not (Test-PhaseAPreflightJournal $Journal $experiment @('HEAD'))) { return $false }
  $ancestor = Invoke-PhaseAGit $Repository ("merge-base --is-ancestor " + $Base + " " + $ExpectedHead) $Journal $ProcessFactory $experiment 'ANCESTOR' 1 $Observer
  if ($null -eq $ancestor -or $ancestor.code -ne 0 -or -not (Test-PhaseAPreflightJournal $Journal $experiment @('HEAD','ANCESTOR'))) { return $false }
  $clean = Invoke-PhaseAGit $Repository 'diff --quiet HEAD --' $Journal $ProcessFactory $experiment 'CLEAN' 2 $Observer
  if ($null -eq $clean -or $clean.code -ne 0 -or -not (Test-PhaseAPreflightJournal $Journal $experiment @('HEAD','ANCESTOR','CLEAN'))) { return $false }
  $pins = @{}
  foreach ($path in @('.t3-phase2-harness/Actor.ps1','.t3-phase2-harness/Invoke-Phase2.ps1',
    '.t3-phase2-harness/JobSupervisor.ps1','.t3-phase2-harness/Test-JobObject.ps1',
    '.t3-phase2-harness/README.md','src/persistence/productionOperations.ts')) {
    try { $pins[$path] = (Get-FileHash -LiteralPath (Join-Path $Repository $path) -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant() }
    catch { return $false }
  }
  return (Test-PhaseAPins $pins)
}
function Invoke-PhaseAManagerPreflightGate([hashtable]$Config,[string]$Repository,[string]$Base,$Journal,[scriptblock]$Checkout,[scriptblock]$AfterCheckout) {
  if(-not (Test-PhaseAConfig $Config)){return 'CONFIGURATION_REJECTED'}
  try {
    if(-not (& $Checkout $Repository $Config.sha $Base $Journal)){return 'CHECKOUT_REJECTED'}
    if($Journal.Count -ne 3 -or -not (Test-PhaseAPreflightJournal $Journal $Journal[0].experiment @('HEAD','ANCESTOR','CLEAN'))){return 'CHECKOUT_REJECTED'}
  } catch { return 'CHECKOUT_REJECTED' }
  return (& $AfterCheckout)
}
