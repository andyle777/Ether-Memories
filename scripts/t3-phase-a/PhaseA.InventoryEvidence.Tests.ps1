$ErrorActionPreference='Stop'
. "$PSScriptRoot/PhaseA.Inventory.ps1"
$root=Join-Path ([IO.Path]::GetTempPath()) ('ether-inventory-test-'+[Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($root)|Out-Null;$file=Join-Path $root 'synthetic.bin';[IO.File]::WriteAllText($file,'synthetic')
try {
 $v=Get-PhaseAInventory $root -Detailed
 if($v -isnot [hashtable] -or $v.digest -cnotmatch '^[0-9a-f]{64}$' -or $v.entries.Count -ne 2){throw 'inventory details missing'}
 if($v.digest -cne (Get-PhaseAInventory $root)){throw 'inventory digest mismatch'}
 if((Get-PhaseAInventoryEntriesDigest $v.entries) -cne $v.digest){throw 'canonical reconstruction failed'}
 $forged=@($v.entries | ForEach-Object { $_.Clone() });$forged[0].name='../escape';if($null -ne (Get-PhaseAInventoryEntriesDigest $forged)){throw 'unsafe entry accepted'}
 [IO.File]::WriteAllText($file,'modified')
 if((Get-PhaseAInventory $root -Detailed).digest -ceq $v.digest){throw 'mutation was missed'}
 $base=Get-PhaseAInventory $root -Detailed;$extra=Join-Path $root 'extra.bin';[IO.File]::WriteAllText($extra,'x')
 if((Get-PhaseAInventory $root -Detailed).digest -ceq $base.digest){throw 'addition missed'};[IO.File]::Delete($extra)
 if((Get-PhaseAInventory $root -Detailed).digest -cne $base.digest){throw 'deletion not restored'}
 [IO.File]::Delete($file);if((Get-PhaseAInventory $root -Detailed).digest -ceq $base.digest){throw 'original file deletion missed'};[IO.File]::WriteAllText($file,'modified')
 $security=Get-Acl -LiteralPath $file;$security.SetAccessRuleProtection(-not $security.AreAccessRulesProtected,$true);Set-Acl -LiteralPath $file -AclObject $security
 if((Get-PhaseAInventory $root -Detailed).digest -ceq $base.digest){throw 'ACL change missed'}
 $oversize=Join-Path $root 'oversize.bin';$stream=[IO.File]::Create($oversize);try{$stream.SetLength(8388609)}finally{$stream.Dispose()};$tooLarge=$false;try{$null=Get-PhaseAInventory $root -Detailed}catch{$tooLarge=$true};[IO.File]::Delete($oversize);if(-not $tooLarge){throw 'oversized inventory accepted'}
 $missingRejected=$false;try{$null=Get-PhaseAInventory (Join-Path $root 'missing') -Detailed}catch{$missingRejected=$true};if(-not $missingRejected){throw 'missing root accepted'}
 $outside=Join-Path ([IO.Path]::GetTempPath()) ('ether-inventory-target-'+[Guid]::NewGuid().ToString('N'));[IO.Directory]::CreateDirectory($outside)|Out-Null;$junction=Join-Path $root 'junction'
 try {New-Item -ItemType Junction -Path $junction -Target $outside | Out-Null;$rejected=$false;try{$null=Get-PhaseAInventory $root -Detailed}catch{$rejected=$true};if(-not $rejected){throw 'reparse point accepted'}} finally {if([IO.Directory]::Exists($junction)){[IO.Directory]::Delete($junction,$false)};[IO.Directory]::Delete($outside,$false)}
 Write-Output 'PASS detailed inventory content, addition, deletion, ACL, missing root and reparse controls'
} finally {[IO.File]::Delete($file);[IO.Directory]::Delete($root,$false)}
