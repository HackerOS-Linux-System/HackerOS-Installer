import type {
  Choice, DiskInfo, InstallConfig, InstallProgress, Mirror, OtherOs, PartInfo, Profile, StepMeta, WifiNet,
} from './types';

/**
 * Typowany kontrakt komend H# (standard/src/main.h#). Jedna tabela:
 * nazwa → { args, result }. `call()` pilnuje zgodności argumentów i wyniku.
 */
type ConfigArgs = { config: InstallConfig };

interface Commands {
  bootstrap: {
    args: undefined;
    result: {
      core_version: string; uefi: boolean; default_hostname: string; ram_mb: number; cpus: number;
      has_resume: boolean; steps: StepMeta[];
      locales: Choice[]; keyboards: Choice[]; timezones: Choice[];
      gparted: boolean; alongside_min_mb: number; hsharp_version: string; bit_version: string;
    };
  };
  network_status: { args: undefined; result: { online: boolean; wifi_available: boolean; mirrors: Mirror[] } };
  wifi_scan: { args: { rescan: boolean }; result: { networks: WifiNet[] } };
  wifi_connect: { args: { ssid: string; password: string }; result: Ok };
  wifi_poll: { args: undefined; result: { done: boolean; ok?: boolean; message?: string; online?: boolean } };
  list_disks: { args: undefined; result: { disks: DiskInfo[] } };
  disk_info: {
    args: { disk: string };
    result: {
      free_mb: number; free_start_mb: number; free_end_mb: number; table: string; esp: string;
      partitions: PartInfo[];
    };
  };
  probe_os: { args: { disk: string }; result: { prober: boolean; systems: OtherOs[] } };
  open_gparted: { args: undefined; result: Ok };
  list_profiles: { args: undefined; result: { profiles: Profile[] } };
  validate_step: { args: ConfigArgs; result: { ok: boolean; message: string } };
  nav: { args: ConfigArgs & { dir: 'next' | 'back' }; result: { step: number } };
  summary: { args: ConfigArgs; result: { lines: string[]; plan: string[] } };
  probe_install: { args: ConfigArgs; result: { state: 'none' | 'resume' | 'running' } };
  start_install: { args: ConfigArgs & { resume: boolean }; result: Ok };
  poll_install: { args: { with_log?: boolean }; result: InstallProgress };
  load_resume: { args: undefined; result: { config: Partial<InstallConfig> } };
  reboot: { args: undefined; result: Ok };
}

export type Ok = { ok: boolean; error?: string };

export function call<K extends keyof Commands>(
  cmd: K,
  ...args: Commands[K]['args'] extends undefined ? [] : [Commands[K]['args']]
): Promise<Commands[K]['result']> {
  return silver.invoke(cmd, args[0] as Record<string, unknown> | undefined);
}
