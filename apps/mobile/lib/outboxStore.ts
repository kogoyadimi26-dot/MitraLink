import AsyncStorage from '@react-native-async-storage/async-storage';
import type { OutboxItem } from './outbox';

const KEY = 'mitralink.outbox.v1';

/** Reads the saved queue. A damaged or missing value starts an empty queue. */
export async function loadOutbox(): Promise<OutboxItem[]> {
  try {
    const raw = await AsyncStorage.getItem(KEY);
    return raw ? (JSON.parse(raw) as OutboxItem[]) : [];
  } catch {
    return [];
  }
}

export async function saveOutbox(items: OutboxItem[]): Promise<void> {
  try {
    await AsyncStorage.setItem(KEY, JSON.stringify(items));
  } catch {
    // Storage full or unavailable: the queue stays in memory for this session.
  }
}
