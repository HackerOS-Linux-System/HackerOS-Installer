import { For, Show, createMemo } from 'solid-js';
import { Button, DiskBar, Field, Notice, OptionList, Section, StrengthMeter, Toggle } from '../components/ui';
import { boot, cfg, diskInfo, disks, openGparted, osInfo, pickDisk, rescanOs, selectedDisk, setCfg } from '../state';
import { formatMiB } from '../lib/format';
import type { PartitionMode, RootFs } from '../types';

const MODES: { id: PartitionMode; label: string; sub: string }[] = [
  { id: 'auto', label: 'Wymaż cały dysk', sub: 'Najprostsza opcja. Cała zawartość wybranego dysku zostanie trwale usunięta.' },
  { id: 'alongside', label: 'Obok istniejących systemów', sub: 'Dual-boot: nowy system trafia do wolnego miejsca, istniejące partycje zostają nietknięte.' },
  { id: 'manual', label: 'Ręcznie', sub: 'Sam przypiszesz punkty montowania do istniejących partycji (następny ekran).' },
];

const FS: RootFs[] = ['ext4', 'btrfs', 'xfs'];

function partKind(fs: string, esp: boolean): string {
  if (esp) return 'esp';
  if (fs === 'swap') return 'swap';
  if (fs === 'ext4' || fs === 'btrfs' || fs === 'xfs') return 'linux';
  if (fs === '') return 'other';
  return 'win';
}

export default function Disk() {
  const bar = createMemo(() => {
    const parts = diskInfo.partitions.map((p) => ({
      label: p.device.replace('/dev/', ''), mb: p.size_mb, kind: partKind(p.fstype, p.is_esp),
    }));
    if (diskInfo.freeMb > 0) parts.push({ label: 'wolne', mb: diskInfo.freeMb, kind: 'free' });
    return parts;
  });
  const minMb = () => boot()?.alongsideMinMb ?? 20480;

  return (
    <div class="col">
      <Show when={disks().length > 0} fallback={<Notice kind="error">Nie wykryto żadnego dysku. Podłącz nośnik i uruchom instalator ponownie.</Notice>}>
        <Section title="Dysk instalacyjny">
          <OptionList
            items={disks()}
            selected={(d) => d.device === cfg.target_disk}
            onSelect={(d) => pickDisk(d.device)}
            label={(d) => d.device + (d.model ? '  ·  ' + d.model : '')}
            sub={(d) => d.size_gb + ' GB'}
            tag={(d) => (d.removable ? 'wymienny' : undefined)}
          />
        </Section>
      </Show>

      <Show when={cfg.target_disk !== ''}>
        <Show when={selectedDisk()?.removable}>
          <Notice kind="warn">To urządzenie jest oznaczone jako wymienne (USB?) — upewnij się, że to właściwy dysk.</Notice>
        </Show>

        <Show when={diskInfo.loaded && bar().length > 0}>
          <Section title="Układ dysku">
            <DiskBar parts={bar()} />
          </Section>
        </Show>

        <Section title="Wykryte systemy na tym dysku">
          <Show
            when={osInfo.systems.length > 0}
            fallback={
              <p class="muted">
                {osInfo.probing
                  ? 'Skanowanie…'
                  : osInfo.prober ? 'os-prober nie wykrył innych systemów na tym dysku.' : 'Brak os-prober — nie można wykryć innych systemów.'}
              </p>
            }
          >
            <For each={osInfo.systems}>{(s) => <p class="item">• {s.text}</p>}</For>
          </Show>
          <div class="row"><Button small onClick={() => void rescanOs()}>Skanuj systemy ponownie</Button></div>
        </Section>

        <Section title="Sposób partycjonowania">
          <OptionList
            items={MODES}
            selected={(m) => m.id === cfg.partition_mode}
            onSelect={(m) => setCfg('partition_mode', m.id)}
            label={(m) => m.label}
            sub={(m) => m.sub}
          />
          <Show when={cfg.partition_mode === 'auto'}>
            <Notice kind="error">Cała zawartość dysku {cfg.target_disk} zostanie trwale usunięta.</Notice>
          </Show>
          <Show when={cfg.partition_mode === 'alongside'}>
            <Notice kind={diskInfo.freeMb >= minMb() ? 'info' : 'error'}>
              Największy wolny obszar: <b>{formatMiB(diskInfo.freeMb)}</b> (wymagane co najmniej {formatMiB(minMb())}).
              {diskInfo.freeMb < minMb() ? ' Zmniejsz partycję innego systemu (np. w GParted).' : ' Istniejące partycje nie są ruszane.'}
            </Notice>
          </Show>
          <Show when={boot()?.gparted && cfg.partition_mode !== 'auto'}>
            <div class="row"><Button small onClick={() => void openGparted()}>Otwórz GParted</Button></div>
          </Show>
        </Section>

        <Show when={cfg.partition_mode !== 'manual'}>
          <Section title="System plików">
            <OptionList row items={FS} selected={(f) => f === cfg.filesystem} onSelect={(f) => setCfg('filesystem', f)} label={(f) => f} />
            <Toggle on={cfg.enable_swap} onChange={(v) => setCfg('enable_swap', v)} label="Plik wymiany (swap)" />
            <Show when={cfg.enable_swap}>
              <Field
                label="Rozmiar pliku wymiany (MiB)"
                value={cfg.swap_size_mb ? String(cfg.swap_size_mb) : ''}
                onInput={(v) => setCfg('swap_size_mb', parseInt(v.replace(/\D/g, ''), 10) || 0)}
                placeholder="2048"
              />
            </Show>
          </Section>
        </Show>

        <Section title="Szyfrowanie">
          <Toggle
            on={cfg.luks}
            onChange={(v) => setCfg('luks', v)}
            label="Zaszyfruj dysk (LUKS2)"
            hint={cfg.partition_mode === 'manual' ? 'Partycja / zostanie zaszyfrowana; potrzebna osobna /boot.' : 'Powstanie niezaszyfrowana partycja /boot (1 GiB). Hasło będzie wymagane przy każdym starcie.'}
          />
          <Show when={cfg.luks}>
            <Field label="Hasło szyfrowania (min. 8 znaków)" type="password" value={cfg.luks_password} onInput={(v) => setCfg('luks_password', v)} />
            <StrengthMeter password={cfg.luks_password} />
            <Field
              label="Powtórz hasło szyfrowania"
              type="password"
              value={cfg.luks_confirm}
              onInput={(v) => setCfg('luks_confirm', v)}
              error={cfg.luks_confirm !== '' && cfg.luks_confirm !== cfg.luks_password ? 'Hasła nie są takie same.' : undefined}
            />
          </Show>
        </Section>
      </Show>
    </div>
  );
}
