import { types as utilTypes } from "node:util";
import type { ContextCitation } from "../types/index.js";
import { err, ok, type Result } from "../utils/result.js";

export type AdaptiveOperation = "local_excerpt" | "semantic_summary";
export type AdaptiveRoute = "native-assisted" | "hybrid" | "local-deterministic" | "unavailable";
export type AdaptiveResultKind = "host_text" | "host_text_with_evidence" | "local_excerpt" | "unavailable";
export type AdaptiveReason = "disclosure_denied" | "capability_absent" | "capability_malformed" | "hybrid_unsupported" | "host_failed" | "host_output_invalid" | "timeout";
interface AdaptiveRequestCommon {
  readonly maxChars: number;
  readonly allowHostDisclosure?: boolean;
  readonly allowDegradedFallback?: boolean;
  readonly timeoutMs?: number;
}
export type AdaptiveSummaryRequest = AdaptiveRequestCommon & (
  | { readonly operation: "local_excerpt"; readonly text: string; readonly references?: never }
  | { readonly operation: "semantic_summary"; readonly text: string; readonly references?: never }
  | { readonly operation: "semantic_summary"; readonly text?: never; readonly references: readonly ContextCitation[] }
);
export type EvidenceLookup = { readonly status: "found"; readonly content: string } | { readonly status: "missing" } | { readonly status: "unsupported_schema" } | { readonly status: "failed" };
export type EvidenceResolver = (kind: ContextCitation["kind"], id: string) => EvidenceLookup;
export interface AdaptiveCapabilities {
  readonly summarize?: (payload: Readonly<{ text: string; maxChars: number }>) => Promise<string>;
  readonly summarizeEvidence?: (payload: Readonly<{ evidence: ReadonlyArray<Readonly<{ id: string; kind: ContextCitation["kind"]; excerpt: string }>>; maxChars: number }>) => Promise<string>;
}
export interface AdaptiveDependencies { readonly evidence?: EvidenceResolver; readonly host?: AdaptiveCapabilities }
export interface AdaptiveEvidenceTrace { readonly providedToHost: readonly ContextCitation[]; readonly excerptSources: readonly ContextCitation[] }
interface AdaptiveResultBase { readonly operation: AdaptiveOperation; readonly plannedRoute: AdaptiveRoute; readonly evidence: AdaptiveEvidenceTrace; readonly hostMayStillBeProcessing: boolean }
export type AdaptiveSummary =
  | (AdaptiveResultBase & { readonly route: "native-assisted"; readonly kind: "host_text"; readonly text: string; readonly textOrigin: "host"; readonly degraded: false; readonly reason?: never })
  | (AdaptiveResultBase & { readonly route: "hybrid"; readonly kind: "host_text_with_evidence"; readonly text: string; readonly textOrigin: "host"; readonly degraded: false; readonly reason?: never })
  | (AdaptiveResultBase & { readonly route: "local-deterministic"; readonly kind: "local_excerpt"; readonly text: string; readonly textOrigin: "local"; readonly degraded: boolean; readonly reason?: AdaptiveReason })
  | (AdaptiveResultBase & { readonly route: "unavailable"; readonly kind: "unavailable"; readonly reason: AdaptiveReason; readonly text?: never; readonly textOrigin?: never; readonly degraded?: never });

const invalid = () => err("INVALID_INPUT", "Invalid adaptive summary request.");
const missing = () => err("NOT_FOUND", "Unknown evidence reference.");
const unsupported = () => err("UNSUPPORTED_SCHEMA", "Unsupported evidence record.");
const storage = () => err("STORAGE_ERROR", "Evidence lookup failed.");
const isObject = (v: unknown): v is object => (typeof v === "object" && v !== null) || typeof v === "function";
const own = (obj: object, key: PropertyKey): PropertyDescriptor | undefined => Object.getOwnPropertyDescriptor(obj, key);
const data = (d: PropertyDescriptor | undefined): boolean => !!d && "value" in d;
type Prepared = { citation: ContextCitation; excerpt: string };

/** Summarizes explicitly selected caller text or trusted, locally resolved evidence.
 * The caller and resolver enforce authorization and redaction; this is not a sandbox.
 * A deadline does not cancel a host, retract disclosure, or interrupt synchronous code. */
export async function summarizeAdaptive(request: AdaptiveSummaryRequest, deps?: AdaptiveDependencies): Promise<Result<AdaptiveSummary>> {
  let operation: AdaptiveOperation, maxChars: number, text: string | undefined;
  let allowHost: boolean, allowFallback: boolean, timeout: number;
  let references: ContextCitation[] | undefined;
  try {
    if (!isObject(request)) return invalid();
    const op = own(request, "operation"), max = own(request, "maxChars"), td = own(request, "text"), refs = own(request, "references");
    const host = own(request, "allowHostDisclosure"), fallback = own(request, "allowDegradedFallback"), deadline = own(request, "timeoutMs");
    if (!data(op) || !data(max) || (td && !data(td)) || (refs && !data(refs)) || (host && !data(host)) || (fallback && !data(fallback)) || (deadline && !data(deadline))) return invalid();
    if (op!.value !== "local_excerpt" && op!.value !== "semantic_summary") return invalid();
    if (!Number.isInteger(max!.value) || max!.value < 1 || max!.value > 12000) return invalid();
    if (host && typeof host.value !== "boolean" || fallback && typeof fallback.value !== "boolean") return invalid();
    if (deadline && (!Number.isInteger(deadline.value) || deadline.value < 100 || deadline.value > 30000)) return invalid();
    operation = op!.value; maxChars = max!.value; allowHost = host?.value === true; allowFallback = fallback?.value === true; timeout = deadline?.value ?? 3000;
    if (!!td === !!refs || operation === "local_excerpt" && !!refs) return invalid();
    if (td) {
      if (typeof td.value !== "string" || td.value.length > 12000 || operation === "semantic_summary" && td.value.length === 0) return invalid();
      text = td.value;
    } else {
      if (!Array.isArray(refs!.value)) return invalid();
      const array = refs!.value;
      const length = own(array, "length");
      if (!data(length) || !Number.isInteger(length!.value) || length!.value < 1 || length!.value > 32) return invalid();
      references = []; const seen = new Set<string>(); let hasUnsupported = false;
      for (let i = 0; i < length!.value; i++) {
        const entry = own(array, String(i));
        if (!data(entry) || !isObject(entry!.value)) return invalid();
        const r = own(entry!.value, "ref"), k = own(entry!.value, "kind"), id = own(entry!.value, "id");
        if (!data(r) || !data(k) || !data(id) || !["note", "diary", "node", "edge"].includes(k!.value) || typeof id!.value !== "string" || id!.value.length < 1 || id!.value.length > 256 || /[\u0000-\u001f\u007f-\u009f]/.test(id!.value) || r!.value !== `${k!.value}:${id!.value}` || seen.has(r!.value)) return invalid();
        seen.add(r!.value); if (k!.value === "node" || k!.value === "edge") hasUnsupported = true;
        references.push(Object.freeze({ ref: r!.value, kind: k!.value, id: id!.value }));
      }
      if (hasUnsupported) return unsupported();
    }
  } catch { return invalid(); }

  const plannedRoute: AdaptiveRoute = operation === "local_excerpt" ? "local-deterministic" : allowHost ? references ? "hybrid" : "native-assisted" : allowFallback ? "local-deterministic" : "unavailable";
  const trace = (provided: readonly ContextCitation[], sources: readonly ContextCitation[]): AdaptiveEvidenceTrace => Object.freeze({ providedToHost: Object.freeze([...provided]), excerptSources: Object.freeze([...sources]) });
  const base = (provided: readonly ContextCitation[] = [], sources: readonly ContextCitation[] = [], pending = false) => ({ operation, plannedRoute, evidence: trace(provided, sources), hostMayStillBeProcessing: pending });
  if (operation === "local_excerpt") return ok({ ...base(), route: "local-deterministic", kind: "local_excerpt", text: text!.slice(0, maxChars), textOrigin: "local", degraded: false });
  if (!allowHost && !allowFallback) return ok({ ...base(), route: "unavailable", kind: "unavailable", reason: "disclosure_denied" });

  const prepared: Prepared[] = [];
  if (references) {
    let resolver: unknown;
    try { if (isObject(deps)) { const d = own(deps, "evidence"); if (data(d)) { if (typeof d!.value !== "function") return storage(); resolver = d!.value; } } } catch { /* inaccessible resolver */ }
    if (typeof resolver !== "function") return ok({ ...base(), route: "unavailable", kind: "unavailable", reason: "hybrid_unsupported" });
    let budget = 12000;
    for (const citation of references) {
      let content: string;
      try {
        const outcome: unknown = Reflect.apply(resolver, undefined, [citation.kind, citation.id]);
        // Resolver results are synchronous; the trusted resolver owns any asynchronous work.
        if (utilTypes.isPromise(outcome)) return storage();
        if (!isObject(outcome)) return storage();
        const status = own(outcome, "status");
        if (!data(status)) return storage();
        if (status!.value === "missing") return missing();
        if (status!.value === "unsupported_schema") return unsupported();
        if (status!.value !== "found") return storage();
        const found = own(outcome, "content");
        if (!data(found) || typeof found!.value !== "string") return storage();
        content = found!.value;
      } catch { return storage(); }
      if (!content.trim()) return missing();
      const room = budget - (prepared.length ? 1 : 0);
      if (room > 0) { const excerpt = content.slice(0, room); prepared.push({ citation, excerpt }); budget -= excerpt.length + (prepared.length > 1 ? 1 : 0); }
    }
  }
  let localText = text ?? ""; const localSources: ContextCitation[] = [];
  if (references) {
    localText = "";
    for (const item of prepared) {
      const room = maxChars - localText.length - (localText.length ? 1 : 0);
      if (room <= 0) break;
      const part = item.excerpt.slice(0, room);
      if (part) { if (localText.length) localText += "\n"; localText += part; localSources.push(item.citation); }
    }
  } else localText = localText.slice(0, maxChars);
  const fail = (reason: AdaptiveReason, provided: readonly ContextCitation[] = [], pending = false): Result<AdaptiveSummary> => allowFallback
    ? ok({ ...base(provided, localSources, pending), route: "local-deterministic", kind: "local_excerpt", text: localText, textOrigin: "local", degraded: true, reason })
    : ok({ ...base(provided, [], pending), route: "unavailable", kind: "unavailable", reason });
  if (!allowHost) return fail("disclosure_denied");

  let callback: unknown; let reason: AdaptiveReason = "capability_absent";
  try {
    const descriptor = isObject(deps) ? own(deps, "host") : undefined;
    if (descriptor && !data(descriptor)) reason = "capability_malformed";
    else if (data(descriptor) && descriptor!.value != null) {
      if (!isObject(descriptor!.value)) reason = "capability_malformed";
      else {
        const cap = own(descriptor!.value, references ? "summarizeEvidence" : "summarize");
        if (cap && (!data(cap) || typeof cap.value !== "function")) reason = "capability_malformed";
        else if (cap) callback = cap.value;
      }
    }
  } catch { reason = "capability_malformed"; }
  if (typeof callback !== "function") return fail(reason);
  const provided = references ? prepared.map(p => p.citation) : [];
  const payload = references
    ? Object.freeze({ evidence: Object.freeze(prepared.map(p => Object.freeze({ id: p.citation.id, kind: p.citation.kind, excerpt: p.excerpt }))), maxChars })
    : Object.freeze({ text: text!, maxChars });
  type HostOutcome = { kind: "value"; value: unknown } | { kind: "failed" } | { kind: "timeout" };
  const outcome = await new Promise<HostOutcome>(resolve => {
    let done = false;
    const finish = (value: HostOutcome) => { if (!done) { done = true; clearTimeout(timer); resolve(value); } };
    const timer = setTimeout(() => finish({ kind: "timeout" }), timeout);
    try { Promise.resolve(Reflect.apply(callback as Function, undefined, [payload])).then(value => finish({ kind: "value", value }), () => finish({ kind: "failed" })); }
    catch { finish({ kind: "failed" }); }
  });
  if (outcome.kind === "timeout") return fail("timeout", provided, true);
  if (outcome.kind === "failed") return fail("host_failed", provided);
  if (typeof outcome.value !== "string" || !outcome.value.length || outcome.value.length > maxChars) return fail("host_output_invalid", provided);
  if (references) return ok({ ...base(provided), route: "hybrid", kind: "host_text_with_evidence", text: outcome.value, textOrigin: "host", degraded: false });
  return ok({ ...base(), route: "native-assisted", kind: "host_text", text: outcome.value, textOrigin: "host", degraded: false });
}
