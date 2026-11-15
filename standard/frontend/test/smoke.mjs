import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { JSDOM, VirtualConsole } from 'jsdom';

const here = dirname(fileURLToPath(import.meta.url));
const bundle = readFileSync(join(here, '..', 'dist', 'app.js'), 'utf8');

const steps = ['Witaj', 'Sieć', 'Dysk', 'Konto', 'Podsumowanie', 'Instalacja'].map((title, index) => ({
  index, title, subtitle: '', can_back: index > 0, can_next: index < 5,
}));
const choice = (code, label) => ({ code, label });
const replies = {
  bootstrap: {
    core_version: '0.2.0', uefi: true, default_hostname: 'hackeros', ram_mb: 8192, cpus: 4,
    has_resume: false, steps,
    locales: [choice('pl_PL.UTF-8', 'Polski')], keyboards: [choice('pl', 'Polski')],
    timezones: [choice('Europe/Warsaw', 'Warszawa')],
    gparted: false, alongside_min_mb: 20480, hsharp_version: 'test', bit_version: 'test',
  },
  network_status: { online: true, wifi_available: false, mirrors: [] },
  list_disks: { disks: [] },
  list_profiles: { profiles: [] },
  validate_step: { ok: true, message: '' },
  load_resume: { config: {} },
};

const errors = [];
const calls = [];
const vc = new VirtualConsole();
vc.on('jsdomError', (e) => errors.push(String(e.message || e)));
vc.on('error', (...a) => errors.push(a.join(' ')));

const dom = new JSDOM('<!DOCTYPE html><body><div id="root"></div></body>', {
  runScripts: 'outside-only', pretendToBeVisual: true, virtualConsole: vc,
});
const w = dom.window;
w.silver = {
  version: 'test',
  registerSourceMap() {},
  invoke: async (cmd) => { calls.push(cmd); return cmd in replies ? replies[cmd] : { ok: true }; },
  listen: () => () => {},
  once: () => () => {},
  window: new Proxy({}, { get: () => async () => {} }),
  dialog: new Proxy({}, { get: () => async () => null }),
  clipboard: { readText: async () => '', writeText: async () => {} },
};

let failed = 0;
const ok = (c, m) => { console.log(`  ${c ? 'ok  ' : 'FAIL'}  ${m}`); if (!c) failed++; };

try { w.eval(bundle); } catch (e) { errors.push(String(e && e.stack || e)); }
await new Promise((r) => setTimeout(r, 400));

const root = w.document.getElementById('root');
ok(errors.length === 0, `brak błędów w skrypcie${errors.length ? ': ' + errors[0] : ''}`);
ok(calls.includes('bootstrap'), 'wywołano komendę bootstrap');
ok(root.children.length > 0, 'interfejs wyrenderowany');
ok((root.textContent || '').trim().length > 0, 'interfejs zawiera tekst');

console.log(failed ? `\n${failed} test(y) nieudane` : '\nWszystko ok');
process.exit(failed ? 1 : 0);
