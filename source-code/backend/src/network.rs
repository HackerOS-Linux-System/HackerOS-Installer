use anyhow::Result;
use serde::{Deserialize, Serialize};
use tokio::process::Command;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NetworkInterface {
    pub name: String,
    pub interface_type: String, // "wifi", "ethernet", "loopback", "other"
    pub connected: bool,
    pub ip_address: Option<String>,
    pub mac_address: Option<String>,
    pub device_path: Option<String>,
    pub signal_strength: Option<i32>, // for wifi
    pub ssid: Option<String>,         // for wifi
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WifiNetwork {
    pub ssid: String,
    pub signal: i32,
    pub security: String, // "WPA2", "WPA3", "WEP", "Open"
    pub frequency: Option<String>,
    pub in_use: bool,
}

pub struct NetworkManager;

impl NetworkManager {
    pub fn new() -> Self {
        Self
    }
}

pub async fn list_interfaces() -> Result<Vec<NetworkInterface>> {
    let output = Command::new("nmcli")
        .args(["-t", "-f", "DEVICE,TYPE,STATE,CONNECTION,CON-PATH", "device"])
        .output()
        .await?;

    let stdout = String::from_utf8_lossy(&output.stdout);
    let mut interfaces = Vec::new();

    for line in stdout.lines() {
        let parts: Vec<&str> = line.split(':').collect();
        if parts.len() < 3 {
            continue;
        }

        let name = parts[0].to_string();
        let dev_type = parts[1];
        let state = parts[2];

        if name == "lo" || dev_type == "loopback" {
            continue;
        }

        let interface_type = match dev_type {
            "wifi" => "wifi",
            "ethernet" => "ethernet",
            _ => "other",
        };

        let connected = state == "connected";

        // Get IP address
        let ip = if connected {
            get_ip_address(&name).await.ok()
        } else {
            None
        };

        // Get SSID if wifi and connected
        let ssid = if interface_type == "wifi" && connected {
            get_wifi_ssid(&name).await.ok()
        } else {
            None
        };

        // Get signal strength
        let signal_strength = if interface_type == "wifi" && connected {
            get_wifi_signal(&name).await.ok()
        } else {
            None
        };

        interfaces.push(NetworkInterface {
            name,
            interface_type: interface_type.to_string(),
            connected,
            ip_address: ip,
            mac_address: None,
            device_path: None,
            signal_strength,
            ssid,
        });
    }

    Ok(interfaces)
}

pub async fn scan_wifi(interface: &str) -> Result<Vec<WifiNetwork>> {
    // Rescan first
    let _ = Command::new("nmcli")
        .args(["device", "wifi", "rescan", "ifname", interface])
        .output()
        .await;

    // Small delay for scan to complete
    tokio::time::sleep(tokio::time::Duration::from_secs(2)).await;

    let output = Command::new("nmcli")
        .args([
            "-t",
            "-f",
            "SSID,SIGNAL,SECURITY,FREQ,IN-USE",
            "device",
            "wifi",
            "list",
            "ifname",
            interface,
        ])
        .output()
        .await?;

    let stdout = String::from_utf8_lossy(&output.stdout);
    let mut networks = Vec::new();
    let mut seen_ssids = std::collections::HashSet::new();

    for line in stdout.lines() {
        let parts: Vec<&str> = line.splitn(5, ':').collect();
        if parts.len() < 4 {
            continue;
        }

        let ssid = parts[0].to_string();
        if ssid.is_empty() || seen_ssids.contains(&ssid) {
            continue;
        }
        seen_ssids.insert(ssid.clone());

        let signal: i32 = parts[1].parse().unwrap_or(0);
        let security = parts[2].to_string();
        let freq = parts[3].to_string();
        let in_use = parts.get(4).map(|s| *s == "*").unwrap_or(false);

        let security_str = if security.is_empty() {
            "Open".to_string()
        } else if security.contains("WPA3") {
            "WPA3".to_string()
        } else if security.contains("WPA2") || security.contains("WPA") {
            "WPA2".to_string()
        } else {
            security
        };

        networks.push(WifiNetwork {
            ssid,
            signal,
            security: security_str,
            frequency: if freq.is_empty() { None } else { Some(freq) },
            in_use,
        });
    }

    // Sort by signal strength descending
    networks.sort_by(|a, b| b.signal.cmp(&a.signal));
    Ok(networks)
}

pub async fn connect_wifi(interface: &str, ssid: &str, password: Option<&str>) -> Result<()> {
    let mut args = vec!["device", "wifi", "connect", ssid, "ifname", interface];

    let pw_string;
    if let Some(pw) = password {
        pw_string = pw.to_string();
        args.push("password");
        args.push(&pw_string);
    }

    let output = Command::new("nmcli").args(&args).output().await?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        anyhow::bail!("nmcli connect failed: {}", stderr);
    }

    Ok(())
}

pub async fn connect_ethernet(interface: &str) -> Result<()> {
    let output = Command::new("nmcli")
        .args(["device", "connect", interface])
        .output()
        .await?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        anyhow::bail!("nmcli connect failed: {}", stderr);
    }

    Ok(())
}

pub async fn disconnect(interface: &str) -> Result<()> {
    let output = Command::new("nmcli")
        .args(["device", "disconnect", interface])
        .output()
        .await?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        anyhow::bail!("nmcli disconnect failed: {}", stderr);
    }

    Ok(())
}

async fn get_ip_address(interface: &str) -> Result<String> {
    let output = Command::new("nmcli")
        .args(["-t", "-f", "IP4.ADDRESS", "device", "show", interface])
        .output()
        .await?;

    let stdout = String::from_utf8_lossy(&output.stdout);
    for line in stdout.lines() {
        if let Some(ip) = line.strip_prefix("IP4.ADDRESS[1]:") {
            return Ok(ip.trim().to_string());
        }
    }

    anyhow::bail!("No IP address found for {}", interface)
}

async fn get_wifi_ssid(interface: &str) -> Result<String> {
    let output = Command::new("nmcli")
        .args(["-t", "-f", "GENERAL.CONNECTION", "device", "show", interface])
        .output()
        .await?;

    let stdout = String::from_utf8_lossy(&output.stdout);
    for line in stdout.lines() {
        if let Some(ssid) = line.strip_prefix("GENERAL.CONNECTION:") {
            return Ok(ssid.trim().to_string());
        }
    }

    anyhow::bail!("No SSID found")
}

async fn get_wifi_signal(interface: &str) -> Result<i32> {
    let output = Command::new("nmcli")
        .args(["-t", "-f", "WIFI-PROPERTIES.STRENGTH", "device", "show", interface])
        .output()
        .await?;

    let stdout = String::from_utf8_lossy(&output.stdout);
    for line in stdout.lines() {
        if let Some(strength) = line.strip_prefix("WIFI-PROPERTIES.STRENGTH:") {
            if let Ok(val) = strength.trim().parse::<i32>() {
                return Ok(val);
            }
        }
    }

    Ok(0)
}
