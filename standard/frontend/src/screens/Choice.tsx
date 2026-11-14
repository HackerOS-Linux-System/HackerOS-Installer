import { SearchList } from '../components/ui';
import { boot, cfg, pickKeyboard, pickLocale, pickTimezone } from '../state';

export function LanguageScreen() {
  return (
    <SearchList
      items={boot()?.locales ?? []}
      value={cfg.locale}
      onPick={pickLocale}
      placeholder="Szukaj języka…"
    />
  );
}

export function KeyboardScreen() {
  return (
    <SearchList
      items={boot()?.keyboards ?? []}
      value={cfg.keyboard}
      onPick={pickKeyboard}
      placeholder="Szukaj układu klawiatury…"
    />
  );
}

export function TimezoneScreen() {
  return (
    <SearchList
      items={boot()?.timezones ?? []}
      value={cfg.timezone}
      onPick={pickTimezone}
      placeholder="Szukaj strefy czasowej…"
    />
  );
}
