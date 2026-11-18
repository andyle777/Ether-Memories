$ErrorActionPreference='Stop'
$file=Join-Path $PSScriptRoot 'proposals/gate-b1.workflow.proposed.yml'
$s=Get-Content -LiteralPath $file -Raw
foreach($term in @('workflow_dispatch','windows-2025','timeout-minutes: 5','contents: read','persist-credentials: false','11bd71901bbe5b1630ceea73d27597364c9af683','ea165f8d65b6e75b540449e92b4886f43607fa02','if: ${{ false }}','--locked-mode','Capture, decode and validate','APPROVED_SUMMARY_ONLY','MISSING_RECEIPT','CANCELLED_UNVERIFIED')) {
 if(-not $s.Contains($term)){throw ('WORKFLOW_MISSING_'+$term)}
}
if($s -match '(?m)^\s*(pull_request|push):'){throw 'UNTRUSTED_WORKFLOW_TRIGGER'}
if($s -notmatch 'if-no-files-found:\s*error'){throw 'SUMMARY_ARTIFACT_NOT_REQUIRED'}
if(-not $s.Contains('-Recurse')){throw 'NESTED_NATIVE_DEPENDENCIES_NOT_CHECKED'}
if(-not $s.Contains('dotnet --version') -or -not $s.Contains('System.Web.Extensions')){throw 'ACTIVE_RUNTIME_NOT_CHECKED'}
$manifest=Get-Content -Raw (Join-Path $PSScriptRoot 'GATE-B-003-BUILD-HASHES.sha256')
foreach($name in @('amd64/KernelTraceControl.dll','amd64/msdia140.dll','arm64/KernelTraceControl.dll','arm64/msdia140.dll','x86/KernelTraceControl.dll','x86/KernelTraceControl.Win61.dll','x86/msdia140.dll')){if(-not $manifest.Contains($name)){throw ('MISSING_NATIVE_DEPENDENCY_'+$name)}}
if($s -match 'upload-artifact[^\r\n]*\n(?:[^\r\n]*\n){0,10}\s*path:\s*.*\.(etl|log)'){throw 'RAW_ARTIFACT_UPLOAD'}
Write-Output 'PASS disabled workflow trigger, pins, budgets and summary-only proposal controls'
