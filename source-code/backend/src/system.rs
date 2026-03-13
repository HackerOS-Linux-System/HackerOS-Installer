use anyhow::Result;
use serde::{Deserialize, Serialize};
use tokio::fs;
use tokio::process::Command;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SystemInfo {
    pub hostname:        String,
    pub cpu_model:       String,
    pub cpu_cores:       u32,
    pub ram_total_bytes: u64,
    pub ram_total_human: String,
    pub arch:            String,
    pub is_efi:          bool,
    pub is_vm:           bool,
}

impl SystemInfo {
    pub async fn gather() -> Result<Self> {
        let hostname = fs::read_to_string("/etc/hostname").await
        .unwrap_or_else(|_| "hackeros".to_string())
        .trim().to_string();

        let cpu_info = fs::read_to_string("/proc/cpuinfo").await.unwrap_or_default();
        let cpu_model = cpu_info.lines()
        .find(|l| l.starts_with("model name"))
        .and_then(|l| l.split(':').nth(1))
        .map(|s| s.trim().to_string())
        .unwrap_or_else(|| "Unknown CPU".to_string());
        let cpu_cores = cpu_info.lines().filter(|l| l.starts_with("processor")).count() as u32;

        let mem_info = fs::read_to_string("/proc/meminfo").await.unwrap_or_default();
        let ram_total_bytes = mem_info.lines()
        .find(|l| l.starts_with("MemTotal:"))
        .and_then(|l| l.split_whitespace().nth(1))
        .and_then(|s| s.parse::<u64>().ok())
        .unwrap_or(0) * 1024;

        let arch   = std::env::consts::ARCH.to_string();
        let is_efi = std::path::Path::new("/sys/firmware/efi").exists();
        let is_vm  = check_is_vm().await;

        Ok(SystemInfo {
            hostname, cpu_model, cpu_cores, ram_total_bytes,
            // FIX: bytes_to_human → bytes_human (poprawna nazwa funkcji w disk.rs)
            ram_total_human: crate::disk::bytes_human(ram_total_bytes),
           arch, is_efi, is_vm,
        })
    }
}

async fn check_is_vm() -> bool {
    if let Ok(out) = Command::new("systemd-detect-virt").output().await {
        let v = String::from_utf8_lossy(&out.stdout);
        let v = v.trim();
        v != "none" && !v.is_empty()
    } else { false }
}

pub async fn list_timezones() -> Result<Vec<TimezoneInfo>> {
    let out = Command::new("timedatectl").args(["list-timezones"]).output().await?;
    let stdout = String::from_utf8_lossy(&out.stdout);
    let mut tzs = Vec::new();
    for tz in stdout.lines() {
        let tz = tz.trim().to_string();
        if tz.is_empty() { continue; }
        let region = tz.split('/').next().unwrap_or("Other").to_string();
        let city   = tz.split('/').last().unwrap_or(&tz).replace('_', " ");
        tzs.push(TimezoneInfo { id: tz, region, city });
    }
    Ok(tzs)
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TimezoneInfo { pub id: String, pub region: String, pub city: String }

pub async fn list_locales() -> Result<Vec<LocaleInfo>> {
    let locales = vec![
        ("pl_PL.UTF-8", "Polski (Polska)"),
        ("en_US.UTF-8", "English (United States)"),
        ("en_GB.UTF-8", "English (United Kingdom)"),
        ("de_DE.UTF-8", "Deutsch (Deutschland)"),
        ("fr_FR.UTF-8", "Français (France)"),
        ("es_ES.UTF-8", "Español (España)"),
        ("it_IT.UTF-8", "Italiano (Italia)"),
        ("pt_BR.UTF-8", "Português (Brasil)"),
        ("pt_PT.UTF-8", "Português (Portugal)"),
        ("ru_RU.UTF-8", "Русский (Россия)"),
        ("cs_CZ.UTF-8", "Čeština (Česko)"),
        ("nl_NL.UTF-8", "Nederlands (Nederland)"),
        ("sv_SE.UTF-8", "Svenska (Sverige)"),
        ("tr_TR.UTF-8", "Türkçe (Türkiye)"),
        ("uk_UA.UTF-8", "Українська (Україна)"),
        ("zh_CN.UTF-8", "中文 (简体)"),
        ("zh_TW.UTF-8", "中文 (繁體)"),
        ("ja_JP.UTF-8", "日本語 (日本)"),
        ("ko_KR.UTF-8", "한국어 (대한민국)"),
        ("ar_SA.UTF-8", "العربية (السعودية)"),
        ("hu_HU.UTF-8", "Magyar (Magyarország)"),
        ("ro_RO.UTF-8", "Română (România)"),
        ("hi_IN.UTF-8", "हिन्दी (भारत)"),
    ];
    Ok(locales.into_iter()
    .map(|(id, name)| LocaleInfo { id: id.to_string(), name: name.to_string() })
    .collect())
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LocaleInfo { pub id: String, pub name: String }

pub async fn list_keyboard_layouts() -> Result<Vec<KeyboardLayout>> {
    let layouts = vec![
        ("pl","Polski"), ("us","English (US)"), ("gb","English (UK)"),
        ("de","Deutsch"), ("fr","Français"), ("es","Español"),
        ("it","Italiano"), ("pt","Português"), ("br","Português (BR)"),
        ("ru","Русский"), ("ua","Українська"), ("cs","Čeština"),
        ("nl","Nederlands"), ("se","Svenska"), ("no","Norsk"),
        ("dk","Dansk"), ("fi","Suomi"), ("hu","Magyar"),
        ("tr","Türkçe"), ("ro","Română"), ("gr","Ελληνικά"),
        ("ara","العربية"), ("il","עברית"), ("jp","日本語"),
        ("kr","한국어"), ("cn","中文"), ("latam","Español (LATAM)"),
        ("hr","Hrvatski"), ("sk","Slovenčina"),
    ];
    Ok(layouts.into_iter()
    .map(|(id, name)| KeyboardLayout { id: id.to_string(), name: name.to_string() })
    .collect())
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct KeyboardLayout { pub id: String, pub name: String }
