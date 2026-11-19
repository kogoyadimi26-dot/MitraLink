/**
 * Order codes: `PDC-<TOWN>-<NNNN>`, for example PDC-W-0001 (product spec section 9).
 * Codes are unique and never reused. The sequence is per town.
 */

const TOWN_CODE = /^[A-Z]{1,2}$/;

export class OrderCodeError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'OrderCodeError';
  }
}

export function formatOrderCode(townCode: string, sequence: number): string {
  if (!TOWN_CODE.test(townCode)) {
    throw new OrderCodeError(`Town code must be one or two capital letters, got "${townCode}"`);
  }
  if (!Number.isSafeInteger(sequence) || sequence < 1) {
    throw new OrderCodeError(`Sequence must be a positive whole number, got ${sequence}`);
  }
  return `PDC-${townCode}-${String(sequence).padStart(4, '0')}`;
}

const ORDER_CODE = /^PDC-([A-Z]{1,2})-(\d{4,})$/;

export function parseOrderCode(code: string): { townCode: string; sequence: number } {
  const match = ORDER_CODE.exec(code);
  if (!match) {
    throw new OrderCodeError(`Not a valid order code: "${code}"`);
  }
  return { townCode: match[1] as string, sequence: Number(match[2]) };
}
