import { describe, expect, it } from 'vitest';
import { normalizeIndonesianPhone } from '../src/phone';

describe('normalizeIndonesianPhone', () => {
  it('accepts the common ways of writing a number', () => {
    expect(normalizeIndonesianPhone('0812 3456 7890')).toBe('+6281234567890');
    expect(normalizeIndonesianPhone('812-3456-7890')).toBe('+6281234567890');
    expect(normalizeIndonesianPhone('+62 812 3456 7890')).toBe('+6281234567890');
    expect(normalizeIndonesianPhone('6281234567890')).toBe('+6281234567890');
  });

  it('refuses numbers that do not fit the stored format', () => {
    expect(normalizeIndonesianPhone('')).toBeNull();
    expect(normalizeIndonesianPhone('0812')).toBeNull();
    expect(normalizeIndonesianPhone('08123456789012345')).toBeNull();
    expect(normalizeIndonesianPhone('abc')).toBeNull();
  });
});
