param([string]$Root,[string]$Nonce,[string]$Source)
$ErrorActionPreference='Stop'
$result=@{schemaVersion=1;probeNonce=$Nonce;outcome='FAIL';reason='SETUP_ERROR';operationReached=$false;leaseCount=0;callbackCount=0;observedError='NONE';claimRetained=$false}
$exitCode=9
try {
 $result.reason='INVALID_NONCE'
 if($Nonce -cnotmatch '^[0-9a-f]{32}$'){throw 'PROBE_NONCE_INVALID'}
 $result.reason='SOURCE_UNAVAILABLE_OR_INVALID'
 . $Source
 $result.reason='INVALID_DOMAIN_BINDING'
 if([string]::IsNullOrWhiteSpace($Root) -or $Root -cnotmatch '^[A-Za-z]:\\'){throw 'PROBE_ROOT_INVALID'}
 $result.reason='DOMAIN_MISSING_OR_INACCESSIBLE'
 if(-not [IO.Directory]::Exists($Root)){throw 'PROBE_ROOT_UNAVAILABLE'}
 $result.reason='DOMAIN_VALIDATION_FAILED'
 $validRoot=Get-AdmissionRoot $Root
 $result.reason='CLAIM_PREREQUISITE_FAILED'
 $claim=Join-Path $validRoot 'admission.lock'
 $wasClaimed=[IO.File]::Exists($claim)
 if($wasClaimed){$item=Get-Item -LiteralPath $claim -Force -ErrorAction Stop;if($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'CLAIM_INVALID'}}
 $result.reason='CLAIM_OPERATION_SOURCE_INVALID'
 $lineText='$lk=New-Object IO.FileStream((Join-Path $root ''admission.lock''),[IO.FileMode]::CreateNew,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)'
 $lines=[IO.File]::ReadAllLines($Source);$indexes=@(0..($lines.Length-1)|Where-Object {$lines[$_].Trim() -ceq $lineText});if($indexes.Count -ne 1){throw 'CLAIM_OPERATION_SOURCE_INVALID'}
 $script:reached=$false
 try {
  $owner=Initialize-PhaseAAdmissionStore $validRoot {param($point) if($point -ceq 'INIT_LOCK_BEFORE_CREATE'){$script:reached=$true}}
  Close-PhaseAAdmissionLease $owner
  $result.operationReached=$script:reached;$result.reason='CLAIM_CREATED';$result.claimRetained=[IO.File]::Exists($claim);$exitCode=4
 }catch{
  $errorRecord=$_;$base=$errorRecord.Exception.GetBaseException();$hr=[uint32]([long]$base.HResult -band 0xffffffffL)
  $result.operationReached=$script:reached;$result.observedError=('{0:X8}' -f $hr);$result.claimRetained=[IO.File]::Exists($claim)
  $sameSource=[string]::Equals([IO.Path]::GetFullPath($errorRecord.InvocationInfo.ScriptName),[IO.Path]::GetFullPath($Source),[StringComparison]::OrdinalIgnoreCase)
  if($script:reached -and $sameSource -and $errorRecord.InvocationInfo.ScriptLineNumber -eq ($indexes[0]+1) -and $errorRecord.FullyQualifiedErrorId -ceq 'ConstructorInvokedThrowException,Microsoft.PowerShell.Commands.NewObjectCommand' -and $base -is [IO.IOException] -and $hr -eq [uint32]2147942480 -and $result.claimRetained){$result.outcome='DENIED';$result.reason='DOMAIN_ALREADY_CLAIMED';$exitCode=0}else{$result.reason='UNRELATED_OR_UNVERIFIED_ERROR';$exitCode=7}
 }
}catch{$exception=$_.Exception.GetBaseException();$result.observedError=('{0:X8}' -f [uint32]([long]$exception.HResult -band 0xffffffffL));$exitCode=8}
$result|ConvertTo-Json -Compress
exit $exitCode
