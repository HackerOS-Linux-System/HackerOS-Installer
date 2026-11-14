import { batch, createMemo, createSignal } from 'solid-js';
import { createStore, produce, reconcile, unwrap } from 'solid-js/store';
import { call } from './api';
import type {
  Choice, DiskInfo, InstallConfig, InstallProgress, ManualPart, Mirror, OtherOs, PartFs, PartInfo, Profile,
  StepMeta, WifiNet,
} from './types';
import { Step } from './types';

// ─────────────────────────────────────────────────────────────────────
// Cały stan kreatora żyje tutaj (sygnały + store Solida). Backend H# jest
// bezstanowy: dostaje konfigurację w każdym wywołaniu.
// ─────────────────────────────────────────────────────────────────────

export const defaultConfig = (): InstallConfig => ({
  step: Step.Welcome,
  locale: 'en_US.UTF-8', keyboard: 'us', timezone: 'UTC',
  online: false, mirror_id: 'default', mirror_url: '',
  target_disk: '', partition_mode: 'auto', filesystem: 'ext4',
  enable_swap: true, swap_size_mb: 2048,
  luks: false, luks_password: '', luks_confirm: '',
  manual_parts: [],
  profile: 'minimal', install_hsharp: false, install_bit: false,
  hostname: 'hackeros', username: '', full_name: '',
  password: '', password_confirm: '', is_admin: true,
  root_password: '', root_confirm: '',
  accepted_summary: false, resume_available: false, resume: false,
});

export const [cfg, setCfg] = createStore<InstallConfig>(defaultConfig());

// ── ogólne ───────────────────────────────────────────────────────────
export const [step, setStep] = createSignal<number>(Step.Welcome);
export const [booted, setBooted] = createSignal(false);
export const [busy, setBusy] = createSignal(false);
export const [error, setError] = createSignal('');
export const [notice, setNotice] = createSignal('');

export interface Boot {
  coreVersion: string; uefi: boolean; ramMb: number; cpus: number; hasResume: boolean;
  steps: StepMeta[]; locales: Choice[]; keyboards: Choice[]; timezones: Choice[];
  gparted: boolean; alongsideMinMb: number; hsharpVersion: string; bitVersion: string;
}
export const [boot, setBoot] = createSignal<Boot | null>(null);

export const stepMeta = createMemo(() => boot()?.steps.find((s) => s.index === step()));

// ── dane ładowane przy wejściu w kroki ───────────────────────────────
export const [net, setNet] = createStore({
  online: false, wifiAvailable: false, networks: [] as WifiNet[], mirrors: [] as Mirror[],
  ssid: '', open: false, password: '', message: '', connecting: false, scanning: false,
});

export const [disks, setDisks] = createSignal<DiskInfo[]>([]);
export const [diskInfo, setDiskInfo] = createStore({
  freeMb: 0, table: '', esp: '', partitions: [] as PartInfo[], loaded: false,
});
export const [osInfo, setOsInfo] = createStore({ prober: false, systems: [] as OtherOs[], probing: false });
export const [profiles, setProfiles] = createSignal<Profile[]>([]);
export const [summary, setSummary] = createStore({ lines: [] as string[], plan: [] as string[], showPlan: false });

export interface PartRow extends ManualPart { text: string; size_mb: number; is_esp: boolean }
export const [rows, setRows] = createStore<PartRow[]>([]);
let rowsFor = '';

export const [progress, setProgress] = createStore<InstallProgress>({
  state: 'idle', step: 0, total: 0, label: '', percent: 0, steps: [],
  failed_label: '', failed_code: 0, error_text: '', warnings: 0, log_path: '',
});
export const [installOk, setInstallOk] = createSignal(false);

// ── konfiguracja → ładunek dla H# ────────────────────────────────────
export function manualFromRows(): ManualPart[] {
  return rows
    .filter((r) => r.mountpoint.trim() !== '')
    .map((r) => ({ device: r.device, mountpoint: r.mountpoint.trim(), fs: r.fs, format: r.format }));
}

export function payload(): { config: InstallConfig } {
  const c = { ...unwrap(cfg) };
  c.step = step();
  c.online = net.online;
  c.manual_parts = c.partition_mode === 'manual' ? manualFromRows() : [];
  c.mirror_url = c.mirror_url.trim();
  return { config: c };
}

async function guard<T>(fn: () => Promise<T>): Promise<T | undefined> {
  try {
    return await fn();
  } catch (e) {
    setError(e instanceof Error ? e.message : String(e));
    return undefined;
  }
}

// ── start ────────────────────────────────────────────────────────────
export async function init(): Promise<void> {
  const b = await guard(() => call('bootstrap'));
  if (!b) { setBooted(true); return; }
  batch(() => {
    setBoot({
      coreVersion: b.core_version, uefi: b.uefi, ramMb: b.ram_mb, cpus: b.cpus, hasResume: b.has_resume,
      steps: b.steps, locales: b.locales, keyboards: b.keyboards, timezones: b.timezones,
      gparted: b.gparted, alongsideMinMb: b.alongside_min_mb, hsharpVersion: b.hsharp_version, bitVersion: b.bit_version,
    });
    setCfg('hostname', b.default_hostname || 'hackeros');
    setBooted(true);
  });
}

// ── podpowiedzi: język → klawiatura + strefa ─────────────────────────
const SUGGEST: Record<string, [string, string]> = {
  'pl_PL.UTF-8': ['pl', 'Europe/Warsaw'], 'de_DE.UTF-8': ['de', 'Europe/Berlin'],
  'fr_FR.UTF-8': ['fr', 'Europe/Paris'], 'es_ES.UTF-8': ['es', 'Europe/Madrid'],
  'it_IT.UTF-8': ['it', 'Europe/Rome'], 'pt_BR.UTF-8': ['pt', 'America/Sao_Paulo'],
  'ru_RU.UTF-8': ['ru', 'Europe/Moscow'], 'uk_UA.UTF-8': ['ua', 'Europe/Kyiv'],
  'ja_JP.UTF-8': ['jp', 'Asia/Tokyo'], 'zh_CN.UTF-8': ['us', 'Asia/Shanghai'],
  'en_US.UTF-8': ['us', 'UTC'],
};
const touched = { keyboard: false, timezone: false };

export function pickLocale(code: string): void {
  batch(() => {
    setCfg('locale', code);
    const s = SUGGEST[code];
    if (s) {
      if (!touched.keyboard) setCfg('keyboard', s[0]);
      if (!touched.timezone) setCfg('timezone', s[1]);
    }
  });
}
export function pickKeyboard(code: string): void { touched.keyboard = true; setCfg('keyboard', code); }
export function pickTimezone(code: string): void { touched.timezone = true; setCfg('timezone', code); }

// ── wejście do kroku (jednorazowe ładowanie danych) ──────────────────
export async function enter(s: number): Promise<void> {
  switch (s) {
    case Step.Network: await loadNetwork(); break;
    case Step.Disk: await loadDisks(); break;
    case Step.Partitions: await loadPartitions(); break;
    case Step.Profile: await loadProfiles(); break;
    case Step.Summary: await loadSummary(); break;
    default: break;
  }
}

export async function loadNetwork(): Promise<void> {
  const st = await guard(() => call('network_status'));
  if (!st) return;
  batch(() => {
    setNet({ online: st.online, wifiAvailable: st.wifi_available, mirrors: st.mirrors, message: '' });
    if (!st.mirrors.some((m) => m.id === cfg.mirror_id)) setCfg('mirror_id', 'default');
  });
  if (st.wifi_available) await scanWifi(true);
}

export async function recheckNet(): Promise<void> {
  const st = await guard(() => call('network_status'));
  if (st) setNet('online', st.online);
}

export async function scanWifi(rescan: boolean): Promise<void> {
  setNet('scanning', true);
  const r = await guard(() => call('wifi_scan', { rescan }));
  batch(() => {
    if (r) setNet('networks', reconcile(r.networks, { key: 'ssid' }));
    setNet('scanning', false);
    if (r && rescan) setNet('message', r.networks.length ? '' : 'Nie znaleziono sieci.');
  });
}

export function pickWifi(n: WifiNet): void {
  batch(() => { setNet({ ssid: n.ssid, open: n.security === '', password: '', message: '' }); });
}

let wifiTimer: ReturnType<typeof setInterval> | undefined;
export async function connectWifi(): Promise<void> {
  if (!net.ssid) { setNet('message', 'Najpierw wybierz sieć z listy.'); return; }
  const r = await guard(() => call('wifi_connect', { ssid: net.ssid, password: net.open ? '' : net.password }));
  if (!r || r.ok === false) { setNet('message', r?.error ?? 'Nie udało się rozpocząć łączenia.'); return; }
  setNet({ connecting: true, message: 'Łączenie z ' + net.ssid + '…' });
  if (wifiTimer) clearInterval(wifiTimer);
  wifiTimer = setInterval(async () => {
    const p = await guard(() => call('wifi_poll'));
    if (!p || !p.done) return;
    if (wifiTimer) clearInterval(wifiTimer);
    batch(() => {
      setNet({ connecting: false, message: p.message ?? '' });
      if (p.online !== undefined) setNet('online', p.online);
    });
    void scanWifi(false);
  }, 700);
}

export async function loadDisks(): Promise<void> {
  const r = await guard(() => call('list_disks'));
  if (!r) return;
  setDisks(r.disks);
  if (cfg.target_disk && !r.disks.some((d) => d.device === cfg.target_disk)) pickDisk('');
  if (cfg.target_disk) await loadDiskDetails();
}

export function pickDisk(device: string): void {
  if (device === cfg.target_disk) return;
  batch(() => {
    setCfg('target_disk', device);
    setRows([]);
    rowsFor = '';
    setOsInfo({ systems: [], prober: false });
    setDiskInfo({ loaded: false, freeMb: 0, partitions: [] });
  });
  if (device) void loadDiskDetails();
}

export async function loadDiskDetails(): Promise<void> {
  const disk = cfg.target_disk;
  if (!disk) return;
  const info = await guard(() => call('disk_info', { disk }));
  if (info && disk === cfg.target_disk) {
    setDiskInfo({ freeMb: info.free_mb, table: info.table, esp: info.esp, partitions: info.partitions, loaded: true });
  }
  await rescanOs();
}

export async function rescanOs(): Promise<void> {
  const disk = cfg.target_disk;
  if (!disk) return;
  setOsInfo('probing', true);
  const r = await guard(() => call('probe_os', { disk }));
  if (r && disk === cfg.target_disk) setOsInfo({ prober: r.prober, systems: r.systems });
  setOsInfo('probing', false);
}

function defaultFs(p: PartInfo): PartFs {
  if (p.is_esp) return 'vfat';
  if (p.fstype === 'swap') return 'swap';
  return 'ext4';
}

export async function loadPartitions(): Promise<void> {
  const disk = cfg.target_disk;
  if (!disk || rowsFor === disk) return;
  const info = await guard(() => call('disk_info', { disk }));
  if (!info) return;
  rowsFor = disk;
  setRows(
    info.partitions.map((p) => ({
      device: p.device, text: p.text, size_mb: p.size_mb, is_esp: p.is_esp,
      mountpoint: '', fs: defaultFs(p), format: false,
    })),
  );
}

/** Szybki wybór punktu montowania: dobiera sensowny system plików i formatowanie. */
export function assignMount(i: number, mp: string): void {
  setRows(
    produce((rs) => {
      const r = rs[i];
      if (!r) return;
      r.mountpoint = mp;
      if (mp === 'swap') { r.fs = 'swap'; r.format = true; }
      else if (mp === '/boot/efi') { r.fs = 'vfat'; }
      else if (r.fs === 'swap' || (r.fs === 'vfat' && mp !== '/boot/efi')) { r.fs = 'ext4'; }
      if (mp === '/') r.format = true;
    }),
  );
}

export async function loadProfiles(): Promise<void> {
  const r = await guard(() => call('list_profiles'));
  if (!r) return;
  setProfiles(r.profiles);
  if (!r.profiles.some((p) => p.id === cfg.profile)) setCfg('profile', r.profiles[0]?.id ?? 'minimal');
}

export async function loadSummary(): Promise<void> {
  const [sum, pr] = await Promise.all([
    guard(() => call('summary', payload())),
    guard(() => call('probe_install', payload())),
  ]);
  batch(() => {
    if (sum) setSummary({ lines: sum.lines, plan: sum.plan, showPlan: false });
    setCfg({ accepted_summary: false });
    const st = pr?.state ?? 'none';
    setCfg({ resume_available: st === 'resume', resume: st === 'resume' });
    if (st === 'running') {
      setNotice('Instalacja już trwa w tle — dołączam do niej.');
      setStep(Step.Installing);
      startPolling();
    }
  });
}

// ── nawigacja ────────────────────────────────────────────────────────
export async function go(dir: 'next' | 'back'): Promise<void> {
  if (busy()) return;
  setBusy(true);
  setError('');
  try {
    if (dir === 'next') {
      const v = await guard(() => call('validate_step', payload()));
      if (!v) return;
      if (!v.ok) { setError(v.message); return; }
      if (step() === Step.Summary) { await beginInstall(cfg.resume); return; }
    }
    const nav = await guard(() => call('nav', { ...payload(), dir }));
    if (!nav) return;
    setNotice('');
    setStep(nav.step);
    await enter(nav.step);
  } finally {
    setBusy(false);
  }
}

// ── instalacja ───────────────────────────────────────────────────────
export async function beginInstall(resume: boolean): Promise<void> {
  const r = await guard(() => call('start_install', { ...payload(), resume }));
  if (!r) return;
  if (r.ok === false) { setError(r.error ?? 'Nie udało się rozpocząć instalacji.'); return; }
  batch(() => {
    setProgress(reconcile({
      state: 'idle', step: 0, total: 0, label: '', percent: 0, steps: [],
      failed_label: '', failed_code: 0, error_text: '', warnings: 0, log_path: '',
    }));
    setStep(Step.Installing);
    setError('');
  });
  startPolling();
}

let pollTimer: ReturnType<typeof setInterval> | undefined;
let idleTicks = 0;
export function startPolling(): void {
  stopPolling();
  idleTicks = 0;
  const tick = async (): Promise<void> => {
    const p = await guard(() => call('poll_install', { with_log: true }));
    if (!p) return;
    setProgress(reconcile(p));
    if (p.state === 'idle') {
      if (++idleTicks > 20) {
        stopPolling();
        batch(() => {
          setError('Wykonawca instalacji nie wystartował (brak pliku statusu). Sprawdź /var/log/hackeros-installer.log.');
          setInstallOk(false);
          setStep(Step.Done);
        });
      }
      return;
    }
    idleTicks = 0;
    if (p.state === 'ok' || p.state === 'failed') {
      stopPolling();
      batch(() => { setInstallOk(p.state === 'ok'); setStep(Step.Done); });
    }
  };
  void tick();
  pollTimer = setInterval(() => void tick(), 600);
}
export function stopPolling(): void {
  if (pollTimer) clearInterval(pollTimer);
  pollTimer = undefined;
}

export async function retryInstall(): Promise<void> {
  setError('');
  await beginInstall(true);
}

// ── wznawianie zapisanej konfiguracji ────────────────────────────────
export async function loadResume(): Promise<void> {
  const r = await guard(() => call('load_resume'));
  if (!r) return;
  batch(() => {
    const c = r.config;
    setCfg({ ...defaultConfig(), ...c, hostname: c.hostname || cfg.hostname });
    setCfg({ password: '', password_confirm: '', root_password: '', root_confirm: '', luks_password: '', luks_confirm: '' });
    if (c.manual_parts?.length) {
      rowsFor = '';
      pendingManual = c.manual_parts;
    }
    setStep(Step.Account);
    setNotice('Wczytano zapisaną konfigurację. Wpisz ponownie hasła — nie są nigdzie zapisywane.');
  });
  await recheckNet();
  if (cfg.partition_mode === 'manual' && pendingManual) {
    await loadPartitions();
    const saved = pendingManual;
    pendingManual = undefined;
    setRows(produce((rs) => {
      for (const r of rs) {
        const m = saved.find((p) => p.device === r.device);
        if (m) { r.mountpoint = m.mountpoint; r.fs = m.fs; r.format = m.format; }
      }
    }));
  }
}
let pendingManual: ManualPart[] | undefined;

export async function reboot(): Promise<void> { await guard(() => call('reboot')); }
export async function openGparted(): Promise<void> { await guard(() => call('open_gparted')); }

export const isManual = () => cfg.partition_mode === 'manual';
export const selectedDisk = () => disks().find((d) => d.device === cfg.target_disk);
