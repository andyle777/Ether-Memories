$ErrorActionPreference='Stop'
$project=Join-Path $PSScriptRoot 'EtLDecoder.csproj'
$missing=Join-Path $PSScriptRoot 'not-an-etl-file.etl'
$ErrorActionPreference='Continue'
$target=Join-Path ([IO.Path]::GetTempPath()) ([Guid]::NewGuid().ToString('N')+'.json')
$output=& dotnet run --project $project --no-restore -- $missing $target 2>&1
$ErrorActionPreference='Stop'
if ($LASTEXITCODE -ne 2 -or (($output -join "`n") -notmatch 'INPUT_MISSING')) { throw "DECODER_MISSING_INPUT_CONTRACT: exit=$LASTEXITCODE" }
Write-Output 'PASS decoder rejects missing ETL'
$invalid=Join-Path ([IO.Path]::GetTempPath()) ([Guid]::NewGuid().ToString('N')+'.etl')
[IO.File]::WriteAllText($invalid,'not a trace')
try {
 $ErrorActionPreference='Continue'
 $output=& dotnet run --project $project --no-restore -- $invalid $target 2>&1
 $exit=$LASTEXITCODE
 $ErrorActionPreference='Stop'
 if ($exit -ne 2 -or (($output -join "`n") -notmatch 'ETL_READ_FAILED') -or (Test-Path -LiteralPath $target)) {throw "INVALID_ETL_ACCEPTED: exit=$exit"}
 Write-Output 'PASS malformed ETL rejected without output'
} finally { [IO.File]::Delete($invalid) }
