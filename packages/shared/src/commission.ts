/**
 * Commission calculation. Rules: BR-02, BR-03, BR-04, FR-17.
 *
 * Confirmed by the founder: the minimum applies once per order, not per line.
 * For an order with several categories, each line's commission is calculated,
 * the lines are summed, and the minimum is applied to the total:
 *
 *   commission = max( sum(line commissions), minimumCommission )
 *
 * Only the server may call this to set a stored commission. The apps may call
 * it to display an estimate (BR-04).
 */

import { applyBasisPoints, assertRupiah, type Rupiah } from './money.js';
import { rateFor, type BusinessConfig, type CategoryId } from './config.js';

export interface OrderLine {
  category: CategoryId;
  /** Line value in rupiah: unit price × quantity. */
  lineValue: Rupiah;
}

export interface CommissionLine {
  category: CategoryId;
  rateBp: number;
  basisAmount: Rupiah;
  commissionAmount: Rupiah;
}

export interface OrderCommission {
  lines: CommissionLine[];
  /** Sum of line commissions before the minimum. */
  subtotalCommission: Rupiah;
  /** Commission charged for the order. */
  commission: Rupiah;
  /** True when the minimum raised the commission (FR-17, minimum_applied). */
  minimumApplied: boolean;
  /** Order value: sum of line values. */
  orderValue: Rupiah;
}

export function calculateOrderCommission(lines: readonly OrderLine[], config: BusinessConfig): OrderCommission {
  if (lines.length === 0) {
    throw new Error('An order must have at least one line');
  }

  const commissionLines: CommissionLine[] = lines.map((line) => {
    assertRupiah(line.lineValue, 'lineValue');
    const rateBp = rateFor(config, line.category);
    return {
      category: line.category,
      rateBp,
      basisAmount: line.lineValue,
      commissionAmount: applyBasisPoints(line.lineValue, rateBp),
    };
  });

  const orderValue = lines.reduce((sum, line) => sum + line.lineValue, 0);
  const subtotalCommission = commissionLines.reduce((sum, line) => sum + line.commissionAmount, 0);
  const minimum = config.minimumCommission;
  const commission = Math.max(subtotalCommission, minimum);

  return {
    lines: commissionLines,
    subtotalCommission,
    commission,
    minimumApplied: commission !== subtotalCommission,
    orderValue,
  };
}
