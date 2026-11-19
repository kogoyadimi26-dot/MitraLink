import { useCallback, useEffect, useRef, useState } from 'react';
import NetInfo from '@react-native-community/netinfo';
import { dismiss, enqueue, flush, type ActionKind, type OutboxItem } from './outbox';
import { loadOutbox, saveOutbox } from './outboxStore';
import { sendItem } from './outboxSync';
import { newClientId } from './cart';

/**
 * The phone's offline queue. Actions are saved at once and sent when the phone is online
 * (on start, when the connection returns, and on demand). onApplied runs after queued actions
 * reach the server, so screens can reload.
 */
export function useOutbox(onApplied: () => void) {
  const [items, setItems] = useState<OutboxItem[]>([]);
  const [syncing, setSyncing] = useState(false);
  const itemsRef = useRef<OutboxItem[]>([]);
  const busy = useRef(false);
  const appliedRef = useRef(onApplied);
  appliedRef.current = onApplied;

  const persist = useCallback((next: OutboxItem[]) => {
    itemsRef.current = next;
    setItems(next);
    saveOutbox(next);
  }, []);

  const flushNow = useCallback(async () => {
    if (busy.current) return;
    busy.current = true;
    setSyncing(true);
    try {
      const snapshot = itemsRef.current;
      const { items: next, applied } = await flush(snapshot, sendItem);
      // Keep anything queued while the flush was running, and apply the new state to the rest.
      const sentIds = new Set(snapshot.filter((s) => !next.some((n) => n.clientId === s.clientId)).map((s) => s.clientId));
      const updated = new Map(next.map((n) => [n.clientId, n]));
      persist(itemsRef.current.filter((i) => !sentIds.has(i.clientId)).map((i) => updated.get(i.clientId) ?? i));
      if (applied > 0) appliedRef.current();
    } finally {
      busy.current = false;
      setSyncing(false);
    }
  }, [persist]);

  // Load the saved queue, send it, and send again whenever the connection returns.
  useEffect(() => {
    let cancelled = false;
    loadOutbox().then((saved) => {
      if (cancelled) return;
      itemsRef.current = saved;
      setItems(saved);
      flushNow();
    });
    const unsubscribe = NetInfo.addEventListener((state) => {
      if (state.isConnected && state.isInternetReachable !== false) flushNow();
    });
    return () => {
      cancelled = true;
      unsubscribe();
    };
  }, [flushNow]);

  /** Queues an action and tries to send it now. Returns its client id. */
  const enqueueAction = useCallback(
    (action: ActionKind, payload: Record<string, unknown>): string => {
      const clientId = newClientId();
      persist(enqueue(itemsRef.current, { clientId, action, payload, createdAt: new Date().toISOString() }));
      flushNow();
      return clientId;
    },
    [persist, flushNow],
  );

  const dismissItem = useCallback((clientId: string) => persist(dismiss(itemsRef.current, clientId)), [persist]);

  return { items, syncing, enqueueAction, flushNow, dismissItem };
}
