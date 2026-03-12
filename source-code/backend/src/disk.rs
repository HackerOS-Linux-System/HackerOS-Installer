use anyhow::Result;
use serde::{Deserialize, Serialize};
use tokio::process::Command;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DiskInfo {
    pub path:       String,
    pub name:       String,
    pub size_bytes: u64,
    pub size_human: String,
    pub model:      String,
    pub disk_type:  String,
    pub partitions: Vec<PartitionInfo>,
    pub removable:  bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PartitionInfo {
    pub path:       String,
    pub name:       String,
    pub size_bytes: u64,
    pub size_human: String,
    pub filesystem: String,
    pub mountpoint: Option<String>,
    pub label:      Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PartitionPlan {
    pub disk:       String,
    pub mode:       PartitionMode,
    pub partitions: Vec<PartitionSpec>,
    pub filesystem: String,
    pub efi:        bool,
    pub swap:       SwapSpec,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum PartitionMode { Auto, Manual, UseEntireDisk }

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PartitionSpec {
    pub mountpoint:      String,
    pub size_mb:         Option<u64>,
    pub filesystem:      String,
    pub flags:           Vec<String>,
    pub btrfs_subvolume: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SwapSpec {
    pub swap_type: String,
    pub size_gb:   u32,
}

// ─── Listowanie dysków ────────────────────────────────────────────────────────

pub async fn list_disks() -> Result<Vec<DiskInfo>> {
    let out = Command::new("lsblk")
    .args(["-J", "-b", "-o", "NAME,SIZE,MODEL,TYPE,FSTYPE,MOUNTPOINT,LABEL,RM"])
    .output().await?;

    let val: serde_json::Value = serde_json::from_str(&String::from_utf8_lossy(&out.stdout))?;
    let mut disks = Vec::new();

    if let Some(devices) = val["blockdevices"].as_array() {
        for dev in devices {
            if dev["type"].as_str() != Some("disk") { continue; }
            let name = dev["name"].as_str().unwrap_or("").to_string();
            if name.starts_with("loop") { continue; }

            let size_bytes = dev["size"].as_str()
            .and_then(|s| s.parse::<u64>().ok()).unwrap_or(0);
            if size_bytes < 8_000_000_000 { continue; }

            let removable = dev["rm"].as_bool().unwrap_or(false);
            let disk_type = if name.starts_with("nvme") { "nvme" }
            else if removable { "usb" }
            else {
                let rot = format!("/sys/block/{}/queue/rotational", name);
                match tokio::fs::read_to_string(&rot).await {
                    Ok(c) => if c.trim() == "0" { "ssd" } else { "hdd" },
                    Err(_) => "unknown",
                }
            };

            let mut partitions = Vec::new();
            if let Some(children) = dev["children"].as_array() {
                for child in children {
                    let pname = child["name"].as_str().unwrap_or("").to_string();
                    let psize = child["size"].as_str()
                    .and_then(|s| s.parse::<u64>().ok()).unwrap_or(0);
                    partitions.push(PartitionInfo {
                        path:       format!("/dev/{}", pname),
                                    name:       pname,
                                    size_bytes: psize,
                                    size_human: bytes_human(psize),
                                    filesystem: child["fstype"].as_str().unwrap_or("").to_string(),
                                    mountpoint: child["mountpoint"].as_str().map(String::from),
                                    label:      child["label"].as_str().map(String::from),
                    });
                }
            }

            disks.push(DiskInfo {
                path:       format!("/dev/{}", name),
                       name:       name.clone(),
                       size_bytes,
                       size_human: bytes_human(size_bytes),
                       model:      dev["model"].as_str().unwrap_or("Unknown").trim().to_string(),
                       disk_type:  disk_type.to_string(),
                       partitions,
                       removable,
            });
        }
    }
    Ok(disks)
}

pub fn bytes_human(b: u64) -> String {
    const KB: u64 = 1024;
    const MB: u64 = KB * 1024;
    const GB: u64 = MB * 1024;
    const TB: u64 = GB * 1024;
    if b >= TB      { format!("{:.1} TB", b as f64 / TB as f64) }
    else if b >= GB { format!("{:.1} GB", b as f64 / GB as f64) }
    else if b >= MB { format!("{:.1} MB", b as f64 / MB as f64) }
    else            { format!("{:.1} KB", b as f64 / KB as f64) }
}

fn is_efi() -> bool {
    std::path::Path::new("/sys/firmware/efi").exists()
}

/// FIX: _disk_size_bytes z prefixem _ żeby wyciszyć warning o nieużywanej zmiennej
pub fn create_auto_partition_plan(
    disk:               &str,
    _disk_size_bytes:   u64,
    filesystem:         &str,
    swap_type:          &str,
    swap_size_gb:       u32,
    is_gaming:          bool,
) -> PartitionPlan {
    let efi = is_efi();
    let mut partitions = Vec::new();

    if efi {
        partitions.push(PartitionSpec {
            mountpoint:      "/boot/efi".to_string(),
                        size_mb:         Some(512),
                        filesystem:      "fat32".to_string(),
                        flags:           vec!["esp".to_string(), "boot".to_string()],
                        btrfs_subvolume: None,
        });
    } else {
        partitions.push(PartitionSpec {
            mountpoint:      "/boot".to_string(),
                        size_mb:         Some(1024),
                        filesystem:      "ext4".to_string(),
                        flags:           vec!["boot".to_string()],
                        btrfs_subvolume: None,
        });
    }

    if swap_type == "partition" {
        partitions.push(PartitionSpec {
            mountpoint:      "swap".to_string(),
                        size_mb:         Some(swap_size_gb as u64 * 1024),
                        filesystem:      "linux-swap".to_string(),
                        flags:           vec!["swap".to_string()],
                        btrfs_subvolume: None,
        });
    }

    let root_fs = if is_gaming && filesystem == "btrfs" { "btrfs" } else { filesystem };
    let root_subvol = if is_gaming && filesystem == "btrfs" { Some("@".to_string()) } else { None };

    partitions.push(PartitionSpec {
        mountpoint:      "/".to_string(),
                    size_mb:         None,
                    filesystem:      root_fs.to_string(),
                    flags:           vec![],
                    btrfs_subvolume: root_subvol,
    });

    PartitionPlan {
        disk: disk.to_string(),
        mode: PartitionMode::Auto,
        partitions,
        filesystem: filesystem.to_string(),
        efi,
        swap: SwapSpec { swap_type: swap_type.to_string(), size_gb: swap_size_gb },
    }
}

pub fn part_path(disk: &str, num: usize) -> String {
    if disk.contains("nvme") || disk.contains("mmcblk") {
        format!("{}p{}", disk, num)
    } else {
        format!("{}{}", disk, num)
    }
}
