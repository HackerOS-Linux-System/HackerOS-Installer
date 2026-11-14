import { For, Show, createMemo, createSignal, type JSX } from 'solid-js';
import { passwordStrength } from '../lib/strength';

// ── drobne klocki interfejsu (zamiast ręcznie sklejanego HTML) ───────

export function Button(props: {
  kind?: 'primary' | 'ghost' | 'danger';
  disabled?: boolean;
  small?: boolean;
  onClick: () => void;
  children: JSX.Element;
}) {
  return (
    <button
      class={'btn ' + (props.kind ?? 'ghost') + (props.small ? ' small' : '') + (props.disabled ? ' disabled' : '')}
      onClick={() => { if (!props.disabled) props.onClick(); }}
    >
      {props.children}
    </button>
  );
}

export function Notice(props: { kind: 'info' | 'warn' | 'error' | 'ok'; children: JSX.Element }) {
  return <div class={'notice ' + props.kind}>{props.children}</div>;
}

export function Section(props: { title: string; hint?: string; children: JSX.Element }) {
  return (
    <section class="section">
      <h2>{props.title}</h2>
      <Show when={props.hint}><p class="muted">{props.hint}</p></Show>
      {props.children}
    </section>
  );
}

/** Lista wyboru jednokrotnego: jedna pozycja = jeden przycisk. */
export function OptionList<T>(props: {
  items: readonly T[];
  selected: (item: T) => boolean;
  onSelect: (item: T) => void;
  label: (item: T) => string;
  sub?: (item: T) => string | undefined;
  tag?: (item: T) => string | undefined;
  row?: boolean;
  empty?: string;
}) {
  return (
    <div class={props.row ? 'options row' : 'options'}>
      <For each={props.items} fallback={<p class="muted">{props.empty ?? 'Brak pozycji.'}</p>}>
        {(item) => (
          <button class={'option' + (props.selected(item) ? ' selected' : '')} onClick={() => props.onSelect(item)}>
            <span class="option-main">{props.label(item)}</span>
            <Show when={props.tag?.(item)}><span class="option-tag">{props.tag?.(item)}</span></Show>
            <Show when={props.sub?.(item)}><span class="option-sub">{props.sub?.(item)}</span></Show>
          </button>
        )}
      </For>
    </div>
  );
}

export function Toggle(props: { on: boolean; onChange: (v: boolean) => void; label: string; hint?: string }) {
  return (
    <button class={'toggle' + (props.on ? ' on' : '')} onClick={() => props.onChange(!props.on)}>
      <span class="switch"><span class="knob" /></span>
      <span class="toggle-text">
        <span class="toggle-label">{props.label}</span>
        <Show when={props.hint}><span class="toggle-hint">{props.hint}</span></Show>
      </span>
    </button>
  );
}

export function Field(props: {
  label: string;
  value: string;
  onInput: (v: string) => void;
  type?: 'text' | 'password';
  placeholder?: string;
  hint?: string;
  error?: string;
  maxlength?: number;
}) {
  return (
    <label class="field">
      <span class="field-label">{props.label}</span>
      <input
        class={props.error ? 'bad' : ''}
        type={props.type ?? 'text'}
        value={props.value}
        placeholder={props.placeholder ?? ''}
        maxlength={props.maxlength}
        onInput={(e) => props.onInput(e.currentTarget.value)}
      />
      <Show when={props.error}><span class="field-error">{props.error}</span></Show>
      <Show when={!props.error && props.hint}><span class="field-hint">{props.hint}</span></Show>
    </label>
  );
}

export function ProgressBar(props: { percent: number }) {
  return (
    <div class="bar">
      <div class="bar-fill" style={{ width: Math.max(0, Math.min(100, props.percent)) + '%' }} />
    </div>
  );
}

export function StrengthMeter(props: { password: string }) {
  const s = createMemo(() => passwordStrength(props.password));
  return (
    <Show when={props.password.length > 0}>
      <div class="strength">
        <For each={[1, 2, 3, 4]}>{(n) => <span class={'seg' + (n <= s().score ? ' s' + s().score : '')} />}</For>
        <span class="strength-label">{s().label}</span>
      </div>
    </Show>
  );
}

/** Lista z wyszukiwarką — język, klawiatura, strefa czasowa. */
export function SearchList(props: {
  items: readonly { code: string; label: string }[];
  value: string;
  onPick: (code: string) => void;
  placeholder: string;
}) {
  const [q, setQ] = createSignal('');
  const shown = createMemo(() => {
    const t = q().trim().toLowerCase();
    if (!t) return props.items;
    return props.items.filter((i) => i.label.toLowerCase().includes(t) || i.code.toLowerCase().includes(t));
  });
  return (
    <div class="searchlist">
      <input class="search" type="text" placeholder={props.placeholder} value={q()} onInput={(e) => setQ(e.currentTarget.value)} />
      <div class="options scrollbox">
        <For each={shown()} fallback={<p class="muted">Nic nie pasuje do „{q()}”.</p>}>
          {(i) => (
            <button class={'option' + (i.code === props.value ? ' selected' : '')} onClick={() => props.onPick(i.code)}>
              <span class="option-main">{i.label}</span>
              <span class="option-tag">{i.code}</span>
            </button>
          )}
        </For>
      </div>
      <p class="muted">{shown().length} z {props.items.length}</p>
    </div>
  );
}

/** Pasek ilustrujący układ dysku: partycje proporcjonalnie do rozmiaru. */
export function DiskBar(props: { parts: { label: string; mb: number; kind: string }[] }) {
  const total = createMemo(() => props.parts.reduce((a, p) => a + p.mb, 0) || 1);
  return (
    <div class="diskbar">
      <For each={props.parts}>
        {(p) => (
          <div class={'seg-part ' + p.kind} style={{ 'flex-grow': String(Math.max(p.mb / total(), 0.04)) }}>
            <span>{p.label}</span>
          </div>
        )}
      </For>
    </div>
  );
}
