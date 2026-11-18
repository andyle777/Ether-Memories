// Synthetic-only validation preparation. No ETL decoder or trust promotion.
using System;
using System.Collections.Generic;
namespace Orion.OfflineEvidence {
  public sealed class FixtureInput {
    public string Experiment,ExpectedExperiment,Target,ExpectedTarget,FileId,ExpectedFileId;
    public ulong Volume,ExpectedVolume,FileObject;
    public int MappingCount;
    public long StartTick,EndTick,OperationTick;
    public bool Reparse,Replaced;
  }
  public sealed class TraceInput {
    public bool ProviderExpected,SettingsMatch,Started,Stopped,Finalized,MetadataValid,LossKnown,CompletionPresent,WindowCovered,Contradictory,Replay;
    public int EventsLost,BuffersLost;
  }
  // No caller-selectable provenance and no trusted deserialization constructor.
  public sealed class Result {
    public string Status {get{return "UNVERIFIED";}}
    public string Source {get{return "SYNTHETIC_TEST";}}
    public string Reason {get;private set;}
    internal Result(string reason){Reason=reason;}
  }
  public static class Verifier {
    public static Result Fixture(FixtureInput x) {
      if(x==null)return new Result("MISSING_RECORD");
      if(String.IsNullOrWhiteSpace(x.Experiment)||x.Experiment!=x.ExpectedExperiment)return new Result("EXPERIMENT_MISMATCH");
      if(String.IsNullOrWhiteSpace(x.Target)||x.Target!=x.ExpectedTarget)return new Result("TARGET_MISMATCH");
      if(x.Volume==0||x.Volume!=x.ExpectedVolume)return new Result("VOLUME_MISMATCH");
      if(String.IsNullOrWhiteSpace(x.FileId)||x.FileId!=x.ExpectedFileId)return new Result("FILE_ID_MISMATCH");
      if(x.Reparse)return new Result("REPARSE_REJECTED");
      if(x.Replaced)return new Result("REPLACEMENT_DETECTED");
      if(x.FileObject==0)return new Result("FILE_OBJECT_MAPPING_MISSING");
      if(x.MappingCount!=1)return new Result("AMBIGUOUS_MAPPING");
      if(x.StartTick<0||x.EndTick<=x.StartTick||x.OperationTick<x.StartTick||x.OperationTick>x.EndTick)return new Result("TARGET_LIFETIME_MISMATCH");
      return new Result("SYNTHETIC_MATCH_NOT_PROOF");
    }
    public static Result Trace(TraceInput x) {
      if(x==null)return new Result("MISSING_RECORD");
      if(!x.ProviderExpected)return new Result("PROVIDER_MISMATCH");
      if(!x.SettingsMatch)return new Result("SETTINGS_MISMATCH");
      if(!x.Started)return new Result("START_MISSING");
      if(!x.Stopped)return new Result("STOP_MISSING");
      if(!x.Finalized)return new Result("FINALIZATION_MISSING");
      if(!x.MetadataValid)return new Result("METADATA_INVALID");
      if(!x.LossKnown||x.EventsLost<0||x.BuffersLost<0)return new Result("LOSS_UNKNOWN");
      if(x.EventsLost>0)return new Result("EVENT_LOSS");
      if(x.BuffersLost>0)return new Result("BUFFER_LOSS");
      if(!x.CompletionPresent)return new Result("COMPLETION_MISSING");
      if(!x.WindowCovered)return new Result("WINDOW_UNCOVERED");
      if(x.Contradictory)return new Result("CONTRADICTION");
      if(x.Replay)return new Result("REPLAY_DETECTED");
      return new Result("SYNTHETIC_MATCH_NOT_PROOF");
    }
    public static Result Identity(){return new Result("EFFECTIVE_IDENTITY_UNCORROBORATED");}
  }
  // Validates synthetic, already-extracted properties only; never parses ETL.
  public sealed class ReadDecode {
    public string Status {get{return "UNVERIFIED";}}
    public string Source {get{return "SYNTHETIC_TEST";}}
    public string Reason {get;internal set;}
    public ulong RequestId {get;internal set;}
    public ulong FileObject {get;internal set;}
    public uint RequestedBytes {get;internal set;}
  }
  public static class Schema {
    static readonly Guid FileIoGuid=new Guid("90cbdc39-4a3e-11d1-84f4-0000f80464e3");
    static bool Length(IDictionary<string,byte[]> p,string key,int n){return p.ContainsKey(key)&&p[key]!=null&&p[key].Length==n;}
    static ulong Pointer(byte[] b){return b.Length==4?BitConverter.ToUInt32(b,0):BitConverter.ToUInt64(b,0);}
    public static ReadDecode ReadRequest(Guid provider,int version,int opcode,int pointerSize,IDictionary<string,byte[]> p){
      var r=new ReadDecode();
      if(provider!=FileIoGuid){r.Reason="PROVIDER_MISMATCH";return r;}
      if(version!=2){r.Reason="SCHEMA_UNSUPPORTED";return r;}
      if(opcode!=67){r.Reason="EVENT_MISMATCH";return r;}
      if(!BitConverter.IsLittleEndian || p==null || (pointerSize!=4&&pointerSize!=8) || p.Count!=7 || !Length(p,"Offset",8) || !Length(p,"IrpPtr",pointerSize) || !Length(p,"TTID",4) || !Length(p,"FileObject",pointerSize) || !Length(p,"FileKey",pointerSize) || !Length(p,"IoSize",4) || !Length(p,"IoFlags",4)){r.Reason="PROPERTY_INVALID";return r;}
      r.RequestId=Pointer(p["IrpPtr"]);r.FileObject=Pointer(p["FileObject"]);r.RequestedBytes=BitConverter.ToUInt32(p["IoSize"],0);
      r.Reason="SYNTHETIC_MATCH_NOT_PROOF";return r;
    }
  }
}
