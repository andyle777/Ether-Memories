$ErrorActionPreference='Stop'
. "$PSScriptRoot/PhaseA.GateBSummary.ps1"
$r=@{sourceSha=('a'*40);controllerSha256=('b'*64);decoderSha256=('c'*64);experiment=('d'*32);requestedBytes=4;actualBytes=4;fixtureDigestMatch=$true;stop='SESSION_STOPPED';statisticsValid=$false;eventsLost=$null;logBuffersLost=$null;realTimeBuffersLost=$null;createPresent=$false;readPresent=$false;completionPresent=$false}
$j=ConvertTo-PhaseAGateBPublicSummary $r | ConvertFrom-Json
if($j.securityStatus -cne 'UNVERIFIED' -or $null -ne $j.eventsLost){throw 'SUMMARY_BOUNDARY_FAILED'}
foreach($mutation in @('unknown','path','sid','loss','status')) {
 $x=$r.Clone()
 switch($mutation){'unknown'{$x.extra='private'} 'path'{$x.experiment='C:\private'} 'sid'{$x.sourceSha='S-1-5-21'} 'loss'{$x.eventsLost=0} 'status'{$x.stop='LIVE'}}
 $rejected=$false;try {$null=ConvertTo-PhaseAGateBPublicSummary $x}catch{$rejected=$true};if(-not $rejected){throw ('SUMMARY_ACCEPTED_'+$mutation)}
}
Write-Output 'PASS summary rejects unknown fields, paths, SIDs, false loss and LIVE status'
