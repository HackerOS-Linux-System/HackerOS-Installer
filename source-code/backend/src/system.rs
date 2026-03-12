use anyhow::Result;
use serde::{Deserialize, Serialize};
use tokio::fs;
use tokio::process::Command;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SystemInfo {
    pub hostname: String,
    pub cpu_model: String,
    pub cpu_cores: u32,
    pub ram_total_bytes: u64,
    pub ram_total_human: String,
    pub arch: String,
    pub is_efi: bool,
    pub is_vm: bool,
}

impl SystemInfo {
    pub async fn gather() -> Result<Self> {
        let hostname = fs::read_to_string("/etc/hostname")
            .await
            .unwrap_or_else(|_| "hackeros".to_string())
            .trim()
            .to_string();

        let cpu_info = fs::read_to_string("/proc/cpuinfo").await.unwrap_or_default();
        let cpu_model = cpu_info
            .lines()
            .find(|l| l.starts_with("model name"))
            .and_then(|l| l.split(':').nth(1))
            .map(|s| s.trim().to_string())
            .unwrap_or_else(|| "Unknown CPU".to_string());

        let cpu_cores = cpu_info
            .lines()
            .filter(|l| l.starts_with("processor"))
            .count() as u32;

        let mem_info = fs::read_to_string("/proc/meminfo").await.unwrap_or_default();
        let ram_total_bytes = mem_info
            .lines()
            .find(|l| l.starts_with("MemTotal:"))
            .and_then(|l| l.split_whitespace().nth(1))
            .and_then(|s| s.parse::<u64>().ok())
            .unwrap_or(0)
            * 1024;

        let arch = std::env::consts::ARCH.to_string();
        let is_efi = std::path::Path::new("/sys/firmware/efi").exists();

        // Check if running in VM
        let is_vm = check_is_vm().await;

        Ok(SystemInfo {
            hostname,
            cpu_model,
            cpu_cores,
            ram_total_bytes,
            ram_total_human: crate::disk::bytes_to_human(ram_total_bytes),
            arch,
            is_efi,
            is_vm,
        })
    }
}

async fn check_is_vm() -> bool {
    if let Ok(output) = Command::new("systemd-detect-virt").output().await {
        let stdout = String::from_utf8_lossy(&output.stdout);
        let virt = stdout.trim();
        virt != "none" && !virt.is_empty()
    } else {
        false
    }
}

pub async fn list_timezones() -> Result<Vec<TimezoneInfo>> {
    let output = Command::new("timedatectl")
        .args(["list-timezones"])
        .output()
        .await?;

    let stdout = String::from_utf8_lossy(&output.stdout);
    let mut timezones = Vec::new();

    for tz in stdout.lines() {
        let tz = tz.trim().to_string();
        if tz.is_empty() {
            continue;
        }

        let region = tz.split('/').next().unwrap_or("Other").to_string();
        let city = tz.split('/').last().unwrap_or(&tz).replace('_', " ");

        timezones.push(TimezoneInfo { id: tz, region, city });
    }

    Ok(timezones)
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TimezoneInfo {
    pub id: String,
    pub region: String,
    pub city: String,
}

pub async fn list_locales() -> Result<Vec<LocaleInfo>> {
    // Return common locales
    let common_locales = vec![
        ("en_US.UTF-8", "English (United States)"),
        ("en_GB.UTF-8", "English (United Kingdom)"),
        ("de_DE.UTF-8", "German (Germany)"),
        ("fr_FR.UTF-8", "French (France)"),
        ("es_ES.UTF-8", "Spanish (Spain)"),
        ("it_IT.UTF-8", "Italian (Italy)"),
        ("pt_BR.UTF-8", "Portuguese (Brazil)"),
        ("pt_PT.UTF-8", "Portuguese (Portugal)"),
        ("ru_RU.UTF-8", "Russian (Russia)"),
        ("zh_CN.UTF-8", "Chinese (Simplified)"),
        ("zh_TW.UTF-8", "Chinese (Traditional)"),
        ("ja_JP.UTF-8", "Japanese (Japan)"),
        ("ko_KR.UTF-8", "Korean (South Korea)"),
        ("ar_SA.UTF-8", "Arabic (Saudi Arabia)"),
        ("pl_PL.UTF-8", "Polish (Poland)"),
        ("nl_NL.UTF-8", "Dutch (Netherlands)"),
        ("sv_SE.UTF-8", "Swedish (Sweden)"),
        ("tr_TR.UTF-8", "Turkish (Turkey)"),
        ("cs_CZ.UTF-8", "Czech (Czech Republic)"),
        ("hu_HU.UTF-8", "Hungarian (Hungary)"),
        ("uk_UA.UTF-8", "Ukrainian (Ukraine)"),
        ("vi_VN.UTF-8", "Vietnamese (Vietnam)"),
        ("th_TH.UTF-8", "Thai (Thailand)"),
        ("id_ID.UTF-8", "Indonesian (Indonesia)"),
        ("hi_IN.UTF-8", "Hindi (India)"),
    ];

    Ok(common_locales
        .into_iter()
        .map(|(id, name)| LocaleInfo { id: id.to_string(), name: name.to_string() })
        .collect())
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LocaleInfo {
    pub id: String,
    pub name: String,
}

pub async fn list_keyboard_layouts() -> Result<Vec<KeyboardLayout>> {
    let layouts = vec![
        ("us", "English (US)"),
        ("gb", "English (UK)"),
        ("de", "German"),
        ("fr", "French"),
        ("es", "Spanish"),
        ("it", "Italian"),
        ("pt", "Portuguese"),
        ("ru", "Russian"),
        ("pl", "Polish"),
        ("nl", "Dutch"),
        ("se", "Swedish"),
        ("no", "Norwegian"),
        ("dk", "Danish"),
        ("fi", "Finnish"),
        ("hu", "Hungarian"),
        ("cs", "Czech"),
        ("sk", "Slovak"),
        ("tr", "Turkish"),
        ("jp", "Japanese"),
        ("kr", "Korean"),
        ("cn", "Chinese"),
        ("br", "Brazilian Portuguese"),
        ("latam", "Latin American Spanish"),
        ("ua", "Ukrainian"),
        ("ro", "Romanian"),
        ("hr", "Croatian"),
        ("si", "Slovenian"),
        ("gr", "Greek"),
        ("il", "Hebrew"),
        ("ara", "Arabic"),
        ("th", "Thai"),
        ("vn", "Vietnamese"),
    ];

    Ok(layouts
        .into_iter()
        .map(|(id, name)| KeyboardLayout { id: id.to_string(), name: name.to_string() })
        .collect())
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct KeyboardLayout {
    pub id: String,
    pub name: String,
}
