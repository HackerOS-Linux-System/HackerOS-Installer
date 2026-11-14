export interface Strength { score: 0 | 1 | 2 | 3 | 4; label: string }

export function passwordStrength(pw: string): Strength {
  if (pw.length === 0) return { score: 0, label: '' };
  let points = 0;
  if (pw.length >= 8) points++;
  if (pw.length >= 12) points++;
  if (/[a-z]/.test(pw) && /[A-Z]/.test(pw)) points++;
  if (/\d/.test(pw)) points++;
  if (/[^A-Za-z0-9]/.test(pw)) points++;
  if (pw.length < 6) points = Math.min(points, 1);
  const score = Math.max(1, Math.min(4, points)) as 1 | 2 | 3 | 4;
  const label = ['', 'słabe', 'średnie', 'dobre', 'mocne'][score] ?? '';
  return { score, label };
}
