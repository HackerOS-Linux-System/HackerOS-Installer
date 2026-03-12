use crate::config::{Edition, InstallerConfig};
use crate::disk::{part_path, PartitionPlan};
use crate::user::UserConfig;
use anyhow::Result;
use serde::{Deserialize, Serialize};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use tokio::process::Command;
use tracing::{error, info, warn};

const TARGET: &str = "/mnt/hackeros-install";

// ─── Postęp ───────────────────────────────────────────────────────────────────

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct InstallProgress {
    pub phase:        InstallPhase,
    pub percent:      u8,
    pub current_task: String,
    pub log_lines:    Vec<String>,
    pub error:        Option<String>,
    pub completed:    bool,
    pub cancelled:    bool,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "snake_case")]
pub enum InstallPhase {
    NotStarted,
    Partitioning,
    Formatting,
    MountingFilesystems,
    InstallingBase,
    InstallingPackages,
    ConfiguringSystem,
    InstallingBootloader,
    CreatingUsers,
    GamingSetup,
    FinalSetup,
    Complete,
    Failed,
}

// ─── Manager ──────────────────────────────────────────────────────────────────

pub struct InstallManager {
    progress:       Arc<std::sync::Mutex<InstallProgress>>,
    cancelled:      Arc<AtomicBool>,
    locale:         Option<LocaleConfig>,
    partition_plan: Option<PartitionPlan>,
    user_config:    Option<UserConfig>,
}

#[derive(Debug, Clone)]
struct LocaleConfig {
    locale:   String,
    timezone: String,
    keyboard: String,
}

impl InstallManager {
    pub fn new() -> Self {
        Self {
            progress: Arc::new(std::sync::Mutex::new(InstallProgress {
                phase:        InstallPhase::NotStarted,
                percent:      0,
                current_task: "Oczekiwanie...".to_string(),
                                                     log_lines:    Vec::new(),
                                                     error:        None,
                                                     completed:    false,
                                                     cancelled:    false,
            })),
            cancelled:      Arc::new(AtomicBool::new(false)),
            locale:         None,
            partition_plan: None,
            user_config:    None,
        }
    }

    pub fn set_locale_config(&mut self, locale: String, timezone: String, keyboard: String) {
        self.locale = Some(LocaleConfig { locale, timezone, keyboard });
    }
    pub fn set_partition_plan(&mut self, plan: PartitionPlan) { self.partition_plan = Some(plan); }
    pub fn set_user_config(&mut self, user: UserConfig)       { self.user_config    = Some(user); }
    pub fn get_progress(&self) -> InstallProgress              { self.progress.lock().unwrap().clone() }

    pub fn cancel(&mut self) {
        self.cancelled.store(true, Ordering::SeqCst);
        let mut p = self.progress.lock().unwrap();
        p.cancelled    = true;
        p.current_task = "Anulowano przez użytkownika.".to_string();
    }

    fn upd(&self, phase: InstallPhase, pct: u8, task: &str) {
        let mut p = self.progress.lock().unwrap();
        p.phase        = phase;
        p.percent      = pct;
        p.current_task = task.to_string();
        p.log_lines.push(format!("[{:3}%] {}", pct, task));
        info!("{}", task);
    }

    fn log(&self, msg: &str) {
        self.progress.lock().unwrap().log_lines.push(msg.to_string());
        info!("{}", msg);
    }

    fn set_error(&self, err: &str) {
        let mut p  = self.progress.lock().unwrap();
        p.phase    = InstallPhase::Failed;
        p.error    = Some(err.to_string());
        error!("{}", err);
    }

    // ── Główna pętla ─────────────────────────────────────────────────────────

    pub async fn start_installation(&mut self, config: &InstallerConfig) -> Result<()> {
        let plan   = self.partition_plan.clone()
        .ok_or_else(|| anyhow::anyhow!("Brak planu partycjonowania"))?;
        let user   = self.user_config.clone()
        .ok_or_else(|| anyhow::anyhow!("Brak konfiguracji użytkownika"))?;
        let locale = self.locale.clone()
        .ok_or_else(|| anyhow::anyhow!("Brak konfiguracji lokalizacji"))?;

        let cancelled = Arc::clone(&self.cancelled);

        macro_rules! chk { () => {
            if cancelled.load(Ordering::SeqCst) {
                self.log("Anulowano przez użytkownika.");
                return Ok(());
            }
        };}

        macro_rules! step {
            ($phase:expr, $pct:expr, $msg:expr, $fut:expr) => {{
                self.upd($phase, $pct, $msg);
                chk!();
                if let Err(e) = $fut.await {
                    self.set_error(&format!("{}: {}", $msg, e));
                    return Err(e);
                }
            }};
        }

        step!(InstallPhase::Partitioning,         5,  "Partycjonowanie dysku...",
              self.do_partition(&plan));

        step!(InstallPhase::Formatting,           15, "Formatowanie partycji...",
              self.do_format(&plan));

        step!(InstallPhase::MountingFilesystems,  20, "Montowanie systemów plików...",
              self.do_mount(&plan, config));

        step!(InstallPhase::InstallingBase,       25,
              &format!("Instalowanie systemu bazowego ({})...", config.base().display_name()),
              self.do_debootstrap(config));

        // Pakiety: gaming instaluje narzędzia; official pomija
        if config.is_gaming_edition() {
            step!(InstallPhase::InstallingPackages, 55, "Instalowanie pakietów...",
                  self.do_install_packages(config));
        } else {
            self.upd(InstallPhase::InstallingPackages, 55,
                     "Edycja Official – brak dodatkowych pakietów.");
            chk!();
        }

        step!(InstallPhase::ConfiguringSystem,    72, "Konfigurowanie systemu...",
              self.do_configure_system(config, &locale, &plan));

        step!(InstallPhase::InstallingBootloader, 82, "Instalowanie GRUB...",
              self.do_install_bootloader(&plan));

        step!(InstallPhase::CreatingUsers,        88, "Tworzenie kont użytkowników...",
              self.do_create_users(&user, config));

        if config.is_gaming_edition() {
            step!(InstallPhase::GamingSetup, 92,
                  "Konfigurowanie środowiska gaming (gamescope + distrobox)...",
                  self.do_gaming_setup(config, &user));
        }

        step!(InstallPhase::FinalSetup, 97, "Finalizacja...",
              self.do_final_setup(config));

        {
            let mut p   = self.progress.lock().unwrap();
            p.phase     = InstallPhase::Complete;
            p.percent   = 100;
            p.current_task = "Instalacja zakończona! Uruchom ponownie komputer.".to_string();
            p.completed = true;
        }
        info!("Instalacja zakończona pomyślnie.");
        Ok(())
    }

    // ── 1. Partycjonowanie ────────────────────────────────────────────────────

    async fn do_partition(&self, plan: &PartitionPlan) -> Result<()> {
        self.log(&format!("  Czyszczenie: {}", plan.disk));
        run("wipefs", &["-a", &plan.disk]).await?;
        run("parted", &["-s", &plan.disk, "mklabel", "gpt"]).await?;

        let mut start_mb: u64 = 1;
        for (i, part) in plan.partitions.iter().enumerate() {
            let num   = (i + 1).to_string();
            let start = format!("{}MiB", start_mb);
            let size  = part.size_mb.unwrap_or(0);
            let end   = if size == 0 { "100%".to_string() } else { format!("{}MiB", start_mb + size) };

            self.log(&format!("  Partycja {}: {} {}–{}", i + 1, part.filesystem, start, end));
            run("parted", &["-s", &plan.disk, "mkpart", "primary", &start, &end]).await?;
            for flag in &part.flags {
                run("parted", &["-s", &plan.disk, "set", &num, flag, "on"]).await?;
            }
            if size > 0 { start_mb += size; }
        }
        let _ = run("partprobe", &[&plan.disk]).await;
        tokio::time::sleep(tokio::time::Duration::from_secs(2)).await;
        Ok(())
    }

    // ── 2. Formatowanie ───────────────────────────────────────────────────────

    async fn do_format(&self, plan: &PartitionPlan) -> Result<()> {
        for (i, part) in plan.partitions.iter().enumerate() {
            let dev = part_path(&plan.disk, i + 1);
            self.log(&format!("  {} → {}", dev, part.filesystem));
            match part.filesystem.as_str() {
                "fat32"      => run("mkfs.fat",  &["-F32", "-n", "EFI",  &dev]).await?,
                "fat16"      => run("mkfs.fat",  &["-F16",              &dev]).await?,
                "ext4"       => run("mkfs.ext4", &["-F", "-L", "root",  &dev]).await?,
                "btrfs"      => run("mkfs.btrfs",&["-f", "-L", "root",  &dev]).await?,
                "linux-swap" => run("mkswap",    &["-L", "swap",        &dev]).await?,
                other        => { self.log(&format!("  Pomijanie: {}", other)); }
            }
        }
        Ok(())
    }

    // ── 3. Montowanie ─────────────────────────────────────────────────────────

    async fn do_mount(&self, plan: &PartitionPlan, config: &InstallerConfig) -> Result<()> {
        tokio::fs::create_dir_all(TARGET).await?;

        // Root
        for (i, part) in plan.partitions.iter().enumerate() {
            if part.mountpoint != "/" { continue; }
            let dev = part_path(&plan.disk, i + 1);

            if part.filesystem == "btrfs" && config.is_gaming_edition() {
                self.log("  Tworzenie BTRFS subvolumes...");
                run("mount", &[&dev, TARGET]).await?;

                let gcfg   = config.gaming_config();
                let subvols = gcfg.btrfs_subvolumes.clone().unwrap_or_default();
                for sv in &subvols {
                    run("btrfs", &["subvolume", "create",
                        &format!("{}/{}", TARGET, sv.name)]).await?;
                }
                run("umount", &[TARGET]).await?;

                // Remontuj @ jako root
                let opts = subvols.iter().find(|s| s.name == "@")
                .and_then(|s| s.mount_options.as_deref())
                .unwrap_or("compress=zstd,noatime");
                run("mount", &["-o", &format!("subvol=@,{}", opts), &dev, TARGET]).await?;

                // Pozostałe subvolumy
                for sv in &subvols {
                    if sv.mountpoint == "/" { continue; }
                    let mp   = format!("{}{}", TARGET, sv.mountpoint);
                    let opts2 = sv.mount_options.as_deref().unwrap_or("compress=zstd,noatime");
                    tokio::fs::create_dir_all(&mp).await?;
                    run("mount", &["-o", &format!("subvol={},{}", sv.name, opts2), &dev, &mp]).await?;
                }
            } else {
                run("mount", &[&dev, TARGET]).await?;
            }
            break;
        }

        // Pozostałe (nie root, nie swap, nie btrfs-już-zamontowane)
        for (i, part) in plan.partitions.iter().enumerate() {
            if part.mountpoint == "/" || part.filesystem == "linux-swap" { continue; }
            if part.filesystem == "btrfs" { continue; }
            let dev = part_path(&plan.disk, i + 1);
            let mp  = format!("{}{}", TARGET, part.mountpoint);
            tokio::fs::create_dir_all(&mp).await?;
            run("mount", &[&dev, &mp]).await?;
        }
        Ok(())
    }

    // ── 4. Debootstrap ────────────────────────────────────────────────────────

    async fn do_debootstrap(&self, config: &InstallerConfig) -> Result<()> {
        let suite  = config.base().suite();
        let mirror = "http://deb.debian.org/debian";
        self.log(&format!("  debootstrap {} → {}", suite, TARGET));

        let include = concat!(
            "linux-image-amd64,linux-headers-amd64,",
            "grub-pc,grub-efi-amd64,grub-efi-amd64-signed,shim-signed,",
            "initramfs-tools,systemd,systemd-sysv,dbus,",
            "network-manager,wpasupplicant,",
            "sudo,bash,ca-certificates,apt-transport-https,gnupg,",
            "locales,keyboard-configuration,console-setup,",
            "firmware-linux-free,firmware-linux-nonfree,",
            "firmware-iwlwifi,firmware-atheros,firmware-realtek,",
            "firmware-amd-graphics,firmware-misc-nonfree"
        );

        run("debootstrap", &[
            "--arch=amd64",
            &format!("--include={}", include),
            "--components=main,contrib,non-free,non-free-firmware",
            suite, TARGET, mirror,
        ]).await?;
        Ok(())
    }

    // ── 5. Pakiety ────────────────────────────────────────────────────────────
    // Wywoływane tylko dla gaming edition

    async fn do_install_packages(&self, config: &InstallerConfig) -> Result<()> {
        self.bind_mounts(true).await?;

        // Zaktualizuj sources.list
        tokio::fs::write(
            format!("{}/etc/apt/sources.list", TARGET),
                config.build_sources_list(),
        ).await?;

        chroot("apt-get", &["update", "-qq"]).await?;

        let gcfg = config.gaming_config();
        let mut pkgs: Vec<&str> = vec![
            "systemd-timesyncd", "curl", "wget", "gnupg", "ca-certificates",
            "vim", "nano", "avahi-daemon", "libnss-mdns",
            "pipewire", "pipewire-pulse", "wireplumber",
            "xwayland",
            // DE: gaming używa SDDM + KDE/Plasma (lekki shell bez pełnego Plasma desktop)
            "sddm", "sddm-theme-breeze",
            "mesa-vulkan-drivers", "mesa-utils", "vulkan-tools", "libvulkan1",
            "steam-devices",
            "gamemode",
            "distrobox", "podman",
            "git",
        ];

        if gcfg.install_lutris   { pkgs.push("lutris"); }
        if gcfg.install_mangohud { pkgs.push("mangohud"); }
        if gcfg.install_wine     { pkgs.extend_from_slice(&["wine", "wine32", "wine64"]); }

        // Extra packages z config.yml
        let extra_owned: Vec<String> = config.extra_packages
        .split_whitespace().map(String::from).collect();
        let extra_refs: Vec<&str> = extra_owned.iter().map(String::as_str).collect();
        pkgs.extend_from_slice(&extra_refs);

        if config.swap_type == "zram" { pkgs.push("zram-tools"); }

        let mut args = vec!["install", "-y", "--no-install-recommends"];
        args.extend_from_slice(&pkgs);
        chroot("apt-get", &args).await?;

        Ok(())
    }

    // ── 6. Konfiguracja systemu ───────────────────────────────────────────────

    async fn do_configure_system(
        &self,
        config: &InstallerConfig,
        locale: &LocaleConfig,
        plan:   &PartitionPlan,
    ) -> Result<()> {
        if config.configure_apt_sources {
            tokio::fs::write(
                format!("{}/etc/apt/sources.list", TARGET),
                    config.build_sources_list(),
            ).await?;
        }

        // Hostname
        let hostname = self.user_config.as_ref()
        .map(|u| u.hostname.clone())
        .unwrap_or_else(|| "hackeros".to_string());
        tokio::fs::write(format!("{}/etc/hostname", TARGET),
                         format!("{}\n", hostname)).await?;
                         tokio::fs::write(format!("{}/etc/hosts", TARGET), format!(
                             "127.0.0.1\tlocalhost\n127.0.1.1\t{hostname}\n::1\tlocalhost\n"
                         )).await?;

                         // Locale
                         chroot("bash", &["-c",
                                &format!("echo '{} UTF-8' > /etc/locale.gen && locale-gen", locale.locale)
                         ]).await?;
                         tokio::fs::write(format!("{}/etc/default/locale", TARGET),
                                          format!("LANG={}\n", locale.locale)).await?;

                                          // Timezone
                                          chroot("ln", &["-sf",
                                                 &format!("/usr/share/zoneinfo/{}", locale.timezone), "/etc/localtime"
                                          ]).await?;
                                          chroot("dpkg-reconfigure", &["-f", "noninteractive", "tzdata"]).await?;

                                          // Klawiatura
                                          tokio::fs::write(format!("{}/etc/default/keyboard", TARGET), format!(
                                              "XKBLAYOUT=\"{}\"\nXKBMODEL=\"pc105\"\nXKBOPTIONS=\"\"\n",
                                              locale.keyboard
                                          )).await?;

                                          // fstab
                                          let fstab = build_fstab(plan, config).await?;
                                          tokio::fs::write(format!("{}/etc/fstab", TARGET), fstab).await?;

                                          // NetworkManager
                                          chroot("systemctl", &["enable", "NetworkManager"]).await?;

                                          // zram
                                          if config.swap_type == "zram" {
                                              tokio::fs::write(format!("{}/etc/default/zramswap", TARGET), format!(
                                                  "PERCENT=50\nMAX_SIZE={}\n", config.swap_size_gb * 1024
                                              )).await?;
                                              chroot("systemctl", &["enable", "zramswap"]).await?;
                                          }

                                          Ok(())
    }

    // ── 7. Bootloader ─────────────────────────────────────────────────────────

    async fn do_install_bootloader(&self, plan: &PartitionPlan) -> Result<()> {
        if plan.efi {
            chroot("grub-install", &[
                "--target=x86_64-efi",
                "--efi-directory=/boot/efi",
                "--bootloader-id=HackerOS",
                "--recheck",
            ]).await?;
        } else {
            chroot("grub-install", &["--target=i386-pc", "--recheck", &plan.disk]).await?;
        }
        chroot("update-grub", &[]).await?;
        Ok(())
    }

    // ── 8. Użytkownicy ────────────────────────────────────────────────────────

    async fn do_create_users(&self, user: &UserConfig, config: &InstallerConfig) -> Result<()> {
        let mut groups = "sudo,audio,video,plugdev,cdrom,netdev,input,render".to_string();
        if config.is_gaming_edition() { groups.push_str(",gamemode"); }

        chroot("useradd", &[
            "-m", "-s", "/bin/bash",
            "-G", &groups,
            "-c", &user.full_name,
            &user.username,
        ]).await?;

        chroot("bash", &["-c",
               &format!("echo '{}:{}' | chpasswd", user.username, user.password)
        ]).await?;

        let root_pw = if user.use_same_password_for_root {
            user.password.clone()
        } else {
            user.root_password.clone().unwrap_or_else(|| user.password.clone())
        };
        chroot("bash", &["-c", &format!("echo 'root:{}' | chpasswd", root_pw)]).await?;

        if user.autologin {
            self.setup_autologin(user, config).await?;
        }
        Ok(())
    }

    async fn setup_autologin(&self, user: &UserConfig, config: &InstallerConfig) -> Result<()> {
        let dir = format!("{}/etc/sddm.conf.d", TARGET);
        tokio::fs::create_dir_all(&dir).await?;

        let session = if config.is_gaming_edition() {
            "gamescope-session-steam"
        } else {
            match config.desktop_environment.as_str() {
                "kde"  => "plasma",
                "xfce" => "xfce",
                _      => "gnome",
            }
        };

        tokio::fs::write(format!("{}/autologin.conf", dir), format!(
            "[Autologin]\nUser={}\nSession={}\n", user.username, session
        )).await?;
        Ok(())
    }

    // ── 9. Gaming setup ───────────────────────────────────────────────────────

    async fn do_gaming_setup(&self, config: &InstallerConfig, user: &UserConfig) -> Result<()> {
        let gcfg    = config.gaming_config();
        let repo    = gcfg.gamescope_session_repo.as_deref()
        .unwrap_or("https://github.com/HackerOS-Linux-System/gamescope-session-steam.git");

        // a) Klonuj gamescope-session-steam i kopiuj /usr do /
        self.log(&format!("  Klonowanie gamescope-session-steam z {}...", repo));
        let script_clone = format!(
            r#"#!/bin/bash
            set -e
            cd /tmp
            rm -rf gamescope-session-steam
            git clone --depth=1 "{repo}" gamescope-session-steam
            if [ -d /tmp/gamescope-session-steam/usr ]; then
                cp -rv /tmp/gamescope-session-steam/usr /
                echo "gamescope-session-steam: /usr skopiowany"
                else
                    echo "UWAGA: brak folderu /usr w repo!" >&2
                    fi
                    rm -rf /tmp/gamescope-session-steam
                    "#, repo = repo);
                let p = format!("{}/tmp/gamescope-clone.sh", TARGET);
            tokio::fs::write(&p, &script_clone).await?;
            chroot("bash", &["/tmp/gamescope-clone.sh"]).await?;
            let _ = tokio::fs::remove_file(&p).await;

            // b) SDDM default session
            let sddm_dir = format!("{}/etc/sddm.conf.d", TARGET);
            tokio::fs::create_dir_all(&sddm_dir).await?;
            tokio::fs::write(format!("{}/gaming.conf", sddm_dir), format!(
                "[Desktop]\nSession=gamescope-session-steam\n\n\
[Autologin]\nUser={}\nSession=gamescope-session-steam\n",
user.username
            )).await?;
            chroot("systemctl", &["enable", "sddm"]).await?;

            // c–e) distrobox first-boot service
            self.create_gaming_firstboot(config, user).await?;
            Ok(())
    }

    async fn create_gaming_firstboot(&self, config: &InstallerConfig, user: &UserConfig) -> Result<()> {
        let gcfg      = config.gaming_config();
        let container = &gcfg.distrobox_container_name;
        let image     = &gcfg.distrobox_image;
        let pkgs      = gcfg.arch_packages.join(" ");
        let username  = &user.username;

        let script = format!(
            r#"#!/bin/bash
            # HackerOS Gaming First Boot – konfiguracja kontenera Steam
            set -e
            LOG="$HOME/.hackeros-gaming-setup.log"
            exec > >(tee -a "$LOG") 2>&1
            echo "=== HackerOS Gaming Setup $(date) ==="

            echo "[1/3] Tworzenie kontenera distrobox: {container} ({image})..."
            distrobox create "{container}" --image "{image}" --yes || true

            echo "[2/3] Włączanie multilib w kontenerze Arch Linux..."
            distrobox enter "{container}" -- bash -c '
        if ! grep -q "^\[multilib\]" /etc/pacman.conf; then
            printf "\n[multilib]\nInclude = /etc/pacman.d/mirrorlist\n" >> /etc/pacman.conf
            fi
            pacman -Syu --noconfirm
            '

        echo "[3/3] Instalowanie pakietów Steam/gamescope..."
        distrobox enter "{container}" -- pacman -S --noconfirm --needed {pkgs}

        echo "=== Konfiguracja zakończona pomyślnie ==="
        systemctl --user disable hackeros-gaming-setup.service 2>/dev/null || true
        "#,
        container = container,
        image     = image,
        pkgs      = pkgs,
        );

        // Skrypt
        let lib_dir = format!("{}/usr/lib/HackerOS", TARGET);
        tokio::fs::create_dir_all(&lib_dir).await?;
        let script_chroot = "/usr/lib/HackerOS/gaming-setup.sh";
        tokio::fs::write(format!("{}{}", TARGET, script_chroot), &script).await?;
        chroot("chmod", &["+x", script_chroot]).await?;

        // systemd user service w /etc/skel (kopiowany przy useradd -m)
        let skel_dir = format!("{}/etc/skel/.config/systemd/user", TARGET);
        tokio::fs::create_dir_all(&skel_dir).await?;
        tokio::fs::write(format!("{}/hackeros-gaming-setup.service", skel_dir), format!(
            r#"[Unit]
            Description=HackerOS Gaming First Boot
            After=network-online.target
            Wants=network-online.target
            ConditionPathExists=/usr/lib/HackerOS/gaming-setup.sh

            [Service]
            Type=oneshot
            ExecStart=/usr/lib/HackerOS/gaming-setup.sh
            StandardOutput=journal
            RemainAfterExit=yes

            [Install]
            WantedBy=default.target
            "#
        )).await?;

        // Symlink wants
        let wants = format!("{}/etc/skel/.config/systemd/user/default.target.wants", TARGET);
        tokio::fs::create_dir_all(&wants).await?;
        let _ = tokio::fs::remove_file(
            format!("{}/hackeros-gaming-setup.service", wants)).await;
            run("ln", &["-sf",
                "../hackeros-gaming-setup.service",
                &format!("{}/hackeros-gaming-setup.service", wants),
            ]).await?;

            // linger
            chroot("bash", &["-c",
                   &format!("loginctl enable-linger {} 2>/dev/null || true", username)
            ]).await?;

            self.log("  First-boot service utworzony: hackeros-gaming-setup.service");
            Ok(())
    }

    // ── 10. Finalizacja ───────────────────────────────────────────────────────

    // FIX: parametr _user z prefiksem _ żeby wyciszyć warning
    async fn do_final_setup(&self, config: &InstallerConfig) -> Result<()> {
        if let Some(script) = &config.post_install_script {
            if std::path::Path::new(script).exists() {
                let dst = format!("{}/tmp/post-install.sh", TARGET);
                tokio::fs::copy(script, &dst).await?;
                chroot("bash", &["/tmp/post-install.sh"]).await?;
                let _ = tokio::fs::remove_file(&dst).await;
            }
        }

        chroot("update-initramfs", &["-u", "-k", "all"]).await
        .unwrap_or_else(|e| warn!("update-initramfs: {}", e));
        chroot("apt-get", &["autoremove", "-y", "--purge"]).await
        .unwrap_or_else(|e| warn!("autoremove: {}", e));
        chroot("apt-get", &["clean"]).await
        .unwrap_or_else(|e| warn!("apt clean: {}", e));

        self.bind_mounts(false).await?;
        let _ = run("sync", &[]).await;
        self.log("  Instalacja zakończona.");
        Ok(())
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    async fn bind_mounts(&self, mount: bool) -> Result<()> {
        let mps = [
            ("/proc",    format!("{}/proc",    TARGET)),
            ("/sys",     format!("{}/sys",     TARGET)),
            ("/dev",     format!("{}/dev",     TARGET)),
            ("/dev/pts", format!("{}/dev/pts", TARGET)),
            ("/run",     format!("{}/run",     TARGET)),
        ];
        if mount {
            for (src, dst) in &mps {
                tokio::fs::create_dir_all(dst).await?;
                run("mount", &["--bind", src, dst]).await
                .unwrap_or_else(|e| warn!("bind {}: {}", src, e));
            }
        } else {
            for (_, dst) in mps.iter().rev() {
                run("umount", &["-lf", dst]).await
                .unwrap_or_else(|e| warn!("umount {}: {}", dst, e));
            }
        }
        Ok(())
    }
}

// ─── Funkcje pomocnicze ───────────────────────────────────────────────────────

async fn run(cmd: &str, args: &[&str]) -> Result<()> {
    info!("$ {} {}", cmd, args.join(" "));
    let out = Command::new(cmd).args(args).output().await?;
    if !out.status.success() {
        anyhow::bail!("{}: {}", cmd, String::from_utf8_lossy(&out.stderr).trim());
    }
    Ok(())
}

async fn chroot(cmd: &str, args: &[&str]) -> Result<()> {
    let mut full = vec![TARGET, cmd];
    full.extend_from_slice(args);
    info!("chroot $ {} {}", cmd, args.join(" "));
    let out = Command::new("chroot").args(&full).output().await?;
    if !out.status.success() {
        anyhow::bail!("chroot {}: {}", cmd, String::from_utf8_lossy(&out.stderr).trim());
    }
    Ok(())
}

async fn get_uuid(dev: &str) -> Result<String> {
    let out = Command::new("blkid")
    .args(["-s", "UUID", "-o", "value", dev])
    .output().await?;
    let uuid = String::from_utf8_lossy(&out.stdout).trim().to_string();
    if uuid.is_empty() { anyhow::bail!("Brak UUID dla {}", dev); }
    Ok(uuid)
}

async fn build_fstab(plan: &PartitionPlan, config: &InstallerConfig) -> Result<String> {
    let mut out = String::from(
        "# /etc/fstab – wygenerowany przez HackerOS Installer\n\
# <file system>  <mount>  <type>  <options>  <dump>  <pass>\n\n"
    );

    let gcfg = if config.is_gaming_edition() { Some(config.gaming_config()) } else { None };

    for (i, part) in plan.partitions.iter().enumerate() {
        let dev  = part_path(&plan.disk, i + 1);
        let uuid = get_uuid(&dev).await.unwrap_or_else(|_| dev.clone());

        match part.filesystem.as_str() {
            "linux-swap" => { out.push_str(&format!("UUID={}\tnone\tswap\tsw\t0\t0\n", uuid)); }
            "fat32" | "fat16" => {
                out.push_str(&format!("UUID={}\t{}\tvfat\tumask=0077\t0\t2\n",
                                      uuid, part.mountpoint));
            }
            "btrfs" => {
                if let Some(gcfg) = &gcfg {
                    if let Some(subvols) = &gcfg.btrfs_subvolumes {
                        for sv in subvols {
                            let opts = sv.mount_options.as_deref().unwrap_or("compress=zstd,noatime");
                            let pass = if sv.mountpoint == "/" { 1 } else { 0 };
                            out.push_str(&format!("UUID={}\t{}\tbtrfs\tsubvol={},{}\t0\t{}\n",
                                                  uuid, sv.mountpoint, sv.name, opts, pass));
                        }
                        continue;
                    }
                }
                out.push_str(&format!("UUID={}\t{}\tbtrfs\tcompress=zstd,noatime\t0\t1\n",
                                      uuid, part.mountpoint));
            }
            _ => {
                let pass = if part.mountpoint == "/" { 1 } else { 2 };
                out.push_str(&format!("UUID={}\t{}\t{}\tdefaults,noatime\t0\t{}\n",
                                      uuid, part.mountpoint, part.filesystem, pass));
            }
        }
    }
    if config.swap_type == "zram" {
        out.push_str("\n# zram swap zarządzany przez serwis zramswap\n");
    }
    Ok(out)
}
