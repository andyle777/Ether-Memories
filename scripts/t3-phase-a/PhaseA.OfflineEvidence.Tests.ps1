$ErrorActionPreference='Stop'
$source=Join-Path $PSScriptRoot 'PhaseA.OfflineEvidence.cs'
if(-not (Test-Path -LiteralPath $source)){throw 'OFFLINE_EVIDENCE_BOUNDARY_MISSING'}
Add-Type -Path $source
function Check($condition,$name){if(-not $condition){throw $name}}
function MapFixture {$m=[Orion.OfflineEvidence.FixtureInput]::new();$m.Experiment='e';$m.ExpectedExperiment='e';$m.Target='protected';$m.ExpectedTarget='protected';$m.Volume=11;$m.ExpectedVolume=11;$m.FileId='abc';$m.ExpectedFileId='abc';$m.FileObject=10;$m.MappingCount=1;$m.StartTick=10;$m.EndTick=20;$m.OperationTick=15;return $m}
$m=MapFixture;$r=[Orion.OfflineEvidence.Verifier]::Fixture($m);Check ($r.Status -ceq 'UNVERIFIED' -and $r.Reason -ceq 'SYNTHETIC_MATCH_NOT_PROOF') 'SYNTHETIC_MAPPING_PROMOTED'
foreach($case in @(@('Volume',12,'VOLUME_MISMATCH'),@('FileId','bad','FILE_ID_MISMATCH'),@('Target','other','TARGET_MISMATCH'),@('Experiment','other','EXPERIMENT_MISMATCH'),@('FileObject',0,'FILE_OBJECT_MAPPING_MISSING'),@('MappingCount',2,'AMBIGUOUS_MAPPING'),@('Reparse',$true,'REPARSE_REJECTED'),@('Replaced',$true,'REPLACEMENT_DETECTED'),@('OperationTick',21,'TARGET_LIFETIME_MISMATCH'))){$m=MapFixture;$m.($case[0])=$case[1];$r=[Orion.OfflineEvidence.Verifier]::Fixture($m);Check ($r.Status -ceq 'UNVERIFIED' -and $r.Reason -ceq $case[2]) ('FIXTURE_'+$case[0]+'_'+$r.Reason)}
function TraceFixture {$x=[Orion.OfflineEvidence.TraceInput]::new();$x.ProviderExpected=$true;$x.SettingsMatch=$true;$x.Started=$true;$x.Stopped=$true;$x.Finalized=$true;$x.MetadataValid=$true;$x.LossKnown=$true;$x.CompletionPresent=$true;$x.WindowCovered=$true;return $x}
$x=TraceFixture;$r=[Orion.OfflineEvidence.Verifier]::Trace($x);Check ($r.Reason -ceq 'SYNTHETIC_MATCH_NOT_PROOF') 'TRACE_PROMOTED'
foreach($case in @(@('ProviderExpected',$false,'PROVIDER_MISMATCH'),@('SettingsMatch',$false,'SETTINGS_MISMATCH'),@('Started',$false,'START_MISSING'),@('Stopped',$false,'STOP_MISSING'),@('Finalized',$false,'FINALIZATION_MISSING'),@('MetadataValid',$false,'METADATA_INVALID'),@('LossKnown',$false,'LOSS_UNKNOWN'),@('EventsLost',1,'EVENT_LOSS'),@('BuffersLost',1,'BUFFER_LOSS'),@('CompletionPresent',$false,'COMPLETION_MISSING'),@('WindowCovered',$false,'WINDOW_UNCOVERED'),@('Contradictory',$true,'CONTRADICTION'),@('Replay',$true,'REPLAY_DETECTED'))){$x=TraceFixture;$x.($case[0])=$case[1];$r=[Orion.OfflineEvidence.Verifier]::Trace($x);Check ($r.Status -ceq 'UNVERIFIED' -and $r.Reason -ceq $case[2]) ('TRACE_'+$case[0]+'_'+$r.Reason)}
$x=TraceFixture;$r=[Orion.OfflineEvidence.Verifier]::Trace($x);$x.EventsLost=1;Check ($r.Reason -ceq 'SYNTHETIC_MATCH_NOT_PROOF') 'MUTABLE_VERDICT'
$r=[Orion.OfflineEvidence.Verifier]::Identity();Check ($r.Reason -ceq 'EFFECTIVE_IDENTITY_UNCORROBORATED') 'IDENTITY_PROMOTED'
Write-Output 'PASS offline fixture, completeness, immutable verdict and identity controls'
$props=New-Object 'System.Collections.Generic.Dictionary[string,byte[]]'
$props.Add('IrpPtr',[BitConverter]::GetBytes([UInt64]42));$props.Add('TTID',[BitConverter]::GetBytes([UInt32]9));$props.Add('FileObject',[BitConverter]::GetBytes([UInt64]10));$props.Add('IoSize',[BitConverter]::GetBytes([UInt32]2))
$props.Add('Offset',[BitConverter]::GetBytes([UInt64]0));$props.Add('FileKey',[BitConverter]::GetBytes([UInt64]11));$props.Add('IoFlags',[BitConverter]::GetBytes([UInt32]0))
$guid=[Guid]::Parse('90cbdc39-4a3e-11d1-84f4-0000f80464e3')
$r=[Orion.OfflineEvidence.Schema]::ReadRequest($guid,2,67,8,$props)
Check ($r.Reason -ceq 'SYNTHETIC_MATCH_NOT_PROOF' -and $r.RequestId -eq 42 -and $r.FileObject -eq 10 -and $r.RequestedBytes -eq 2) 'SCHEMA_READ_REJECTED'
$r=[Orion.OfflineEvidence.Schema]::ReadRequest([Guid]::Empty,2,67,8,$props);Check ($r.Reason -ceq 'PROVIDER_MISMATCH') 'WRONG_PROVIDER_ACCEPTED'
$r=[Orion.OfflineEvidence.Schema]::ReadRequest($guid,1,67,8,$props);Check ($r.Reason -ceq 'SCHEMA_UNSUPPORTED') 'WRONG_SCHEMA_ACCEPTED'
$r=[Orion.OfflineEvidence.Schema]::ReadRequest($guid,2,64,8,$props);Check ($r.Reason -ceq 'EVENT_MISMATCH') 'WRONG_EVENT_ACCEPTED'
$props['IrpPtr']=[byte[]](1,2);$r=[Orion.OfflineEvidence.Schema]::ReadRequest($guid,2,67,8,$props);Check ($r.Reason -ceq 'PROPERTY_INVALID') 'TRUNCATED_PROPERTY_ACCEPTED'
$props.Remove('IrpPtr')|Out-Null;$r=[Orion.OfflineEvidence.Schema]::ReadRequest($guid,2,67,8,$props);Check ($r.Reason -ceq 'PROPERTY_INVALID') 'MISSING_PROPERTY_ACCEPTED'
Write-Output 'PASS synthetic FileIo v2 property boundary rejects malformed fields'
