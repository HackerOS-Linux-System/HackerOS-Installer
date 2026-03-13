use anyhow::Result;
use serde::{Deserialize, Serialize};
use tokio::process::Command;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NetworkInterface {
    pub name:            String,
    pub interface_type:  String,   // "wifi" | "ethernet" | "other"
    pub connected:       bool,
    pub ip_address:      Option<String>,
    pub mac_address:     Option<String>,
    pub device_path:     Option<String>,
    pub signal_strength: Option<i32>,
    pub ssid:            Option<String>,
    // Dodatkowe pole – bezpośredni wynik testu internetu
    pub has_internet:    bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WifiNetwork {
    pub ssid:      String,
    pub signal:    i32,
    pub security:  String,
    pub frequency: Option<String>,
    pub in_use:    bool,
}

pub struct NetworkManager;
impl NetworkManager { pub fn new() -> Self { Self } }

// ─── Sprawdzenie internetu przez curl/ping ────────────────────────────────────
// Działa niezależnie od nmcli – testuje faktyczną dostępność sieci.
pub async fn check_internet() -> bool {
    // Próba 1: curl HEAD do detectportal.firefox.com (lekkie, 200 OK bez treści)
    if let Ok(out) = Command::new("curl")
        .args(["-s", "--max-time", "4", "--head",
              "http://detectportal.firefox.com/success.txt"])
        .output().await
        {
            if out.status.success() {
                let body = String::from_utf8_lossy(&out.stdout);
                if body.contains("200") || body.contains("204") {
                    return true;
                }
            }
        }

        // Próba 2: ping 8.8.8.8 (1 pakiet, 3 sekundy)
        if let Ok(out) = Command::new("ping")
            .args(["-c", "1", "-W", "3", "8.8.8.8"])
            .output().await
            {
                if out.status.success() {
                    return true;
                }
            }

            // Próba 3: ping 1.1.1.1
            if let Ok(out) = Command::new("ping")
                .args(["-c", "1", "-W", "3", "1.1.1.1"])
                .output().await
                {
                    if out.status.success() {
                        return true;
                    }
                }

                false
}

// ─── Lista interfejsów ────────────────────────────────────────────────────────
// Sprawdza IP przez `ip addr` (działa zawsze), nmcli tylko pomocniczo.
pub async fn list_interfaces() -> Result<Vec<NetworkInterface>> {
    let has_net = check_internet().await;
    let mut interfaces = Vec::new();

    // Pobierz listę interfejsów z `ip -br addr` – format: NAME  STATE  IP/PREFIX
    let out = Command::new("ip")
    .args(["-br", "addr"])
    .output().await?;
    let stdout = String::from_utf8_lossy(&out.stdout);

    for line in stdout.lines() {
        let parts: Vec<&str> = line.split_whitespace().collect();
        if parts.len() < 2 { continue; }

        let name  = parts[0].to_string();
        let state = parts[1].to_string(); // UP / DOWN / UNKNOWN

        if name == "lo" || name.starts_with("docker") || name.starts_with("br-")
            || name.starts_with("veth") || name.starts_with("virbr") { continue; }

            // IP z trzeciego kolumna (może być puste)
            let ip_raw = parts.get(2).unwrap_or(&"").to_string();
        let ip = if ip_raw.is_empty() || ip_raw == "--" { None }
        else { Some(ip_raw.split('/').next().unwrap_or("").to_string()) };

        // Interfejs "połączony" jeśli ma IP lub stan UP/UNKNOWN z IP
        let connected = ip.is_some() && (
            state == "UP" || state == "UNKNOWN" || state == "up" || state == "unknown"
        );

        // Typ interfejsu
        let interface_type = detect_iface_type(&name).await;

        // SSID jeśli WiFi i połączony
        let ssid = if interface_type == "wifi" && connected {
            get_wifi_ssid(&name).await.ok()
        } else { None };

        let signal_strength = if interface_type == "wifi" && connected {
            get_wifi_signal(&name).await.ok()
        } else { None };

        interfaces.push(NetworkInterface {
            name,
            interface_type,
            connected,
            ip_address: ip,
            mac_address: None,
            device_path: None,
            signal_strength,
            ssid,
            // Interfejsy z IP dostają has_internet = wynik globalnego testu
            has_internet: connected && has_net,
        });
    }

    // Jeśli ip -br nie zadziałało lub zwróciło pustą listę, fallback do nmcli
    if interfaces.is_empty() {
        return list_interfaces_nmcli(has_net).await;
    }

    Ok(interfaces)
}

async fn detect_iface_type(name: &str) -> String {
    // Sprawdź /sys/class/net/<name>/wireless
    if tokio::fs::metadata(format!("/sys/class/net/{}/wireless", name)).await.is_ok() {
        return "wifi".to_string();
    }
    // Sprawdź typ przez nmcli jeśli dostępny
    if let Ok(out) = Command::new("nmcli")
        .args(["-t", "-f", "GENERAL.TYPE", "device", "show", name])
        .output().await
        {
            let s = String::from_utf8_lossy(&out.stdout);
            for line in s.lines() {
                if let Some(t) = line.strip_prefix("GENERAL.TYPE:") {
                    let t = t.trim().to_lowercase();
                    if t.contains("wifi") || t.contains("wireless") { return "wifi".to_string(); }
                    if t.contains("ethernet") { return "ethernet".to_string(); }
                }
            }
        }
        // Heurystyka po nazwie
        if name.starts_with("wl") || name.contains("wifi") || name.contains("wlan") {
            return "wifi".to_string();
        }
        "ethernet".to_string()
}

// Fallback gdy `ip -br addr` nie zadziała
async fn list_interfaces_nmcli(has_net: bool) -> Result<Vec<NetworkInterface>> {
    let output = Command::new("nmcli")
    .args(["-t", "-f", "DEVICE,TYPE,STATE,CONNECTION", "device"])
    .output().await?;

    let stdout = String::from_utf8_lossy(&output.stdout);
    let mut interfaces = Vec::new();

    for line in stdout.lines() {
        let parts: Vec<&str> = line.split(':').collect();
        if parts.len() < 3 { continue; }

        let name      = parts[0].to_string();
        let dev_type  = parts[1];
        let state     = parts[2];

        if name == "lo" || dev_type == "loopback" { continue; }

        let interface_type = match dev_type {
            "wifi"     => "wifi",
            "ethernet" => "ethernet",
            _          => "other",
        };

        // nmcli state: "connected", "disconnected", "unavailable", "unmanaged", "unknown"
        let connected = matches!(state, "connected" | "unmanaged")
        || {
            // Podwójne sprawdzenie przez IP
            let ip = get_ip_address(&name).await.ok();
            ip.is_some()
        };

        let ip = if connected { get_ip_address(&name).await.ok() } else { None };
        let ssid = if interface_type == "wifi" && connected {
            get_wifi_ssid(&name).await.ok()
        } else { None };

        interfaces.push(NetworkInterface {
            name,
            interface_type: interface_type.to_string(),
                        connected,
                        ip_address: ip,
                        mac_address: None,
                        device_path: None,
                        signal_strength: None,
                        ssid,
                        has_internet: connected && has_net,
        });
    }

    Ok(interfaces)
}

// ─── Skanowanie WiFi ──────────────────────────────────────────────────────────
pub async fn scan_wifi(interface: &str) -> Result<Vec<WifiNetwork>> {
    let _ = Command::new("nmcli")
    .args(["device", "wifi", "rescan", "ifname", interface])
    .output().await;

    tokio::time::sleep(tokio::time::Duration::from_secs(2)).await;

    let output = Command::new("nmcli")
    .args(["-t", "-f", "SSID,SIGNAL,SECURITY,FREQ,IN-USE",
          "device", "wifi", "list", "ifname", interface])
    .output().await?;

    let stdout = String::from_utf8_lossy(&output.stdout);
    let mut networks = Vec::new();
    let mut seen = std::collections::HashSet::new();

    for line in stdout.lines() {
        let parts: Vec<&str> = line.splitn(5, ':').collect();
        if parts.len() < 4 { continue; }

        let ssid = parts[0].to_string();
        if ssid.is_empty() || seen.contains(&ssid) { continue; }
        seen.insert(ssid.clone());

        let signal: i32 = parts[1].parse().unwrap_or(0);
        let security    = parts[2].to_string();
        let freq        = parts[3].to_string();
        let in_use      = parts.get(4).map(|s| s.trim() == "*").unwrap_or(false);

        let security_str = if security.is_empty() { "Open".to_string() }
        else if security.contains("WPA3")              { "WPA3".to_string() }
        else if security.contains("WPA2") || security.contains("WPA") { "WPA2".to_string() }
        else { security };

        networks.push(WifiNetwork {
            ssid, signal, security: security_str,
            frequency: if freq.is_empty() { None } else { Some(freq) },
                      in_use,
        });
    }

    networks.sort_by(|a, b| b.signal.cmp(&a.signal));
    Ok(networks)
}

// ─── Połącz WiFi ─────────────────────────────────────────────────────────────
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

// ─── Połącz Ethernet ─────────────────────────────────────────────────────────
pub async fn connect_ethernet(interface: &str) -> Result<()> {
    let output = Command::new("nmcli")
    .args(["device", "connect", interface])
    .output().await?;
    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        anyhow::bail!("nmcli connect failed: {}", stderr);
    }
    Ok(())
}

pub async fn disconnect(interface: &str) -> Result<()> {
    let output = Command::new("nmcli")
    .args(["device", "disconnect", interface])
    .output().await?;
    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        anyhow::bail!("nmcli disconnect failed: {}", stderr);
    }
    Ok(())
}

// ─── Helpers ──────────────────────────────────────────────────────────────────
async fn get_ip_address(interface: &str) -> Result<String> {
    // Metoda 1: ip addr show
    let out = Command::new("ip")
    .args(["addr", "show", interface])
    .output().await?;
    let s = String::from_utf8_lossy(&out.stdout);
    for line in s.lines() {
        let t = line.trim();
        if t.starts_with("inet ") {
            if let Some(ip) = t.split_whitespace().nth(1) {
                return Ok(ip.split('/').next().unwrap_or(ip).to_string());
            }
        }
    }
    anyhow::bail!("No IP for {}", interface)
}

async fn get_wifi_ssid(interface: &str) -> Result<String> {
    let out = Command::new("nmcli")
    .args(["-t", "-f", "GENERAL.CONNECTION", "device", "show", interface])
    .output().await?;
    let s = String::from_utf8_lossy(&out.stdout);
    for line in s.lines() {
        if let Some(ssid) = line.strip_prefix("GENERAL.CONNECTION:") {
            let ssid = ssid.trim().to_string();
            if !ssid.is_empty() { return Ok(ssid); }
        }
    }
    anyhow::bail!("No SSID")
}

async fn get_wifi_signal(interface: &str) -> Result<i32> {
    let out = Command::new("nmcli")
    .args(["-t", "-f", "WIFI-PROPERTIES.STRENGTH", "device", "show", interface])
    .output().await?;
    let s = String::from_utf8_lossy(&out.stdout);
    for line in s.lines() {
        if let Some(v) = line.strip_prefix("WIFI-PROPERTIES.STRENGTH:") {
            if let Ok(n) = v.trim().parse::<i32>() { return Ok(n); }
        }
    }
    Ok(0)
}
