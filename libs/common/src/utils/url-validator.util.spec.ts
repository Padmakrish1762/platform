import { isPrivateIp, validateDidWebDomain } from './url-validator.util';

describe('validateDidWebDomain', () => {
  it('accepts a plain public domain', () => {
    expect(validateDidWebDomain('issuer.example.com')).toEqual({ valid: true });
  });

  it('accepts a public domain with a port', () => {
    expect(validateDidWebDomain('issuer.example.com:8013')).toEqual({ valid: true });
  });

  it('accepts a public devtunnel-style domain', () => {
    expect(validateDidWebDomain('7wkh080x-9013.inc1.devtunnels.ms')).toEqual({ valid: true });
  });

  it('rejects localhost', () => {
    const result = validateDidWebDomain('localhost');
    expect(result.valid).toBe(false);
    expect(result.reason).toMatch(/loopback/i);
  });

  it('rejects the Docker bridge private IPv4 address that caused this bug (172.17.0.1)', () => {
    const result = validateDidWebDomain('172.17.0.1:8017');
    expect(result.valid).toBe(false);
    expect(result.reason).toMatch(/private\/internal/i);
  });

  it.each(['10.0.0.5', '172.16.0.1', '172.31.255.254', '192.168.1.1', '127.0.0.1'])(
    'rejects private/loopback IPv4 address %s',
    (ip) => {
      expect(validateDidWebDomain(ip).valid).toBe(false);
    }
  );

  it('rejects loopback IPv6 (::1)', () => {
    expect(validateDidWebDomain('::1').valid).toBe(false);
  });

  it('rejects bracketed loopback IPv6 ([::1]) with a port', () => {
    expect(validateDidWebDomain('[::1]:8013').valid).toBe(false);
  });

  it('rejects an empty domain', () => {
    expect(validateDidWebDomain('').valid).toBe(false);
  });

  it('rejects a malformed hostname', () => {
    expect(validateDidWebDomain('not a valid host!!').valid).toBe(false);
  });

  it('rejects a bare single-label hostname (no public TLD)', () => {
    expect(validateDidWebDomain('myagent').valid).toBe(false);
  });
});

describe('isPrivateIp', () => {
  it('is exported for reuse outside of isValidWebhookUrl', () => {
    expect(isPrivateIp('172.17.0.1')).toBe(true);
    expect(isPrivateIp('8.8.8.8')).toBe(false);
  });
});
