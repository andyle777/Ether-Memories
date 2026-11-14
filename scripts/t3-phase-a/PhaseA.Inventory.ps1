Set-StrictMode -Version Latest
# Returns only a digest; the raw names and security descriptors remain local.
# Reject reparse points before descending, so the traversal cannot intentionally
# leave the protected tree. This helper is not a substitute for an ACL audit.
function Get-PhaseAInventory([string]$Root, [switch]$Detailed) {
  $rootPath = [IO.Path]::GetFullPath($Root).TrimEnd([IO.Path]::DirectorySeparatorChar)
  if (-not [IO.Directory]::Exists($rootPath)) { throw 'Inventory root unavailable' }
  [long]$totalBytes=0
  $pending = New-Object 'System.Collections.Generic.Stack[string]'
  $records = New-Object 'System.Collections.Generic.List[string]'
  $pending.Push($rootPath)
  while ($pending.Count -gt 0) {
    $path = $pending.Pop()
    $item = Get-Item -LiteralPath $path -Force -ErrorAction Stop
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Inventory contains a reparse point' }
    $isDirectory = ($item.Attributes -band [IO.FileAttributes]::Directory) -ne 0
    $relative = if ($path -ceq $rootPath) { '.' } else { $path.Substring($rootPath.Length + 1).Replace('\','/') }
    if ($Detailed -and ($records.Count -ge 1024 -or $relative.Length -gt 512)) { throw 'Inventory limits exceeded' }
    $name = [Convert]::ToBase64String((New-Object Text.UTF8Encoding($false,$true)).GetBytes($relative))
    $sddl = (Get-Acl -LiteralPath $path -ErrorAction Stop).GetSecurityDescriptorSddlForm([Security.AccessControl.AccessControlSections]'Owner, Group, Access')
    if ($Detailed -and $sddl.Length -gt 8192) { throw 'Inventory limits exceeded' }
    $encodedAcl = [Convert]::ToBase64String((New-Object Text.UTF8Encoding($false,$true)).GetBytes($sddl))
    if ($isDirectory) {
      $records.Add("D|$name|$encodedAcl")
      foreach ($child in [IO.Directory]::EnumerateFileSystemEntries($path)) { if($Detailed -and ($pending.Count + $records.Count -ge 1024)){throw 'Inventory limits exceeded'}; $pending.Push($child) }
    } else {
      $stream = [IO.File]::Open($path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
      try {
        $size = $stream.Length
        if($Detailed){$totalBytes += $size;if($size -gt 8388608 -or $totalBytes -gt 8388608){throw 'Inventory byte limit exceeded'}}
        $sha = [Security.Cryptography.SHA256]::Create()
        try { $hash = [BitConverter]::ToString($sha.ComputeHash($stream)).Replace('-','').ToLowerInvariant() } finally { $sha.Dispose() }
      } finally { $stream.Dispose() }
      $records.Add("F|$name|$size|$hash|$encodedAcl")
    }
  }
  [string[]]$ordered = $records.ToArray()
  [Array]::Sort($ordered, [StringComparer]::Ordinal)
  $bytes = [Text.Encoding]::UTF8.GetBytes(($ordered -join "`n"))
  $sha = [Security.Cryptography.SHA256]::Create()
  try { $digest=[BitConverter]::ToString($sha.ComputeHash($bytes)).Replace('-','').ToLowerInvariant() } finally { $sha.Dispose() }
  if (-not $Detailed) { return $digest }
  $entries=New-Object 'System.Collections.Generic.List[object]'
  foreach($record in $ordered) {
    $parts=$record.Split('|'); $name=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($parts[1]))
    if($parts[0] -ceq 'D') {$entries.Add(@{name=$name;type='directory';descriptor=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($parts[2]))})}
    else {$entries.Add(@{name=$name;type='file';size=[long]$parts[2];sha256=$parts[3];descriptor=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($parts[4]))})}
  }
  return @{digest=$digest;entries=$entries.ToArray()}

}
function Get-PhaseAInventoryEntriesDigest($Entries) {
 try {
  if($Entries -isnot [array] -or $Entries.Count -lt 1 -or $Entries.Count -gt 1024){return $null}
  $records=New-Object 'System.Collections.Generic.List[string]';$names=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase);$dirs=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase);$hasRoot=$false;[long]$totalBytes=0
  foreach($e in $Entries) {
   if($e -isnot [hashtable] -or $e.name -isnot [string] -or $e.name.Length -gt 512 -or $e.name.Length -eq 0 -or $e.descriptor -isnot [string] -or $e.descriptor.Length -gt 8192 -or $e.descriptor.Length -eq 0 -or -not $names.Add($e.name)){return $null}
   if($e.name -cne '.' -and ($e.name.StartsWith('/') -or $e.name.Contains('\') -or $e.name.Contains(':') -or @($e.name.Split('/')|Where-Object {$_ -in @('','.','..')}).Count -gt 0)){return $null}
   $null=New-Object Security.AccessControl.RawSecurityDescriptor($e.descriptor)
   $name=[Convert]::ToBase64String((New-Object Text.UTF8Encoding($false,$true)).GetBytes($e.name));$acl=[Convert]::ToBase64String((New-Object Text.UTF8Encoding($false,$true)).GetBytes($e.descriptor))
   if($e.type -ceq 'directory' -and $e.Count -eq 3){if($e.name -ceq '.'){$hasRoot=$true};$null=$dirs.Add($e.name);$records.Add("D|$name|$acl")}
   elseif($e.type -ceq 'file' -and $e.Count -eq 5 -and $e.name -cne '.' -and $e.size -is [long] -and $e.size -ge 0 -and $e.sha256 -cmatch '^[0-9a-f]{64}$'){$totalBytes += $e.size;if($e.size -gt 8388608 -or $totalBytes -gt 8388608){return $null};$records.Add("F|$name|$($e.size)|$($e.sha256)|$acl")}
   else{return $null}
  }
  if(-not $hasRoot){return $null};foreach($entry in $Entries){if($entry.name -ceq '.'){continue};$cut=$entry.name.LastIndexOf('/');$parentName=if($cut -lt 0){'.'}else{$entry.name.Substring(0,$cut)};if(-not $dirs.Contains($parentName)){return $null}};[string[]]$ordered=$records.ToArray();[Array]::Sort($ordered,[StringComparer]::Ordinal);$bytes=[Text.Encoding]::UTF8.GetBytes(($ordered -join "`n"));$sha=[Security.Cryptography.SHA256]::Create()
  try{return [BitConverter]::ToString($sha.ComputeHash($bytes)).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose()}
 } catch {return $null}
}
