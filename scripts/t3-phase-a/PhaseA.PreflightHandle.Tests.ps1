$ErrorActionPreference='Stop'
. "$PSScriptRoot/PhaseA.Core.ps1"
$start=New-Object Diagnostics.ProcessStartInfo
$start.FileName=Join-Path $PSHOME 'powershell.exe';$start.Arguments='-NoProfile -NonInteractive -Command exit';$start.UseShellExecute=$false;$start.CreateNoWindow=$true
$p=New-Object Diagnostics.Process;$p.StartInfo=$start
try {
 if(-not $p.Start()){throw 'PROCESS_START_FAILED'}
 $expectedPid=$p.Id;$expectedTime=$p.StartTime.ToUniversalTime().ToString('o')
 $handle=$p.SafeHandle
 if(-not $p.WaitForExit(10000)){throw 'PROCESS_WAIT_FAILED'}
 $identity=Get-PhaseARetainedProcessIdentity $handle
 if($identity.pid -ne $expectedPid -or $identity.createdAt -cne $expectedTime){throw 'RETAINED_HANDLE_IDENTITY_MISMATCH'}
}finally{$p.Dispose()}
Write-Output 'PASS native retained handle identity after exit'
