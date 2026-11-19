import { describe, expect, it } from 'vitest';
import { applyBasisPoints, formatRupiah, MoneyError } from '../src/money.js';

describe('applyBasisPoints', () => {
  it('applies a percentage and rounds half up to whole rupiah', () => {
    expect(applyBasisPoints(1_000_000, 150)).toBe(15_000); // 1.5%
    expect(applyBasisPoints(2_000_000, 200)).toBe(40_000); // 2%
    expect(applyBasisPoints(1, 5000)).toBe(1); // 0.5 rounds up
    expect(applyBasisPoints(1, 4999)).toBe(0); // 0.4999 rounds down
  });

  it('always returns an integer', () => {
    for (let amount = 0; amount <= 2000; amount += 37) {
      for (const rate of [0, 150, 200, 300, 333]) {
        expect(Number.isInteger(applyBasisPoints(amount, rate))).toBe(true);
      }
    }
  });

  it('rejects fractional amounts and invalid rates', () => {
    expect(() => applyBasisPoints(10.5, 150)).toThrow(MoneyError);
    expect(() => applyBasisPoints(-1, 150)).toThrow(MoneyError);
    expect(() => applyBasisPoints(1000, 10001)).toThrow(MoneyError);
    expect(() => applyBasisPoints(1000, 1.5)).toThrow(MoneyError);
  });
});

describe('formatRupiah', () => {
  it('uses dots as thousands separators', () => {
    expect(formatRupiah(0)).toBe('Rp0');
    expect(formatRupiah(999)).toBe('Rp999');
    expect(formatRupiah(1000)).toBe('Rp1.000');
    expect(formatRupiah(25000)).toBe('Rp25.000');
    expect(formatRupiah(1_000_000)).toBe('Rp1.000.000');
    expect(formatRupiah(1_234_567_890)).toBe('Rp1.234.567.890');
  });
});
