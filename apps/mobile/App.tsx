import { useEffect, useState } from 'react';
import { ActivityIndicator, FlatList, Pressable, SafeAreaView, StyleSheet, Text, View } from 'react-native';
import { formatRupiah } from '@mitralink/shared';
import { getSupabase } from './lib/supabase';

type Product = {
  product_id: string;
  distributor_name: string;
  product_name: string;
  unit: string;
  price: number;
  available: boolean;
};

type Screen = 'home' | 'catalogue';

export default function App() {
  const [screen, setScreen] = useState<Screen>('home');
  return (
    <SafeAreaView style={styles.safe}>
      {screen === 'home' ? <Home onOpen={() => setScreen('catalogue')} /> : <Catalogue onBack={() => setScreen('home')} />}
    </SafeAreaView>
  );
}

function Home({ onOpen }: { onOpen: () => void }) {
  return (
    <View style={styles.page}>
      <Text style={styles.title}>MitraLink</Text>
      <Text style={styles.body}>Pesan barang dari distributor di Jayapura dan Wamena.</Text>
      <Pressable style={styles.button} onPress={onOpen}>
        <Text style={styles.buttonText}>Lihat katalog</Text>
      </Pressable>
      <Text style={styles.note}>Masuk belum tersedia. Menunggu keputusan penyedia SMS (D-001).</Text>
    </View>
  );
}

function Catalogue({ onBack }: { onBack: () => void }) {
  const [items, setItems] = useState<Product[] | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    const supabase = getSupabase();
    if (!supabase) {
      setError('Konfigurasi Supabase belum diisi (lihat .env.example).');
      return;
    }
    supabase
      .rpc('browse_catalogue', { p_town_code: 'J' })
      .then(({ data, error: rpcError }) => {
        if (rpcError) setError(rpcError.message);
        else setItems((data as Product[]) ?? []);
      });
  }, []);

  return (
    <View style={styles.page}>
      <Pressable onPress={onBack}>
        <Text style={styles.link}>Kembali</Text>
      </Pressable>
      <Text style={styles.title}>Katalog Jayapura</Text>
      {error ? <Text style={styles.error}>{error}</Text> : null}
      {!error && items === null ? <ActivityIndicator /> : null}
      {items && items.length === 0 ? <Text style={styles.body}>Belum ada produk. Masuk diperlukan untuk melihat katalog.</Text> : null}
      <FlatList
        data={items ?? []}
        keyExtractor={(item) => item.product_id}
        renderItem={({ item }) => (
          <View style={styles.card}>
            <Text style={styles.cardTitle}>{item.product_name}</Text>
            <Text style={styles.body}>
              {item.distributor_name} · {formatRupiah(item.price)} / {item.unit}
            </Text>
            {!item.available ? <Text style={styles.note}>Tidak tersedia</Text> : null}
          </View>
        )}
      />
    </View>
  );
}

const styles = StyleSheet.create({
  safe: { flex: 1, backgroundColor: '#f6f4ee' },
  page: { flex: 1, padding: 16, gap: 12 },
  title: { fontSize: 26, fontWeight: '700', color: '#1d2623' },
  body: { fontSize: 16, color: '#1d2623' },
  note: { fontSize: 13, color: '#5d6661' },
  error: { fontSize: 15, color: '#9b3d2e' },
  link: { fontSize: 16, color: '#2c6b4f' },
  button: { backgroundColor: '#2c6b4f', padding: 14, borderRadius: 10, alignItems: 'center' },
  buttonText: { color: '#ffffff', fontSize: 17, fontWeight: '600' },
  card: { backgroundColor: '#ffffff', borderRadius: 10, padding: 14, marginBottom: 10, gap: 4 },
  cardTitle: { fontSize: 17, fontWeight: '600', color: '#1d2623' },
});
