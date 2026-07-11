// Runs before anything else; a "no" means zero observers, zero messaging.

const SENSITIVE_HOST_PATTERNS = [
  /bank/i,
  /paypal/i,
  /checkout/i,
  /payment/i,
  /\.gov$/i,
  /health/i,
  /medical/i,
  /pharma/i,
  /insurance/i,
  /login\./i,
  /accounts?\./i,
];

export interface GateInput {
  protocol: string;
  host: string;
  enabled: boolean;
  blockedHosts: string[];
  ambientItemCount: number;
}

export function shouldRunOnPage(input: GateInput): boolean {
  if (!input.enabled) return false;
  if (input.protocol !== "http:" && input.protocol !== "https:") return false;
  if (input.ambientItemCount === 0) return false;

  const host = input.host.toLowerCase();
  if (SENSITIVE_HOST_PATTERNS.some((p) => p.test(host))) return false;

  // User blocks apply per eTLD+1-ish suffix match.
  return !input.blockedHosts.some(
    (blocked) => host === blocked.toLowerCase() || host.endsWith("." + blocked.toLowerCase()),
  );
}

/** eTLD+1 approximation for event tagging (never full URLs — P3). */
export function coarseHost(hostname: string): string {
  const parts = hostname.toLowerCase().split(".");
  return parts.length <= 2 ? hostname.toLowerCase() : parts.slice(-2).join(".");
}
