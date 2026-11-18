Set-StrictMode -Version Latest
. "$PSScriptRoot/PhaseA.ReadPipeNative.ps1"
. "$PSScriptRoot/PhaseA.ReadPipeReceipt.ps1"
function Confirm-PhaseAReadChildTermination($Child) {
 try { if(-not $Child.Wait(5000)){$Child.Terminate();if(-not $Child.Wait(5000)){throw 'unconfirmed'}} }
 catch {throw 'STAGE2_CHILD_UNCONFIRMED'}
}
function New-PhaseAWitnessIoOwner($Pipe,[byte[]]$Buffer,[string]$Attempt,[string]$Experiment='') {
 if($null -eq $Pipe -or $null -eq $Buffer -or $Attempt -cnotmatch '^[0-9a-f]{32}$' -or ($Experiment -cne '' -and $Experiment -cnotmatch '^[0-9a-f]{32}$')){throw 'WITNESS_IO_OWNER_REJECTED'}
 $domain=[AppDomain]::CurrentDomain;$key='EtherPhaseAWitnessIoOwners';$owners=$domain.GetData($key)
 if($null -eq $owners){$owners=New-Object 'System.Collections.Generic.List[object]';$domain.SetData($key,$owners)}
 if($owners -isnot [Collections.Generic.List[object]] -or $owners.Count -ge 16){throw 'WITNESS_IO_OWNER_UNAVAILABLE'}
 $owner=@{pipe=$Pipe;buffer=$Buffer;attempt=$Attempt;experiment=$Experiment;managerPid=$PID;connection=@{state='NOT_ISSUED';result=$null};read=@{state='NOT_ISSUED';result=$null}}
 $owners.Add($owner);return $owner
}
function Invoke-PhaseAWitnessIoIssue($Owner,[ValidateSet('connection','read')][string]$Operation,[scriptblock]$Issue) {
 $owners=[AppDomain]::CurrentDomain.GetData('EtherPhaseAWitnessIoOwners')
 if($owners -isnot [Collections.Generic.List[object]] -or -not $owners.Contains($Owner)){throw 'WITNESS_IO_OWNER_REJECTED'}
 if($Owner[$Operation].state -cne 'NOT_ISSUED'){throw 'WITNESS_IO_ALREADY_ISSUED'}
 $Owner[$Operation].state='ISSUING'
 try{$result=& $Issue;if($null -eq $result){throw 'no async result'};$Owner[$Operation].result=$result;$Owner[$Operation].state='ISSUED';return $result}
 catch {$Owner[$Operation].state='ISSUE_UNCONFIRMED';throw}
}
function Remove-PhaseAWitnessIoOwner($Owner) {
 $owners=[AppDomain]::CurrentDomain.GetData('EtherPhaseAWitnessIoOwners')
 if($owners -isnot [Collections.Generic.List[object]] -or -not $owners.Contains($Owner)){throw 'WITNESS_IO_OWNER_REJECTED'}
 foreach($key in @('connection','read')){if($Owner[$key].state -cnotin @('NOT_ISSUED','COMPLETED')){throw 'WITNESS_IO_STILL_PENDING'}}
 if(-not $owners.Remove($Owner)){throw 'WITNESS_IO_OWNER_REJECTED'}
}
function Get-PhaseAWitnessCompletionError($ErrorRecord) {
 $e=$ErrorRecord.Exception
 while($null -ne $e){if($e -is [OperationCanceledException] -or ($e.HResult -band 65535) -eq 995){return 'CANCELED'};$e=$e.InnerException}
 return 'ERROR'
}
function Complete-PhaseAWitnessPipeCleanup($Pipe,$Pending,$Read,$PendingWait,$ReadWait,[bool]$ConnectionEnded,[bool]$ReadEnded,[hashtable]$Record,[hashtable]$Io=@{}) {
 if($Io.Count -eq 0){$Io=@{Cancel={param($p) [PhaseAReadPipeNative]::CancelPending($p.SafePipeHandle)};Wait={param($w) $w.WaitOne(5000)};EndConnection={param($p,$a) try{$p.EndWaitForConnection($a);return 'ENDED'}catch{return (Get-PhaseAWitnessCompletionError $_)}};EndRead={param($p,$a) try{$null=$p.EndRead($a);return 'ENDED'}catch{return (Get-PhaseAWitnessCompletionError $_)}};DisposeWait={param($w) $w.Dispose()};DisposePipe={param($p) $p.Dispose()}}}
 $Record.pipeCancel='NOT_ATTEMPTED';$Record.connectionEnd=if($ConnectionEnded){'ENDED'}else{'NOT_ATTEMPTED'};$Record.readEnd=if($ReadEnded){'ENDED'}else{'NOT_ATTEMPTED'}
 $ok=$true;$complete=$true
 if($null -eq $Pipe){return ($null -eq $Pending -and $null -eq $Read)}
 if(($Pending -and -not $ConnectionEnded) -or ($Read -and -not $ReadEnded)){
  try{$Record.pipeCancel=& $Io.Cancel $Pipe;if($Record.pipeCancel -cnotin @('REQUESTED','NOT_FOUND')){throw 'cancel result'}}catch{$Record.pipeCancel='FAILED';$ok=$false}
 }
 foreach($item in @(@('connectionWaitCleanup','connectionEnd',$Pending,$PendingWait,$ConnectionEnded),@('readWaitCleanup','readEnd',$Read,$ReadWait,$ReadEnded))){
  $waitField=$item[0];$endField=$item[1];$async=$item[2];$wait=$item[3];$ended=$item[4]
  if($null -eq $async){continue}
  if($ended){try{if($wait){$null=& $Io.DisposeWait $wait};$Record[$waitField]='DISPOSE_RETURNED'}catch [ObjectDisposedException] {$Record[$waitField]='FAILED';$ok=$false}catch{$Record[$waitField]='FAILED';$ok=$false};continue}
  if($null -eq $wait){$Record[$waitField]='UNCONFIRMED';$complete=$false;$ok=$false;continue}
  try{$signaled=& $Io.Wait $wait;if($signaled -isnot [bool] -or -not $signaled){$Record[$waitField]='UNCONFIRMED';$complete=$false;$ok=$false;continue}}catch{$Record[$waitField]='UNCONFIRMED';$complete=$false;$ok=$false;continue}
  try{$end=if($endField -ceq 'connectionEnd'){& $Io.EndConnection $Pipe $async}else{& $Io.EndRead $Pipe $async};if($end -cnotin @('ENDED','CANCELED','ERROR')){throw 'end result'};$Record[$endField]=$end;if($end -ceq 'ERROR'){$complete=$false;$ok=$false;continue}}catch{$Record[$endField]='FAILED';$complete=$false;$ok=$false;continue}
  try{$null=& $Io.DisposeWait $wait;$Record[$waitField]='SIGNALED_DISPOSE_RETURNED'}catch [ObjectDisposedException] {$Record[$waitField]='FAILED';$ok=$false}catch{$Record[$waitField]='FAILED';$ok=$false}
 }
 if($complete){try{$null=& $Io.DisposePipe $Pipe;$Record.pipeDispose='DISPOSE_RETURNED'}catch{$Record.pipeDispose='FAILED';$ok=$false}}else{$Record.pipeDispose='RETAINED'}
 return $ok
}
function Complete-PhaseAWitnessTokenReference($Handle,[bool]$ReferenceHeld,[bool]$Retain,[hashtable]$Record,[scriptblock]$Release={param($h) $h.DangerousRelease()}) {
 if(-not $ReferenceHeld){return 'NOT_HELD'}
 if($Retain){$Record.tokenReferenceRelease='RETAINED';return 'RETAINED'}
 try{$null=& $Release $Handle;$Record.tokenReferenceRelease='RELEASE_RETURNED';return 'RELEASED'}catch{$Record.tokenReferenceRelease='FAILED';return 'RELEASE_FAILED'}
}
function Invoke-PhaseAReadPipeProcessCore($Token,[string]$ExpectedSid,[string]$Target,[string]$TargetId,[string]$FixtureRoot,[bool]$TestCurrentIdentity=$false,[bool]$TestStall=$false,[string]$Operation='Read',[hashtable]$LifecycleRecord=@{}) {
 if((Get-Variable -Name PhaseAUnconfirmedWitnessResources -Scope Script -ErrorAction SilentlyContinue) -and $null -ne $script:PhaseAUnconfirmedWitnessResources){throw 'WITNESS_CLEANUP_FAILED'}
 if($TestStall -and -not $TestCurrentIdentity){throw 'WITNESS_ARGUMENT_REJECTED'}
 $source=Join-Path $PSScriptRoot 'PhaseA.ReadPipeWitness.cs'
 $pin='c3adbdddada140db59b8a8283ec21ecbc60226ff50e6bf8520e9c30f03eded41'
 $sourceText=[IO.File]::ReadAllText($source).Replace("`r`n","`n")
 $sourceSha=[Security.Cryptography.SHA256]::Create();try{$sourceHash=[BitConverter]::ToString($sourceSha.ComputeHash([Text.Encoding]::UTF8.GetBytes($sourceText))).Replace('-','').ToLowerInvariant()}finally{$sourceSha.Dispose()}
 if($sourceHash -cne $pin){throw 'WITNESS_SOURCE_MISMATCH'}
 if((($Operation -cin @('Read','Overwrite') -and $TargetId -cnotin @('protectedFile','controlFile')) -or ($Operation -ceq 'Create' -and $TargetId -cnotin @('deniedFile','authorizedProbeFile','controlProbeFile')) -or $Operation -cnotin @('Read','Overwrite','Create')) -or [string]::IsNullOrWhiteSpace($ExpectedSid)){throw 'WITNESS_ARGUMENT_REJECTED'}
 if(-not $TestCurrentIdentity) {
  $root=[IO.Path]::GetFullPath($FixtureRoot);$dir=if($TargetId -cin @('controlFile','controlProbeFile')){'control'}else{'protected'};$filename=switch($TargetId){'protectedFile' {'original.bin'} 'controlFile' {'original.bin'} 'deniedFile' {'rejected.bin'} 'authorizedProbeFile' {'witness-authorized.bin'} 'controlProbeFile' {'witness-permissive.bin'}}
  if(-not [IO.Path]::GetFileName($root).StartsWith('ether-phase-a-store-') -or [IO.Path]::GetFullPath($Target) -cne [IO.Path]::Combine($root,$dir,$filename)){throw 'WITNESS_ARGUMENT_REJECTED'}
  if($Token.sid -cne $ExpectedSid -or $Token.handle.IsClosed -or $Token.handle.IsInvalid){throw 'WITNESS_IDENTITY_REJECTED'}
 }
 $LifecycleRecord.source=if($TestCurrentIdentity){'CURRENT_IDENTITY'}else{'NOT_VERIFIED'};$LifecycleRecord.operation=$Operation;$LifecycleRecord.target=$TargetId;$LifecycleRecord.attempt=[Guid]::NewGuid().ToString('N');$LifecycleRecord.expectedSid=$ExpectedSid;$LifecycleRecord.launch='NOT_ATTEMPTED';$LifecycleRecord.jobCreate='NOT_ATTEMPTED';$LifecycleRecord.jobClose='NOT_ATTEMPTED';$LifecycleRecord.jobCloseError='NONE';$LifecycleRecord.containment='NOT_OBSERVED';$LifecycleRecord.jobLimits=$null;$LifecycleRecord.child=$null;$LifecycleRecord.tokenInspectionClose='NOT_ATTEMPTED';$LifecycleRecord.inspectionDispose='NOT_ATTEMPTED';$LifecycleRecord.inspectionDisposeError='NONE';$LifecycleRecord.pipeDispose='NOT_ATTEMPTED';$LifecycleRecord.connectionWaitCleanup='NOT_ATTEMPTED';$LifecycleRecord.readWaitCleanup='NOT_ATTEMPTED';$LifecycleRecord.tokenReferenceRelease='NOT_ATTEMPTED';$LifecycleRecord.binaryDispose='NOT_ATTEMPTED';$LifecycleRecord.scratchCleanup='NOT_ATTEMPTED';$LifecycleRecord.operationFailure='NONE';$LifecycleRecord.operationError='NONE';$LifecycleRecord.cleanupDependency='NOT_OBSERVED'
 if(-not $TestCurrentIdentity){
  if(-not (Get-Variable -Name PhaseATokenOwners -Scope Script -ErrorAction SilentlyContinue) -or -not $script:PhaseATokenOwners.ContainsKey($Token)){throw 'WITNESS_IDENTITY_REJECTED'}
  $owner=$script:PhaseATokenOwners[$Token];if(-not $script:PhaseATrustedTokenRecords.Contains($owner) -or $owner.source -cne 'LIVE' -or $owner.accountSid -cne $ExpectedSid -or $owner.role -cnotin @('broker','legacy') -or $script:PhaseAActorExperimentId -cnotmatch '^[0-9a-f]{32}$'){throw 'WITNESS_IDENTITY_REJECTED'};$LifecycleRecord.experiment=$script:PhaseAActorExperimentId
  $LifecycleRecord.source='LIVE';$LifecycleRecord.role=$owner.role
  if(-not $owner.ContainsKey('witnessLifecycle')){$owner.witnessLifecycle=New-Object 'System.Collections.Generic.List[object]'}
  $owner.witnessLifecycle.Add($LifecycleRecord)
 }else{$LifecycleRecord.role='CURRENT_IDENTITY'}
 $common=if($TestCurrentIdentity){[IO.Path]::GetTempPath()}else{[Environment]::GetFolderPath([Environment+SpecialFolder]::CommonApplicationData)}
 $parent=[IO.Path]::GetFullPath($common).TrimEnd('\');$scratch=Join-Path $parent ('ether-phase-a-read-'+[Guid]::NewGuid().ToString('N'))
 $exe=Join-Path $scratch 'witness.exe';$pipe=$null;$pipeOwner=$null;$pending=$null;$read=$null;$buffer=$null;$pendingWait=$null;$readWait=$null;$connectionEnded=$false;$readEnded=$false;$connectionEndResult='NOT_ATTEMPTED';$readEndResult='NOT_ATTEMPTED';$job=[IntPtr]::Zero;$child=$null;$process=$null;$held=$null;$unconfirmed=$false;$cleanupFailed=$false;$created=$false;$tokenRef=$false;$launchHandle=$null
 try {
  [IO.Directory]::CreateDirectory($scratch)|Out-Null;$created=$true
  if(((Get-Item -LiteralPath $scratch -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw 'WITNESS_SETUP_FAILED'}
  if(-not $TestCurrentIdentity){$manager=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value;$null=Set-PhaseAFixtureAcl $scratch @($manager,'S-1-5-18') @($ExpectedSid)}
  Add-Type -TypeDefinition $sourceText -OutputAssembly $exe -OutputType ConsoleApplication -ErrorAction Stop
  $hash=(Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash;$held=[IO.File]::Open($exe,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
  if((Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash -cne $hash){throw 'WITNESS_BINARY_MISMATCH'}
  $id=[Guid]::NewGuid().ToString('N');$nonce=[Guid]::NewGuid().ToString('N');$name='ether-phase-a-read-'+$id
  $acl=New-Object IO.Pipes.PipeSecurity;$acl.SetAccessRuleProtection($true,$false);$network=New-Object Security.Principal.SecurityIdentifier('S-1-5-2');$deny=New-Object IO.Pipes.PipeAccessRule($network,[IO.Pipes.PipeAccessRights]::FullControl,[Security.AccessControl.AccessControlType]::Deny);$acl.AddAccessRule($deny);$managerSid=[Security.Principal.WindowsIdentity]::GetCurrent().User
  $managerRule=New-Object IO.Pipes.PipeAccessRule($managerSid,[IO.Pipes.PipeAccessRights]::FullControl,[Security.AccessControl.AccessControlType]::Allow);$acl.AddAccessRule($managerRule)
  if($ExpectedSid -cne $managerSid.Value){$sid=New-Object Security.Principal.SecurityIdentifier($ExpectedSid);$rule=New-Object IO.Pipes.PipeAccessRule($sid,[IO.Pipes.PipeAccessRights]::Write,[Security.AccessControl.AccessControlType]::Allow);$acl.AddAccessRule($rule)}
  $pipe=New-Object IO.Pipes.NamedPipeServerStream($name,[IO.Pipes.PipeDirection]::In,1,[IO.Pipes.PipeTransmissionMode]::Byte,[IO.Pipes.PipeOptions]::Asynchronous,4096,4096,$acl)
  $buffer=New-Object byte[] 4096;$experiment=if($LifecycleRecord.ContainsKey('experiment')){$LifecycleRecord.experiment}else{''};$pipeOwner=New-PhaseAWitnessIoOwner $pipe $buffer $LifecycleRecord.attempt $experiment
  $pending=Invoke-PhaseAWitnessIoIssue $pipeOwner 'connection' { $pipe.BeginWaitForConnection($null,$null) };$pendingWait=$pending.AsyncWaitHandle
  if($exe.Contains('"') -or $Target.Contains('"')){throw 'WITNESS_ARGUMENT_REJECTED'}
  $mode=switch($Operation){'Read'{'read'} 'Overwrite'{'write'} 'Create'{'create'}};if($TestStall){$mode='stall-'+$mode}; $cmd='"'+$exe+'" '+$mode+' "'+$Target+'" '+$name+' '+$nonce+' '+$TargetId
  $LifecycleRecord.jobCreate='ATTEMPTED';$job=[EtherPhaseAJob]::Create();$LifecycleRecord.jobCreate='CREATED';$LifecycleRecord.jobLimits=[EtherPhaseAJob]::QueryLimitFlags($job);if(($LifecycleRecord.jobLimits -band 0x2000) -eq 0){throw 'WITNESS_CONTAINMENT_FAILED'}
  if($TestCurrentIdentity){$LifecycleRecord.launch='ATTEMPTED';$child=[EtherPhaseAAtomic]::CreateSelfInDirectory($job,$exe,$cmd,$scratch)}else{
   $launchHandle=$Token.handle;$launchHandle.DangerousAddRef([ref]$tokenRef);$stats=[EtherPhaseANative]::InspectTokenHandle($launchHandle.DangerousGetHandle());$account=@{role=$owner.role;sid=$ExpectedSid}
   if(-not (Test-PhaseAOwnedLaunchToken $owner $account $stats)){throw 'WITNESS_IDENTITY_REJECTED'}
   $LifecycleRecord.launchTokenId=$stats.tokenId;$LifecycleRecord.launchAuthenticationId=$stats.authenticationId;$LifecycleRecord.launchModifiedId=$stats.modifiedId
   $LifecycleRecord.launch='ATTEMPTED'
   $child=[EtherPhaseAAtomic]::CreateWithTokenInDirectory($launchHandle.DangerousGetHandle(),$job,$exe,$cmd,$scratch)
  }
  $LifecycleRecord.launch='CREATED';$LifecycleRecord.pid=[int]$child.Pid
  if(-not $child.InJob() -or $child.Exited()){$LifecycleRecord.containment='REJECTED';throw 'WITNESS_CONTAINMENT_FAILED'}
  $LifecycleRecord.containment='MEMBER'
  $process=Get-Process -Id $child.Pid -ErrorAction Stop;$LifecycleRecord.launchCreatedAt=$process.StartTime.ToUniversalTime().ToString('o')
  $LifecycleRecord.tokenInspectionClose='UNKNOWN'
  try{$observed=Get-PhaseAProcessToken $process $true;$LifecycleRecord.tokenInspectionClose='CLOSED'}catch{if($_.Exception.GetBaseException().Message -ceq 'TOKEN_INSPECTION_CLOSE_FAILED'){$LifecycleRecord.tokenInspectionClose='FAILED';$cleanupFailed=$true};throw}
  $LifecycleRecord.observedPid=$observed.pid;$LifecycleRecord.observedSid=$observed.sid;$LifecycleRecord.createdAt=$observed.createdAt;$LifecycleRecord.observedAuthenticationId=$observed.authenticationId;$LifecycleRecord.observedPrimary=$observed.primary
  if($observed.pid -ne $child.Pid -or $observed.sid -cne $ExpectedSid -or $observed.createdAt -cne $LifecycleRecord.launchCreatedAt){throw 'WITNESS_IDENTITY_REJECTED'}
  if(-not $TestCurrentIdentity){$post=[EtherPhaseANative]::InspectTokenHandle($launchHandle.DangerousGetHandle());foreach($key in @('tokenId','authenticationId','modifiedId')){if($post.$key -cne $stats.$key){throw 'WITNESS_IDENTITY_REJECTED'}};if(-not $observed.primary -or $observed.authenticationId -cne $stats.authenticationId){throw 'WITNESS_IDENTITY_REJECTED'}}
  $clock=[Diagnostics.Stopwatch]::StartNew();$child.Resume()
  if(-not $pendingWait.WaitOne(8000)){throw 'WITNESS_TIMEOUT'}
  $connectionEnded=$true;try{$pipe.EndWaitForConnection($pending);$connectionEndResult='ENDED'}catch{$connectionEndResult='ENDED_WITH_ERROR';throw};$clientPid=[PhaseAReadPipeNative]::ClientPid($pipe.SafePipeHandle)
  if($clientPid -ne $child.Pid){throw 'WITNESS_CLIENT_REJECTED'}
  $read=Invoke-PhaseAWitnessIoIssue $pipeOwner 'read' { $pipe.BeginRead($buffer,0,$buffer.Length,$null,$null) };$readWait=$read.AsyncWaitHandle
  $remaining=[Math]::Max(0,10000-[int]$clock.ElapsedMilliseconds)
  if(-not $readWait.WaitOne($remaining)){throw 'WITNESS_TIMEOUT'}
  $readEnded=$true;try{$count=$pipe.EndRead($read);$readEndResult='ENDED'}catch{$readEndResult='ENDED_WITH_ERROR';throw};$parts=[Text.Encoding]::UTF8.GetString($buffer,0,$count).Split('|')
  $remaining=[Math]::Max(0,10000-[int]$clock.ElapsedMilliseconds)
  if(-not $child.Wait([uint32]$remaining)){throw 'WITNESS_TIMEOUT'}
  if($child.ExitCode() -ne 0 -or -not (Test-PhaseAReadPipeReceipt $parts $nonce $child.Pid $clientPid $ExpectedSid $observed.createdAt $TargetId ($clock.ElapsedMilliseconds -le 10000) $Operation)){throw 'WITNESS_RECEIPT_REJECTED'}
  if((Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash -cne $hash){throw 'WITNESS_BINARY_MISMATCH'}
  $LifecycleRecord.witnessOutcome=@{operation=$Operation;target=$TargetId;allowed=($parts[6] -ceq 'ALLOWED');nativeError=[int]$parts[7];pid=[int]$child.Pid;createdAt=$observed.createdAt;pipeClientPid=[int]$clientPid;nonce=$nonce;source=$LifecycleRecord.source}
  return @{execution='PROCESS';sid=$observed.sid;operation=$Operation;attempted=$true;allowed=($parts[6] -ceq 'ALLOWED');error=[int]$parts[7];processVerified=$true;terminated=$true;handlesClosed=$true;pid=$child.Pid;createdAt=$observed.createdAt;pipeClientPid=[int]$clientPid;nonce=$nonce}
 } catch {$LifecycleRecord.operationError=Get-PhaseAActorErrorCategory $_;$failure=$_.Exception.GetBaseException().Message;$LifecycleRecord.operationFailure=if($failure -cin @('WITNESS_TIMEOUT','WITNESS_IDENTITY_REJECTED','WITNESS_CONTAINMENT_FAILED','WITNESS_RECEIPT_REJECTED','WITNESS_CLIENT_REJECTED')){$failure}else{'WITNESS_OPERATION_FAILED'};if($LifecycleRecord.launch -ceq 'ATTEMPTED'){$LifecycleRecord.launch='FAILED'};if($LifecycleRecord.jobCreate -ceq 'ATTEMPTED'){$LifecycleRecord.jobCreate='FAILED'};throw} finally {
  $pipeSafe=$false
  if($pipeOwner -and ($pipeOwner.connection.state -ceq 'ISSUE_UNCONFIRMED' -or $pipeOwner.read.state -ceq 'ISSUE_UNCONFIRMED')){$LifecycleRecord.pipeDispose='RETAINED';$cleanupFailed=$true}
  else {try{$pipeSafe=Complete-PhaseAWitnessPipeCleanup $pipe $pending $read $pendingWait $readWait $connectionEnded $readEnded $LifecycleRecord}catch{$pipeSafe=$false;$LifecycleRecord.pipeCleanupError=Get-PhaseAActorErrorCategory $_};if(-not $pipeSafe){$cleanupFailed=$true}}
  if($pipeOwner -and $pipeSafe){try{foreach($key in @('connection','read')){if($pipeOwner[$key].state -ceq 'ISSUED'){$pipeOwner[$key].state='COMPLETED'}};Remove-PhaseAWitnessIoOwner $pipeOwner;$LifecycleRecord.pipeRetention='RELEASED'}catch{$cleanupFailed=$true;$LifecycleRecord.pipeRetention='FAILED'}}
  elseif($pipeOwner){$LifecycleRecord.pipeRetention='PROCESS_LIFETIME'}
  if($connectionEnded){$LifecycleRecord.connectionEnd=$connectionEndResult};if($readEnded){$LifecycleRecord.readEnd=$readEndResult}
  if($job -ne [IntPtr]::Zero){try{if(-not (Invoke-PhaseAActorJobClose $job $LifecycleRecord)){$cleanupFailed=$true}}catch{$LifecycleRecord.jobClose='UNKNOWN';$LifecycleRecord.jobCloseError=Get-PhaseAActorErrorCategory $_;$cleanupFailed=$true}}
  if($child){$LifecycleRecord.child=@{};try{$childResult=Invoke-PhaseAActorChildCleanup $child $LifecycleRecord.child;$unconfirmed= -not $childResult.confirmed;if($childResult.cleanupFailed){$cleanupFailed=$true}}catch{$LifecycleRecord.child.error=Get-PhaseAActorErrorCategory $_;$unconfirmed=$true;$cleanupFailed=$true}}
  if($process){try{$process.Dispose();$LifecycleRecord.inspectionDispose='DISPOSE_RETURNED'}catch{$cleanupFailed=$true;$LifecycleRecord.inspectionDispose='FAILED';$LifecycleRecord.inspectionDisposeError=Get-PhaseAActorErrorCategory $_}}

  if($held -and -not $unconfirmed -and -not $cleanupFailed){try{$held.Dispose();$LifecycleRecord.binaryDispose='DISPOSE_RETURNED'}catch{$LifecycleRecord.binaryDispose='FAILED';$cleanupFailed=$true}}
  if(-not $unconfirmed -and -not $cleanupFailed -and $created){try{if(-not [IO.Path]::GetFullPath($scratch).StartsWith($parent+'\',[StringComparison]::OrdinalIgnoreCase) -or -not [IO.Path]::GetFileName($scratch).StartsWith('ether-phase-a-read-')){throw 'path rejected'};if([IO.File]::Exists($exe)){[IO.File]::Delete($exe)};[IO.Directory]::Delete($scratch,$false);$LifecycleRecord.scratchCleanup='DELETE_RETURNED'}catch{$LifecycleRecord.scratchCleanup='FAILED';$cleanupFailed=$true}}
  $tokenDisposition=Complete-PhaseAWitnessTokenReference $launchHandle $tokenRef ($unconfirmed -or $cleanupFailed) $LifecycleRecord;if($tokenDisposition -ceq 'RELEASE_FAILED'){$cleanupFailed=$true}
  if($unconfirmed -or $cleanupFailed){$jobUncertain=if($LifecycleRecord.jobClose -cin @('FAILED','UNKNOWN')){$job}else{[IntPtr]::Zero};$script:PhaseAUnconfirmedWitnessResources=@{child=$child;binaryHandle=$held;scratch=$scratch;pipe=$pipe;connection=$pending;read=$read;tokenHandle=$launchHandle;tokenReference=$tokenDisposition;jobHandle=$jobUncertain;jobHandleState=$LifecycleRecord.jobClose}}
  $LifecycleRecord.cleanupDependency=if($unconfirmed -or $cleanupFailed){'RETAIN'}else{'RELEASE_ELIGIBLE'}
  if($unconfirmed){$e=New-Object InvalidOperationException('STAGE2_CHILD_UNCONFIRMED');if($LifecycleRecord.ContainsKey('witnessOutcome')){$e.Data['PhaseAWitnessOutcome']=$LifecycleRecord.witnessOutcome};throw $e}
  if($cleanupFailed){$e=New-Object InvalidOperationException('WITNESS_CLEANUP_FAILED');if($LifecycleRecord.ContainsKey('witnessOutcome')){$e.Data['PhaseAWitnessOutcome']=$LifecycleRecord.witnessOutcome};throw $e}
 }
}

function Invoke-PhaseAReadPipeProcess($Token,[string]$ExpectedSid,[string]$Target,[string]$TargetId,[string]$FixtureRoot,[bool]$TestCurrentIdentity=$false,[bool]$TestStall=$false,[string]$Operation='Read',[hashtable]$LifecycleRecord=@{}) {
 $domain=[AppDomain]::CurrentDomain;$key='EtherPhaseAWitnessResourceGate'
 [Threading.Monitor]::Enter($domain)
 try {if($null -ne $domain.GetData($key)){throw 'WITNESS_CLEANUP_FAILED'};$domain.SetData($key,@{state='IN_FLIGHT'})} finally {[Threading.Monitor]::Exit($domain)}
 try { Invoke-PhaseAReadPipeProcessCore $Token $ExpectedSid $Target $TargetId $FixtureRoot $TestCurrentIdentity $TestStall $Operation $LifecycleRecord }
 finally {
  $retained=$null
  if((Get-Variable -Name PhaseAUnconfirmedWitnessResources -Scope Script -ErrorAction SilentlyContinue) -and $null -ne $script:PhaseAUnconfirmedWitnessResources){$retained=$script:PhaseAUnconfirmedWitnessResources}
  $unsafe=($null -ne $retained) -or ($LifecycleRecord.ContainsKey('cleanupDependency') -and $LifecycleRecord.cleanupDependency -cne 'RELEASE_ELIGIBLE')
  [Threading.Monitor]::Enter($domain)
  try {if($unsafe){$domain.SetData($key,@{state='UNRESOLVED';resources=$retained;lifecycle=$LifecycleRecord})}else{$domain.SetData($key,$null)}} finally {[Threading.Monitor]::Exit($domain)}
 }
}