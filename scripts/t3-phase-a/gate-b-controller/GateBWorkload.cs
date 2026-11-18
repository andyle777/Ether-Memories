using System;
using System.IO;
using System.Security.Cryptography;
using System.Runtime.InteropServices;
using System.Diagnostics;

namespace Orion.GateB {
  public interface IReadAttempt { int Read(string path, byte[] buffer); }
  public sealed class FileReadAttempt : IReadAttempt {
    public int Read(string path, byte[] buffer) {
      using (var file = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read))
        return file.Read(buffer, 0, buffer.Length); // One synchronous application read; short reads are not retried.
    }
  }
  public sealed class WorkloadResult {
    public string Outcome, ExpectedSha256, ActualSha256, StartedUtc, CompletedUtc;
    public int RequestedBytes, ActualBytes, ProcessId; public uint ThreadId; public long StartTicks, EndTicks;
  }
  public static class Workload {
    static readonly byte[] Content = System.Text.Encoding.UTF8.GetBytes("ORION Gate B synthetic fixture v1\n");
    [DllImport("kernel32.dll")] static extern uint GetCurrentThreadId();
    static string Hash(byte[] bytes, int length) { using(var sha=SHA256.Create()) return BitConverter.ToString(sha.ComputeHash(bytes,0,length)).Replace("-", "").ToLowerInvariant(); }
    public static void CreateFixture(string path) {
      using(var f=new FileStream(path,FileMode.CreateNew,FileAccess.Write,FileShare.None)) { f.Write(Content,0,Content.Length); f.Flush(true); }
    }
    public static WorkloadResult Run(bool captureVerified, string path, IReadAttempt reader) {
      var r=new WorkloadResult { Outcome="NOT_RUN", RequestedBytes=Content.Length, ExpectedSha256=Hash(Content,Content.Length) };
      if(!captureVerified) return r;
      r.ProcessId=Process.GetCurrentProcess().Id; r.ThreadId=GetCurrentThreadId();
      r.StartedUtc=DateTime.UtcNow.ToString("o"); r.StartTicks=Stopwatch.GetTimestamp();
      var bytes=new byte[Content.Length];
      try {
        int n=reader.Read(path,bytes); r.ActualBytes=n;
        if(n<0 || n>bytes.Length) { r.Outcome="READ_INVALID"; }
        else { r.ActualSha256=Hash(bytes,n); r.Outcome=n==0?"READ_EMPTY":n!=bytes.Length?"READ_SHORT":r.ActualSha256!=r.ExpectedSha256?"DIGEST_MISMATCH":"READ_COMPLETE"; }
      } catch(FileNotFoundException) { r.Outcome="FIXTURE_MISSING"; }
        catch { r.Outcome="READ_FAILED"; }
      r.EndTicks=Stopwatch.GetTimestamp(); r.CompletedUtc=DateTime.UtcNow.ToString("o"); return r;
    }
  }
}
