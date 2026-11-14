import { For, Show } from 'solid-js';
import { Button, Notice, Section, Toggle } from '../components/ui';
import { assignMount, boot, cfg, openGparted, rows, setRows } from '../state';
import { formatMiB } from '../lib/format';
import type { PartFs } from '../types';

const MOUNTS = ['/', '/boot', '/boot/efi', '/home', 'swap'];
const FS: PartFs[] = ['ext4', 'btrfs', 'xfs', 'vfat', 'swap'];

export default function Partitions() {
  return (
    <div class="col">
      <Notice kind="info">
        Wpisz punkt montowania (<b>/</b>, <b>/home</b>, <b>/boot</b>, <b>/boot/efi</b>, <b>swap</b>) albo wybierz go przyciskiem.
        Puste pole = partycja nie jest używana. Partycja <b>/</b> musi być sformatowana
        {boot()?.uefi ? '; w trybie UEFI potrzebna jest też /boot/efi (vfat)' : ''}
        {cfg.luks ? '; przy szyfrowaniu potrzebna jest osobna /boot' : ''}.
      </Notice>
      <Show
        when={rows.length > 0}
        fallback={
          <>
            <Notice kind="error">Na dysku nie ma partycji. Utwórz je (np. w GParted) i wróć do tego kroku.</Notice>
            <Show when={boot()?.gparted}><div class="row"><Button small onClick={() => void openGparted()}>Otwórz GParted</Button></div></Show>
          </>
        }
      >
        <For each={rows}>
          {(r, i) => (
            <Section title={r.device.replace('/dev/', '') + '  ·  ' + formatMiB(r.size_mb)} hint={r.text}>
              <div class="row wrap">
                <input
                  class="mp"
                  type="text"
                  placeholder="punkt montowania"
                  value={r.mountpoint}
                  onInput={(e) => setRows(i(), 'mountpoint', e.currentTarget.value)}
                />
                <For each={MOUNTS}>
                  {(m) => (
                    <button class={'chipbtn' + (r.mountpoint === m ? ' on' : '')} onClick={() => assignMount(i(), m)}>{m}</button>
                  )}
                </For>
              </div>
              <Show when={r.mountpoint.trim() !== ''}>
                <div class="row wrap">
                  <For each={FS}>
                    {(f) => (
                      <button class={'chipbtn' + (r.fs === f ? ' on' : '')} onClick={() => setRows(i(), 'fs', f)}>{f}</button>
                    )}
                  </For>
                </div>
                <Toggle
                  on={r.format}
                  onChange={(v) => setRows(i(), 'format', v)}
                  label={r.format ? 'Formatuj (dane zostaną usunięte)' : 'Zachowaj dane'}
                />
              </Show>
            </Section>
          )}
        </For>
      </Show>
    </div>
  );
}
