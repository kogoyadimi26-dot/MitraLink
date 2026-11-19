import { getSupabase } from './supabase';
import { RetryLater, type OutboxItem, type SendResult } from './outbox';

/**
 * Sends one queued action through the sync_action function. Business answers (applied, conflict,
 * rejected) come back as a status. A failed request is not an answer: it throws RetryLater, so the
 * item stays queued and is sent again later.
 */
export async function sendItem(item: OutboxItem): Promise<SendResult> {
  const supabase = getSupabase();
  if (!supabase) throw new RetryLater('not configured');
  const { data, error } = await supabase.rpc('sync_action', {
    p_client_id: item.clientId,
    p_action: item.action,
    p_payload: item.payload,
  });
  if (error || !data) throw new RetryLater(error?.message ?? 'no answer');
  const answer = data as { status: string; reason: string | null };
  return {
    status: answer.status as SendResult['status'],
    reason: answer.reason ?? null,
  };
}
