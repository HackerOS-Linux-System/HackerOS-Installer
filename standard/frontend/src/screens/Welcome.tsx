import { Show } from 'solid-js';
import { Button, Notice } from '../components/ui';
import { boot, loadResume } from '../state';
import { formatMiB } from '../lib/format';

export default function Welcome() {
  return (
    <div class="col">
      <p class="lead">
        Ten kreator przeprowadzi Cię przez instalację HackerOS (Standard Edition) na tym komputerze.
        Zajmie to kilka minut — w każdej chwili możesz wrócić do poprzedniego kroku.
      </p>
      <Show when={boot()}>
        {(b) => (
          <div class="chips">
            <span class="chip">{b().uefi ? 'Rozruch UEFI' : 'Rozruch BIOS / Legacy'}</span>
            <span class="chip">RAM: {formatMiB(b().ramMb)}</span>
            <span class="chip">Procesory: {b().cpus}</span>
            <span class="chip">Rdzeń instalatora {b().coreVersion}</span>
          </div>
        )}
      </Show>
      <Show when={boot()?.hasResume}>
        <Notice kind="warn">
          Znaleziono konfigurację przerwanej instalacji. Możesz ją wczytać — hasła trzeba będzie wpisać ponownie.
        </Notice>
        <div class="row"><Button kind="primary" onClick={() => void loadResume()}>Wznów przerwaną instalację</Button></div>
      </Show>
      <p class="muted">Kliknij „Dalej”, aby rozpocząć.</p>
    </div>
  );
}
