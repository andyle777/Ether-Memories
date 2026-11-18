// Harmless test process; never used by the decoder or live manager.
var mode = File.ReadAllText(args[0]);
void WriteResult(string result) {
    if(args.Length==4 && args[2]=="--pipe-output") {
        if(mode!="REPLAY" && result.StartsWith("{")) result="{\"Experiment\":\""+args[3]+"\","+result.Substring(1);
        Console.Out.Write(result);Console.Out.Flush();return;
    }
    bool owned=args.Length==3 && args[2]=="--owned-output";
    using var file=new FileStream(args[1],owned?FileMode.Open:FileMode.Create,FileAccess.Write,owned?FileShare.ReadWrite:FileShare.None);
    file.SetLength(0);
    using var writer=new StreamWriter(file);
    writer.Write(result);
}
if (mode == "HANG") { Thread.Sleep(60000); return 0; }
if (mode == "BOTH_FLOOD") {var t=new Thread(()=>{for(int i=0;i<10000;i++)Console.Error.Write("EEEEEEEEEEEEEEEE");});t.Start();for(int i=0;i<10000;i++)Console.Out.Write("OOOOOOOOOOOOOOOO");t.Join();return 0;}
if (mode == "CRASH") return 9;
// Abruptly terminate only this harmless test child; produces no worker receipt.
if (mode == "ABRUPT") { System.Diagnostics.Process.GetCurrentProcess().Kill(); return 9; }
if (mode == "NONZERO") { Console.Error.Write("TEST_NONZERO"); return 3; }
if (mode == "MALFORMED") { WriteResult("not-json{"); return 0; }
if (mode == "DUPLICATE") { WriteResult("{\"Source\":\"CAPTURED_UNTRUSTED\",\"Status\":\"UNVERIFIED\",\"vmDisposalRequired\":true,\"vmDisposalRequired\":false,\"vmDisposalConfirmed\":false}"); return 0; }
if (mode == "CONTRADICT") { WriteResult("{\"Source\":\"CAPTURED_UNTRUSTED\",\"Status\":\"UNVERIFIED\",\"vmDisposalRequired\":false,\"vmDisposalConfirmed\":true}"); return 0; }
if (mode == "VALID") { WriteResult(System.Text.Json.JsonSerializer.Serialize(new {Source="CAPTURED_UNTRUSTED",Status="UNVERIFIED",state="FINALIZATION_UNVERIFIED",stop="SESSION_STOPPED",statistics=new {FinalStatistics="INCOMPLETE",StatisticsValid=false,EventsLost=(uint?)null,LogBuffersLost=(uint?)null,RealTimeBuffersLost=(uint?)null},code=0,operationFailure=(string)null,workloadFailure=(string)null,controllerException=(string)null,cleanupFailure=(string)null,cleanupException=(string)null,attempt=Guid.NewGuid().ToString("N"),session="Orion-T3-GateB-Feasibility",etl=Path.Combine(Path.GetDirectoryName(args[0])!,"synthetic.etl"),vmDisposalRequired=true,vmDisposalConfirmed=false,workload=new {Outcome="READ_COMPLETE",ExpectedSha256="a",ActualSha256="a",StartedUtc="x",CompletedUtc="x",RequestedBytes=1,ActualBytes=1,ProcessId=1,ThreadId=1,StartTicks=1,EndTicks=2},initial=(object)null,final=new {Code=0}})); return 0; }
if (mode == "MISSING") return 0;
if (mode == "OVERSIZE") { WriteResult(new string('x',200000)); return 0; }
if (mode == "FORGED") { WriteResult("{\"Source\":\"LIVE\",\"Status\":\"PASS\"}"); return 0; }
if (mode == "MUTATE_INPUT") { try { File.WriteAllText(args[0], "MUTATED"); } catch (IOException) { } }
if (mode == "ATTACK_DEPENDENCY") {
    string target=Path.ChangeExtension(Environment.ProcessPath!, ".runtimeconfig.json");
    bool modified=false;
    try {File.WriteAllText(target,"MUTATED");modified=true;} catch (IOException) {} catch (UnauthorizedAccessException) {}
    WriteResult(System.Text.Json.JsonSerializer.Serialize(new {Source="CAPTURED_UNTRUSTED",Status="UNVERIFIED",modified}));
    return 0;
}
if (mode == "ATTACK_EXECUTABLE") {
    string target=Environment.ProcessPath!;
    bool modify=false,rename=false,delete=false,replace=false;
    try {File.WriteAllText(target,"MUTATED");modify=true;} catch (IOException) {} catch (UnauthorizedAccessException) {}
    try {File.Move(target,target+".renamed");rename=true;} catch (IOException) {} catch (UnauthorizedAccessException) {}
    try {File.Delete(target);delete=true;} catch (IOException) {} catch (UnauthorizedAccessException) {}
    string replacement=args[0]+".replacement";File.WriteAllText(replacement,"REPLACEMENT");
    try {File.Replace(replacement,target,null);replace=true;} catch (IOException) {} catch (UnauthorizedAccessException) {}
    WriteResult(System.Text.Json.JsonSerializer.Serialize(new {Source="CAPTURED_UNTRUSTED",Status="UNVERIFIED",modify,rename,delete,replace}));
    return 0;
}
if (mode == "ATTACK_INPUT") {
    bool modify=false,rename=false,delete=false,replace=false;
    try {File.WriteAllText(args[0],"MUTATED");modify=true;} catch (IOException) {}
    try {File.Move(args[0],args[0]+".renamed");rename=true;} catch (IOException) {}
    try {File.Delete(args[0]);delete=true;} catch (IOException) {}
    var replacement=args[0]+".replacement";File.WriteAllText(replacement,"REPLACEMENT");
    try {File.Replace(replacement,args[0],null);replace=true;} catch (IOException) {}
    WriteResult(System.Text.Json.JsonSerializer.Serialize(new { Source="CAPTURED_UNTRUSTED", Status="UNVERIFIED",modify,rename,delete,replace }));
    return 0;
}
if (mode == "SUBSTITUTE_OUTPUT") {
    var replacement=args[1]+".replacement";File.WriteAllText(replacement,"REPLACEMENT");
    bool substituted=false,deleted=false;
    try {File.Move(replacement,args[1],true);substituted=true;} catch (IOException) {} catch (UnauthorizedAccessException) {}
    try {File.Delete(args[1]);deleted=true;} catch (IOException) {} catch (UnauthorizedAccessException) {}
    WriteResult(System.Text.Json.JsonSerializer.Serialize(new { Source="CAPTURED_UNTRUSTED", Status="UNVERIFIED",substituted,deleted }));
    return 0;
}
WriteResult("{\"Source\":\"CAPTURED_UNTRUSTED\",\"Status\":\"UNVERIFIED\"}");
return 0;
