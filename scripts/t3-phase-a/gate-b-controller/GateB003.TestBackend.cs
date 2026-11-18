using System;
using Orion.GateB;
public sealed class FakeRead : IReadAttempt {
 public int Calls; public int Count; public bool Fail; public bool Bad;
 public int Read(string path, byte[] bytes) { Calls++; if(Fail)throw new Exception(); int n=Math.Min(Count,bytes.Length); for(int i=0;i<n;i++)bytes[i]=(byte)(Bad?42:0); return n; }
}
