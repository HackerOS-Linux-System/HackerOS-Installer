import { Show } from 'solid-js';
import { Button, Field, Notice, OptionList, Section } from '../components/ui';
import { cfg, connectWifi, net, pickWifi, recheckNet, scanWifi, setCfg, setNet } from '../state';

export default function Network() {
  return (
    <div class="col">
      <Show
        when={net.online}
        fallback={
          <Notice kind="warn">
            Brak połączenia z Internetem. Możesz kontynuować offline (profil Minimalny) albo połączyć się poniżej.
          </Notice>
        }
      >
        <Notice kind="ok">Połączono z Internetem.</Notice>
      </Show>
      <div class="row"><Button small onClick={() => void recheckNet()}>Sprawdź ponownie</Button></div>

      <Show
        when={net.wifiAvailable}
        fallback={<p class="muted">Nie wykryto karty Wi-Fi albo brak NetworkManagera — użyj kabla sieciowego.</p>}
      >
        <Section title="Sieci Wi-Fi">
          <OptionList
            items={net.networks}
            selected={(n) => n.ssid === net.ssid}
            onSelect={pickWifi}
            label={(n) => n.ssid + (n.in_use ? '  ✓' : '')}
            sub={(n) => n.signal + '% · ' + (n.security === '' ? 'otwarta' : n.security)}
            empty={net.scanning ? 'Skanowanie…' : 'Nie znaleziono sieci. Kliknij „Skanuj ponownie”.'}
          />
          <Show when={net.ssid !== '' && !net.open}>
            <Field label={'Hasło do sieci ' + net.ssid} type="password" value={net.password} onInput={(v) => setNet('password', v)} />
          </Show>
          <div class="row">
            <Button small onClick={() => void scanWifi(true)}>{net.scanning ? 'Skanowanie…' : 'Skanuj ponownie'}</Button>
            <Button small kind="primary" disabled={net.connecting || net.ssid === ''} onClick={() => void connectWifi()}>
              {net.connecting ? 'Łączenie…' : 'Połącz'}
            </Button>
          </div>
          <Show when={net.message}><p class="muted">{net.message}</p></Show>
        </Section>
      </Show>

      <Section title="Serwer pakietów" hint="Używany do pobierania pakietów profilu. Domyślny nie zmienia niczego w nowym systemie.">
        <OptionList
          items={net.mirrors}
          selected={(m) => m.id === cfg.mirror_id}
          onSelect={(m) => setCfg('mirror_id', m.id)}
          label={(m) => m.label}
        />
        <Show when={cfg.mirror_id === 'custom'}>
          <Field
            label="Adres serwera"
            placeholder="https://mirror.example.org/archlinux"
            hint="Bez końcówki /$repo/os/$arch — instalator dopisze ją sam."
            value={cfg.mirror_url}
            onInput={(v) => setCfg('mirror_url', v)}
          />
        </Show>
      </Section>
    </div>
  );
}
