import { For, Show } from 'solid-js';
import { Button, Notice } from '../components/ui';
import { error, installOk, progress, reboot, retryInstall } from '../state';

const PREFIX: Record<string, string> = { ok: 'OK', warn: 'OSTRZEŻENIE', fail: 'BŁĄD' };

export default function Done() {
  const tail = () => progress.error_text.split('\n').filter((l) => l.trim() !== '').slice(-8);
  return (
    <div class="col">
      <Show
        when={installOk()}
        fallback={
          <>
            <Notice kind="error">Instalacja nie powiodła się.</Notice>
            <Show when={progress.failed_label}>
              <p class="error-text">Błąd w kroku: {progress.failed_label} (kod wyjścia {progress.failed_code})</p>
            </Show>
            <Show when={error()}><p class="error-text">{error()}</p></Show>
            <Show when={tail().length > 0}>
              <pre class="log"><For each={tail()}>{(l) => <>{l + '\n'}</>}</For></pre>
            </Show>
          </>
        }
      >
        <Notice kind="ok">HackerOS został zainstalowany. Możesz uruchomić komputer ponownie.</Notice>
      </Show>

      <div class="results">
        <For each={progress.steps.filter((s) => s.status !== 'skip')}>
          {(s) => <div class={'result ' + s.status}><span>{(PREFIX[s.status] ?? '') + '  ' + s.label}</span></div>}
        </For>
      </div>
      <p class="muted">Pełny log: {progress.log_path || '/var/log/hackeros-installer.log'}</p>
      <Show when={progress.warnings > 0}>
        <p class="muted">Kroki oznaczone jako OSTRZEŻENIE były opcjonalne i nie powiodły się (np. brak sieci) — system jest zainstalowany.</p>
      </Show>

      <div class="row">
        <Show when={!installOk()}>
          <Button kind="primary" onClick={() => void retryInstall()}>Wznów instalację od miejsca błędu</Button>
        </Show>
        <Button kind={installOk() ? 'primary' : 'ghost'} onClick={() => void reboot()}>Uruchom ponownie</Button>
      </div>
    </div>
  );
}
