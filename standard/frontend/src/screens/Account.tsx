import { Field, Section, StrengthMeter, Toggle } from '../components/ui';
import { cfg, setCfg } from '../state';
import { isSlug } from '../lib/format';

export default function Account() {
  return (
    <div class="col">
      <Section title="Komputer i użytkownik">
        <Field
          label="Nazwa hosta"
          value={cfg.hostname}
          placeholder="hackeros"
          onInput={(v) => setCfg('hostname', v)}
          error={cfg.hostname !== '' && !isSlug(cfg.hostname) ? 'Małe litery, cyfry, „-” i „_”; zacznij od litery.' : undefined}
        />
        <Field
          label="Nazwa użytkownika"
          value={cfg.username}
          onInput={(v) => setCfg('username', v)}
          error={cfg.username !== '' && !isSlug(cfg.username) ? 'Małe litery, cyfry, „-” i „_”; zacznij od litery.' : undefined}
        />
        <Field label="Imię i nazwisko (opcjonalnie)" value={cfg.full_name} onInput={(v) => setCfg('full_name', v)} />
        <Field label="Hasło" type="password" value={cfg.password} onInput={(v) => setCfg('password', v)} />
        <StrengthMeter password={cfg.password} />
        <Field
          label="Powtórz hasło"
          type="password"
          value={cfg.password_confirm}
          onInput={(v) => setCfg('password_confirm', v)}
          error={cfg.password_confirm !== '' && cfg.password_confirm !== cfg.password ? 'Hasła nie są takie same.' : undefined}
        />
        <Toggle on={cfg.is_admin} onChange={(v) => setCfg('is_admin', v)} label="Konto administratora (sudo)" />
      </Section>

      <Section title="Konto roota" hint="Zostaw puste, aby zablokować logowanie na roota (zalecane — używaj sudo).">
        <Field label="Hasło roota (opcjonalnie)" type="password" value={cfg.root_password} onInput={(v) => setCfg('root_password', v)} />
        <Field
          label="Powtórz hasło roota"
          type="password"
          value={cfg.root_confirm}
          onInput={(v) => setCfg('root_confirm', v)}
          error={cfg.root_confirm !== '' && cfg.root_confirm !== cfg.root_password ? 'Hasła nie są takie same.' : undefined}
        />
      </Section>
    </div>
  );
}
