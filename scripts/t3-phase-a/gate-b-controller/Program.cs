using System.Text.Json;
using Orion.EtwPrepared;
using Orion.GateB;
using System.Diagnostics;

// A command-line acknowledgement is not machine attestation or authorization.
// The experimental mode must only be run after separate owner approval, on a
// disposable VM under the reviewed single-controller threat model.
const string SessionName="Orion-T3-GateB-Feasibility";
if (args.Length==1 && args[0]=="--dry-run") {
    using var p=new NativePropertiesBuffer(SessionName,Guid.NewGuid(),Path.GetFullPath(Path.Combine(Path.GetTempPath(),"orion-dry-run.etl")));
    Console.WriteLine(JsonSerializer.Serialize(new {status="DRY_RUN_ONLY",session=SessionName,mode=p.Mode,flags=p.EnableFlags,maxMiB=64,captureSeconds=15,nativeCalls=0}));
    return 0;
}
if(args.Length!=4 || args[2]!="--pipe-output" || !Guid.TryParseExact(args[3],"N",out _)) {
    Console.Error.WriteLine("EXPERIMENT_NOT_AUTHORIZED");return 2;
}
using var config=JsonDocument.Parse(File.ReadAllText(args[0]));
if(!config.RootElement.TryGetProperty("mode",out var mode) || mode.ValueKind!=JsonValueKind.String){Console.Error.WriteLine("INVALID_CONFIG");return 2;}
// Harmless process-supervision control: never enters the native collector.
if(mode.GetString()=="offline-stall-test") {Thread.Sleep(TimeSpan.FromSeconds(60));return 2;}
if(mode.GetString()=="dry-run") {
    Console.WriteLine(JsonSerializer.Serialize(new {Source="CAPTURED_UNTRUSTED",Status="UNVERIFIED",Experiment=args[3],nativeCalls=0,session=SessionName,maxMiB=64,captureSeconds=15}));
    return 0;
}
if(mode.GetString()!="experimental-disposable-vm" || !config.RootElement.TryGetProperty("ownerApproval",out var approval) || approval.GetString()!="separately-authorized") {Console.Error.WriteLine("EXPERIMENT_NOT_AUTHORIZED");return 2;}
string root=Path.GetFullPath(Path.GetDirectoryName(args[0])!);
if(!Directory.Exists(root) || (File.GetAttributes(root)&FileAttributes.ReparsePoint)!=0) {Console.Error.WriteLine("EXPERIMENT_DIRECTORY_INVALID");return 2;}
string attempt=Guid.NewGuid().ToString("N");
Guid sessionId;
do {sessionId=Guid.NewGuid();} while(sessionId==new Guid("9e814aad-3204-11d2-9a82-006008a86939"));
string leasePath=Path.Combine(root,"orion-"+attempt+".reservation");
string etlPath=Path.Combine(root,"orion-"+attempt+".etl");
using(var lease=new FileStream(leasePath,FileMode.CreateNew,FileAccess.Write,FileShare.Read)) {
    byte[] intent=System.Text.Encoding.UTF8.GetBytes(JsonSerializer.Serialize(new {phase="PRE_START_INTENT",attempt,session=SessionName,sessionId,etlPath}));
    lease.Write(intent);lease.Flush(true);
}
if(File.Exists(etlPath)){Console.Error.WriteLine("OUTPUT_COLLISION");return 2;}
string fixturePath=Path.Combine(root,"synthetic-read.bin");
try { Workload.CreateFixture(fixturePath); } catch {Console.Error.WriteLine("FIXTURE_CREATE_FAILED_VM_DISPOSAL_REQUIRED");return 2;}
var controller=EtwLifecycle.CreateDisposableExperiment(SessionName,sessionId,etlPath);
WorkloadResult initialWorkload=Workload.Run(false,fixturePath,new FileReadAttempt());
var run=ControllerOrchestration.Run(controller,initialWorkload,
    () => Workload.Run(true,fixturePath,new FileReadAttempt()),
    clock => { var remaining=TimeSpan.FromSeconds(15)-clock.Elapsed; if(remaining>TimeSpan.Zero) Thread.Sleep(remaining); },
    active => active.Stop());
Console.WriteLine(ControllerReceipt.Serialize(args[3],controller,run,attempt,SessionName,etlPath));
// A stopped session or non-empty ETL is not security evidence or finalisation.
return controller.State==EtwState.FINALIZATION_UNVERIFIED && run.ControllerException==null && run.CleanupException==null && run.WorkloadFailure==null && controller.OriginalFailure==null && controller.CleanupFailure==null && run.Workload?.Outcome=="READ_COMPLETE" ? 0 : 2;
