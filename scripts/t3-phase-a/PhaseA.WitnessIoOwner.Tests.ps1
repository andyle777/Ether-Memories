$ErrorActionPreference='Stop'
. "$PSScriptRoot/PhaseA.Stage3.ps1"
$script:issued=0
$owner=New-PhaseAWitnessIoOwner 'pipe' (New-Object byte[] 16) ('a'*32) ('e'*32)
if($owner.experiment -cne ('e'*32) -or $owner.managerPid -ne $PID){throw 'OWNER_EXPERIMENT_OR_PROCESS_MISSING'}
$result=Invoke-PhaseAWitnessIoIssue $owner 'connection' { $script:issued++; 'pending' }
if($script:issued -ne 1 -or $result -cne 'pending' -or $owner.connection.state -cne 'ISSUED' -or $owner.connection.result -cne 'pending'){throw 'REGISTERED_IO_NOT_OBSERVED'}
$script:issued=0;$fake=@{attempt=('b'*32);pipe='pipe';buffer=(New-Object byte[] 16)}
try {$null=Invoke-PhaseAWitnessIoIssue $fake 'connection' { $script:issued++; 'pending' }}catch{}
if($script:issued -ne 0){throw 'UNREGISTERED_IO_ISSUED'}
$errorCode='';try{$null=Invoke-PhaseAWitnessIoIssue $owner 'connection' {throw 'duplicate'}}catch{$errorCode=$_.Exception.GetBaseException().Message}
if($errorCode -cne 'WITNESS_IO_ALREADY_ISSUED'){throw 'IO_ISSUED_TWICE'}
$errorCode='';try{Remove-PhaseAWitnessIoOwner $owner}catch{$errorCode=$_.Exception.GetBaseException().Message}
if($errorCode -cne 'WITNESS_IO_STILL_PENDING'){throw 'PENDING_OWNER_RELEASED'}
$owner.connection.state='COMPLETED';Remove-PhaseAWitnessIoOwner $owner
$errorCode='';try{Remove-PhaseAWitnessIoOwner $owner}catch{$errorCode=$_.Exception.GetBaseException().Message}
if($errorCode -cne 'WITNESS_IO_OWNER_REJECTED'){throw 'OWNER_RELEASED_TWICE'}
$registered=New-Object 'System.Collections.Generic.List[object]'
for($i=0;$i -lt 16;$i++){$registered.Add((New-PhaseAWitnessIoOwner 'pipe' (New-Object byte[] 16) ('c'*32)))}
$errorCode='';try{$null=New-PhaseAWitnessIoOwner 'pipe' (New-Object byte[] 16) ('d'*32)}catch{$errorCode=$_.Exception.GetBaseException().Message}
if($errorCode -cne 'WITNESS_IO_OWNER_UNAVAILABLE'){throw 'OWNER_REGISTRY_NOT_BOUNDED'}
foreach($o in $registered){Remove-PhaseAWitnessIoOwner $o}
Write-Output 'PASS pre-registration and duplicate issuance controls'
