/**
 * The offline queue (FR-29). Pure rules, so they can be tested without a device.
 *
 * Each action taken with no signal is stored with a client id and sent later through sync_action.
 * The server applies each client id once, so a retry is safe. A conflict or rejection is kept and
 * shown to the user with its reason; it is never dropped or applied silently.
 */

export type ActionKind = 'place_order' | 'transition' | 'dispute_photo' | 'payment_proof';

export type OutboxItem = {
  clientId: string;
  action: ActionKind;
  payload: Record<string, unknown>;
  createdAt: string;
  status: 'pending' | 'conflict' | 'rejected';
  reason: string | null;
};

export type SendResult = { status: 'applied' | 'duplicate' | 'conflict' | 'rejected'; reason: string | null };

/** Thrown by the sender when the action could not be sent now (no signal, server unreachable). */
export class RetryLater extends Error {}

export type Sender = (item: OutboxItem) => Promise<SendResult>;

export function enqueue(items: OutboxItem[], item: Omit<OutboxItem, 'status' | 'reason'>): OutboxItem[] {
  if (items.some((i) => i.clientId === item.clientId)) return items;
  return [...items, { ...item, status: 'pending', reason: null }];
}

/**
 * Sends the pending items in the order they were made. Stops at the first item that cannot be sent
 * now, so later items are not sent out of order. Applied items leave the queue. Conflicts and
 * rejections stay in the queue with the reason.
 */
export async function flush(items: OutboxItem[], send: Sender): Promise<{ items: OutboxItem[]; applied: number }> {
  let current = items;
  let applied = 0;
  for (const item of items) {
    if (item.status !== 'pending') continue;
    let result: SendResult;
    try {
      result = await send(item);
    } catch (err) {
      if (err instanceof RetryLater) break;
      throw err;
    }
    if (result.status === 'applied' || result.status === 'duplicate') {
      current = current.filter((i) => i.clientId !== item.clientId);
      applied += 1;
    } else {
      current = current.map((i) =>
        i.clientId === item.clientId ? { ...i, status: result.status === 'conflict' ? 'conflict' : 'rejected', reason: result.reason } : i,
      );
    }
  }
  return { items: current, applied };
}

export function pendingCount(items: OutboxItem[]): number {
  return items.filter((i) => i.status === 'pending').length;
}

/** Items the user must look at: conflicts and rejections. */
export function problemItems(items: OutboxItem[]): OutboxItem[] {
  return items.filter((i) => i.status !== 'pending');
}

/** The user removes a conflict or rejection after reading it. */
export function dismiss(items: OutboxItem[], clientId: string): OutboxItem[] {
  return items.filter((i) => i.clientId !== clientId);
}
