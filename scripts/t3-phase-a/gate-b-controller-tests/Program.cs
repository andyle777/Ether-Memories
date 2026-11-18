using System.Text.Json;
using Orion.EtwPrepared;
using Orion.GateB;

static void Assert(bool ok, string message) { if (!ok) throw new Exception(message); }
static string Field(JsonElement e, string name) => e.GetProperty(name).ValueKind == JsonValueKind.Null ? null : e.GetProperty(name).GetString();

string directory=Path.Combine(Path.GetTempPath(), "gate-b-orchestration-"+Guid.NewGuid().ToString("N"));
Directory.CreateDirectory(directory);
string fixture=Path.Combine(directory,"fixture.bin");
Workload.CreateFixture(fixture);
try {
  foreach (string test in new[]{"READ_FAIL_STOP_OK","READ_FAIL_STOP_ERROR","READ_FAIL_STOP_EXCEPTION","READ_FAIL_FINAL_CHECK_EXCEPTION","READ_FAIL_FINALLY_EXCEPTION","READ_OK_STATS_INCOMPLETE"}) {
    var backend=new EtwTestBackend();
    if(test=="READ_FAIL_STOP_ERROR")backend.StopCode=5;
    if(test=="READ_FAIL_STOP_EXCEPTION")backend.ThrowStop=true;
    if(test=="READ_FAIL_FINAL_CHECK_EXCEPTION")backend.ThrowFinal=true;
    if(test=="READ_OK_STATS_INCOMPLETE")backend.StopCode=234;
    var lifecycle=new EtwLifecycle(backend,"Orion-T3-GateB-Feasibility",Guid.NewGuid(),Path.Combine(directory,"out.etl"));
    int calls=0, waits=0, stopInvocations=0;
    var failedRead=new FakeRead { Fail=true };
    var initial=Workload.Run(false,fixture,new FileReadAttempt());
    var run=ControllerOrchestration.Run(lifecycle,initial,() => { calls++; return test=="READ_OK_STATS_INCOMPLETE" ? Workload.Run(true,fixture,new FileReadAttempt()) : Workload.Run(true,fixture,failedRead); },clock=>waits++, active => { stopInvocations++; if(test=="READ_FAIL_FINALLY_EXCEPTION")throw new InvalidOperationException("injected cleanup failure"); active.Stop(); });
    string json=ControllerReceipt.Serialize("11111111111111111111111111111111",lifecycle,run,"attempt","Orion-T3-GateB-Feasibility",Path.Combine(directory,"out.etl"));
    using var receipt=JsonDocument.Parse(json);
    var r=receipt.RootElement;
    Assert(calls==1 && stopInvocations==1 && backend.StopCalls==(test=="READ_FAIL_FINALLY_EXCEPTION"?0:1),"RETRY_"+test);
    Assert(r.GetProperty("vmDisposalRequired").GetBoolean() && !r.GetProperty("vmDisposalConfirmed").GetBoolean(),"DISPOSAL_"+test);
    if(test.StartsWith("READ_FAIL",StringComparison.Ordinal)) {
      Assert(Field(r,"workloadFailure")=="WORKLOAD_FAILED" && Field(r.GetProperty("workload"),"Outcome")=="READ_FAILED","ORIGINAL_FAILURE_LOST_"+test);
      Assert(failedRead.Calls==1,"READ_NOT_EXECUTED_EXACTLY_ONCE_"+test);
      Assert(waits==0,"FAILED_READ_WAITED_"+test);
    } else { Assert(Field(r,"workloadFailure")==null && waits==1,"SUCCESS_NOT_RECORDED"); }
    if(test=="READ_FAIL_STOP_OK")Assert(Field(r,"stop")=="SESSION_STOPPED" && Field(r,"cleanupFailure")==null,"STOP_OK_LOST");
    if(test=="READ_FAIL_STOP_ERROR")Assert(Field(r,"cleanupFailure")=="STOP_UNCONFIRMED","STOP_ERROR_LOST");
    if(test=="READ_FAIL_STOP_EXCEPTION")Assert(Field(r,"cleanupFailure")=="STOP_EXCEPTION","STOP_EXCEPTION_LOST");
    if(test=="READ_FAIL_FINAL_CHECK_EXCEPTION")Assert(Field(r,"cleanupFailure")=="FINAL_FILE_CHECK_FAILED","CLEANUP_EXCEPTION_LOST");
    if(test=="READ_FAIL_FINALLY_EXCEPTION")Assert(Field(r,"cleanupException")=="CLEANUP_EXCEPTION" && Field(r,"controllerException")==null && Field(r,"stop")==null,"FINALLY_EXCEPTION_LOST");
    if(test=="READ_OK_STATS_INCOMPLETE") {
      var stats=r.GetProperty("statistics");
      Assert(!stats.GetProperty("StatisticsValid").GetBoolean() && stats.GetProperty("EventsLost").ValueKind==JsonValueKind.Null && stats.GetProperty("LogBuffersLost").ValueKind==JsonValueKind.Null && stats.GetProperty("RealTimeBuffersLost").ValueKind==JsonValueKind.Null,"INCOMPLETE_LOSS_COERCED");
      Assert(Field(r,"operationFailure")=="FINAL_STATISTICS_INCOMPLETE","INCOMPLETE_FAILURE_LOST");
    }
    Console.WriteLine("PASS "+test+" readCalls="+calls+" stopAttempts="+stopInvocations+" nativeStopCalls="+backend.StopCalls);
  }
} finally { File.Delete(fixture); Directory.Delete(directory); }
