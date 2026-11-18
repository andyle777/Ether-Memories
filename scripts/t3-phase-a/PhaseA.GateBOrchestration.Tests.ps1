$ErrorActionPreference='Stop'
& dotnet run --project "$PSScriptRoot/gate-b-controller-tests/GateBOrchestration.Tests.csproj" --configuration Debug --nologo
if($LASTEXITCODE -ne 0){throw "ORCHESTRATION_TEST_FAILED exit=$LASTEXITCODE"}
