$ErrorActionPreference='Stop'
. "$PSScriptRoot/PhaseA.Native.ps1"
. "$PSScriptRoot/PhaseA.Atomic.ps1"
Add-Type -TypeDefinition @'
using System;using System.ComponentModel;using System.Runtime.InteropServices;using System.Security.Principal;
public static class LineageProbe {
 [StructLayout(LayoutKind.Sequential)] public struct Luid { public uint Low; public int High; }
 [StructLayout(LayoutKind.Sequential)] public struct Statistics { public Luid TokenId, AuthenticationId;public long Expiration;public int Type,Impersonation;public uint Charged,Available,Groups,Privileges;public Luid ModifiedId; }
 [DllImport("kernel32.dll")] static extern IntPtr GetCurrentProcess();
 [DllImport("advapi32.dll",SetLastError=true)] static extern bool OpenProcessToken(IntPtr process,uint access,out IntPtr token);
 [DllImport("advapi32.dll",SetLastError=true)] static extern bool DuplicateTokenEx(IntPtr token,uint access,IntPtr attrs,int level,int type,out IntPtr result);
 [DllImport("advapi32.dll",SetLastError=true)] static extern bool GetTokenInformation(IntPtr token,int kind,out Statistics stats,int length,out int returned);
 [DllImport("kernel32.dll",SetLastError=true)] static extern bool CloseHandle(IntPtr h);
 static void Require(bool ok){if(!ok)throw new Win32Exception(Marshal.GetLastWin32Error());}
 public static IntPtr Current(){IntPtr t;Require(OpenProcessToken(GetCurrentProcess(),0xb,out t));return t;}
 public static IntPtr Duplicate(IntPtr t){IntPtr d;Require(DuplicateTokenEx(t,0x02000000,IntPtr.Zero,2,1,out d));return d;}
 public static IntPtr ProcessToken(IntPtr p){IntPtr t;Require(OpenProcessToken(p,8,out t));return t;}
 public static Statistics Read(IntPtr t){Statistics s;int n;Require(GetTokenInformation(t,10,out s,Marshal.SizeOf(typeof(Statistics)),out n));return s;}
 public static string Sid(IntPtr t){using(var id=new WindowsIdentity(t)){return id.User.Value;}}
 public static bool Equal(Luid a,Luid b){return a.Low==b.Low && a.High==b.High;}
 public static string Format(Luid v){return unchecked((uint)v.High).ToString("x8")+v.Low.ToString("x8");}
 public static void Close(IntPtr h){if(h!=IntPtr.Zero)Require(CloseHandle(h));}
}
'@
$original=[IntPtr]::Zero;$duplicate=[IntPtr]::Zero;$childToken=[IntPtr]::Zero;$job=[IntPtr]::Zero;$child=$null;$process=$null
try {
 $original=[LineageProbe]::Current();$duplicate=[LineageProbe]::Duplicate($original)
 $a=[LineageProbe]::Read($original);$b=[LineageProbe]::Read($duplicate)
 if([LineageProbe]::Sid($original) -cne [LineageProbe]::Sid($duplicate) -or [LineageProbe]::Equal($a.TokenId,$b.TokenId) -or -not [LineageProbe]::Equal($a.AuthenticationId,$b.AuthenticationId) -or $a.Type -ne 1 -or $b.Type -ne 1){throw 'SAME_IDENTITY_DUPLICATION_UNEXPECTED'}
 Write-Output ('SAME_IDENTITY duplicate_different_token_id=True shared_authentication_id=True original_primary=True duplicate_primary=True modified_id_equal='+[LineageProbe]::Equal($a.ModifiedId,$b.ModifiedId))
 $job=[EtherPhaseAJob]::Create();$exe=Join-Path $PSHOME 'powershell.exe';$command='"'+$exe+'" -NoProfile -NonInteractive -Command "exit 0"'
 $child=[EtherPhaseAAtomic]::CreateWithTokenInDirectory($duplicate,$job,$exe,$command,[IO.Path]::GetTempPath())
 if(-not $child.InJob() -or $child.Exited()){throw 'CHILD_CONTAINMENT_UNVERIFIED'}
 $process=Get-Process -Id $child.Pid -ErrorAction Stop;$created=$process.StartTime.ToUniversalTime();$childToken=[LineageProbe]::ProcessToken($process.Handle);$c=[LineageProbe]::Read($childToken);$managerObservation=Get-PhaseAProcessToken $process $true
 if([LineageProbe]::Sid($childToken) -cne [LineageProbe]::Sid($duplicate) -or $c.Type -ne 1){throw 'CHILD_IDENTITY_MISMATCH'}
 $expectedToken=[LineageProbe]::Format($c.TokenId);$expectedAuth=[LineageProbe]::Format($c.AuthenticationId)
 if($managerObservation.pid -ne $child.Pid -or -not $managerObservation.primary -or $managerObservation.tokenId -cne $expectedToken -or $managerObservation.authenticationId -cne $expectedAuth){throw 'MANAGER_PROCESS_TOKEN_QUERY_MISMATCH'}
 Write-Output ('SUSPENDED_CHILD contained=True process_id_positive='+($child.Pid -gt 0)+' creation_time_observed='+($created -ne [DateTime]::MinValue)+' child_primary=True token_id_matches_input='+[LineageProbe]::Equal($b.TokenId,$c.TokenId)+' authentication_id_matches_input='+[LineageProbe]::Equal($b.AuthenticationId,$c.AuthenticationId)+' modified_id_matches_input='+[LineageProbe]::Equal($b.ModifiedId,$c.ModifiedId))
 $child.Terminate();if(-not $child.Wait(5000)){throw 'CHILD_TERMINATION_UNCONFIRMED'};Write-Output 'PASS suspended child independently terminated'
} finally {
 if($childToken -ne [IntPtr]::Zero){[LineageProbe]::Close($childToken)}
 if($child){if(-not $child.Wait(0)){$child.Terminate();if(-not $child.Wait(5000)){throw 'CHILD_TERMINATION_UNCONFIRMED'}};$child.Dispose()}
 if($process){$process.Dispose()};if($job -ne [IntPtr]::Zero){[EtherPhaseAJob]::Close($job)}
 if($duplicate -ne [IntPtr]::Zero){[LineageProbe]::Close($duplicate)};if($original -ne [IntPtr]::Zero){[LineageProbe]::Close($original)}
}
