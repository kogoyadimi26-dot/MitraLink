import { describe, expect, it } from 'vitest';
import { ConfigNotSetError, rateFor, requireDecided, TEST_PHASE_CONFIG, validateConfig } from '../src/config.js';
import { formatOrderCode, parseOrderCode, OrderCodeError } from '../src/orderCode.js';

describe('undecided configuration blocks code that needs it', () => {
  it('refuses to read the auto-confirm period until it is decided (D-006)', () => {
    expect(() => requireDecided(TEST_PHASE_CONFIG, 'autoConfirmDays')).toThrow(ConfigNotSetError);
  });

  it('refuses the overdue block period until decided (D-007)', () => {
    expect(() => requireDecided(TEST_PHASE_CONFIG, 'overdueBlockDays')).toThrow(ConfigNotSetError);
  });

  it('refuses the agent fee until decided (D-008)', () => {
    expect(() => requireDecided(TEST_PHASE_CONFIG, 'agentFeePerOrder')).toThrow(ConfigNotSetError);
  });

  it('returns the value once decided', () => {
    const config = { ...TEST_PHASE_CONFIG, autoConfirmDays: 7 };
    expect(requireDecided(config, 'autoConfirmDays')).toBe(7);
  });
});

describe('rates and validation', () => {
  it('returns the category rate in basis points', () => {
    expect(rateFor(TEST_PHASE_CONFIG, 'staples')).toBe(150);
    expect(rateFor(TEST_PHASE_CONFIG, 'school_office')).toBe(300);
    expect(rateFor(TEST_PHASE_CONFIG, 'electronics_tools')).toBe(200);
  });

  it('the test-phase config is valid and keeps the confirmed minimum', () => {
    expect(() => validateConfig(TEST_PHASE_CONFIG)).not.toThrow();
    expect(TEST_PHASE_CONFIG.minimumCommission).toBe(25_000);
  });

  it('rejects invalid decided values', () => {
    expect(() => validateConfig({ ...TEST_PHASE_CONFIG, autoConfirmDays: 0 })).toThrow();
    expect(() => validateConfig({ ...TEST_PHASE_CONFIG, overdueBlockDays: 2.5 })).toThrow();
    expect(() => validateConfig({ ...TEST_PHASE_CONFIG, agentFeePerOrder: -5000 })).toThrow();
  });
});

describe('order codes (product spec section 9)', () => {
  it('formats codes with a zero-padded four-digit sequence', () => {
    expect(formatOrderCode('W', 1)).toBe('PDC-W-0001');
    expect(formatOrderCode('J', 42)).toBe('PDC-J-0042');
    expect(formatOrderCode('W', 12345)).toBe('PDC-W-12345');
  });

  it('parses codes it formats', () => {
    expect(parseOrderCode('PDC-W-0001')).toEqual({ townCode: 'W', sequence: 1 });
  });

  it('rejects bad town codes and sequences', () => {
    expect(() => formatOrderCode('w', 1)).toThrow(OrderCodeError);
    expect(() => formatOrderCode('WAMENA', 1)).toThrow(OrderCodeError);
    expect(() => formatOrderCode('W', 0)).toThrow(OrderCodeError);
    expect(() => parseOrderCode('PDC-W-1')).toThrow(OrderCodeError);
  });
});
