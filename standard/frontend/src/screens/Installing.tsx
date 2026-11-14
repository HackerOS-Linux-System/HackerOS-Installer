import { For, Show, createSignal } from 'solid-js';
import { ProgressBar, Toggle } from '../components/ui';
import { progress } from '../state';

export default function Installing() {
  const [showLog, setShowLog] = createSignal(false);
  const recent = () => progress.steps.filter((s) => s.status !== 'skip').slice(-6);
  return (
    <div class="col">
      <ProgressBar percent={progress.percent} />
      <p class="lead">
        {progress.percent}%
        <Show when={progress.total > 0}> — krok {Math.min(progress.step + 1, progress.total)} z {progress.total}</Show>
      </p>
      <p class="muted">{progress.label || 'Przygotowanie…'}</p>
      <div class="results">
        <For each={recent()}>
          {(s) => <div class={'result ' + s.status}><span>{s.label}</span></div>}
        </For>
      </div>
      <Toggle on={showLog()} onChange={setShowLog} label="Pokaż log instalacji" />
      <Show when={showLog()}>
        <pre class="log">{progress.log_tail || '(log jest pusty)'}</pre>
      </Show>
      <p class="muted">Nie wyłączaj komputera. Okno można bezpiecznie zamknąć — instalacja działa w tle.</p>
    </div>
  );
}
