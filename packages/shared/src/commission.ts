/**
 * Commission calculation. Rules: BR-02, BR-03, BR-04, FR-17.
 *
 * Confirmed by the founder: the minimum applies once per order, not per line.
 *
 * Rounding is per category: all order lines in one category are added together,
 * the category rate is applied to that total (rounded half up), and the category
 * commissions are summed. The minimum is applied once to the order total:
 *
 *   commission = max( sum over categories of round(categoryValue × rate), minimum )
 *
 * The database function calculate_order_commission uses the same rule.
 * Only the server may set a stored commission. The apps may call this to show
 * an estimate (BR-04).
 */

import { applyBasisPoints, assertRupiah, type Rupiah } from './money';
import { rateFor, type BusinessConfig, type CategoryId } from './config';

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
  /** One entry per category, matching commission_lines in the database. */
  lines: CommissionLine[];
  /** Sum of category commissions before the minimum. */
  subtotalCommission: Rupiah;
  /** Commission charged for the order. */
  commission: Rupiah;
  /** True when the minimum raised the commission (minimum_applied). */
  minimumApplied: boolean;
  /** Order value: sum of line values. */
  orderValue: Rupiah;
}

export function calculateOrderCommission(lines: readonly OrderLine[], config: BusinessConfig): OrderCommission {
  if (lines.length === 0) {
    throw new Error('An order must have at least one line');
  }

  // Group by category first, so rounding happens once per category.
  const totals = new Map<CategoryId, Rupiah>();
  for (const line of lines) {
    assertRupiah(line.lineValue, 'lineValue');
    totals.set(line.category, (totals.get(line.category) ?? 0) + line.lineValue);
  }

  const commissionLines: CommissionLine[] = [...totals.entries()].map(([category, basisAmount]) => {
    const rateBp = rateFor(config, category);
    return {
      category,
      rateBp,
      basisAmount,
      commissionAmount: applyBasisPoints(basisAmount, rateBp),
    };
  });

  const orderValue = lines.reduce((sum, line) => sum + line.lineValue, 0);
  const subtotalCommission = commissionLines.reduce((sum, line) => sum + line.commissionAmount, 0);
  const commission = Math.max(subtotalCommission, config.minimumCommission);

  return {
    lines: commissionLines,
    subtotalCommission,
    commission,
    minimumApplied: commission !== subtotalCommission,
    orderValue,
  };
}
