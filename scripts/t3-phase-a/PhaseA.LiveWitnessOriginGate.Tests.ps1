# RED-first regression: an attacker-controlled probe must not promote LIVE evidence.
# Synthetic fixture and process fields only. This does not prove Windows enforcement.
$ErrorActionPreference='Stop'
. "$PSScriptRoot/PhaseA.Stage3.ps1"

$sid='S-1-5-21-101-202-303-1001'
$token=@{sid=$sid}
$root='C:\synthetic\ether-phase-a-store-'+('a'*32)
$fixture=@{
  root=$root
  protectedDir=(Join-Path $root 'protected')
  protectedFile=(Join-Path $root 'protected\original.bin')
  deniedFile=(Join-Path $root 'protected\rejected.bin')
}
$script:probeCalls=0
$backend=@{
  Exists={param($path) return $true}
  DirectoryExists={param($path) return $true}
  Probe={
    param($actualToken,$expectedSid,$operation,$path,$actualRoot)
    $script:probeCalls++
    return @{
      execution='PROCESS';sid=$expectedSid;operation=$operation
      attempted=$true;allowed=$false;error=5;handlesClosed=$true
      processVerified=$true;terminated=$true
      pid=42424;pipeClientPid=42424;createdAt='2026-11-17T00:00:00Z';nonce=('a'*32)
    }
  }
}
foreach($case in @(@('Read','protectedFile'),@('Overwrite','protectedFile'),@('Create','deniedFile'))) {
  $operation=$case[0];$targetId=$case[1]
  $result=Invoke-PhaseATrustedAccess $backend $fixture $token $sid $operation $targetId 'LIVE'
  if($result.status -cne 'UNVERIFIED' -or $result.reason -cne 'ORIGINAL_OPERATION_UNCORROBORATED' -or $result.evidence -cne 'LIVE') {
    throw "FORGED_LIVE_WITNESS_PROMOTED_$operation"
  }
}
if($script:probeCalls -ne 0) {throw 'LIVE_WITNESS_PROBE_INVOKED_BEFORE_VERIFIER_BRIDGE'}

# Simulation mode retains its historical result classification; it cannot be LIVE proof.
$injected=Invoke-PhaseATrustedAccess $backend $fixture $token $sid 'Read' 'protectedFile' 'INJECTED'
if($injected.status -cne 'OBSERVED' -or $injected.evidence -cne 'INJECTED' -or $injected.outcome -cne 'ACCESS_DENIED') {
  throw 'INJECTED_WITNESS_REGRESSION'
}
if($script:probeCalls -ne 1) {throw 'INJECTED_PROBE_WAS_NOT_EXECUTED'}
Write-Output 'PASS all three forged LIVE witnesses blocked; injected path preserved'
