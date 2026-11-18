$ErrorActionPreference='Stop'
& dotnet run --project (Join-Path $PSScriptRoot 'etl-output-tests/EtlOutputTests.csproj') --no-restore
if($LASTEXITCODE -ne 0) {throw 'DECODER_OUTPUT_TEST_FAILED'}
