$ErrorActionPreference='Stop'
. "$PSScriptRoot/PhaseA.EtlSupervisor.ps1"
$fixture=Join-Path $PSScriptRoot 'external-fixtures/SelfDescribingSingleEvent.etl'
$expected='4C312C63C7D366E12B908C49769943886C017497183733BC2C93B8D80E932C7C'
if((Get-FileHash -LiteralPath $fixture -Algorithm SHA256).Hash -cne $expected){throw 'FIXTURE_HASH_MISMATCH'}
$exe=Join-Path $PSScriptRoot 'etl-decoder/bin/Debug/net10.0/EtLDecoder.exe'
$hash=(Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash
$dir=Join-Path ([IO.Path]::GetTempPath()) ('orion-decoder-pipe-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($dir)
[IO.File]::Copy($fixture,(Join-Path $dir 'input.etl'))
$result=Invoke-PhaseAEtlWorker -Executable $exe -ExecutableHash $hash -ExperimentDirectory $dir -TimeoutMs 10000
if($result.classification -cne 'COMPLETE' -or $result.transfer -cne 'ANONYMOUS_PIPE' -or $result.cleanup -cne 'CONFIRMED'){throw 'DECODER_PIPE_RUN_FAILED'}
$document=$result.outputJson | ConvertFrom-Json
if($document.Experiment -cne $result.experiment -or $document.Source -cne 'CAPTURED_UNTRUSTED' -or $document.Status -cne 'UNVERIFIED'){throw 'DECODER_PIPE_BINDING_FAILED'}
if([IO.File]::Exists((Join-Path $dir 'result.json'))){throw 'MUTABLE_OUTPUT_FILE_USED'}
Write-Output 'PASS real offline decoder emitted experiment-bound UNVERIFIED output through contained pipe'
