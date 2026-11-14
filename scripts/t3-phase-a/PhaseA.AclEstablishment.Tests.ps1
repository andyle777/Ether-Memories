$ErrorActionPreference='Stop'
. "$PSScriptRoot/PhaseA.Stage3.ps1"
$script:fixture=@{root=(Join-Path ([IO.Path]::GetTempPath()) ('ether-phase-a-store-'+('a'*32)))}
$script:fixture.protectedDir=Join-Path $script:fixture.root 'protected';$script:fixture.controlDir=Join-Path $script:fixture.root 'control'
function Run-Targets([string]$fail,[string]$kind) {
 $state=@{last=$null;role=''};$records=New-Object 'System.Collections.Generic.List[object]';$results=@{}
 $io=@{Exists={param($p) $true}; Apply={param($p,$a) if($state.role -ceq $fail -and $kind -ceq 'APPLY'){throw 'secret apply error'};$state.last=$a}.GetNewClosure();Read={param($p) if($state.role -ceq $fail -and $kind -ceq 'READ'){throw 'secret read error'};return $state.last}.GetNewClosure()}
 foreach($spec in @(@('root','.',0),@('protected','protected',1),@('control','control',2))){$state.role=$spec[0];$path=if($spec[0] -ceq 'root'){$script:fixture.root}else{$script:fixture[$spec[0]+'Dir']};try{$null=Invoke-PhaseARecordedFixtureAcl $records $script:fixture $spec[0] $path ([int]$spec[2]) @('S-1-5-18') @() 'INJECTED' $io}catch{break}}
 return ,@($records.ToArray())
}
$all=Run-Targets '' '';if($all.Count -ne 3){throw 'three target records required'}
for($i=0;$i -lt 3;$i++){ $r=$all[$i];if($r.sequence -ne $i -or $r.role -cne @('root','protected','control')[$i] -or $r.relative -cne @('.','protected','control')[$i] -or -not $r.applied -or -not $r.attempted -or $r.actual -cne $r.expected -or -not $r.actualProtected -or $r.source -cne 'INJECTED'){throw 'successful ACL record invalid'};if(($r|Out-String).Contains($script:fixture.root)){throw 'absolute path disclosed'}}
foreach($i in 0,1,2){$role=@('root','protected','control')[$i];$rr=Run-Targets $role 'APPLY';if($rr.Count -ne ($i+1) -or $rr[$i].reason -cne 'APPLY_FAILED' -or -not $rr[$i].attempted -or $rr[$i].applied -or $rr[$i].actual -cne ''){throw "application failure invalid $role"};for($j=0;$j -lt $i;$j++){if(-not $rr[$j].applied -or $rr[$j].reason -cne 'NONE'){throw 'earlier successful record lost'}}}
$rr=Run-Targets 'protected' 'READ';if($rr.Count -ne 2 -or $rr[1].reason -cne 'READ_FAILED' -or -not $rr[1].applied -or $rr[1].actual -cne ''){throw 'read failure invalid'}
$missing=New-Object 'System.Collections.Generic.List[object]';$missingIo=@{Exists={param($p) $false};Apply={throw 'must not apply'}}
try {$null=Invoke-PhaseARecordedFixtureAcl $missing $script:fixture 'root' $script:fixture.root 0 @('S-1-5-18') @() 'INJECTED' $missingIo;throw 'missing target accepted'}catch{if($_.Exception.GetBaseException().Message -cne 'STAGE3_ACL_REJECTED'){throw}}
if($missing.Count -ne 1 -or $missing[0].reason -cne 'TARGET_MISSING' -or $missing[0].attempted -or $missing[0].applied -or $missing[0].targetExists){throw 'unattempted target reported success'}
$sink=@{};$backend=@{Setup={param($accounts,$evidence) $evidence['aclEstablishment']=Run-Targets 'protected' 'READ';throw 'STAGE3_CLEANUP_FAILED'}};$result=Invoke-PhaseAStage3 @() @() $backend @{} $sink
if($result.status -cne 'STAGE3_CLEANUP_FAILED' -or $sink.evidence.aclEstablishment.Count -ne 2 -or $sink.evidence.aclEstablishment[1].reason -cne 'READ_FAILED' -or $sink.evidence.cleanupVerified){throw 'setup or cleanup failure lost evidence'}
Write-Output 'PASS ACL producer: three targets and six injected failure controls'
