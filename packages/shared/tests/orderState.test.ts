import { describe, expect, it } from 'vitest';
import { checkTransition, isTerminal, nextStates, ORDER_STATES, TRANSITIONS } from '../src/orderState.js';

describe('order state machine (product spec section 3)', () => {
  it('allows the happy path in order', () => {
    expect(checkTransition('Placed', 'Accepted', 'distributor').ok).toBe(true);
    expect(checkTransition('Accepted', 'AwaitingPayment', 'system').ok).toBe(true);
    expect(checkTransition('AwaitingPayment', 'Paid', 'distributor').ok).toBe(true);
    expect(checkTransition('Paid', 'Shipped', 'distributor').ok).toBe(true);
    expect(checkTransition('Shipped', 'Confirmed', 'buyer').ok).toBe(true);
  });

  it('never allows shipping before payment (scenario 4, BR-05)', () => {
    expect(checkTransition('Accepted', 'Shipped', 'distributor').ok).toBe(false);
    expect(checkTransition('AwaitingPayment', 'Shipped', 'distributor').ok).toBe(false);
    expect(checkTransition('Placed', 'Shipped', 'distributor').ok).toBe(false);
  });

  it('lets only the buyer set RECEIVED, and the system auto-confirm (BR-12, BR-06)', () => {
    expect(checkTransition('Shipped', 'Confirmed', 'distributor').ok).toBe(false);
    expect(checkTransition('Shipped', 'Confirmed', 'agent').ok).toBe(false);
    expect(checkTransition('Shipped', 'Confirmed', 'system').ok).toBe(true);
  });

  it('lets only the distributor mark PAID and SHIP (BR-12)', () => {
    expect(checkTransition('AwaitingPayment', 'Paid', 'buyer').ok).toBe(false);
    expect(checkTransition('AwaitingPayment', 'Paid', 'agent').ok).toBe(false);
    expect(checkTransition('Paid', 'Shipped', 'buyer').ok).toBe(false);
  });

  it('lets the buyer raise a dispute and only admin resolve it (FR-15)', () => {
    expect(checkTransition('Shipped', 'Disputed', 'buyer').ok).toBe(true);
    expect(checkTransition('Shipped', 'Disputed', 'distributor').ok).toBe(false);
    expect(checkTransition('Disputed', 'Confirmed', 'admin').ok).toBe(true);
    expect(checkTransition('Disputed', 'Confirmed', 'distributor').ok).toBe(false);
  });

  it('rejects every transition not in the table', () => {
    const allowed = new Set(TRANSITIONS.map((r) => `${r.from}>${r.to}`));
    for (const from of ORDER_STATES) {
      for (const to of ORDER_STATES) {
        if (!allowed.has(`${from}>${to}`)) {
          const result = checkTransition(from, to, 'admin');
          expect(result.ok, `${from} to ${to} should be rejected`).toBe(false);
        }
      }
    }
  });

  it('has no way out of terminal states', () => {
    for (const state of ORDER_STATES.filter(isTerminal)) {
      expect(nextStates(state)).toEqual([]);
    }
  });

  it('reaches every non-initial state from Placed', () => {
    const reached = new Set<string>(['Placed']);
    const queue = ['Placed'];
    while (queue.length > 0) {
      const current = queue.shift() as (typeof ORDER_STATES)[number];
      for (const next of nextStates(current)) {
        if (!reached.has(next)) {
          reached.add(next);
          queue.push(next);
        }
      }
    }
    expect([...reached].sort()).toEqual([...ORDER_STATES].sort());
  });
});
