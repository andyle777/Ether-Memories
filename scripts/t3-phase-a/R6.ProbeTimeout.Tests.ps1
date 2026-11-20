$ErrorActionPreference='Stop'
$base=$PSScriptRoot;. (Join-Path $base 'PhaseA.DurableAdmission.ps1');. (Join-Path $base 'PhaseA.RestartProbeValidation.ps1')
$root=Join-Path $env:TEMP ('orion-r6-timeout-'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($root);$owner=Initialize-PhaseAAdmissionStore $root;Close-PhaseAAdmissionLease $owner
$fake=Join-Path $env:TEMP ('orion-r6-timeout-source-'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($fake)
Copy-Item -LiteralPath (Join-Path $base 'PhaseA.DurableAdmission.ps1') -Destination $fake
[IO.File]::WriteAllText((Join-Path $fake 'PhaseA.RestartProbe.ps1'),'Start-Sleep -Seconds 60')
$RootSource=$fake;$tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $base 'PhaseA.InitializationR5.Tests.ps1'),[ref]$tokens,[ref]$errors)
if($errors.Count){throw 'P10_PARSE_FAILED'}
$function=$ast.Find({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq 'RejectRestart'},$true)
if($null -eq $function){throw 'P10_NO_PROBE_FUNCTION'}
. ([scriptblock]::Create($function.Extent.Text))
$timeout=$false;try{$null=RejectRestart $root}catch{$timeout=$_.Exception.GetBaseException().Message -ceq 'PROBE_TIMEOUT'}
if(-not $timeout){throw 'P10_TIMEOUT_NOT_REJECTED'}
'PASS P10 subprocess timeout rejected and termination confirmed'
