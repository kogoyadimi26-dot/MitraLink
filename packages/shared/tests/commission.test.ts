import { describe, expect, it } from 'vitest';
import { calculateOrderCommission } from '../src/commission.js';
import { TEST_PHASE_CONFIG, type BusinessConfig } from '../src/config.js';

describe('calculateOrderCommission (FR-17)', () => {
  it('applies the Rp25,000 minimum to a Rp1,000,000 staples order', () => {
    // 1.5% of 1,000,000 is 15,000, below the minimum, so the minimum applies.
    const result = calculateOrderCommission([{ category: 'staples', lineValue: 1_000_000 }], TEST_PHASE_CONFIG);
    expect(result.subtotalCommission).toBe(15_000);
    expect(result.commission).toBe(25_000);
    expect(result.minimumApplied).toBe(true);
  });

  it('charges the percentage on a Rp2,000,000 electronics order', () => {
    // 2% of 2,000,000 is 40,000, above the minimum.
    const result = calculateOrderCommission([{ category: 'electronics_tools', lineValue: 2_000_000 }], TEST_PHASE_CONFIG);
    expect(result.commission).toBe(40_000);
    expect(result.minimumApplied).toBe(false);
  });

  it('applies the minimum once per order, after summing the lines', () => {
    // Staples 1,000,000 at 1.5% = 15,000. School 500,000 at 3% = 15,000. Sum = 30,000.
    // The minimum is not reached by the sum, so 30,000 is charged, not 50,000.
    const result = calculateOrderCommission(
      [
        { category: 'staples', lineValue: 1_000_000 },
        { category: 'school_office', lineValue: 500_000 },
      ],
      TEST_PHASE_CONFIG,
    );
    expect(result.lines.map((l) => l.commissionAmount)).toEqual([15_000, 15_000]);
    expect(result.subtotalCommission).toBe(30_000);
    expect(result.commission).toBe(30_000);
    expect(result.minimumApplied).toBe(false);
    expect(result.orderValue).toBe(1_500_000);
  });

  it('applies the minimum when several small lines sum below it', () => {
    // Two lines of 100,000 staples = 1,500 each. Sum 3,000. Minimum 25,000 applies once.
    const result = calculateOrderCommission(
      [
        { category: 'staples', lineValue: 100_000 },
        { category: 'staples', lineValue: 100_000 },
      ],
      TEST_PHASE_CONFIG,
    );
    expect(result.subtotalCommission).toBe(3_000);
    expect(result.commission).toBe(25_000);
    expect(result.minimumApplied).toBe(true);
  });

  it('always returns whole rupiah and never less than the minimum', () => {
    for (let value = 1; value <= 3_000_000; value += 99_991) {
      for (const category of ['staples', 'school_office', 'household', 'electronics_tools'] as const) {
        const result = calculateOrderCommission([{ category, lineValue: value }], TEST_PHASE_CONFIG);
        expect(Number.isInteger(result.commission)).toBe(true);
        expect(result.commission).toBeGreaterThanOrEqual(TEST_PHASE_CONFIG.minimumCommission);
      }
    }
  });

  it('refuses restricted goods (BR-03)', () => {
    expect(() => calculateOrderCommission([{ category: 'restricted', lineValue: 100_000 }], TEST_PHASE_CONFIG)).toThrow(
      /restricted/,
    );
  });

  it('refuses an empty order and fractional line values', () => {
    expect(() => calculateOrderCommission([], TEST_PHASE_CONFIG)).toThrow(/at least one line/);
    expect(() => calculateOrderCommission([{ category: 'staples', lineValue: 1.5 }], TEST_PHASE_CONFIG)).toThrow();
  });

  it('uses the configured minimum, not a hard-coded one', () => {
    const config: BusinessConfig = { ...TEST_PHASE_CONFIG, minimumCommission: 30_000 };
    const result = calculateOrderCommission([{ category: 'staples', lineValue: 1_000_000 }], config);
    expect(result.commission).toBe(30_000);
  });
});
