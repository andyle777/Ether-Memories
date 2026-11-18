using Orion.EtwPrepared;
namespace Orion.GateB {
  public sealed class StatisticsReceipt {
    public string FinalStatistics {get;set;} public bool StatisticsValid {get;set;}
    public uint? EventsLost {get;set;} public uint? LogBuffersLost {get;set;} public uint? RealTimeBuffersLost {get;set;}
  }
  public static class Receipt {
    public static StatisticsReceipt Statistics(EtwObservation o, string finalStatistics) {
      bool valid=o!=null && o.Code==0 && finalStatistics=="RETURNED_UNVERIFIED";
      return new StatisticsReceipt { FinalStatistics=valid?"VALID":"INCOMPLETE", StatisticsValid=valid,
        EventsLost=valid?(uint?)o.EventsLost:null, LogBuffersLost=valid?(uint?)o.LogBuffersLost:null, RealTimeBuffersLost=valid?(uint?)o.RealTimeBuffersLost:null };
    }
  }
}
