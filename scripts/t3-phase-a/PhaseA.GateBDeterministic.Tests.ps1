$ErrorActionPreference='Stop'
$files=@('PhaseA.EtwNative.Preparation.cs','PhaseA.EtwLifecycle.cs','gate-b-controller/GateBController.csproj','gate-b-controller/packages.lock.json','gate-b-controller/Program.cs','gate-b-controller/GateBWorkload.cs','gate-b-controller/GateBReceipt.cs','gate-b-controller/GateBOrchestration.cs','gate-b-controller/GateBSerializedReceipt.cs','etl-decoder/EtLDecoder.csproj','etl-decoder/packages.lock.json','etl-decoder/Program.cs','etl-decoder/LimitedOutputStream.cs')
$roots=@()
foreach($index in 0..1){
 $root=Join-Path ([IO.Path]::GetTempPath()) ('orion-build-proof-'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($root);$roots+=$root
 foreach($name in $files){$from=Join-Path $PSScriptRoot $name;$to=Join-Path $root $name;[void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($to));$bytes=[IO.File]::ReadAllBytes($from);if ($name.EndsWith('.cs')) {
    $utf8 = [Text.UTF8Encoding]::new($false, $true)
    $lf = $utf8.GetString($bytes)

    if ($lf.Contains("`r") -or -not $lf.Contains("`n")) {
        throw "NONCANONICAL_SOURCE_$name"
    }

    if ($index -eq 1) {
        $crlf = $utf8.GetBytes($lf.Replace("`n", "`r`n"))

        [IO.File]::WriteAllBytes($to, $crlf)
        $actual = [IO.File]::ReadAllBytes($to)

        if ([Convert]::ToBase64String($actual) -ceq [Convert]::ToBase64String($bytes)) {
            throw "CRLF_NEGATIVE_CONTROL_FAILED_$name"
        }

        $text = $utf8.GetString($actual)

        if (-not $text.Contains("`r`n")) {
            throw "CRLF_NOT_CREATED_$name"
        }

        $canonical = $utf8.GetBytes($text.Replace("`r`n", "`n"))

        if ([Convert]::ToBase64String($canonical) -cne [Convert]::ToBase64String($bytes)) {
            throw "CANONICAL_RESTORATION_FAILED_$name"
        }

        $bytes = $canonical

        Write-Output "PASS genuine CRLF conversion and restoration: $name"
    }
};[IO.File]::WriteAllBytes($to,$bytes)}
 foreach($project in @('gate-b-controller/GateBController.csproj','etl-decoder/EtLDecoder.csproj')){
  & dotnet restore (Join-Path $root $project) --locked-mode --source (Join-Path $env:USERPROFILE '.nuget/packages') -p:NuGetAudit=false 2>&1 | Out-Null
  if($LASTEXITCODE -ne 0){throw 'DETERMINISM_RESTORE_FAILED'}
  & dotnet build (Join-Path $root $project) --no-restore 2>&1 | Out-Null
  if($LASTEXITCODE -ne 0){throw 'DETERMINISM_BUILD_FAILED'}
 }
}
$sets=@();foreach($root in $roots){$paths=@();foreach($dir in @('gate-b-controller/bin/Debug/net10.0','etl-decoder/bin/Debug/net10.0')){$base=[IO.Path]::GetFullPath((Join-Path $root $dir));$paths+=@(Get-ChildItem -LiteralPath $base -File -Recurse | Where-Object {$_.Extension -in @('.dll','.exe','.json')} | ForEach-Object { $dir+'/'+$_.FullName.Substring($base.Length+1).Replace('\','/') })};$sets+=,@($paths | Sort-Object)}
$paths=$sets[0];if(@(Compare-Object $sets[0] $sets[1]).Count -ne 0){throw 'BUILD_OUTPUT_SET_MISMATCH'}
if($paths.Count -lt 2){throw 'BUILD_OUTPUTS_MISSING'}
foreach($name in $paths){$first=(Get-FileHash -LiteralPath (Join-Path $roots[0] $name) -Algorithm SHA256).Hash;$second=(Get-FileHash -LiteralPath (Join-Path $roots[1] $name) -Algorithm SHA256).Hash;$candidate=(Get-FileHash -LiteralPath (Join-Path $PSScriptRoot $name) -Algorithm SHA256).Hash;if($first -cne $second -or $candidate -cne $first){throw ('BUILD_PATH_OR_LINE_ENDING_NONDETERMINISTIC_'+$name)}}
Write-Output ('PASS independent canonical builds match after verified CRLF restoration for {0} runtime files' -f $paths.Count)
