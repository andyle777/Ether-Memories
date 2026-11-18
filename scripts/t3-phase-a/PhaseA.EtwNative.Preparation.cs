// Declarations and injected correlation checks only. No ETW call path is exposed.
using System;
using System.Runtime.InteropServices;

namespace Orion.EtwPrepared {
  // Constructs EVENT_TRACE_PROPERTIES only. No ETW session is started here.
  // The FILE_IO and FILE_IO_INIT flags request operation ends and create/read
  // events; DISK_IO + DISK_FILE_IO request filename mappings.
  [StructLayout(LayoutKind.Sequential)]
  internal struct WnodeHeader {
    internal uint BufferSize,ProviderId;
    internal ulong HistoricalContext,TimeStamp;
    internal Guid Guid;
    internal uint ClientContext,Flags;
  }
  [StructLayout(LayoutKind.Sequential)]
  internal struct TraceProperties {
    internal WnodeHeader Wnode;
    internal uint BufferSize,MinimumBuffers,MaximumBuffers,MaximumFileSize,LogFileMode,FlushTimer,EnableFlags;
    internal int AgeLimit;
    internal uint NumberOfBuffers,FreeBuffers,EventsLost,BuffersWritten,LogBuffersLost,RealTimeBuffersLost;
    internal IntPtr LoggerThreadId;
    internal uint LogFileNameOffset,LoggerNameOffset;
  }
  public sealed class NativePropertiesBuffer : IDisposable {
    IntPtr pointer;
    public IntPtr Pointer {get{return pointer;}}
    public int StructBytes {get;private set;}
    public int TotalBytes {get;private set;}
    public Guid SessionId {get;private set;}
    public uint Mode {get{return 0x02000001;}} // SYSTEM_LOGGER | SEQUENTIAL
    public uint EnableFlags {get{return 0x06000303;}}
    public NativePropertiesBuffer(string name,Guid id,string path) {
      if(String.IsNullOrWhiteSpace(name) || name.Length>128 || name.IndexOf('\0')>=0 || id==Guid.Empty ||
         String.IsNullOrWhiteSpace(path) || path.Length>1024 || path.IndexOf('\0')>=0 || !System.IO.Path.IsPathRooted(path)) throw new ArgumentException("invalid trace configuration");
      StructBytes=Marshal.SizeOf(typeof(TraceProperties));
      byte[] n=System.Text.Encoding.Unicode.GetBytes(name+"\0"), f=System.Text.Encoding.Unicode.GetBytes(path+"\0");
      TotalBytes=checked(StructBytes+n.Length+f.Length); SessionId=id;
      pointer=Marshal.AllocHGlobal(TotalBytes);
      try {
        Marshal.Copy(new byte[TotalBytes],0,pointer,TotalBytes);
        TraceProperties p=new TraceProperties();p.Wnode.BufferSize=(uint)TotalBytes;p.Wnode.Guid=id;p.Wnode.ClientContext=1;p.Wnode.Flags=0x00020000;
        p.BufferSize=64;p.MinimumBuffers=4;p.MaximumBuffers=64;p.MaximumFileSize=64;p.LogFileMode=Mode;p.FlushTimer=1;p.EnableFlags=EnableFlags;
        p.LoggerNameOffset=(uint)StructBytes;p.LogFileNameOffset=(uint)(StructBytes+n.Length);
        Marshal.StructureToPtr(p,pointer,false);Marshal.Copy(n,0,IntPtr.Add(pointer,StructBytes),n.Length);Marshal.Copy(f,0,IntPtr.Add(pointer,StructBytes+n.Length),f.Length);
      } catch {Marshal.FreeHGlobal(pointer);pointer=IntPtr.Zero;throw;}
    }
    public void Dispose(){if(pointer!=IntPtr.Zero){Marshal.FreeHGlobal(pointer);pointer=IntPtr.Zero;}}
  }
  // TRACEHANDLE and CONTROLTRACE_ID are 64-bit on both Windows x86 and x64.
  // The pointers below require correctly allocated native structures; none are
  // constructed here. In particular, no name-only stop helper is provided.
  internal static class NativeDeclarations {
    [DllImport("advapi32.dll",CharSet=CharSet.Unicode,ExactSpelling=true)]
    internal static extern uint StartTraceW(out ulong controllerHandle,string sessionName,IntPtr properties);
    [DllImport("advapi32.dll",CharSet=CharSet.Unicode,ExactSpelling=true)]
    internal static extern uint ControlTraceW(ulong controllerHandle,string sessionName,IntPtr properties,uint controlCode);
    [DllImport("advapi32.dll",ExactSpelling=true)]
    internal static extern uint EnableTraceEx2(ulong controllerHandle,ref Guid providerId,uint controlCode,byte level,ulong matchAnyKeyword,ulong matchAllKeyword,uint timeout,IntPtr parameters);
    [DllImport("advapi32.dll",CharSet=CharSet.Unicode,ExactSpelling=true)]
    internal static extern ulong OpenTraceW(IntPtr logfile);
    [DllImport("advapi32.dll",ExactSpelling=true)]
    internal static extern uint ProcessTrace([In] ulong[] consumerHandles,uint handleCount,IntPtr startTime,IntPtr endTime);
    [DllImport("advapi32.dll",ExactSpelling=true)]
    internal static extern uint CloseTrace(ulong consumerHandle);
  }
  // Deliberately fixed fake: it cannot invoke native ETW or grant LIVE authority.
  public sealed class MockController {
    public uint StartCode, QueryCode, StopCode;
    public bool ReplaceSession;
    public int StopCalls;
    internal Guid Instance=Guid.NewGuid();
    internal ulong Handle=1;
    internal uint Start(){return StartCode;}
    internal Guid Query(){return ReplaceSession?Guid.NewGuid():Instance;}
    internal uint Stop(ulong handle){StopCalls++;return StopCode;}
  }
  public sealed class SessionLease {
    internal readonly MockController Owner;
    internal readonly Guid Instance;
    internal readonly ulong ControllerHandle;
    internal bool StopAttempted;
    internal SessionLease(MockController owner){Owner=owner;Instance=owner.Instance;ControllerHandle=owner.Handle;}
  }
  public sealed class ControllerResult {
    public string Reason;
    public uint NativeCode;
    public bool ResourceUnresolved;
    public SessionLease Lease;
  }
  public static class ControllerHarness {
    public static ControllerResult Start(MockController backend){
      if(backend==null)return new ControllerResult{Reason="INVALID_BACKEND"};
      uint code=backend.Start();
      if(code!=0)return new ControllerResult{Reason="START_FAILED",NativeCode=code};
      return new ControllerResult{Reason="SIMULATED_STARTED",Lease=new SessionLease(backend)};
    }
    public static ControllerResult Stop(MockController backend,SessionLease lease){
      if(backend==null || lease==null || !Object.ReferenceEquals(backend,lease.Owner) || lease.StopAttempted)
        return new ControllerResult{Reason="OWNERSHIP_UNCONFIRMED",ResourceUnresolved=true};
      if(backend.QueryCode!=0)return new ControllerResult{Reason="QUERY_FAILED",NativeCode=backend.QueryCode,ResourceUnresolved=true};
      if(backend.Query()!=lease.Instance)return new ControllerResult{Reason="OWNERSHIP_UNCONFIRMED",ResourceUnresolved=true};
      lease.StopAttempted=true;
      uint code=backend.Stop(lease.ControllerHandle);
      if(code!=0)return new ControllerResult{Reason="STOP_FAILED",NativeCode=code,ResourceUnresolved=true};
      return new ControllerResult{Reason="SIMULATED_STOPPED"};
    }
  }
  // A prepared record is synthetic; it is neither an ETL decoder nor a source
  // authentication mechanism. Unsigned file-object and request identifiers
  // are scoped to the future collector's lifetime and must not be trusted here.
  public sealed class ReadPair {
    public int ProcessId, ExpectedProcessId, ThreadId, ExpectedThreadId;
    public long ProcessCreated, ExpectedProcessCreated, StartTick, EndTick, WindowStart, WindowEnd;
    public ulong FileObject, ExpectedFileObject, RequestId, CompletionId;
    public uint RequestedBytes, CompletedBytes, NativeStatus, EventsLost, BuffersLost;
    public bool Completed, Replay, Contradictory;
  }
  public sealed class CorrelationResult {
    public string Status="UNVERIFIED", Reason;
    public CorrelationResult(string reason){Reason=reason;}
  }
  public static class ReadVerifier {
    public static CorrelationResult CheckInjected(ReadPair p) {
      string why;
      if(p==null) why="MISSING_RECORD";
      else if(p.EventsLost>0 || p.BuffersLost>0) why="EVENT_LOSS";
      else if(p.Replay) why="REPLAY_DETECTED";
      else if(p.Contradictory) why="CONTRADICTORY_COMPLETION";
      else if(p.ProcessId<=0 || p.ProcessCreated<=0 || p.ProcessId!=p.ExpectedProcessId || p.ProcessCreated!=p.ExpectedProcessCreated) why="ACTOR_LIFETIME_MISMATCH";
      else if(p.ThreadId<=0 || p.ThreadId!=p.ExpectedThreadId) why="THREAD_MISMATCH";
      else if(p.FileObject==0 || p.FileObject!=p.ExpectedFileObject) why="FILE_OBJECT_MISMATCH";
      else if(p.RequestId==0 || p.RequestId!=p.CompletionId) why="REQUEST_MISMATCH";
      else if(!p.Completed) why="COMPLETION_MISSING";
      else if(p.WindowStart<0 || p.WindowEnd<=p.WindowStart || p.StartTick<p.WindowStart || p.EndTick<p.StartTick || p.EndTick>p.WindowEnd) why="WINDOW_MISMATCH";
      else if(p.RequestedBytes==0 || p.CompletedBytes>p.RequestedBytes) why="BYTE_COUNT_INVALID";
      else if(p.NativeStatus!=0) why="READ_NOT_SUCCESSFUL";
      else if(p.CompletedBytes==0) why="ZERO_BYTE_READ";
      else why="INJECTED_MATCH_NOT_PROOF";
      return new CorrelationResult(why);
    }
  }
}
