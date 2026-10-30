import { err, ok, type Result } from "../utils/result.js";

export interface HostCapabilities {
  readonly summarize?: (request: Readonly<{ text: string; maxChars: number }>) => Promise<string>;
}

export interface HostSummaryRequest {
  readonly text: string;
  readonly maxChars: number;
  readonly allowHostDisclosure: boolean;
}

export interface HostSummaryResult {
  readonly text: string;
  readonly source: "host" | "local";
}

/**
 * Optionally disclose caller-selected text to a trusted host. Permission must be
 * explicit; callers choose and redact the text and authorize the provider.
 * Unavailable or failed providers produce a UTF-16 local excerpt, not a
 * semantic summary. A provider that never settles leaves this promise pending;
 * the host owns deadlines and any cancellation. This is not a sandbox.
 */
export async function summarizeWithHost(
  request: HostSummaryRequest,
  capabilities?: HostCapabilities
): Promise<Result<HostSummaryResult>> {
  let text: unknown, maxChars: unknown, permission: unknown;
  try {
    if (typeof request !== "object" || request === null) return err("INVALID_INPUT", "Invalid host summary request.");
    const textDescriptor = Object.getOwnPropertyDescriptor(request, "text");
    const maxDescriptor = Object.getOwnPropertyDescriptor(request, "maxChars");
    const permissionDescriptor = Object.getOwnPropertyDescriptor(request, "allowHostDisclosure");
    if (!textDescriptor || !("value" in textDescriptor) || !maxDescriptor || !("value" in maxDescriptor)
      || !permissionDescriptor || !("value" in permissionDescriptor)) return err("INVALID_INPUT", "Invalid host summary request.");
    text = textDescriptor.value; maxChars = maxDescriptor.value; permission = permissionDescriptor.value;
  } catch {
    return err("INVALID_INPUT", "Invalid host summary request.");
  }
  if (typeof text !== "string" || text.length > 12000 || typeof maxChars !== "number"
    || !Number.isInteger(maxChars) || maxChars < 1 || maxChars > 12000 || typeof permission !== "boolean") {
    return err("INVALID_INPUT", "Invalid host summary request.");
  }
  const fallback: HostSummaryResult = { text: text.slice(0, maxChars), source: "local" };
  if (permission !== true) return ok(fallback);

  try {
    if ((typeof capabilities !== "object" && typeof capabilities !== "function") || capabilities === null) return ok(fallback);
    const descriptor = Object.getOwnPropertyDescriptor(capabilities, "summarize");
    if (!descriptor || !("value" in descriptor) || typeof descriptor.value !== "function") return ok(fallback);
    const payload = Object.freeze({ text, maxChars });
    const output: unknown = await Reflect.apply(descriptor.value, undefined, [payload]);
    if (typeof output === "string" && output.length > 0 && output.length <= maxChars) return ok({ text: output, source: "host" });
  } catch {
    // Provider failures are intentionally not disclosed or retried.
  }
  return ok(fallback);
}
