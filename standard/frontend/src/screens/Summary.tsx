import { For, Show } from 'solid-js';
import { Notice, Section, Toggle } from '../components/ui';
import { cfg, setCfg, setSummary, summary } from '../state';

function split(line: string): [string, string] | null {
  const k = line.indexOf(': ');
  if (k <= 0 || line.startsWith(' ')) return null;
  return [line.slice(0, k), line.slice(k + 2)];
}

export default function Summary() {
  const warning = () =>
    cfg.partition_mode === 'auto'
      ? 'Rozumiem, że dysk zostanie wymazany, i chcę kontynuować'
      : cfg.partition_mode === 'alongside'
        ? 'Rozumiem, że zmiany obejmą tablicę partycji i bootloader, i chcę kontynuować'
        : 'Rozumiem, że zaznaczone partycje zostaną sformatowane, i chcę kontynuować';

  return (
    <div class="col">
      <Section title="Podsumowanie">
        <div class="kv">
          <For each={summary.lines}>
            {(line) => {
              const kv = split(line);
              return kv ? (
                <div class="kv-row"><span class="k">{kv[0]}</span><span class="v">{kv[1]}</span></div>
              ) : (
                <div class="kv-row wide"><span class="v">{line}</span></div>
              );
            }}
          </For>
        </div>
      </Section>

      <Toggle
        on={summary.showPlan}
        onChange={(v) => setSummary('showPlan', v)}
        label={'Pokaż pełny plan instalacji (' + summary.plan.length + ' kroków)'}
      />
      <Show when={summary.showPlan}>
        <div class="plan">
          <For each={summary.plan}>{(l, i) => <p class="plan-line">{i() + 1}. {l}</p>}</For>
        </div>
      </Show>

      <Show when={cfg.resume_available}>
        <Notice kind="info">Wykryto przerwaną próbę instalacji dla dokładnie tej konfiguracji.</Notice>
        <Toggle
          on={cfg.resume}
          onChange={(v) => setCfg('resume', v)}
          label="Wznów poprzednią próbę (pomiń już wykonane kroki)"
          hint="Odznacz, aby zacząć od zera."
        />
      </Show>

      <Toggle on={cfg.accepted_summary} onChange={(v) => setCfg('accepted_summary', v)} label={warning()} />
    </div>
  );
}
