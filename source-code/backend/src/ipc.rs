use crate::config::InstallerConfig;
use crate::disk::PartitionPlan;        // DiskInfo usunięty – fix warning
use crate::install::InstallManager;
use crate::network::NetworkManager;
use crate::system::SystemInfo;
use crate::user::UserConfig;
use anyhow::Result;
use serde::{Deserialize, Serialize};
use std::sync::Arc;
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
use tokio::net::{UnixListener, UnixStream};
use tokio::sync::Mutex;
use tracing::{error, info, warn};

// ─── Request / Response ───────────────────────────────────────────────────────

#[derive(Debug, Serialize, Deserialize)]
#[serde(tag = "action", content = "data")]
pub enum IpcRequest {
    Ping,
    CheckInternet,
    GetConfig,
    GetSystemInfo,
    GetDisks,
    GetNetworkInterfaces,
    GetWifiNetworks         { interface: String },
    ConnectWifi             { interface: String, ssid: String, password: Option<String> },
    ConnectEthernet         { interface: String },
    DisconnectNetwork       { interface: String },
    GetTimezones,
    GetLocales,
    GetKeyboardLayouts,
    SetLocaleConfig         { locale: String, timezone: String, keyboard: String },
    SetPartitionPlan        { plan: PartitionPlan },
    SetUserConfig           { user: UserConfig },
    StartInstallation,
    GetInstallProgress,
    CancelInstallation,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct IpcResponse {
    pub success: bool,
    pub data:    Option<serde_json::Value>,
    pub error:   Option<String>,
}

impl IpcResponse {
    fn ok(data: serde_json::Value) -> Self {
        Self { success: true,  data: Some(data), error: None }
    }
    fn err(msg: impl ToString) -> Self {
        Self { success: false, data: None, error: Some(msg.to_string()) }
    }
}

// ─── State ────────────────────────────────────────────────────────────────────

pub struct AppState {
    pub config:          InstallerConfig,
    pub install_manager: InstallManager,
    pub network_manager: NetworkManager,
}

// ─── Server ──────────────────────────────────────────────────────────────────

pub async fn run_ipc_server(socket_path: String, config: InstallerConfig) -> Result<()> {
    let _ = std::fs::remove_file(&socket_path);
    let listener = UnixListener::bind(&socket_path)?;

    use std::os::unix::fs::PermissionsExt;
    std::fs::set_permissions(&socket_path, std::fs::Permissions::from_mode(0o666))?;

    info!("IPC nasłuchuje: {}", socket_path);

    let state = Arc::new(Mutex::new(AppState {
        config,
        install_manager: InstallManager::new(),
                                    network_manager: NetworkManager::new(),
    }));

    loop {
        match listener.accept().await {
            Ok((stream, _)) => {
                let state = Arc::clone(&state);
                tokio::spawn(async move {
                    if let Err(e) = handle_client(stream, state).await {
                        error!("Błąd klienta IPC: {}", e);
                    }
                });
            }
            Err(e) => error!("Accept error: {}", e),
        }
    }
}

async fn handle_client(stream: UnixStream, state: Arc<Mutex<AppState>>) -> Result<()> {
    let (reader, mut writer) = stream.into_split();
    let mut reader = BufReader::new(reader);
    let mut line   = String::new();

    loop {
        line.clear();
        let n = reader.read_line(&mut line).await?;
        if n == 0 { break; }

        let trimmed = line.trim();
        if trimmed.is_empty() { continue; }

        let response = match serde_json::from_str::<IpcRequest>(trimmed) {
            Ok(req)  => handle_request(req, &state).await,
            Err(e)   => {
                warn!("Błąd parsowania żądania: {}", e);
                IpcResponse::err(format!("Błąd parsowania: {}", e))
            }
        };

        let mut s = serde_json::to_string(&response)?;
        s.push('\n');
        writer.write_all(s.as_bytes()).await?;
    }
    Ok(())
}

async fn handle_request(req: IpcRequest, state: &Arc<Mutex<AppState>>) -> IpcResponse {
    match req {
        IpcRequest::Ping => IpcResponse::ok(serde_json::json!({ "pong": true })),

        IpcRequest::CheckInternet => {
            let ok = crate::network::check_internet().await;
            IpcResponse::ok(serde_json::json!({ "connected": ok }))
        }

        IpcRequest::GetConfig => {
            let st = state.lock().await;
            IpcResponse::ok(serde_json::to_value(&st.config).unwrap_or_default())
        }

        IpcRequest::GetSystemInfo => {
            match SystemInfo::gather().await {
                Ok(i)  => IpcResponse::ok(serde_json::to_value(i).unwrap_or_default()),
                Err(e) => IpcResponse::err(e),
            }
        }

        IpcRequest::GetDisks => {
            match crate::disk::list_disks().await {
                Ok(d)  => IpcResponse::ok(serde_json::to_value(d).unwrap_or_default()),
                Err(e) => IpcResponse::err(e),
            }
        }

        IpcRequest::GetNetworkInterfaces => {
            match crate::network::list_interfaces().await {
                Ok(i)  => IpcResponse::ok(serde_json::to_value(i).unwrap_or_default()),
                Err(e) => IpcResponse::err(e),
            }
        }

        IpcRequest::GetWifiNetworks { interface } => {
            match crate::network::scan_wifi(&interface).await {
                Ok(n)  => IpcResponse::ok(serde_json::to_value(n).unwrap_or_default()),
                Err(e) => IpcResponse::err(e),
            }
        }

        IpcRequest::ConnectWifi { interface, ssid, password } => {
            match crate::network::connect_wifi(&interface, &ssid, password.as_deref()).await {
                Ok(_)  => IpcResponse::ok(serde_json::json!({ "connected": true })),
                Err(e) => IpcResponse::err(e),
            }
        }

        IpcRequest::ConnectEthernet { interface } => {
            match crate::network::connect_ethernet(&interface).await {
                Ok(_)  => IpcResponse::ok(serde_json::json!({ "connected": true })),
                Err(e) => IpcResponse::err(e),
            }
        }

        IpcRequest::DisconnectNetwork { interface } => {
            match crate::network::disconnect(&interface).await {
                Ok(_)  => IpcResponse::ok(serde_json::json!({ "disconnected": true })),
                Err(e) => IpcResponse::err(e),
            }
        }

        IpcRequest::GetTimezones => {
            match crate::system::list_timezones().await {
                Ok(t)  => IpcResponse::ok(serde_json::to_value(t).unwrap_or_default()),
                Err(e) => IpcResponse::err(e),
            }
        }

        IpcRequest::GetLocales => {
            match crate::system::list_locales().await {
                Ok(l)  => IpcResponse::ok(serde_json::to_value(l).unwrap_or_default()),
                Err(e) => IpcResponse::err(e),
            }
        }

        IpcRequest::GetKeyboardLayouts => {
            match crate::system::list_keyboard_layouts().await {
                Ok(k)  => IpcResponse::ok(serde_json::to_value(k).unwrap_or_default()),
                Err(e) => IpcResponse::err(e),
            }
        }

        IpcRequest::SetLocaleConfig { locale, timezone, keyboard } => {
            let mut st = state.lock().await;
            st.install_manager.set_locale_config(locale, timezone, keyboard);
            IpcResponse::ok(serde_json::json!({ "ok": true }))
        }

        IpcRequest::SetPartitionPlan { plan } => {
            let mut st = state.lock().await;
            st.install_manager.set_partition_plan(plan);
            IpcResponse::ok(serde_json::json!({ "ok": true }))
        }

        IpcRequest::SetUserConfig { user } => {
            let mut st = state.lock().await;
            st.install_manager.set_user_config(user);
            IpcResponse::ok(serde_json::json!({ "ok": true }))
        }

        IpcRequest::StartInstallation => {
            let config = { state.lock().await.config.clone() };
            let state2 = Arc::clone(state);
            tokio::spawn(async move {
                let mut st = state2.lock().await;
                if let Err(e) = st.install_manager.start_installation(&config).await {
                    error!("Instalacja – błąd: {}", e);
                }
            });
            IpcResponse::ok(serde_json::json!({ "started": true }))
        }

        IpcRequest::GetInstallProgress => {
            let st = state.lock().await;
            let p  = st.install_manager.get_progress();
            IpcResponse::ok(serde_json::to_value(p).unwrap_or_default())
        }

        IpcRequest::CancelInstallation => {
            let mut st = state.lock().await;
            st.install_manager.cancel();
            IpcResponse::ok(serde_json::json!({ "cancelled": true }))
        }
    }
}
