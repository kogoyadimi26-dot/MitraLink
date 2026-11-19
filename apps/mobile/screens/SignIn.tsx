import { useState } from 'react';
import { ActivityIndicator, Pressable, StyleSheet, Text, TextInput, View } from 'react-native';
import { sendCode, verifyCode } from '../lib/session';

type Props = { onSignedIn: () => void };

export default function SignIn({ onSignedIn }: Props) {
  const [step, setStep] = useState<'phone' | 'code'>('phone');
  const [phoneInput, setPhoneInput] = useState('');
  const [phone, setPhone] = useState<string | null>(null);
  const [code, setCode] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function requestCode() {
    setBusy(true);
    setError(null);
    const result = await sendCode(phoneInput);
    setBusy(false);
    if (result.error) {
      setError(result.error);
      return;
    }
    setPhone(result.phone);
    setStep('code');
  }

  async function checkCode() {
    if (!phone) return;
    setBusy(true);
    setError(null);
    const message = await verifyCode(phone, code);
    setBusy(false);
    if (message) {
      setError(message);
      return;
    }
    onSignedIn();
  }

  return (
    <View style={styles.page}>
      <Text style={styles.title}>Masuk</Text>
      {step === 'phone' ? (
        <>
          <Text style={styles.body}>Masukkan nomor HP. Kami akan mengirim kode lewat SMS.</Text>
          <TextInput
            style={styles.input}
            placeholder="0812 3456 7890"
            keyboardType="phone-pad"
            value={phoneInput}
            onChangeText={setPhoneInput}
          />
          <Pressable style={styles.button} onPress={requestCode} disabled={busy}>
            <Text style={styles.buttonText}>Kirim kode</Text>
          </Pressable>
        </>
      ) : (
        <>
          <Text style={styles.body}>Masukkan kode yang dikirim ke {phone}.</Text>
          <TextInput
            style={styles.input}
            placeholder="Kode dari SMS"
            keyboardType="number-pad"
            value={code}
            onChangeText={setCode}
          />
          <Pressable style={styles.button} onPress={checkCode} disabled={busy}>
            <Text style={styles.buttonText}>Masuk</Text>
          </Pressable>
          <Pressable onPress={() => setStep('phone')}>
            <Text style={styles.link}>Ganti nomor</Text>
          </Pressable>
        </>
      )}
      {busy ? <ActivityIndicator /> : null}
      {error ? <Text style={styles.error}>{error}</Text> : null}
    </View>
  );
}

const styles = StyleSheet.create({
  page: { flex: 1, padding: 16, gap: 12, justifyContent: 'center' },
  title: { fontSize: 26, fontWeight: '700', color: '#1d2623' },
  body: { fontSize: 16, color: '#1d2623' },
  error: { fontSize: 15, color: '#9b3d2e' },
  link: { fontSize: 16, color: '#2c6b4f', textAlign: 'center' },
  input: { borderWidth: 1, borderColor: '#dcd8cc', borderRadius: 8, padding: 12, fontSize: 17, backgroundColor: '#ffffff' },
  button: { backgroundColor: '#2c6b4f', padding: 14, borderRadius: 10, alignItems: 'center' },
  buttonText: { color: '#ffffff', fontSize: 17, fontWeight: '600' },
});
