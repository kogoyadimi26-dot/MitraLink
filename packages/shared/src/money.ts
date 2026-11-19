/**
 * Money helpers. Business rule BR-15: amounts are whole rupiah, stored as
 * integers. Nothing in this module uses floating-point money.
 */

export type Rupiah = number;

/** Basis points: 1.5% is 150, 100% is 10000. */
export type BasisPoints = number;

export class MoneyError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'MoneyError';
  }
}

export function assertRupiah(value: number, label = 'amount'): asserts value is Rupiah {
  if (!Number.isSafeInteger(value)) {
    throw new MoneyError(`${label} must be a whole number of rupiah, got ${value}`);
  }
  if (value < 0) {
    throw new MoneyError(`${label} cannot be negative, got ${value}`);
  }
}

export function assertBasisPoints(value: number, label = 'rate'): asserts value is BasisPoints {
  if (!Number.isSafeInteger(value) || value < 0 || value > 10000) {
    throw new MoneyError(`${label} must be whole basis points between 0 and 10000, got ${value}`);
  }
}

/**
 * Applies a rate in basis points to an amount, rounding half up to whole rupiah.
 * Example: 1,000,000 at 150 bp gives 15,000. 1 at 5000 bp gives 1 (0.5 rounds up).
 */
export function applyBasisPoints(amount: Rupiah, rate: BasisPoints): Rupiah {
  assertRupiah(amount, 'amount');
  assertBasisPoints(rate);
  return Math.floor((amount * rate + 5000) / 10000);
}

/** Formats rupiah for display, e.g. 1000000 becomes "Rp1.000.000". */
export function formatRupiah(amount: Rupiah): string {
  assertRupiah(amount, 'amount');
  const digits = String(amount);
  let out = '';
  for (let i = 0; i < digits.length; i++) {
    const fromEnd = digits.length - i;
    out += digits[i];
    if (fromEnd > 1 && fromEnd % 3 === 1) {
      out += '.';
    }
  }
  return `Rp${out}`;
}
