$ErrorActionPreference='Stop'
. "$PSScriptRoot/PhaseA.Stage3.ps1"
if(-not (Get-Command Complete-PhaseAWitnessTokenReference -ErrorAction SilentlyContinue)){throw 'TOKEN_REFERENCE_GUARD_MISSING'}
$script:calls=0;$release={param($h) $script:calls++};$record=@{}
$status=Complete-PhaseAWitnessTokenReference 'token' $true $true $record $release
if($status -cne 'RETAINED' -or $script:calls -ne 0 -or $record.tokenReferenceRelease -cne 'RETAINED'){throw 'UNCONFIRMED_TOKEN_RELEASED'}
$record=@{};$status=Complete-PhaseAWitnessTokenReference 'token' $true $false $record $release
if($status -cne 'RELEASED' -or $script:calls -ne 1 -or $record.tokenReferenceRelease -cne 'RELEASE_RETURNED'){throw 'CONFIRMED_TOKEN_NOT_RELEASED'}
$record=@{};$status=Complete-PhaseAWitnessTokenReference 'token' $true $false $record {param($h) throw 'INJECTED_RELEASE_FAILURE'}
if($status -cne 'RELEASE_FAILED' -or $record.tokenReferenceRelease -cne 'FAILED'){throw 'TOKEN_RELEASE_FAILURE_LOST'}
$source=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'PhaseA.ReadProcess.ps1'))
$count=$source.Split(@('$tokenDisposition=Complete-PhaseAWitnessTokenReference'),[StringSplitOptions]::None).Count - 1
if($count -ne 1){throw 'TOKEN_RELEASE_NOT_EXACTLY_ONCE'}
$release=$source.IndexOf('$tokenDisposition=Complete-PhaseAWitnessTokenReference')
$scratch=$source.IndexOf("`$LifecycleRecord.scratchCleanup='DELETE_RETURNED'")
if($release -lt 0 -or $scratch -lt 0 -or $release -lt $scratch){throw 'TOKEN_RELEASE_PRECEDES_FIXTURE_CLEANUP'}
Write-Output 'PASS token reference retained for unresolved cleanup and released only after confirmation'