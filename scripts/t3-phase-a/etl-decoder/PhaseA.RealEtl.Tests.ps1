$ErrorActionPreference='Stop'
$fixture=Join-Path $PSScriptRoot '../external-fixtures/SelfDescribingSingleEvent.etl'
if (-not [IO.File]::Exists($fixture)) {throw 'REAL_ETL_FIXTURE_UNAVAILABLE'}
$expected='4C312C63C7D366E12B908C49769943886C017497183733BC2C93B8D80E932C7C'
if ((Get-FileHash -LiteralPath $fixture -Algorithm SHA256).Hash -cne $expected) {throw 'REAL_ETL_HASH_MISMATCH'}
$output=Join-Path ([IO.Path]::GetTempPath()) ('orion-real-etl-'+[Guid]::NewGuid().ToString('N')+'.json')
try {
 & dotnet (Join-Path $PSScriptRoot 'bin/Debug/net10.0/EtLDecoder.dll') $fixture $output
 if ($LASTEXITCODE -ne 0) {throw 'REAL_ETL_OPEN_FAILED'}
 $record=Get-Content -Raw -LiteralPath $output | ConvertFrom-Json
 if ($record.Source -cne 'CAPTURED_UNTRUSTED' -or $record.Status -cne 'UNVERIFIED') {throw 'REAL_ETL_TRUST_PROMOTED'}
 if ($record.DynamicDecodedEvents -lt 1) {throw 'REAL_ETL_EVENTS_NOT_DECODED'}
 Write-Output ('PASS real ETL opened; dynamic events decoded={0}; selected FileIo events={1}' -f $record.DynamicDecodedEvents,@($record.Events|Where-Object {$_.Kind -in @('READ','CREATE','OP_END')}).Count)
} finally {if ([IO.File]::Exists($output)) {[IO.File]::Delete($output)}}
