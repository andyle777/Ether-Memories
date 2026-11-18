using System.Text.Json;
using Orion.EtwPrepared;

namespace Orion.GateB {
  public static class ControllerReceipt {
    // Fixed, bounded controller schema. This is untrusted output, not security evidence.
    public static string Serialize(string experiment, EtwLifecycle controller, ControllerRun run,
                                   string attempt, string session, string etlPath) {
      var initial=controller.InitialObservation; var final=controller.FinalObservation;
      var statistics=Receipt.Statistics(final,controller.FinalStatistics);
      return JsonSerializer.Serialize(new {
        Source="CAPTURED_UNTRUSTED",Status="UNVERIFIED",Experiment=experiment,
        state=controller.State.ToString(),stop=controller.StopOutcome,statistics,code=controller.NativeCode,
        operationFailure=controller.OriginalFailure,controllerException=run.ControllerException,
        cleanupFailure=controller.CleanupFailure,cleanupException=run.CleanupException,
        workloadFailure=run.WorkloadFailure,attempt,session,etl=etlPath,
        vmDisposalRequired=true,vmDisposalConfirmed=false,workload=run.Workload,
        initial=initial==null?null:new {initial.Code,initial.Mode,initial.EnableFlags,initial.BufferSize,initial.MinimumBuffers,initial.MaximumBuffers,initial.MaximumFileSize,initial.FlushTimer},
        final=final==null?null:new {final.Code}
      },new JsonSerializerOptions {IncludeFields=true});
    }
  }
}
