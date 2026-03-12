mod config;
mod disk;
mod install;
mod ipc;
mod network;
mod system;
mod user;

use anyhow::Result;
use nix::unistd::Uid;
use std::path::PathBuf;
use tracing::{error, info};
use tracing_subscriber::{fmt, prelude::*, EnvFilter};

#[tokio::main]
async fn main() -> Result<()> {
    tracing_subscriber::registry()
    .with(EnvFilter::try_from_default_env().unwrap_or_else(|_| "info".into()))
    .with(fmt::layer())
    .init();

    info!("HackerOS Installer Backend v1.0 startuje...");

    // FIX: nix feature "user" musi być włączony w Cargo.toml
    // używamy Uid::effective() zamiast nix::unistd::getuid()
    if !Uid::effective().is_root() {
        error!("Backend musi być uruchomiony jako root (sudo)!");
        std::process::exit(1);
    }

    let config_path = PathBuf::from("/usr/lib/HackerOS/Installer/config.yml");
    let config = match config::load_config(&config_path).await {
        Ok(c) => {
            info!("Konfiguracja: edition={}, base={}", c.edition, c.base);
            c
        }
        Err(e) => {
            error!("Błąd wczytywania config ({}): {} — używam domyślnych", config_path.display(), e);
            config::InstallerConfig::default()
        }
    };

    let socket_path = config
    .backend_socket
    .clone()
    .unwrap_or_else(|| "/tmp/hackeros-installer.sock".to_string());

    info!("Serwer IPC: {}", socket_path);
    ipc::run_ipc_server(socket_path, config).await?;
    Ok(())
}
