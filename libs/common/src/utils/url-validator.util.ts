import { promises as dns } from 'dns';
import { Logger } from '@nestjs/common';

const { lookup } = dns;
const logger = new Logger('UrlValidator');

function sanitizeUrlForLog(rawUrl: string): string {
  try {
    const parsed = new URL(rawUrl);
    parsed.username = '';
    parsed.password = '';
    parsed.search = '';
    return `${parsed.origin}${parsed.pathname}`;
  } catch {
    return '<invalid-url>';
  }
}

export function isPrivateIp(ip: string): boolean {
  // IPv4-mapped IPv6: ::ffff:x.x.x.x
  const ipv4MappedMatch = ip.match(/^::ffff:(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})$/i);
  if (ipv4MappedMatch) {
    return isPrivateIp(ipv4MappedMatch[1]);
  }

  // IPv4 checks
  // 0.0.0.0/8 (Unspecified/This-Network)
  if (/^0\./.test(ip)) {
    return true;
  }

  // 100.64.0.0/10 (Shared Address Space / CGNAT)
  if (/^100\.(6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])\./.test(ip)) {
    return true;
  }

  // 127.0.0.0/8 (Loopback)
  if (/^127\./.test(ip)) {
    return true;
  }

  // 10.0.0.0/8 (Private)
  if (/^10\./.test(ip)) {
    return true;
  }

  // 172.16.0.0/12 (Private)
  // 172.16.x.x - 172.31.x.x
  if (/^172\.(1[6-9]|2[0-9]|3[0-1])\./.test(ip)) {
    return true;
  }

  // 192.168.0.0/16 (Private)
  if (/^192\.168\./.test(ip)) {
    return true;
  }

  // 169.254.0.0/16 (Link-Local)
  if (/^169\.254\./.test(ip)) {
    return true;
  }

  // IPv6 checks
  // ::1 / 0:0:0:0:0:0:0:1 (Loopback)
  if (/^(::1|0:0:0:0:0:0:0:1)$/i.test(ip)) {
    return true;
  }

  // :: / 0:0:0:0:0:0:0:0 (Unspecified)
  if (/^(::|0:0:0:0:0:0:0:0)$/i.test(ip)) {
    return true;
  }

  // fe80::/10 (Link-Local)
  if (/^fe80:/i.test(ip)) {
    return true;
  }

  // fc00::/7 (Unique Local Address)
  if (/^f[cd][0-9a-f]{2}:/i.test(ip)) {
    return true;
  }

  return false;
}

export async function isValidWebhookUrl(url: string): Promise<{ isSafe: boolean; resolvedIp?: string }> {
  // Allow local development based on environment variable
  if ('DEV' === process.env.PLATFORM_PROFILE_MODE) {
    logger.warn(`Skipping URL validation for ${sanitizeUrlForLog(url)} in DEV mode`);
    return { isSafe: true };
  }

  try {
    const parsedUrl = new URL(url);

    // 1. Enforce HTTPS
    if ('https:' !== parsedUrl.protocol) {
      logger.warn(`Blocked webhook URL with non-HTTPS protocol: ${sanitizeUrlForLog(url)}`);
      return { isSafe: false };
    }

    // 2. DNS Resolution and IP checking
    // We need to resolve the hostname to an IP address to check against private ranges
    const { address } = await lookup(parsedUrl.hostname);

    if (!address) {
      logger.warn(`Could not resolve hostname for URL: ${sanitizeUrlForLog(url)}`);
      return { isSafe: false };
    }

    if (isPrivateIp(address)) {
      logger.warn(`Blocked webhook URL resolving to private/internal IP: ${sanitizeUrlForLog(url)} -> ${address}`);
      return { isSafe: false };
    }

    return { isSafe: true, resolvedIp: address };
  } catch (error) {
    logger.error(`Error validating webhook URL: ${error.message}`);
    return { isSafe: false };
  }
}

const LOOPBACK_HOSTNAMES = new Set(['localhost', 'localhost.localdomain']);
// At least one dot - a bare single-label name is almost always an internal
// hostname rather than something with real public DNS delegation.
const HOSTNAME_REGEX = /^(?=.{1,253}$)(?:[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,63}$/;
const IPV4_LITERAL_REGEX = /^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/;

function stripDidWebPort(domain: string): string {
  if (domain.startsWith('[')) {
    const closeBracket = domain.indexOf(']');
    return -1 === closeBracket ? domain : domain.slice(0, closeBracket + 1);
  }
  // A bare IPv6 literal is itself made of multiple colons - only a single
  // colon unambiguously means "host:port" for a hostname/IPv4 address.
  if (2 <= (domain.match(/:/g) ?? []).length) {
    return domain;
  }
  const portMatch = /^(.*):(\d+)$/.exec(domain);
  return portMatch ? portMatch[1] : domain;
}

/**
 * Syntax/range check only - no DNS lookup, unlike isValidWebhookUrl above.
 * did:web domains are supplied once at DID-creation time and don't need
 * (and shouldn't pay the cost/flakiness of) a live network round-trip just
 * to validate the shape of the domain.
 */
export function validateDidWebDomain(domain: string): { valid: boolean; reason?: string } {
  if (!domain || !domain.trim()) {
    return { valid: false, reason: 'Domain is required' };
  }

  const host = stripDidWebPort(domain.trim());
  const unbracketedHost = host.startsWith('[') && host.endsWith(']') ? host.slice(1, -1) : host;

  if (LOOPBACK_HOSTNAMES.has(unbracketedHost.toLowerCase())) {
    return {
      valid: false,
      reason: `'${domain}' is a loopback address and cannot be used for did:web - did:web requires a publicly resolvable domain.`
    };
  }

  const isIpLiteral = unbracketedHost.includes(':') || IPV4_LITERAL_REGEX.test(unbracketedHost);
  if (isIpLiteral) {
    if (isPrivateIp(unbracketedHost)) {
      return {
        valid: false,
        reason: `'${domain}' is a private/internal or loopback IP address and cannot be used for did:web - did:web requires a publicly resolvable domain.`
      };
    }
    // A public IP literal (v4 or v6) is an unusual but valid did:web domain.
    return { valid: true };
  }

  if (!HOSTNAME_REGEX.test(unbracketedHost)) {
    return {
      valid: false,
      reason: `'${domain}' is not a valid hostname for did:web - expected a fully-qualified public domain name (e.g. 'issuer.example.com').`
    };
  }

  return { valid: true };
}
