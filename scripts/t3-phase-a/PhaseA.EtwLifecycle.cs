using System;
using System.IO;
using System.Runtime.InteropServices;

namespace Orion.EtwPrepared {
  public enum EtwState { NOT_STARTED, START_FAILED, STARTED_OWNED, QUERY_VERIFIED, OWNERSHIP_UNVERIFIED, STOP_REQUESTED, STOP_CONFIRMED, STOP_UNCONFIRMED, FINALIZATION_UNVERIFIED }
  public sealed class EtwObservation {
    public uint Code, Mode, EnableFlags, BufferSize, MinimumBuffers, MaximumBuffers, MaximumFileSize, FlushTimer, NumberOfBuffers, BuffersWritten, EventsLost, LogBuffersLost, RealTimeBuffersLost;
    public Guid SessionId;
    public string SessionName, OutputPath;
    // Only the injected backend may assert this. Native ETW has not yet supplied
    // independently established continuity of the original session instance.
    public bool ContinuityEstablished;
  }
  public interface IEtwOperations {
    uint Start(string name, Guid id, string path, out ulong handle);
    EtwObservation Query(ulong handle, string name, Guid id, string path);
    EtwObservation Stop(ulong handle, string name, Guid id, string path);
    bool FinalFileExists(string path);
  }
  internal sealed class NativeEtwOperations : IEtwOperations {
    public uint Start(string name,Guid id,string path,out ulong handle) {
      using(var buffer=new NativePropertiesBuffer(name,id,path)) return NativeDeclarations.StartTraceW(out handle,name,buffer.Pointer);
    }
    static EtwObservation Control(ulong handle,string name,Guid id,string path,uint operation) {
      using(var buffer=new NativePropertiesBuffer(name,id,path)) {
        var p=(TraceProperties)Marshal.PtrToStructure(buffer.Pointer,typeof(TraceProperties));
        // Start settings are inputs; erase them so they cannot masquerade as a
        // returned observation. Keep allocated output-string offsets and size.
        p.Wnode.Guid=Guid.Empty; p.BufferSize=0;p.MinimumBuffers=0;p.MaximumBuffers=0;
        p.MaximumFileSize=0;p.LogFileMode=0;p.FlushTimer=0;p.EnableFlags=0;
        Marshal.StructureToPtr(p,buffer.Pointer,false);
        for(int i=buffer.StructBytes;i<buffer.TotalBytes;i++)Marshal.WriteByte(buffer.Pointer,i,0);
        uint code=NativeDeclarations.ControlTraceW(handle,null,buffer.Pointer,operation);
        p=(TraceProperties)Marshal.PtrToStructure(buffer.Pointer,typeof(TraceProperties));
        return new EtwObservation{Code=code,SessionId=p.Wnode.Guid,Mode=p.LogFileMode,EnableFlags=p.EnableFlags,
          BufferSize=p.BufferSize,MinimumBuffers=p.MinimumBuffers,MaximumBuffers=p.MaximumBuffers,
          MaximumFileSize=p.MaximumFileSize,FlushTimer=p.FlushTimer,NumberOfBuffers=p.NumberOfBuffers,BuffersWritten=p.BuffersWritten,
          EventsLost=p.EventsLost,LogBuffersLost=p.LogBuffersLost,RealTimeBuffersLost=p.RealTimeBuffersLost,
          SessionName=ReadString(buffer,p.LoggerNameOffset),OutputPath=ReadString(buffer,p.LogFileNameOffset),ContinuityEstablished=false};
      }
    }
    static string ReadString(NativePropertiesBuffer b,uint offset) {
      if(offset<(uint)b.StructBytes || offset>=(uint)b.TotalBytes || (offset&1)!=0)return null;
      int bytes=b.TotalBytes-(int)offset;
      for(int i=0;i+1<bytes;i+=2) if(Marshal.ReadInt16(b.Pointer,(int)offset+i)==0) return Marshal.PtrToStringUni(IntPtr.Add(b.Pointer,(int)offset),i/2);
      return null;
    }
    public EtwObservation Query(ulong h,string n,Guid id,string p){return Control(h,n,id,p,0);}
    public EtwObservation Stop(ulong h,string n,Guid id,string p){return Control(h,n,id,p,1);}
    public bool FinalFileExists(string path){return File.Exists(path) && new FileInfo(path).Length>0;}
  }
  // Source lifecycle only; no native invocation occurs until Start is called.
  // The public injected constructor cannot produce a LIVE security verdict.
  public sealed class EtwLifecycle {
    readonly IEtwOperations ops; readonly bool native,disposableExperiment; readonly string name,path; readonly Guid id;
    ulong handle; bool started,stopAttempted;
    public EtwState State {get;private set;}
    public string OriginalFailure {get;private set;}
    public string CleanupFailure {get;private set;}
    public string StopOutcome {get;private set;}
    public string FinalStatistics {get;private set;}
    public uint NativeCode {get;private set;}
    public EtwObservation InitialObservation {get;private set;}
    public EtwObservation LatestObservation {get;private set;}
    public EtwObservation FinalObservation {get;private set;}
    public string EvidenceClass {get{return native?"NATIVE_UNVERIFIED":"INJECTED";}}
    public EtwLifecycle(IEtwOperations backend,string sessionName,Guid sessionId,string outputPath):this(backend,sessionName,sessionId,outputPath,false,false){}
    EtwLifecycle(IEtwOperations backend,string sessionName,Guid sessionId,string outputPath,bool isNative,bool experimental) {
      if(backend==null)throw new ArgumentNullException("backend");
      using(var b=new NativePropertiesBuffer(sessionName,sessionId,outputPath)){}
      ops=backend;name=sessionName;id=sessionId;path=outputPath;native=isNative;disposableExperiment=experimental;State=EtwState.NOT_STARTED;
    }
    public static EtwLifecycle CreateNative(string name,Guid id,string path){return new EtwLifecycle(new NativeEtwOperations(),name,id,path,true,false);}
    // Internal to the separately authorised disposable experiment executable.
    internal static EtwLifecycle CreateDisposableExperiment(string name,Guid id,string path){return new EtwLifecycle(new NativeEtwOperations(),name,id,path,true,true);}
    void Failure(string text){if(OriginalFailure==null)OriginalFailure=text;}
    public static string ClassifyStopCode(uint code) {
      switch(code) {
        case 0:return "SESSION_STOPPED";
        case 234:return "SESSION_STOPPED_FINAL_STATISTICS_INCOMPLETE";
        case 4201:return "SESSION_ABSENT_CAUSE_UNKNOWN";
        case 2402:return "STOP_IN_PROGRESS";
        default:return "STOP_UNCONFIRMED";
      }
    }
    public void Start() {
      if(State!=EtwState.NOT_STARTED)throw new InvalidOperationException("INVALID_TRANSITION");
      // A started native session would outlive this process, and this build
      // cannot yet establish continuity for a safe stop. Refuse to create one.
      if(native && !disposableExperiment){State=EtwState.OWNERSHIP_UNVERIFIED;Failure("NATIVE_START_DISABLED_CONTINUITY_UNVERIFIED");return;}
      try {ulong h; uint code=ops.Start(name,id,path,out h);NativeCode=code;
        if(code!=0){State=EtwState.START_FAILED;Failure("START_FAILED");return;}
        if(h==0){State=EtwState.OWNERSHIP_UNVERIFIED;Failure("START_HANDLE_MISSING");return;}
        handle=h;started=true;State=EtwState.STARTED_OWNED;
      } catch {State=EtwState.OWNERSHIP_UNVERIFIED;Failure("START_EXCEPTION");}
    }
    bool Consistent(EtwObservation o) {
      return o!=null && o.Code==0 && o.SessionId==id && String.Equals(o.SessionName,name,StringComparison.OrdinalIgnoreCase)
        && String.Equals(o.OutputPath,path,StringComparison.OrdinalIgnoreCase) && (o.Mode&0x02000001)==0x02000001
        && (o.EnableFlags&0x06000303)==0x06000303 && o.BufferSize>0 && o.MinimumBuffers>0 && o.MaximumBuffers>=o.MinimumBuffers
        && o.MaximumFileSize>0 && o.MaximumFileSize<=64 && o.FlushTimer>0;
    }
    public void Query() {
      if(!started || stopAttempted || (State!=EtwState.STARTED_OWNED && State!=EtwState.QUERY_VERIFIED))throw new InvalidOperationException("INVALID_TRANSITION");
      try {var o=ops.Query(handle,name,id,path);if(InitialObservation==null)InitialObservation=o;LatestObservation=o;
        if(o==null || o.Code!=0){NativeCode=o==null?0:o.Code;Failure("QUERY_FAILED");State=EtwState.OWNERSHIP_UNVERIFIED;return;}
        if(!Consistent(o)){Failure("SETTINGS_OR_IDENTITY_MISMATCH");State=EtwState.OWNERSHIP_UNVERIFIED;return;}
        if(o.EventsLost!=0 || o.LogBuffersLost!=0 || o.RealTimeBuffersLost!=0)Failure("TRACE_LOSS");
        // Disposable feasibility relies on the documented controlled-environment
        // assumption, not a cryptographically authenticated session identity.
        State=(o.ContinuityEstablished && !native) || (native && disposableExperiment)?EtwState.QUERY_VERIFIED:EtwState.OWNERSHIP_UNVERIFIED;
        if(State==EtwState.OWNERSHIP_UNVERIFIED)Failure("CONTINUITY_UNVERIFIED");
      } catch {Failure("QUERY_EXCEPTION");State=EtwState.OWNERSHIP_UNVERIFIED;}
    }
    public void Stop() {
      if(stopAttempted)return; // Never retry or erase a previously observed result.
      if(!started || handle==0 || stopAttempted || State!=EtwState.QUERY_VERIFIED){State=EtwState.OWNERSHIP_UNVERIFIED;CleanupFailure="STOP_NOT_AUTHORIZED";return;}
      // Always requery immediately before stop; no caller-provided handle or name.
      Query();if(State!=EtwState.QUERY_VERIFIED){CleanupFailure="STOP_OWNERSHIP_UNVERIFIED";return;}
      stopAttempted=true;State=EtwState.STOP_REQUESTED;
      try {var o=ops.Stop(handle,name,id,path);FinalObservation=o;
        if(o==null){StopOutcome="STOP_UNCONFIRMED";CleanupFailure="STOP_INDETERMINATE";State=EtwState.STOP_UNCONFIRMED;return;}
        NativeCode=o.Code;StopOutcome=ClassifyStopCode(o.Code);
        if(o.Code==234){StopOutcome="SESSION_STOPPED";FinalStatistics="INCOMPLETE";Failure("FINAL_STATISTICS_INCOMPLETE");State=EtwState.FINALIZATION_UNVERIFIED;return;}
        if(o.Code!=0){CleanupFailure=StopOutcome;State=EtwState.STOP_UNCONFIRMED;return;}
        State=EtwState.STOP_CONFIRMED;
        FinalStatistics=Consistent(o)?"RETURNED_UNVERIFIED":"INCOMPLETE";
        if(!Consistent(o) || o.EventsLost!=0 || o.LogBuffersLost!=0 || o.RealTimeBuffersLost!=0)Failure("FINAL_EVIDENCE_INCOMPLETE");
      } catch {CleanupFailure="STOP_EXCEPTION";State=EtwState.STOP_UNCONFIRMED;}
      if(State==EtwState.STOP_CONFIRMED) {
        try {if(!ops.FinalFileExists(path))Failure("FINAL_EVIDENCE_INCOMPLETE");}
        catch {CleanupFailure="FINAL_FILE_CHECK_FAILED";}
        // Non-empty file and successful STOP are not proof of ETL finalisation.
        State=EtwState.FINALIZATION_UNVERIFIED;
      }
    }
  }
}
