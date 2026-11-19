import { useEffect, useState } from 'react';
import { ActivityIndicator, FlatList, Pressable, StyleSheet, Text, View } from 'react-native';
import { getSupabase } from '../lib/supabase';
import { money } from '../lib/labels';
import type { CartItem } from '../lib/cart';

type Product = {
  product_id: string;
  distributor_id: string;
  distributor_name: string;
  product_name: string;
  unit: string;
  price: number;
  available: boolean;
};

type Props = {
  cartCount: number;
  onAdd: (product: Omit<CartItem, 'quantity'>) => void;
  onOpenBasket: () => void;
  onBack: () => void;
};

export default function Catalogue({ cartCount, onAdd, onOpenBasket, onBack }: Props) {
  const [items, setItems] = useState<Product[] | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    const supabase = getSupabase();
    if (!supabase) {
      setError('Konfigurasi Supabase belum diisi (lihat .env.example).');
      return;
    }
    supabase.rpc('browse_catalogue', { p_town_code: 'J' }).then(({ data, error: rpcError }) => {
      if (rpcError) setError(rpcError.message);
      else setItems((data as Product[]) ?? []);
    });
  }, []);

  return (
    <View style={styles.page}>
      <View style={styles.row}>
        <Pressable onPress={onBack}>
          <Text style={styles.link}>Kembali</Text>
        </Pressable>
        <Pressable onPress={onOpenBasket}>
          <Text style={styles.link}>Keranjang ({cartCount})</Text>
        </Pressable>
      </View>
      <Text style={styles.title}>Katalog Jayapura</Text>
      {error ? <Text style={styles.error}>{error}</Text> : null}
      {!error && items === null ? <ActivityIndicator /> : null}
      <FlatList
        data={items ?? []}
        keyExtractor={(item) => item.product_id}
        renderItem={({ item }) => (
          <View style={styles.card}>
            <Text style={styles.cardTitle}>{item.product_name}</Text>
            <Text style={styles.body}>
              {item.distributor_name} · {money(item.price)} / {item.unit}
            </Text>
            {item.available ? (
              <Pressable
                style={styles.button}
                onPress={() =>
                  onAdd({
                    productId: item.product_id,
                    distributorId: item.distributor_id,
                    distributorName: item.distributor_name,
                    name: item.product_name,
                    unit: item.unit,
                    price: item.price,
                  })
                }
              >
                <Text style={styles.buttonText}>Tambah</Text>
              </Pressable>
            ) : (
              <Text style={styles.note}>Tidak tersedia</Text>
            )}
          </View>
        )}
      />
    </View>
  );
}

const styles = StyleSheet.create({
  page: { flex: 1, padding: 16, gap: 12 },
  row: { flexDirection: 'row', justifyContent: 'space-between' },
  title: { fontSize: 24, fontWeight: '700', color: '#1d2623' },
  body: { fontSize: 15, color: '#1d2623' },
  note: { fontSize: 13, color: '#5d6661' },
  error: { fontSize: 15, color: '#9b3d2e' },
  link: { fontSize: 16, color: '#2c6b4f' },
  button: { backgroundColor: '#2c6b4f', padding: 10, borderRadius: 8, alignItems: 'center', marginTop: 6 },
  buttonText: { color: '#ffffff', fontSize: 15, fontWeight: '600' },
  card: { backgroundColor: '#ffffff', borderRadius: 10, padding: 14, marginBottom: 10, gap: 4 },
  cardTitle: { fontSize: 17, fontWeight: '600', color: '#1d2623' },
});
