// Bounded JSON syntactic check for Windows PowerShell 5.1. This establishes
// neither the authority nor the authenticity of the receipt.
using System;
using System.Collections.Generic;
using System.Text.RegularExpressions;
using System.Web.Script.Serialization;
public sealed class GateBStrictJson {
  readonly string s; int p; readonly JavaScriptSerializer js = new JavaScriptSerializer();
  GateBStrictJson(string input) { s=input; }
  public static bool Validate(string input) {
    try {
      if(input==null || input.Length>1048576) return false;
      var q=new GateBStrictJson(input); q.Value(0); q.White(); return q.p==q.s.Length;
    } catch { return false; }
  }
  void White(){while(p<s.Length && (s[p]==' ' || s[p]=='\t' || s[p]=='\r' || s[p]=='\n'))p++;}
  void Take(char c){White();if(p>=s.Length || s[p++]!=c)throw new FormatException();}
  string Str(){
    White(); int start=p; if(p>=s.Length || s[p++]!='"')throw new FormatException();
    bool ended=false; while(p<s.Length){char c=s[p++];if(c=='"'){ended=true;break;}if(c<32)throw new FormatException();if(c=='\\'){if(p>=s.Length)throw new FormatException();p++;}}
    if(!ended)throw new FormatException();
    var decoded=js.DeserializeObject("["+s.Substring(start,p-start)+"]") as object[];
    if(decoded==null || decoded.Length!=1 || !(decoded[0] is string))throw new FormatException(); return (string)decoded[0];
  }
  void Value(int depth){
    if(depth>32)throw new FormatException(); White();if(p>=s.Length)throw new FormatException();
    if(s[p]=='{') {p++;var keys=new HashSet<string>(StringComparer.OrdinalIgnoreCase);White();if(p<s.Length&&s[p]=='}'){p++;return;}while(true){string key=Str();if(!keys.Add(key))throw new FormatException();Take(':');Value(depth+1);White();if(p<s.Length&&s[p]=='}'){p++;return;}Take(',');}}
    if(s[p]=='[') {p++;White();if(p<s.Length&&s[p]==']'){p++;return;}while(true){Value(depth+1);White();if(p<s.Length&&s[p]==']'){p++;return;}Take(',');}}
    if(s[p]=='"'){Str();return;}
    foreach(string lit in new[]{"true","false","null"}){if(s.Length-p>=lit.Length && string.CompareOrdinal(s,p,lit,0,lit.Length)==0){p+=lit.Length;return;}}
    Match m=Regex.Match(s.Substring(p),@"^-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?");if(!m.Success)throw new FormatException();p+=m.Length;
  }
}
