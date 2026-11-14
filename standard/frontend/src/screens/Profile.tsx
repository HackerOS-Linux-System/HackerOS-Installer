import { Show } from 'solid-js';
import { Notice, OptionList, Section, Toggle } from '../components/ui';
import { boot, cfg, net, profiles, setCfg } from '../state';

export default function Profile() {
  const current = () => profiles().find((p) => p.id === cfg.profile);
  return (
    <div class="col">
      <Section title="Zestaw oprogramowania">
        <OptionList
          items={profiles()}
          selected={(p) => p.id === cfg.profile}
          onSelect={(p) => setCfg('profile', p.id)}
          label={(p) => p.label}
          sub={(p) => p.description}
          tag={(p) => (p.needs_network ? 'wymaga sieci' : undefined)}
        />
        <Show when={current()?.needs_network && !net.online}>
          <Notice kind="warn">Komputer jest offline — pakiety profilu nie zostaną pobrane (instalacja i tak się powiedzie, z ostrzeżeniem).</Notice>
        </Show>
        <Show when={current() && current()!.packages.length > 0}>
          <p class="muted">Pakiety: {current()!.packages.join(', ')}</p>
        </Show>
      </Section>

      <Section title="Narzędzia programistyczne" hint="Opcjonalne, wymagają sieci.">
        <Toggle
          on={cfg.install_hsharp}
          onChange={(v) => setCfg('install_hsharp', v)}
          label={'Zainstaluj kompilator H# ' + (boot()?.hsharpVersion ?? '')}
        />
        <Toggle
          on={cfg.install_bit}
          onChange={(v) => setCfg('install_bit', v)}
          label={'Zainstaluj menedżer pakietów bit ' + (boot()?.bitVersion ?? '')}
        />
        <Show when={(cfg.install_hsharp || cfg.install_bit) && !net.online}>
          <Notice kind="warn">Komputer jest offline — te narzędzia nie zostaną pobrane (instalacja i tak się powiedzie).</Notice>
        </Show>
      </Section>
    </div>
  );
}
