[CmdletBinding()]
param(
 [Parameter(Mandatory=$true)][ValidateSet('OfflineFixture','HostedCapture','ValidateSummary')][string]$Mode,
 [string]$ParentDirectory='', [string]$FixturePath='', [string]$SourceSha='',
 [string]$ExpectedControllerSha256='', [string]$ExpectedDecoderSha256='',
 [Parameter(Mandatory=$true)][string]$SummaryPath='', [string]$ValidatedSummaryPath=''
)
$ErrorActionPreference='Stop'
try {
 . "$PSScriptRoot/PhaseA.GateBPipeline.ps1"
 if($Mode -ceq 'ValidateSummary') {
  if(-not $ValidatedSummaryPath){throw 'OUTPUT_REQUIRED'}
  $json=ConvertTo-GateBValidatedSummary ([IO.File]::ReadAllText($SummaryPath))
  Write-GateBNewJson $ValidatedSummaryPath $json
 } else {
  $json=Invoke-PhaseAGateBPipelineCore -Mode $Mode -ParentDirectory $ParentDirectory -FixturePath $FixturePath -SourceSha $SourceSha -ControllerSha $ExpectedControllerSha256 -DecoderSha $ExpectedDecoderSha256
  $json=ConvertTo-GateBValidatedSummary $json
  Write-GateBNewJson $SummaryPath $json
 }
 Write-Output '{"classification":"UNVERIFIED","diagnostic":"SUMMARY_WRITTEN"}'
 exit 0
} catch {
 # No exception text, raw diagnostics, trace bytes or machine-specific paths.
 Write-Output '{"classification":"UNVERIFIED","diagnostic":"PIPELINE_INCOMPLETE"}'
 exit 2
}
