export type PartitionMode = 'auto' | 'alongside' | 'manual';
export type RootFs = 'ext4' | 'btrfs' | 'xfs';
export type PartFs = 'ext4' | 'btrfs' | 'xfs' | 'vfat' | 'swap';

export interface Choice { code: string; label: string }

export interface StepMeta {
  index: number;
  title: string;
  subtitle: string;
  can_back: boolean;
  can_next: boolean;
}

/** Indeksy kroków — muszą zgadzać się z `steps::step_index` w rdzeniu (main/src/steps.h#). */
export const Step = {
  Welcome: 0, Language: 1, Keyboard: 2, Timezone: 3, Network: 4, Disk: 5,
  Partitions: 6, Profile: 7, Account: 8, Summary: 9, Installing: 10, Done: 11,
} as const;
export type StepId = (typeof Step)[keyof typeof Step];

export interface DiskInfo {
  device: string; model: string; size_gb: number; removable: boolean; label: string;
}
export interface PartInfo {
  device: string; size_mb: number; fstype: string; label: string; is_esp: boolean; text: string;
}
export interface OtherOs { device: string; name: string; kind: string; text: string }
export interface WifiNet { ssid: string; signal: number; security: string; in_use: boolean; label: string }
export interface Mirror { id: string; label: string; url: string }
export interface Profile {
  id: string; label: string; description: string; packages: string[]; needs_network: boolean;
}

export interface ManualPart { device: string; mountpoint: string; fs: PartFs; format: boolean }

/** Konfiguracja wysyłana do rdzenia (pola 1:1 z `cfg_from` w standard/src/main.h#). */
export interface InstallConfig {
  step: number;
  locale: string; keyboard: string; timezone: string;
  online: boolean; mirror_id: string; mirror_url: string;
  target_disk: string; partition_mode: PartitionMode; filesystem: RootFs;
  enable_swap: boolean; swap_size_mb: number;
  luks: boolean; luks_password: string; luks_confirm: string;
  manual_parts: ManualPart[];
  profile: string; install_hsharp: boolean; install_bit: boolean;
  hostname: string; username: string; full_name: string;
  password: string; password_confirm: string; is_admin: boolean;
  root_password: string; root_confirm: string;
  accepted_summary: boolean; resume_available: boolean; resume: boolean;
}

export type InstallState = 'idle' | 'running' | 'ok' | 'failed';
export type StepStatus = 'ok' | 'warn' | 'fail' | 'skip';

export interface InstallStepResult { label: string; status: StepStatus; code: number }
export interface InstallProgress {
  state: InstallState; step: number; total: number; label: string; percent: number;
  steps: InstallStepResult[];
  failed_label: string; failed_code: number; error_text: string;
  warnings: number; log_path: string; log_tail?: string;
}
