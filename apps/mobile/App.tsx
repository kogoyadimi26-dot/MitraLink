import { useState } from 'react';
import { SafeAreaView, StyleSheet, Text, View, Pressable } from 'react-native';
import Catalogue from './screens/Catalogue';
import Basket from './screens/Basket';
import Orders from './screens/Orders';
import OrderDetail from './screens/OrderDetail';
import { addToCart, type CartItem } from './lib/cart';

type Screen =
  | { name: 'home' }
  | { name: 'catalogue' }
  | { name: 'basket' }
  | { name: 'orders' }
  | { name: 'order'; orderId: string };

export default function App() {
  const [screen, setScreen] = useState<Screen>({ name: 'home' });
  const [cart, setCart] = useState<CartItem[]>([]);
  // Bumped after an order changes, so the order list reloads.
  const [refreshKey, setRefreshKey] = useState(0);

  return (
    <SafeAreaView style={styles.safe}>
      {screen.name === 'home' ? (
        <Home
          onCatalogue={() => setScreen({ name: 'catalogue' })}
          onOrders={() => setScreen({ name: 'orders' })}
        />
      ) : null}
      {screen.name === 'catalogue' ? (
        <Catalogue
          cartCount={cart.reduce((n, i) => n + i.quantity, 0)}
          onAdd={(product) => setCart((items) => addToCart(items, product))}
          onOpenBasket={() => setScreen({ name: 'basket' })}
          onBack={() => setScreen({ name: 'home' })}
        />
      ) : null}
      {screen.name === 'basket' ? (
        <Basket
          cart={cart}
          onChange={setCart}
          onOrdersPlaced={(distributorIds) => {
            // Remove the lines of each distributor whose order was sent.
            setCart((items) => items.filter((i) => !distributorIds.includes(i.distributorId)));
            setRefreshKey((k) => k + 1);
          }}
          onBack={() => setScreen({ name: 'catalogue' })}
        />
      ) : null}
      {screen.name === 'orders' ? (
        <Orders
          refreshKey={refreshKey}
          onOpen={(orderId) => setScreen({ name: 'order', orderId })}
          onBack={() => setScreen({ name: 'home' })}
        />
      ) : null}
      {screen.name === 'order' ? (
        <OrderDetail
          orderId={screen.orderId}
          onChanged={() => setRefreshKey((k) => k + 1)}
          onBack={() => setScreen({ name: 'orders' })}
        />
      ) : null}
    </SafeAreaView>
  );
}

function Home({ onCatalogue, onOrders }: { onCatalogue: () => void; onOrders: () => void }) {
  return (
    <View style={styles.page}>
      <Text style={styles.title}>MitraLink</Text>
      <Text style={styles.body}>Pesan barang dari distributor di Jayapura dan Wamena.</Text>
      <Pressable style={styles.button} onPress={onCatalogue}>
        <Text style={styles.buttonText}>Lihat katalog</Text>
      </Pressable>
      <Pressable style={styles.buttonOutline} onPress={onOrders}>
        <Text style={styles.buttonOutlineText}>Pesanan saya</Text>
      </Pressable>
      <Text style={styles.note}>Masuk belum tersedia. Menunggu keputusan penyedia SMS (D-001).</Text>
    </View>
  );
}

const styles = StyleSheet.create({
  safe: { flex: 1, backgroundColor: '#f6f4ee' },
  page: { flex: 1, padding: 16, gap: 12 },
  title: { fontSize: 26, fontWeight: '700', color: '#1d2623' },
  body: { fontSize: 16, color: '#1d2623' },
  note: { fontSize: 13, color: '#5d6661' },
  button: { backgroundColor: '#2c6b4f', padding: 14, borderRadius: 10, alignItems: 'center' },
  buttonText: { color: '#ffffff', fontSize: 17, fontWeight: '600' },
  buttonOutline: { borderWidth: 1, borderColor: '#2c6b4f', padding: 14, borderRadius: 10, alignItems: 'center' },
  buttonOutlineText: { color: '#2c6b4f', fontSize: 17, fontWeight: '600' },
});
