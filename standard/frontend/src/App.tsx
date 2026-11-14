import { For, Match, Show, Switch, onCleanup, onMount } from 'solid-js';
import { Button, Notice } from './components/ui';
import Account from './screens/Account';
import { KeyboardScreen, LanguageScreen, TimezoneScreen } from './screens/Choice';
import Disk from './screens/Disk';
import Done from './screens/Done';
import Installing from './screens/Installing';
import Network from './screens/Network';
import Partitions from './screens/Partitions';
import Profile from './screens/Profile';
import Summary from './screens/Summary';
import Welcome from './screens/Welcome';
import { boot, booted, busy, cfg, error, go, init, notice, step, stepMeta } from './state';
import { Step } from './types';

function Sidebar() {
  // Krok „Partycje” pokazujemy tylko w trybie ręcznym.
  const visible = () => (boot()?.steps ?? []).filter((s) => s.index !== Step.Partitions || cfg.partition_mode === 'manual');
  return (
    <aside class="sidebar">
      <div class="brand">
        <div class="logo">H</div>
        <div>
          <div class="brand-name">HackerOS</div>
          <div class="brand-sub">Instalator · Standard</div>
        </div>
      </div>
      <nav class="steps">
        <For each={visible()}>
          {(s, n) => (
            <div class={'stepitem' + (s.index === step() ? ' active' : '') + (s.index < step() ? ' done' : '')}>
              <span class="dot">{s.index < step() ? '✓' : String(n() + 1)}</span>
              <span class="steplabel">{s.title}</span>
            </div>
          )}
        </For>
      </nav>
      <div class="sidebar-foot">
        <Show when={boot()}>{(b) => <span>rdzeń {b().coreVersion} · {b().uefi ? 'UEFI' : 'BIOS'}</span>}</Show>
      </div>
    </aside>
  );
}

function Screen() {
  return (
    <Switch>
      <Match when={step() === Step.Welcome}><Welcome /></Match>
      <Match when={step() === Step.Language}><LanguageScreen /></Match>
      <Match when={step() === Step.Keyboard}><KeyboardScreen /></Match>
      <Match when={step() === Step.Timezone}><TimezoneScreen /></Match>
      <Match when={step() === Step.Network}><Network /></Match>
      <Match when={step() === Step.Disk}><Disk /></Match>
      <Match when={step() === Step.Partitions}><Partitions /></Match>
      <Match when={step() === Step.Profile}><Profile /></Match>
      <Match when={step() === Step.Account}><Account /></Match>
      <Match when={step() === Step.Summary}><Summary /></Match>
      <Match when={step() === Step.Installing}><Installing /></Match>
      <Match when={step() === Step.Done}><Done /></Match>
    </Switch>
  );
}

export default function App() {
  const onKey = (e: KeyboardEvent) => {
    if (e.key === 'Enter' && stepMeta()?.can_next) void go('next');
  };
  onMount(() => {
    void init();
    window.addEventListener('keydown', onKey);
  });
  onCleanup(() => window.removeEventListener('keydown', onKey));

  const nextLabel = () => (step() === Step.Summary ? 'Zainstaluj' : step() === Step.Welcome ? 'Rozpocznij' : 'Dalej');

  return (
    <div class="app">
      <Sidebar />
      <main class="main">
        <Show when={booted()} fallback={<div class="body"><p class="muted">Ładowanie…</p></div>}>
          <header class="head">
            <h1>{stepMeta()?.title ?? ''}</h1>
            <p>{stepMeta()?.subtitle ?? ''}</p>
          </header>
          <div class="body">
            <Show when={notice()}><Notice kind="info">{notice()}</Notice></Show>
            <Screen />
          </div>
          <Show when={error() && step() !== Step.Done}><div class="errorbar"><Notice kind="error">{error()}</Notice></div></Show>
          <Show when={stepMeta()?.can_back || stepMeta()?.can_next}>
            <footer class="foot">
              <div>
                <Show when={stepMeta()?.can_back}>
                  <Button disabled={busy()} onClick={() => void go('back')}>Wstecz</Button>
                </Show>
              </div>
              <Show when={stepMeta()?.can_next}>
                <Button kind="primary" disabled={busy()} onClick={() => void go('next')}>{nextLabel()}</Button>
              </Show>
            </footer>
          </Show>
        </Show>
      </main>
    </div>
  );
}
