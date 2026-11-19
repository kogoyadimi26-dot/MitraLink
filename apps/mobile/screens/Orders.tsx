import { useEffect, useState } from 'react';
import { ActivityIndicator, FlatList, Pressable, StyleSheet, Text, View } from 'react-native';
import { getSupabase } from '../lib/supabase';
import { STATE_LABEL, money } from '../lib/labels';

type OrderRow = { id: string; code: string; state: string; subtotal: number; created_at: string };

type Props = { onOpen: (orderId: string) => void; onBack: () => void; refreshKey: number };

export default function Orders({ onOpen, onBack, refreshKey }: Props) {
  const [orders, setOrders] = useState<OrderRow[] | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    const supabase = getSupabase();
    if (!supabase) {
      setError('Konfigurasi Supabase belum diisi (lihat .env.example).');
      return;
    }
    // Row-level security returns only the signed-in user's orders.
    supabase
      .from('orders')
      .select('id, code, state, subtotal, created_at')
      .order('created_at', { ascending: false })
      .then(({ data, error: queryError }) => {
        if (queryError) setError(queryError.message);
        else setOrders((data as OrderRow[]) ?? []);
      });
  }, [refreshKey]);

  return (
    <View style={styles.page}>
      <Pressable onPress={onBack}>
        <Text style={styles.link}>Kembali</Text>
      </Pressable>
      <Text style={styles.title}>Pesanan saya</Text>
      {error ? <Text style={styles.error}>{error}</Text> : null}
      {!error && orders === null ? <ActivityIndicator /> : null}
      {orders && orders.length === 0 ? <Text style={styles.body}>Belum ada pesanan.</Text> : null}
      <FlatList
        data={orders ?? []}
        keyExtractor={(item) => item.id}
        renderItem={({ item }) => (
          <Pressable style={styles.card} onPress={() => onOpen(item.id)}>
            <Text style={styles.cardTitle}>{item.code}</Text>
            <Text style={styles.body}>{STATE_LABEL[item.state] ?? item.state}</Text>
            <Text style={styles.note}>{money(item.subtotal)}</Text>
          </Pressable>
        )}
      />
    </View>
  );
}

const styles = StyleSheet.create({
  page: { flex: 1, padding: 16, gap: 12 },
  title: { fontSize: 24, fontWeight: '700', color: '#1d2623' },
  body: { fontSize: 15, color: '#1d2623' },
  note: { fontSize: 13, color: '#5d6661' },
  error: { fontSize: 15, color: '#9b3d2e' },
  link: { fontSize: 16, color: '#2c6b4f' },
  card: { backgroundColor: '#ffffff', borderRadius: 10, padding: 14, marginBottom: 10, gap: 4 },
  cardTitle: { fontSize: 17, fontWeight: '600', color: '#1d2623' },
});
