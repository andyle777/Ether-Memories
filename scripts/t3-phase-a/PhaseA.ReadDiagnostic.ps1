function Get-PhaseAStallDiagnostic([bool]$Returned,$ErrorRecord,[hashtable]$Lifecycle) {
 $result=@{outcome='UNEXPECTED_FAILURE';nativeError=$null;exception=$null}
 if($null -ne $ErrorRecord){$result.exception=$ErrorRecord.Exception}
 $messages=New-Object 'System.Collections.Generic.List[string]'
 $node=if($null -ne $ErrorRecord){$ErrorRecord.Exception}else{$null}
 while($null -ne $node){
  if($messages.Count -ge 16){return $result}
  $messages.Add([string]$node.Message)
  if($node -is [ComponentModel.Win32Exception]){$result.nativeError=$node.NativeErrorCode}
  $node=$node.InnerException
 }
 if($messages.Contains('STAGE2_CHILD_UNCONFIRMED')){$result.outcome='CHILD_TERMINATION_UNCONFIRMED';return $result}
 if($messages.Contains('WITNESS_CLEANUP_FAILED') -or $messages.Contains('STAGE2_CLEANUP_FAILED')){$result.outcome='CLEANUP_FAILED';return $result}
 if($null -eq $Lifecycle){return $result}
 foreach($key in @('operationFailure','cleanupDependency','launch','jobClose','pipeRetention')){if($Lifecycle.ContainsKey($key) -and $Lifecycle[$key] -isnot [string]){return $result}}
 if($Lifecycle.ContainsKey('cleanupDependency') -and $Lifecycle.cleanupDependency -cnotin @('NOT_OBSERVED','RELEASE_ELIGIBLE','RETAIN')){return $result}
 if($Lifecycle.ContainsKey('jobClose') -and $Lifecycle.jobClose -cnotin @('NOT_ATTEMPTED','CLOSED','FAILED','UNKNOWN')){return $result}
 if($Lifecycle.ContainsKey('pipeRetention') -and $Lifecycle.pipeRetention -cnotin @('RELEASED','PROCESS_LIFETIME','FAILED')){return $result}
 if($Lifecycle.ContainsKey('child') -and $null -ne $Lifecycle.child -and $Lifecycle.child -isnot [hashtable]){return $result}
 $child=if($Lifecycle.ContainsKey('child') -and $Lifecycle.child -is [hashtable]){$Lifecycle.child}else{$null}
 if($messages.Contains('STAGE2_CHILD_UNCONFIRMED') -or ($child -and (($child.ContainsKey('exitState') -and $child.exitState -ceq 'ALIVE') -or ($child.ContainsKey('finalWait') -and $child.finalWait -cin @('TIMEOUT','FAILED','UNCONFIRMED'))))){$result.outcome='CHILD_TERMINATION_UNCONFIRMED';return $result}
 if($messages.Contains('WITNESS_CLEANUP_FAILED') -or $messages.Contains('STAGE2_CLEANUP_FAILED') -or ($Lifecycle.ContainsKey('cleanupDependency') -and $Lifecycle.cleanupDependency -ceq 'RETAIN') -or ($Lifecycle.ContainsKey('jobClose') -and $Lifecycle.jobClose -cin @('FAILED','UNKNOWN')) -or ($Lifecycle.ContainsKey('pipeRetention') -and $Lifecycle.pipeRetention -cin @('PROCESS_LIFETIME','FAILED')) -or ($child -and (($child.ContainsKey('processClose') -and $child.processClose -ceq 'FAILED') -or ($child.ContainsKey('threadClose') -and $child.threadClose -ceq 'FAILED')))){$result.outcome='CLEANUP_FAILED';return $result}
 if($Returned -and $null -ne $ErrorRecord){return $result}
 if($Returned){$result.outcome='STALL_ACCEPTED';return $result}
 if($null -eq $ErrorRecord){return $result}
 if($messages.Contains('WITNESS_TIMEOUT') -and $ErrorRecord.Exception.Message -cne 'WITNESS_TIMEOUT'){return $result}
 if($result.nativeError -in @(1260,4551)){if($Lifecycle.ContainsKey('operationFailure') -and $Lifecycle.operationFailure -cne 'WITNESS_OPERATION_FAILED'){return $result};$result.outcome='EXECUTION_POLICY_BLOCKED';return $result}
 if($messages.Contains('WITNESS_TIMEOUT')){
  foreach($message in $messages){if($message -cne 'WITNESS_TIMEOUT'){return $result}}
  foreach($key in @('operationFailure','cleanupDependency','launch','jobClose','pipeRetention')){if(-not $Lifecycle.ContainsKey($key) -or $Lifecycle[$key] -isnot [string]){return $result}}
  if(-not $child){return $result}
  foreach($key in @('finalWait','exitState','processClose','threadClose')){if(-not $child.ContainsKey($key) -or $child[$key] -isnot [string]){return $result}}
  if($Lifecycle.operationFailure -ceq 'WITNESS_TIMEOUT' -and $Lifecycle.cleanupDependency -ceq 'RELEASE_ELIGIBLE' -and $Lifecycle.launch -ceq 'CREATED' -and $Lifecycle.jobClose -ceq 'CLOSED' -and $Lifecycle.pipeRetention -ceq 'RELEASED' -and $child -and $child.finalWait -ceq 'SIGNALED' -and $child.exitState -ceq 'EXITED' -and $child.processClose -ceq 'CLOSED' -and $child.threadClose -ceq 'CLOSED'){$result.outcome='EXPECTED_TIMEOUT'}
  return $result
 }
 if($null -ne $result.nativeError -or @($messages | Where-Object {$_ -cin @('WITNESS_SETUP_FAILED','WITNESS_CONTAINMENT_FAILED','WITNESS_BINARY_MISMATCH','WITNESS_SOURCE_MISMATCH','WITNESS_ARGUMENT_REJECTED','WITNESS_IDENTITY_REJECTED')}).Count -gt 0){$result.outcome='LAUNCH_OR_SETUP_FAILED'}
 return $result
}