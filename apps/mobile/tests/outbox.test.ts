import { describe, expect, it } from 'vitest';
import { dismiss, enqueue, flush, pendingCount, problemItems, RetryLater, type OutboxItem, type Sender } from '../lib/outbox';

const base = { payload: {}, createdAt: '2026-12-01T08:00:00Z' };
const item = (id: string, action: OutboxItem['action'] = 'transition'): OutboxItem => ({
  ...base,
  clientId: id,
  action,
  status: 'pending',
  reason: null,
});

describe('enqueue', () => {
  it('adds an item once; the same client id is not queued twice', () => {
    let q = enqueue([], { ...item('a') });
    q = enqueue(q, { ...item('a') });
    expect(q).toHaveLength(1);
    expect(pendingCount(q)).toBe(1);
  });
});

describe('flush', () => {
  it('sends in order and removes applied and duplicate items', async () => {
    const sent: string[] = [];
    const send: Sender = async (i) => {
      sent.push(i.clientId);
      return { status: i.clientId === 'b' ? 'duplicate' : 'applied', reason: null };
    };
    const q = [item('a'), item('b'), item('c')];
    const out = await flush(q, send);
    expect(sent).toEqual(['a', 'b', 'c']);
    expect(out.items).toHaveLength(0);
    expect(out.applied).toBe(3);
  });

  it('keeps a conflict with its reason and does not drop it', async () => {
    const send: Sender = async () => ({ status: 'conflict', reason: 'Order was cancelled' });
    const out = await flush([item('a')], send);
    expect(out.items).toHaveLength(1);
    expect(out.items[0]?.status).toBe('conflict');
    expect(out.items[0]?.reason).toBe('Order was cancelled');
    expect(problemItems(out.items)).toHaveLength(1);
    expect(pendingCount(out.items)).toBe(0);
  });

  it('keeps a rejected item too', async () => {
    const send: Sender = async () => ({ status: 'rejected', reason: 'Not your order' });
    const out = await flush([item('a')], send);
    expect(out.items[0]?.status).toBe('rejected');
  });

  it('stops at the first item that cannot be sent now, keeping the rest in order', async () => {
    const sent: string[] = [];
    const send: Sender = async (i) => {
      sent.push(i.clientId);
      if (i.clientId === 'b') throw new RetryLater('offline');
      return { status: 'applied', reason: null };
    };
    const out = await flush([item('a'), item('b'), item('c')], send);
    expect(sent).toEqual(['a', 'b']);
    expect(out.items.map((i) => i.clientId)).toEqual(['b', 'c']);
    expect(pendingCount(out.items)).toBe(2);
  });

  it('does not send problem items again', async () => {
    const sent: string[] = [];
    const send: Sender = async (i) => {
      sent.push(i.clientId);
      return { status: 'applied', reason: null };
    };
    const q: OutboxItem[] = [{ ...item('a'), status: 'conflict', reason: 'x' }, item('b')];
    await flush(q, send);
    expect(sent).toEqual(['b']);
  });
});

describe('dismiss', () => {
  it('removes a problem item the user has read', () => {
    const q: OutboxItem[] = [{ ...item('a'), status: 'conflict', reason: 'x' }, item('b')];
    expect(dismiss(q, 'a').map((i) => i.clientId)).toEqual(['b']);
  });
});
