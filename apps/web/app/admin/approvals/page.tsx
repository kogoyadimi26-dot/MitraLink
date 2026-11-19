import { getSupabase } from '@/lib/supabase';

type Distributor = { id: string; business_name: string; approval_status: string; created_at: string };

export default async function ApprovalsPage() {
  const supabase = getSupabase();
  if (!supabase) {
    return <p>Konfigurasi Supabase belum diisi (lihat .env.example).</p>;
  }

  const { data, error } = await supabase
    .from('distributors')
    .select('id, business_name, approval_status, created_at')
    .eq('approval_status', 'pending')
    .order('created_at', { ascending: true });

  return (
    <section>
      <h1>Persetujuan distributor</h1>
      <p>Distributor yang menunggu persetujuan. Persetujuan dilakukan melalui fungsi approve_distributor.</p>
      {error ? (
        <p style={{ color: '#9b3d2e' }}>Tidak dapat memuat: {error.message}</p>
      ) : (data as Distributor[] | null)?.length ? (
        <ul>
          {(data as Distributor[]).map((d) => (
            <li key={d.id}>{d.business_name}</li>
          ))}
        </ul>
      ) : (
        <p>Tidak ada distributor yang menunggu.</p>
      )}
    </section>
  );
}
