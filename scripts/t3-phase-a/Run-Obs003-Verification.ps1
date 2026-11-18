$ErrorActionPreference='Stop'
$suites=@(Get-ChildItem -LiteralPath $PSScriptRoot -Filter 'PhaseA.*Tests.ps1' | Sort-Object Name)
$failures=@()
foreach($suite in $suites) {
 Write-Output ("RUN " + $suite.Name)
 & powershell.exe -NoProfile -NonInteractive -File $suite.FullName
 $code=$LASTEXITCODE
 Write-Output ("RESULT {0} exit={1}" -f $suite.Name,$code)
 if($code -ne 0){$failures+= $suite.Name}
}
Write-Output ("SUITES total={0} passed={1} failed={2}" -f $suites.Count,($suites.Count-$failures.Count),$failures.Count)
if($failures.Count){Write-Output ($failures -join ',');exit 1}
exit 0
