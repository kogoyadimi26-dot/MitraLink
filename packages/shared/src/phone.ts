/**
 * Indonesian mobile numbers in the form the database stores: +62 followed by 8 to 13 digits
 * (profiles.phone). Accepts 08..., 8..., 62..., +62... with spaces or dashes.
 */

const STORED = /^\+62[0-9]{8,13}$/;

/** Returns the stored form, or null if the input is not a valid Indonesian mobile number. */
export function normalizeIndonesianPhone(input: string): string | null {
  const digits = input.replace(/[\s\-().]/g, '');
  let national: string;
  if (digits.startsWith('+62')) {
    national = digits.slice(3);
  } else if (digits.startsWith('62')) {
    national = digits.slice(2);
  } else if (digits.startsWith('0')) {
    national = digits.slice(1);
  } else {
    national = digits;
  }
  if (!/^[0-9]+$/.test(national)) return null;
  const stored = `+62${national}`;
  return STORED.test(stored) ? stored : null;
}
