using System;
using System.IO;
// Limits the decoder's own output protocol, not writes by a hostile process.
public sealed class LimitedOutputStream : Stream {
    readonly Stream inner;
    readonly long limit;
    long written;
    public LimitedOutputStream(Stream inner,long limit) {
        this.inner=inner ?? throw new ArgumentNullException(nameof(inner));
        if (!inner.CanWrite || limit < 0) throw new ArgumentOutOfRangeException(nameof(limit));
        this.limit=limit;
    }
    void Check(int count) { if (count < 0 || count > limit-written) throw new InvalidDataException("OUTPUT_LIMIT"); }
    public override void Write(byte[] buffer,int offset,int count) { Check(count);inner.Write(buffer,offset,count);written+=count; }
    public override void Write(ReadOnlySpan<byte> buffer) { Check(buffer.Length);inner.Write(buffer);written+=buffer.Length; }
    public override void WriteByte(byte value) { Check(1);inner.WriteByte(value);written++; }
    public override void Flush()=>inner.Flush();
    public override bool CanRead=>false;
    public override bool CanSeek=>false;
    public override bool CanWrite=>true;
    public override long Length=>written;
    public override long Position {get=>written;set=>throw new NotSupportedException();}
    public override int Read(byte[] b,int o,int c)=>throw new NotSupportedException();
    public override long Seek(long o,SeekOrigin s)=>throw new NotSupportedException();
    public override void SetLength(long v)=>throw new NotSupportedException();
}
