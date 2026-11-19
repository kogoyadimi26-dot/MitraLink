import { getSupabase } from './supabase';

/**
 * The signed-in user's id, or null. Sign-in is not built yet (waits for D-001), so this is null
 * until it is, and the screens then ask the user to sign in instead of failing.
 */
export async function currentUserId(): Promise<string | null> {
  const supabase = getSupabase();
  if (!supabase) return null;
  const { data } = await supabase.auth.getSession();
  return data.session?.user.id ?? null;
}
