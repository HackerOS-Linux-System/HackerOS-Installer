export function formatMiB(mb: number): string {
  if (mb >= 1024 * 1024) return (mb / 1024 / 1024).toFixed(1) + ' TiB';
  if (mb >= 1024) return (mb / 1024).toFixed(mb >= 10240 ? 0 : 1) + ' GiB';
  return mb + ' MiB';
}

/** Znaki przyjmowane w nazwie użytkownika/hosta (zgodnie z validate::is_valid_slug). */
export function isSlug(s: string): boolean {
  return /^[a-z][a-z0-9_-]{0,31}$/.test(s);
}

export function clamp(n: number, lo: number, hi: number): number {
  return Math.max(lo, Math.min(hi, n));
}
