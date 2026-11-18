using var raw = new MemoryStream();
using var bounded = new LimitedOutputStream(raw, 8);
bounded.Write(new byte[8]);
try { bounded.WriteByte(1); throw new Exception("OUTPUT_BOUND_MISSING"); }
catch (InvalidDataException e) when (e.Message == "OUTPUT_LIMIT") { }
if (raw.Length != 8) throw new Exception("OVERSIZED_OUTPUT_WRITTEN");
Console.WriteLine("PASS decoder output stream enforces byte limit");
