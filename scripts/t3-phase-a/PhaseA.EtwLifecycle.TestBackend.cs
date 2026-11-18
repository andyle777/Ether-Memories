using System;
using Orion.EtwPrepared;
public sealed class EtwTestBackend : IEtwOperations {
 public uint StartCode,QueryCode,StopCode,EventsLost,BuffersLost; public bool WrongId,Replace,ReplaceOnSecond,WrongSettings,Continuity=true,MissingFinal,NullStop,ThrowStop,ThrowStart,ThrowFinal;
 public int StartCalls,QueryCalls,StopCalls;
 public uint Start(string n,Guid id,string p,out ulong h){StartCalls++;h=123;if(ThrowStart)throw new Exception();return StartCode;}
 EtwObservation Make(string n,Guid id,string p,uint code){return new EtwObservation{Code=code,SessionId=WrongId||Replace||(ReplaceOnSecond && QueryCalls>=2)?Guid.NewGuid():id,SessionName=n,OutputPath=p,Mode=WrongSettings?0u:0x02000001u,EnableFlags=0x06000303u,BufferSize=64,MinimumBuffers=4,MaximumBuffers=64,MaximumFileSize=32,FlushTimer=1,EventsLost=EventsLost,LogBuffersLost=BuffersLost,ContinuityEstablished=Continuity};}
 public EtwObservation Query(ulong h,string n,Guid id,string p){QueryCalls++;return Make(n,id,p,QueryCode);}
 public EtwObservation Stop(ulong h,string n,Guid id,string p){StopCalls++;if(ThrowStop)throw new Exception();return NullStop?null:Make(n,id,p,StopCode);}
 public bool FinalFileExists(string p){if(ThrowFinal)throw new Exception();return !MissingFinal;}
}
