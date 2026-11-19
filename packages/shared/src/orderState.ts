/**
 * Order state machine. Source: docs/product-spec.md section 3 (FR-09 to FR-16).
 *
 * Only transitions in the table are allowed. Anything else is rejected, and
 * every allowed transition must also write an OrderEvent on the server (BR-13).
 */

export const ORDER_STATES = [
  'Placed',
  'Accepted',
  'Declined',
  'AwaitingPayment',
  'Paid',
  'Shipped',
  'Confirmed',
  'Disputed',
  'Cancelled',
] as const;

export type OrderState = (typeof ORDER_STATES)[number];

/** Who may perform a transition. `system` covers automatic steps and jobs. */
export type Actor = 'buyer' | 'agent' | 'distributor' | 'admin' | 'system';

interface Rule {
  from: OrderState;
  to: OrderState;
  actors: readonly Actor[];
}

/**
 * Allowed transitions and who may trigger them (product spec section 3 table).
 * Note: Paid is reached only from AwaitingPayment, and Shipped only from Paid,
 * so a distributor cannot ship before payment is recorded (BR-05, FR-13).
 */
export const TRANSITIONS: readonly Rule[] = [
  { from: 'Placed', to: 'Accepted', actors: ['distributor'] },
  { from: 'Placed', to: 'Declined', actors: ['distributor'] },
  { from: 'Accepted', to: 'AwaitingPayment', actors: ['system'] },
  { from: 'AwaitingPayment', to: 'Paid', actors: ['distributor'] },
  { from: 'AwaitingPayment', to: 'Cancelled', actors: ['admin', 'system'] },
  { from: 'Paid', to: 'Shipped', actors: ['distributor'] },
  { from: 'Shipped', to: 'Confirmed', actors: ['buyer', 'system'] },
  { from: 'Shipped', to: 'Disputed', actors: ['buyer'] },
  { from: 'Disputed', to: 'Confirmed', actors: ['admin'] },
  { from: 'Disputed', to: 'Cancelled', actors: ['admin'] },
];

export const TERMINAL_STATES: readonly OrderState[] = ['Confirmed', 'Declined', 'Cancelled'];

export type TransitionResult = { ok: true } | { ok: false; reason: string };

export function checkTransition(from: OrderState, to: OrderState, actor: Actor): TransitionResult {
  const rule = TRANSITIONS.find((r) => r.from === from && r.to === to);
  if (!rule) {
    return { ok: false, reason: `Transition ${from} to ${to} is not allowed.` };
  }
  if (!rule.actors.includes(actor)) {
    return { ok: false, reason: `${actor} cannot move an order from ${from} to ${to}.` };
  }
  return { ok: true };
}

export function nextStates(from: OrderState): OrderState[] {
  return TRANSITIONS.filter((r) => r.from === from).map((r) => r.to);
}

export function isTerminal(state: OrderState): boolean {
  return TERMINAL_STATES.includes(state);
}
