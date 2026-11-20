function Test-PhaseARestartProbeResult([string]$Output,[int]$ExitCode,[string]$Nonce) {
 if($ExitCode -ne 0 -or $Nonce -cnotmatch '^[0-9a-f]{32}$' -or [string]::IsNullOrWhiteSpace($Output) -or $Output.Length -gt 4096){return $false}
 try{$value=ConvertFrom-Json -InputObject $Output -ErrorAction Stop}catch{return $false}
 if($null -eq $value -or $value -is [array]){return $false}
 $names=@('schemaVersion','probeNonce','outcome','reason','operationReached','leaseCount','callbackCount','observedError','claimRetained')
 $properties=@($value.PSObject.Properties.Name)
 if($properties.Count -ne $names.Count){return $false}
 foreach($name in $names){if($properties -cnotcontains $name){return $false}}
 if($value.schemaVersion -isnot [int] -or $value.schemaVersion -ne 1 -or $value.probeNonce -isnot [string] -or $value.probeNonce -cne $Nonce -or $value.outcome -cne 'DENIED' -or $value.reason -cne 'DOMAIN_ALREADY_CLAIMED' -or $value.operationReached -isnot [bool] -or -not $value.operationReached -or $value.claimRetained -isnot [bool] -or -not $value.claimRetained -or $value.leaseCount -isnot [int] -or $value.leaseCount -ne 0 -or $value.callbackCount -isnot [int] -or $value.callbackCount -ne 0 -or $value.observedError -cne '80070050'){return $false}
 return $true
}
function Test-PhaseAClaimCreatedProbeResult([string]$Output,[int]$ExitCode,[string]$Nonce) {
 if($ExitCode -ne 4 -or $Nonce -cnotmatch '^[0-9a-f]{32}$' -or [string]::IsNullOrWhiteSpace($Output) -or $Output.Length -gt 4096){return $false}
 try{$v=ConvertFrom-Json -InputObject $Output -ErrorAction Stop}catch{return $false}
 if($null -eq $v -or $v -is [array]){return $false}
 $names=@('schemaVersion','probeNonce','outcome','reason','operationReached','leaseCount','callbackCount','observedError','claimRetained');$props=@($v.PSObject.Properties.Name)
 if($props.Count -ne $names.Count){return $false};foreach($name in $names){if($props -cnotcontains $name){return $false}}
 return ($v.schemaVersion -is [int] -and $v.schemaVersion -eq 1 -and $v.probeNonce -is [string] -and $v.probeNonce -ceq $Nonce -and $v.outcome -ceq 'FAIL' -and $v.reason -ceq 'CLAIM_CREATED' -and $v.operationReached -is [bool] -and $v.operationReached -and $v.claimRetained -is [bool] -and $v.claimRetained -and $v.leaseCount -is [int] -and $v.leaseCount -eq 0 -and $v.callbackCount -is [int] -and $v.callbackCount -eq 0 -and $v.observedError -ceq 'NONE')
}
