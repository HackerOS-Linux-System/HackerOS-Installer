use anyhow::Result;
use serde::{Deserialize, Serialize};
use std::path::Path;
use tokio::fs;

// ─── Edycje (tylko 2) ────────────────────────────────────────────────────────

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "lowercase")]
pub enum Edition {
    Gaming,
    Official,
}

impl Edition {
    pub fn from_str(s: &str) -> Self {
        match s.to_lowercase().as_str() {
            "official" => Edition::Official,
            _          => Edition::Gaming,
        }
    }
    pub fn as_str(&self) -> &'static str {
        match self {
            Edition::Gaming   => "gaming",
            Edition::Official => "official",
        }
    }
    pub fn display_name(&self) -> &'static str {
        match self {
            Edition::Gaming   => "Gaming Edition",
            Edition::Official => "Official Edition",
        }
    }
}

// ─── Baza ────────────────────────────────────────────────────────────────────
// trixie = Debian 13 Stable
// forky  = Debian Testing (kryptonim „forky")

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "lowercase")]
pub enum Base {
    Trixie,
    Forky,
}

impl Base {
    pub fn from_str(s: &str) -> Self {
        match s.to_lowercase().as_str() {
            "forky" | "testing" => Base::Forky,
            _                   => Base::Trixie,
        }
    }
    pub fn suite(&self) -> &'static str {
        match self { Base::Trixie => "trixie", Base::Forky => "forky" }
    }
    pub fn security_suite(&self) -> &'static str {
        match self { Base::Trixie => "trixie-security", Base::Forky => "forky-security" }
    }
    pub fn display_name(&self) -> &'static str {
        match self {
            Base::Trixie => "Debian 13 Trixie (Stable)",
            Base::Forky  => "Debian Testing – Forky (Rolling)",
        }
    }
}

// ─── Główna konfiguracja ─────────────────────────────────────────────────────

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct InstallerConfig {
    /// "gaming" lub "official"
    pub edition:               String,
    /// "trixie" (stable) lub "forky" (testing/rolling)
    pub base:                  String,
    pub desktop_environment:   String,
    pub bootloader:            String,
    pub swap_type:             String,
    pub swap_size_gb:          u32,
    pub require_network:       bool,
    pub backend_socket:        Option<String>,
    pub log_file:              Option<String>,
    pub configure_apt_sources: bool,
    pub extra_packages:        String,
    pub post_install_script:   Option<String>,
    pub gaming:                Option<GamingConfig>,
    pub official:              Option<OfficialConfig>,
}

// ─── Gaming ─────────────────────────────────────────────────────────────────

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GamingConfig {
    pub filesystem:               String,
    pub btrfs_subvolumes:         Option<Vec<BtrfsSubvolume>>,
    pub gamescope_session_repo:   Option<String>,
    pub distrobox_container_name: String,
    pub distrobox_image:          String,
    pub arch_packages:            Vec<String>,
    pub sddm_default_session:     String,
    pub install_lutris:           bool,
    pub install_wine:             bool,
    pub install_gamemode:         bool,
    pub install_mangohud:         bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BtrfsSubvolume {
    pub name:          String,
    pub mountpoint:    String,
    pub mount_options: Option<String>,
}

// ─── Official ────────────────────────────────────────────────────────────────

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OfficialConfig {
    pub filesystem: String,
}

// ─── Default ─────────────────────────────────────────────────────────────────

impl Default for InstallerConfig {
    fn default() -> Self {
        Self {
            edition:               "gaming".to_string(),
            base:                  "trixie".to_string(),
            desktop_environment:   "kde".to_string(),
            bootloader:            "grub".to_string(),
            swap_type:             "zram".to_string(),
            swap_size_gb:          8,
            require_network:       false,
            backend_socket:        Some("/tmp/hackeros-installer.sock".to_string()),
            log_file:              Some("/tmp/hackeros-installer.log".to_string()),
            configure_apt_sources: true,
            extra_packages:        "".to_string(),
            post_install_script:   None,
            gaming:                Some(default_gaming_config()),
            official:              None,
        }
    }
}

pub async fn load_config(path: &Path) -> Result<InstallerConfig> {
    let contents = fs::read_to_string(path).await?;
    let config: InstallerConfig = serde_yaml::from_str(&contents)?;
    Ok(config)
}

// ─── Metody pomocnicze ────────────────────────────────────────────────────────

impl InstallerConfig {
    pub fn edition(&self) -> Edition { Edition::from_str(&self.edition) }
    pub fn base(&self) -> Base       { Base::from_str(&self.base) }

    pub fn is_gaming_edition(&self) -> bool  { self.edition() == Edition::Gaming }
    pub fn is_official_edition(&self) -> bool { self.edition() == Edition::Official }

    pub fn get_filesystem(&self) -> &'static str {
        if self.is_gaming_edition() { "btrfs" } else { "ext4" }
    }

    pub fn requires_network(&self) -> bool {
        self.require_network || self.is_gaming_edition()
    }

    pub fn gaming_config(&self) -> GamingConfig {
        self.gaming.clone().unwrap_or_else(default_gaming_config)
    }

    /// Generuje sources.list dla zainstalowanego systemu
    pub fn build_sources_list(&self) -> String {
        let suite    = self.base().suite();
        let security = self.base().security_suite();
        match self.base() {
            Base::Trixie => format!(
                "# HackerOS – Debian {suite} (Stable)\n\
deb http://deb.debian.org/debian {suite} main contrib non-free non-free-firmware\n\
deb http://deb.debian.org/debian {suite}-updates main contrib non-free non-free-firmware\n\
deb http://deb.debian.org/debian {suite}-backports main contrib non-free non-free-firmware\n\
deb http://security.debian.org/debian-security {security} main contrib non-free non-free-firmware\n",
            ),
            Base::Forky => format!(
                "# HackerOS – Debian Testing / Forky (Rolling)\n\
deb http://deb.debian.org/debian {suite} main contrib non-free non-free-firmware\n\
deb http://deb.debian.org/debian {suite}-updates main contrib non-free non-free-firmware\n\
deb http://security.debian.org/debian-security {security} main contrib non-free non-free-firmware\n",
            ),
        }
    }
}

pub fn default_gaming_config() -> GamingConfig {
    GamingConfig {
        filesystem: "btrfs".to_string(),
        btrfs_subvolumes: Some(vec![
            BtrfsSubvolume { name: "@".to_string(),          mountpoint: "/".to_string(),           mount_options: Some("compress=zstd,noatime".to_string()) },
                               BtrfsSubvolume { name: "@home".to_string(),      mountpoint: "/home".to_string(),        mount_options: Some("compress=zstd,noatime".to_string()) },
                               BtrfsSubvolume { name: "@snapshots".to_string(), mountpoint: "/.snapshots".to_string(),  mount_options: Some("compress=zstd,noatime".to_string()) },
                               BtrfsSubvolume { name: "@var_log".to_string(),   mountpoint: "/var/log".to_string(),     mount_options: Some("compress=zstd,noatime".to_string()) },
                               BtrfsSubvolume { name: "@var_cache".to_string(), mountpoint: "/var/cache".to_string(),   mount_options: Some("compress=zstd,noatime".to_string()) },
        ]),
        gamescope_session_repo: Some(
            "https://github.com/HackerOS-Linux-System/gamescope-session-steam.git".to_string(),
        ),
        distrobox_container_name: "HackerOS-Steam".to_string(),
        distrobox_image: "archlinux:latest".to_string(),
        arch_packages: [
            "gamescope","steam",
            "lib32-mesa","lib32-vulkan-icd-loader","lib32-alsa-lib","lib32-gcc-libs",
            "lib32-gtk3","lib32-libgcrypt","lib32-libpulse","lib32-libva","lib32-libxml2",
            "lib32-nss","lib32-openal","lib32-sdl2",
            "lib32-vulkan-intel","lib32-vulkan-radeon","lib32-nvidia-utils",
            "lib32-libxss","lib32-libgpg-error","lib32-dbus",
            "lib32-vulkan-freedreno","lib32-vulkan-nouveau","lib32-vulkan-swrast","lib32-vulkan-virtio",
            "noto-fonts","ttf-bitstream-vera","ttf-croscore","ttf-dejavu","ttf-droid",
            "ttf-ibm-plex","ttf-liberation","ttf-roboto",
        ].iter().map(|s| s.to_string()).collect(),
        sddm_default_session: "/usr/share/wayland-sessions/gamescope-session-steam.desktop".to_string(),
        install_lutris:   true,
        install_wine:     true,
        install_gamemode: true,
        install_mangohud: true,
    }
}
