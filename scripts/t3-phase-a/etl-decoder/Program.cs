// Offline importer only: this process never starts, controls or stops an ETW session.
using System.Text.Json;
using Microsoft.Diagnostics.Tracing;
using Microsoft.Diagnostics.Tracing.Parsers.Kernel;

const long MaxInput = 256L * 1024 * 1024;
const int MaxEvents = 100000;
var events = new List<ObservedEvent>();
var pending = new HashSet<ulong>();
var seen = new HashSet<ulong>();
string reason = "INCOMPLETE_CORRELATION";
int lost = -1;
int dynamicDecodedEvents = 0;
try {
    if (args.Length != 2 && (args.Length != 3 || args[2] != "--owned-output") && (args.Length != 4 || args[2] != "--pipe-output" || !Guid.TryParseExact(args[3],"N",out _))) throw new InvalidDataException("ARGUMENTS_INVALID");
    bool ownedOutput=args.Length==3 && args[2]=="--owned-output";
    bool pipeOutput=args.Length==4 && args[2]=="--pipe-output";
    string input = Path.GetFullPath(args[0]), output = Path.GetFullPath(args[1]);
    if (!File.Exists(input)) throw new InvalidDataException("INPUT_MISSING");
    if (String.Equals(input, output, StringComparison.OrdinalIgnoreCase)) throw new InvalidDataException("PATH_COLLISION");
    if (new FileInfo(input).Length > MaxInput) throw new InvalidDataException("INPUT_TOO_LARGE");
    if (!ownedOutput && !pipeOutput && File.Exists(output)) throw new InvalidDataException("OUTPUT_EXISTS");
    void Add(ObservedEvent e) { if (events.Count >= MaxEvents) throw new InvalidDataException("EVENT_LIMIT"); events.Add(e); }
    void Check(TraceEvent e, int minimum) {
        if (e.Version != 2) throw new InvalidDataException("SCHEMA_UNSUPPORTED");
        if (e.PointerSize != 4 && e.PointerSize != 8) throw new InvalidDataException("POINTER_SIZE_INVALID");
        if (e.EventDataLength < minimum) throw new InvalidDataException("EVENT_TRUNCATED");
    }
    using var source = new ETWTraceEventSource(input);
    // Count only events whose dynamic payload was actually decoded. Payload values
    // are deliberately not exported, and this count does not imply FileIo coverage.
    source.Dynamic.All += e => {
        if (++dynamicDecodedEvents > MaxEvents) throw new InvalidDataException("EVENT_LIMIT");
        for (int i=0; i<e.PayloadNames.Length; i++) _=e.PayloadValue(i);
    };
    source.Kernel.ProcessStartGroup += e => Add(ObservedEvent.From(e, "PROCESS_START"));
    source.Kernel.ProcessEndGroup += e => Add(ObservedEvent.From(e, "PROCESS_END"));
    source.Kernel.ThreadStartGroup += e => Add(ObservedEvent.From(e, "THREAD_START"));
    source.Kernel.ThreadEndGroup += e => Add(ObservedEvent.From(e, "THREAD_END"));
    void CheckString(TraceEvent e, int offset) {
        byte[] bytes=e.EventData();
        if (bytes.Length < offset+2 || (bytes.Length-offset)%2 != 0 || bytes[^1]!=0 || bytes[^2]!=0) throw new InvalidDataException("EVENT_TRUNCATED");
    }
    source.Kernel.FileIOName += e => { Check(e, e.PointerSize + 2); CheckString(e,e.PointerSize); var r=ObservedEvent.From(e,"FILE_NAME"); r.FileKey=e.FileKey; r.Path=e.FileName; Add(r); };
    source.Kernel.FileIOCreate += e => {
        Check(e, 2 * e.PointerSize + 18);
        CheckString(e, 2 * e.PointerSize + 16);
        var r=ObservedEvent.From(e,"CREATE"); r.Operation=e.IrpPtr; r.FileObject=e.FileObject; r.Path=e.FileName;
        if (r.Operation==0 || !seen.Add(r.Operation) || !pending.Add(r.Operation)) throw new InvalidDataException("OPERATION_REUSED");
        Add(r);
    };
    source.Kernel.FileIORead += e => {
        Check(e, 8 + 3 * e.PointerSize + 12);
        var r=ObservedEvent.From(e,"READ"); r.Operation=e.IrpPtr; r.FileObject=e.FileObject; r.FileKey=e.FileKey; r.RequestedBytes=e.IoSize;
        if (r.Operation==0 || !seen.Add(r.Operation) || !pending.Add(r.Operation)) throw new InvalidDataException("OPERATION_REUSED");
        Add(r);
    };
    source.Kernel.FileIOOperationEnd += e => {
        Check(e, 2 * e.PointerSize + 4);
        var r=ObservedEvent.From(e,"OP_END"); r.Operation=e.IrpPtr; r.NativeStatus=unchecked((uint)e.NtStatus); r.ExtraInfo=e.ExtraInfo;
        // Unmatched completions may belong to unselected operation types.
        r.Matched = pending.Remove(r.Operation); Add(r);
    };
    source.Process();
    lost=source.EventsLost;
    reason = lost != 0 ? "EVENT_LOSS_OR_UNKNOWN" : pending.Count != 0 ? "COMPLETION_MISSING" : "UNTRUSTED_CAPTURE";
    var document=new { Source="CAPTURED_UNTRUSTED", Status="UNVERIFIED", Experiment=pipeOutput?args[3]:null, Reason=reason, EventsLost=lost, BufferLoss="UNKNOWN", DynamicDecodedEvents=dynamicDecodedEvents, PendingOperations=pending.Count, Events=events };
    using (Stream file=pipeOutput ? Console.OpenStandardOutput() : new FileStream(output,ownedOutput ? FileMode.Open : FileMode.CreateNew,FileAccess.Write,ownedOutput ? FileShare.ReadWrite : FileShare.None))
    using (var bounded=new LimitedOutputStream(file,65536)) {
        if (ownedOutput) file.SetLength(0);
        JsonSerializer.Serialize(bounded,document);
    }
    if(pipeOutput)Console.Error.WriteLine(reason);else Console.WriteLine(reason);
    return 0;
} catch (Exception ex) {
    // Do not expose paths or trace contents through diagnostics.
    reason = ex is InvalidDataException && ex.Message.All(c=>char.IsAsciiLetterUpper(c)||c=='_') ? ex.Message : "ETL_READ_FAILED";
    Console.Error.WriteLine(reason);
    return 2;
}

sealed class ObservedEvent {
    public string Kind {get;set;}="";
    public int ProcessId {get;set;}
    public int ThreadId {get;set;}
    public long TimeStampQpc {get;set;}
    public int Version {get;set;}
    public ulong Operation {get;set;}
    public ulong FileObject {get;set;}
    public ulong FileKey {get;set;}
    public string? Path {get;set;}
    public long RequestedBytes {get;set;}
    public uint NativeStatus {get;set;}
    public ulong ExtraInfo {get;set;}
    public bool Matched {get;set;}
    public static ObservedEvent From(TraceEvent e,string kind) => new() {Kind=kind,ProcessId=e.ProcessID,ThreadId=e.ThreadID,TimeStampQpc=e.TimeStampQPC,Version=e.Version};
}
