import { Pressable, StyleSheet, Text, View } from 'react-native';
import { pendingCount, problemItems, type OutboxItem } from '../lib/outbox';

const ACTION_TEXT: Record<string, string> = {
  place_order: 'Pesanan',
  transition: 'Perubahan status',
  dispute_photo: 'Foto masalah',
  payment_proof: 'Bukti bayar',
};

type Props = {
  items: OutboxItem[];
  syncing: boolean;
  onRetry: () => void;
  onDismiss: (clientId: string) => void;
};

/** Shows what is waiting to be sent, and any conflicts or rejections the user must read (FR-30, FR-29). */
export default function SyncStatus({ items, syncing, onRetry, onDismiss }: Props) {
  const waiting = pendingCount(items);
  const problems = problemItems(items);
  if (waiting === 0 && problems.length === 0) {
    return <Text style={styles.ok}>Semua sudah tersinkron</Text>;
  }
  return (
    <View style={styles.box}>
      {waiting > 0 ? (
        <View style={styles.row}>
          <Text style={styles.body}>{waiting} menunggu sinkron {syncing ? '(mengirim...)' : ''}</Text>
          <Pressable onPress={onRetry}>
            <Text style={styles.link}>Kirim ulang</Text>
          </Pressable>
        </View>
      ) : null}
      {problems.map((p) => (
        <View key={p.clientId} style={styles.problem}>
          <Text style={styles.body}>
            {ACTION_TEXT[p.action] ?? p.action} tidak dapat diterapkan
            {p.status === 'conflict' ? ' (sudah berubah di server)' : ''}
          </Text>
          {p.reason ? <Text style={styles.note}>{p.reason}</Text> : null}
          <Pressable onPress={() => onDismiss(p.clientId)}>
            <Text style={styles.link}>Mengerti</Text>
          </Pressable>
        </View>
      ))}
    </View>
  );
}

const styles = StyleSheet.create({
  box: { backgroundColor: '#f7ecd6', borderRadius: 10, padding: 10, gap: 6, marginHorizontal: 16, marginTop: 8 },
  row: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center' },
  problem: { gap: 2, borderTopWidth: 1, borderTopColor: '#dcd8cc', paddingTop: 6 },
  ok: { fontSize: 13, color: '#2c6b4f', marginHorizontal: 16, marginTop: 8 },
  body: { fontSize: 15, color: '#1d2623' },
  note: { fontSize: 13, color: '#5d6661' },
  link: { fontSize: 15, color: '#2c6b4f', fontWeight: '600' },
});
