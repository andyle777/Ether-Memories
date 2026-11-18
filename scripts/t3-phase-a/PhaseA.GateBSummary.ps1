function ConvertTo-PhaseAGateBPublicSummary {
 param([Parameter(Mandatory=$true)][hashtable]$Record)
 $keys=@('sourceSha','controllerSha256','decoderSha256','experiment','requestedBytes','actualBytes','fixtureDigestMatch','stop','statisticsValid','eventsLost','logBuffersLost','realTimeBuffersLost','createPresent','readPresent','completionPresent')
 if(@($Record.Keys | Where-Object {$_ -cnotin $keys}).Count -ne 0 -or @($keys | Where-Object {-not $Record.ContainsKey($_)}).Count -ne 0){throw 'SUMMARY_SCHEMA_INVALID'}
 foreach($k in @('sourceSha','controllerSha256','decoderSha256','experiment')) { $n=if($k -ceq 'sourceSha'){40}elseif($k -ceq 'experiment'){32}else{64}; if($Record[$k] -isnot [string] -or $Record[$k] -cnotmatch ('^[a-f0-9]{'+$n+'}$')){throw 'SUMMARY_ID_INVALID'} }
 foreach($k in @('requestedBytes','actualBytes')){if($Record[$k] -isnot [int] -or $Record[$k] -lt 0 -or $Record[$k] -gt 65536){throw 'SUMMARY_COUNT_INVALID'}}
 foreach($k in @('fixtureDigestMatch','statisticsValid','createPresent','readPresent','completionPresent')){if($Record[$k] -isnot [bool]){throw 'SUMMARY_BOOLEAN_INVALID'}}
 if($Record.stop -cnotin @('SESSION_STOPPED','SESSION_ABSENT_CAUSE_UNKNOWN','STOP_IN_PROGRESS','STOP_UNCONFIRMED','NOT_OBSERVED')){throw 'SUMMARY_STOP_INVALID'}
 foreach($k in @('eventsLost','logBuffersLost','realTimeBuffersLost')) {if(-not $Record.statisticsValid){if($null -ne $Record[$k]){throw 'SUMMARY_UNKNOWN_LOSS'}} elseif($Record[$k] -isnot [uint32]){throw 'SUMMARY_LOSS_INVALID'}}
 $out=[ordered]@{};foreach($k in $keys){$out[$k]=$Record[$k]};$out.provenance='CAPTURED_UNTRUSTED';$out.securityStatus='UNVERIFIED';$out.correlation='UNVERIFIED';$out.limitations=@('RAW_TRACE_NOT_PUBLIC','EFFECTIVE_THREAD_IDENTITY_UNVERIFIED','NO_SECURITY_ACCEPTANCE')
 return ($out | ConvertTo-Json -Compress -Depth 4)
}
