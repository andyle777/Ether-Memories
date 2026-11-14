$ErrorActionPreference='Stop'
. "$PSScriptRoot/PhaseA.Stage3.ps1"
$script:testRoot=Join-Path ([IO.Path]::GetTempPath()) ('ether-phase-a-store-'+[Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($script:testRoot)|Out-Null
try {
 $fixture=@{root=$script:testRoot;protectedDir=(Join-Path $script:testRoot 'protected');controlDir=(Join-Path $script:testRoot 'control')}
 $fixtureId=[IO.Path]::GetFileName($script:testRoot);$sink=@{}
 $backend=@{ObserveAcl={param($fixture,$role,$record) Get-PhaseAManagerAclObservation $fixture $role $record 'INJECTED'};Setup={param($a,$e,$observe) $record=@{fixtureId=$fixtureId;role='root';relative='.';sequence=0};$e.aclEstablishment=@($record);& $observe $fixture $record;throw 'STAGE3_ACL_REJECTED'}.GetNewClosure()}
 $accounts=@(@{sid='S-1-5-21-1'},@{sid='S-1-5-21-2'});$result=Invoke-PhaseAStage3 $accounts @() $backend @{} $sink
 if(-not $sink.evidence.ContainsKey('aclCorroboration') -or $sink.evidence.aclCorroboration.Count -ne 1 -or $sink.evidence.aclCorroboration[0].status -cne 'OBSERVED' -or $sink.evidence.aclCorroboration[0].fixtureId -cne $fixtureId){throw 'manager observation missing after setup failure'}
 if($sink.evidence.aclFixtureBinding.fixtureId -cne $fixtureId -or $sink.evidence.aclFixtureBinding.brokerSid -cne 'S-1-5-21-1' -or $sink.evidence.aclFixtureBinding.legacySid -cne 'S-1-5-21-2'){throw 'manager fixture binding missing'};if($result.status -cne 'STAGE3_ACL_REJECTED'){throw 'setup failure lost'}
 $wrong=@{fixtureId=('ether-phase-a-store-'+('0'*32));role='root';relative='.';sequence=0};$obs=Get-PhaseAManagerAclObservation $fixture 'root' $wrong 'INJECTED';if($obs.status -cne 'UNVERIFIED'){throw 'wrong fixture accepted'}
 Write-Output 'PASS manager ACL observation retention and binding'
} finally {[IO.Directory]::Delete($script:testRoot,$false)}
