/**
 * Business configuration. Values the founder has not decided are `null`, and
 * code that needs them must refuse to run (build plan section 6).
 *
 * Decisions: see docs/decision-log.md (D-006, D-007, D-008).
 */

import { assertBasisPoints, assertRupiah, type BasisPoints, type Rupiah } from './money.js';

export type CategoryId = 'staples' | 'school_office' | 'household' | 'electronics_tools' | 'restricted';

export interface CategoryRate {
  id: CategoryId;
  /** Rate in basis points. `null` means the category is not allowed (restricted goods). */
  rateBp: BasisPoints | null;
}

export interface BusinessConfig {
  categories: readonly CategoryRate[];
  /** Minimum commission per confirmed order (BR-02). Confirmed at Rp25,000. */
  minimumCommission: Rupiah;
  /** Days after SHIP before automatic confirmation (BR-06, D-006). Null until decided. */
  autoConfirmDays: number | null;
  /** Days overdue before new orders are blocked (BR-10, D-007). Null until decided. */
  overdueBlockDays: number | null;
  /** Agent fee per confirmed order (BR-11, D-008). Null until decided. */
  agentFeePerOrder: Rupiah | null;
}

export class ConfigNotSetError extends Error {
  constructor(public readonly key: string) {
    super(`Configuration "${key}" has not been decided yet. See docs/decision-log.md.`);
    this.name = 'ConfigNotSetError';
  }
}

/** Test-phase defaults from docs/business-requirements.md section 5 (BR-02, BR-03). */
export const TEST_PHASE_CONFIG: BusinessConfig = {
  categories: [
    { id: 'staples', rateBp: 150 },
    { id: 'school_office', rateBp: 300 },
    { id: 'household', rateBp: 300 },
    { id: 'electronics_tools', rateBp: 200 },
    { id: 'restricted', rateBp: null },
  ],
  minimumCommission: 25000,
  autoConfirmDays: null,
  overdueBlockDays: null,
  agentFeePerOrder: null,
};

/** Returns a decided value, or throws so the caller cannot continue without it. */
export function requireDecided<K extends 'autoConfirmDays' | 'overdueBlockDays' | 'agentFeePerOrder'>(
  config: BusinessConfig,
  key: K,
): NonNullable<BusinessConfig[K]> {
  const value = config[key];
  if (value === null) {
    throw new ConfigNotSetError(key);
  }
  return value as NonNullable<BusinessConfig[K]>;
}

export function rateFor(config: BusinessConfig, category: CategoryId): BasisPoints {
  const entry = config.categories.find((c) => c.id === category);
  if (!entry) {
    throw new Error(`Unknown category: ${category}`);
  }
  if (entry.rateBp === null) {
    throw new Error(`Category "${category}" is restricted and cannot be sold on MitraLink (BR-03).`);
  }
  assertBasisPoints(entry.rateBp, `rate for ${category}`);
  return entry.rateBp;
}

export function validateConfig(config: BusinessConfig): void {
  assertRupiah(config.minimumCommission, 'minimumCommission');
  for (const c of config.categories) {
    if (c.rateBp !== null) {
      assertBasisPoints(c.rateBp, `rate for ${c.id}`);
    }
  }
  if (config.autoConfirmDays !== null && (!Number.isInteger(config.autoConfirmDays) || config.autoConfirmDays < 1)) {
    throw new Error('autoConfirmDays must be a positive whole number of days when set');
  }
  if (config.overdueBlockDays !== null && (!Number.isInteger(config.overdueBlockDays) || config.overdueBlockDays < 1)) {
    throw new Error('overdueBlockDays must be a positive whole number of days when set');
  }
  if (config.agentFeePerOrder !== null) {
    assertRupiah(config.agentFeePerOrder, 'agentFeePerOrder');
  }
}
