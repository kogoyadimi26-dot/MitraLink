import { useState } from 'react';
import { ActivityIndicator, Pressable, ScrollView, StyleSheet, Text, TextInput, View } from 'react-native';
import { normalizeIndonesianPhone } from '@mitralink/shared';
import { getSupabase } from '../lib/supabase';
import { currentPhone, currentUserId, TERMS_VERSION } from '../lib/session';

const BUSINESS_TYPES = [
  { code: 'kios', label: 'Kios' },
  { code: 'warung', label: 'Warung' },
  { code: 'sekolah', label: 'Sekolah' },
  { code: 'gereja', label: 'Gereja' },
  { code: 'lainnya', label: 'Lainnya' },
];
const TOWNS = [
  { code: 'J', label: 'Jayapura' },
  { code: 'W', label: 'Wamena' },
];

type Props = { onRegistered: () => void };

/** First-time registration for a buyer after sign-in (FR-02). The database checks everything else. */
export default function RegisterBuyer({ onRegistered }: Props) {
  const [fullName, setFullName] = useState('');
  const [businessName, setBusinessName] = useState('');
  const [businessType, setBusinessType] = useState('kios');
  const [town, setTown] = useState('J');
  const [accepted, setAccepted] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function submit() {
    setError(null);
    if (!fullName.trim() || !businessName.trim()) {
      setError('Isi nama dan nama usaha.');
      return;
    }
    if (!accepted) {
      setError('Setujui syarat dan ketentuan untuk mendaftar.');
      return;
    }
    const supabase = getSupabase();
    const userId = await currentUserId();
    // Supabase stores the number without the leading +; the database needs +62 (profiles.phone).
    const phone = normalizeIndonesianPhone((await currentPhone()) ?? '');
    if (!supabase || !userId || !phone) {
      setError('Masuk dulu dengan nomor HP.');
      return;
    }
    setBusy(true);
    const { error: rpcError } = await supabase.rpc('register_buyer', {
      p_user_id: userId,
      p_phone: phone,
      p_full_name: fullName.trim(),
      p_business_name: businessName.trim(),
      p_business_type: businessType,
      p_town_code: town,
      p_terms_version: TERMS_VERSION,
    });
    setBusy(false);
    if (rpcError) {
      setError(rpcError.message);
      return;
    }
    onRegistered();
  }

  return (
    <ScrollView contentContainerStyle={styles.page}>
      <Text style={styles.title}>Daftar pembeli</Text>
      <Text style={styles.body}>Pendaftaran gratis. Isi data usaha Anda.</Text>

      <Text style={styles.label}>Nama Anda</Text>
      <TextInput style={styles.input} value={fullName} onChangeText={setFullName} placeholder="Nama lengkap" />

      <Text style={styles.label}>Nama usaha</Text>
      <TextInput style={styles.input} value={businessName} onChangeText={setBusinessName} placeholder="Kios Maju Jaya" />

      <Text style={styles.label}>Jenis usaha</Text>
      <View style={styles.chips}>
        {BUSINESS_TYPES.map((t) => (
          <Pressable key={t.code} style={[styles.chip, businessType === t.code && styles.chipOn]} onPress={() => setBusinessType(t.code)}>
            <Text style={businessType === t.code ? styles.chipTextOn : styles.chipText}>{t.label}</Text>
          </Pressable>
        ))}
      </View>

      <Text style={styles.label}>Kota</Text>
      <View style={styles.chips}>
        {TOWNS.map((t) => (
          <Pressable key={t.code} style={[styles.chip, town === t.code && styles.chipOn]} onPress={() => setTown(t.code)}>
            <Text style={town === t.code ? styles.chipTextOn : styles.chipText}>{t.label}</Text>
          </Pressable>
        ))}
      </View>

      <Pressable style={styles.checkRow} onPress={() => setAccepted(!accepted)}>
        <Text style={styles.check}>{accepted ? '☑' : '☐'}</Text>
        <Text style={styles.body}>Saya setuju dengan syarat dan ketentuan MitraLink (versi {TERMS_VERSION}).</Text>
      </Pressable>

      {error ? <Text style={styles.error}>{error}</Text> : null}
      <Pressable style={styles.button} onPress={submit} disabled={busy}>
        {busy ? <ActivityIndicator color="#ffffff" /> : <Text style={styles.buttonText}>Daftar</Text>}
      </Pressable>
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  page: { padding: 16, gap: 10 },
  title: { fontSize: 24, fontWeight: '700', color: '#1d2623' },
  body: { fontSize: 15, color: '#1d2623', flexShrink: 1 },
  label: { fontSize: 14, color: '#5d6661', marginTop: 6 },
  error: { fontSize: 15, color: '#9b3d2e' },
  input: { borderWidth: 1, borderColor: '#dcd8cc', borderRadius: 8, padding: 12, fontSize: 16, backgroundColor: '#ffffff' },
  chips: { flexDirection: 'row', flexWrap: 'wrap', gap: 8 },
  chip: { borderWidth: 1, borderColor: '#2c6b4f', borderRadius: 16, paddingVertical: 6, paddingHorizontal: 12 },
  chipOn: { backgroundColor: '#2c6b4f' },
  chipText: { color: '#2c6b4f', fontSize: 15 },
  chipTextOn: { color: '#ffffff', fontSize: 15 },
  checkRow: { flexDirection: 'row', gap: 8, alignItems: 'flex-start', marginTop: 8 },
  check: { fontSize: 20, color: '#2c6b4f' },
  button: { backgroundColor: '#2c6b4f', padding: 14, borderRadius: 10, alignItems: 'center', marginTop: 8 },
  buttonText: { color: '#ffffff', fontSize: 17, fontWeight: '600' },
});
