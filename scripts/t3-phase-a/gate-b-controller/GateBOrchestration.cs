using System;
using System.Diagnostics;
using Orion.EtwPrepared;

namespace Orion.GateB {
  public sealed class ControllerRun {
    public WorkloadResult Workload;
    public string WorkloadFailure, ControllerException, CleanupException;
  }
  // The same lifecycle is used in production and with the injected test backend.
  // This function itself does not supply a backend or authorize native tracing.
  public static class ControllerOrchestration {
    public static ControllerRun Run(EtwLifecycle controller, WorkloadResult initial,
                                    Func<WorkloadResult> workload, Action<Stopwatch> wait,
                                    Action<EtwLifecycle> stop) {
      if (controller==null || initial==null || workload==null || wait==null || stop==null) throw new ArgumentNullException();
      var result=new ControllerRun { Workload=initial };
      try {
        controller.Start();
        if(controller.State==EtwState.STARTED_OWNED) {
          controller.Query();
          if(controller.State==EtwState.QUERY_VERIFIED) {
            var clock=Stopwatch.StartNew();
            try {
              var observed=workload();
              if(observed==null) result.WorkloadFailure="WORKLOAD_RESULT_MISSING";
              else {
                result.Workload=observed;
                if(observed.Outcome!="READ_COMPLETE") result.WorkloadFailure="WORKLOAD_FAILED";
              }
            } catch { result.WorkloadFailure="WORKLOAD_EXCEPTION"; }
            if(result.WorkloadFailure==null) wait(clock);
          }
        }
      } catch { result.ControllerException="COLLECTOR_EXCEPTION"; }
      finally {
        try { if(controller.State==EtwState.QUERY_VERIFIED) stop(controller); }
        catch { result.CleanupException="CLEANUP_EXCEPTION"; }
      }
      return result;
    }
  }
}
