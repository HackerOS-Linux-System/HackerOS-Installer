use anyhow::Result;
use crossterm::{
    event::{self, DisableMouseCapture, EnableMouseCapture, Event, KeyCode, KeyEventKind},
    execute,
    terminal::{disable_raw_mode, enable_raw_mode, EnterAlternateScreen, LeaveAlternateScreen},
};
use ratatui::{
    backend::{Backend, CrosstermBackend},
    layout::{Constraint, Direction, Layout},
    style::{Modifier, Style},
    text::Text,
    widgets::{Block, Borders, List, ListItem, ListState, Paragraph, Wrap},
    Frame, Terminal,
};
use std::{
    fs,
    io,
    process::Command,
    sync::{Arc, Mutex},
};

#[derive(Clone, PartialEq)]
enum InstallerStep {
    Welcome,
    CreateUser,
    SelectLocale,
    PartitionDisk,
    SelectDesktop,
    ConfigureNetwork,
    InstallSystem,
    DetectGPU,
    InstallKernel,
    Finalize,
    Done,
}

#[derive(Clone)]
struct InstallerState {
    current_step: InstallerStep,
    username: String,
    password: String,
    country: String,
    timezone: String,
    auto_partition: bool,
    desktop_env: String,
    network_configured: bool,
    target_disk: String,
    mount_point: String,
    gpu_type: String,
    kernel_type: String,
    progress: Vec<String>,
}

impl Default for InstallerState {
    fn default() -> Self {
        InstallerState {
            current_step: InstallerStep::Welcome,
            username: String::new(),
            password: String::new(),
            country: String::from("Poland"),
            timezone: String::from("Europe/Warsaw"),
            auto_partition: true,
            desktop_env: String::from("kde"),
            network_configured: false,
            target_disk: String::from("/dev/sda"),
            mount_point: String::from("/mnt"),
            gpu_type: String::new(),
            kernel_type: String::new(),
            progress: Vec::new(),
        }
    }
}

enum MainContent<'a> {
    Paragraph(Paragraph<'a>),
    List(List<'a>),
}

#[tokio::main]
async fn main() -> Result<()> {
    let state = Arc::new(Mutex::new(InstallerState::default()));

    enable_raw_mode()?;
    let mut stdout = io::stdout();
    execute!(stdout, EnterAlternateScreen, EnableMouseCapture)?;
    let backend = CrosstermBackend::new(stdout);
    let mut terminal = Terminal::new(backend)?;

    let res = run_app(&mut terminal, state.clone()).await;

    disable_raw_mode()?;
    execute!(
        terminal.backend_mut(),
             LeaveAlternateScreen,
             DisableMouseCapture
    )?;
    terminal.show_cursor()?;

    if let Err(err) = res {
        println!("{:?}", err)
    }

    Ok(())
}

async fn run_app<B: Backend>(
    terminal: &mut Terminal<B>,
    state: Arc<Mutex<InstallerState>>,
) -> Result<()> {
    let mut list_state = ListState::default();
    loop {
        terminal.draw(|f| ui(f, &state.lock().unwrap(), &mut list_state))?;

        if let Event::Key(key) = event::read()? {
            if key.kind == KeyEventKind::Press {
                handle_key_event(key.code, state.clone(), &mut list_state).await?;
                let locked_state = state.lock().unwrap();
                if locked_state.current_step == InstallerStep::Done {
                    return Ok(());
                }
            }
        }
    }
}

fn ui<B: Backend>(f: &mut Frame<B>, state: &InstallerState, list_state: &mut ListState) {
    let chunks = Layout::default()
    .direction(Direction::Vertical)
    .constraints([Constraint::Percentage(80), Constraint::Percentage(20)])
    .split(f.size());

    let main_block = Block::default()
    .title("HackerOS Installer")
    .borders(Borders::ALL);
    let progress_block = Block::default().title("Progress").borders(Borders::ALL);

    let main_content = match state.current_step {
        InstallerStep::Welcome => MainContent::Paragraph(Paragraph::new(Text::from("Welcome to HackerOS Installer. Press Enter to start."))
        .wrap(Wrap::default())),
        InstallerStep::CreateUser => MainContent::Paragraph(Paragraph::new(Text::from(format!(
            "Enter username: {}\nEnter password: {}",
            state.username, "*".repeat(state.password.len())
        )))),
        InstallerStep::SelectLocale => MainContent::Paragraph(Paragraph::new(Text::from(format!(
            "Select country: {}\nSelect timezone: {}",
            state.country, state.timezone
        )))),
        InstallerStep::PartitionDisk => MainContent::Paragraph(Paragraph::new(Text::from(format!(
            "Auto partition? {}\nTarget disk: {}",
            if state.auto_partition { "Yes" } else { "No" },
                state.target_disk
        )))),
        InstallerStep::SelectDesktop => {
            let items = vec![
                ListItem::new("KDE Plasma"),
                ListItem::new("GNOME"),
                ListItem::new("Hydra"),
            ];
            MainContent::List(
                List::new(items)
                .block(Block::default().title("Select Desktop Environment").borders(Borders::ALL))
                .highlight_style(Style::default().add_modifier(Modifier::BOLD)),
            )
        }
        InstallerStep::ConfigureNetwork => MainContent::Paragraph(Paragraph::new(Text::from(
            "Configure network. Press Enter to connect (assuming DHCP).",
        ))),
        InstallerStep::InstallSystem => MainContent::Paragraph(Paragraph::new(Text::from("Installing system..."))),
        InstallerStep::DetectGPU => MainContent::Paragraph(Paragraph::new(Text::from("Detecting GPU and installing drivers..."))),
        InstallerStep::InstallKernel => MainContent::Paragraph(Paragraph::new(Text::from("Installing kernel..."))),
        InstallerStep::Finalize => MainContent::Paragraph(Paragraph::new(Text::from("Finalizing installation..."))),
        InstallerStep::Done => MainContent::Paragraph(Paragraph::new(Text::from("Installation complete. Reboot."))),
    };

    f.render_widget(main_block.clone(), chunks[0]);
    let inner_area = main_block.inner(chunks[0]);

    if state.current_step == InstallerStep::SelectDesktop {
        list_state.select(Some(match state.desktop_env.as_str() {
            "kde" => 0,
            "gnome" => 1,
            "hydra" => 2,
            _ => 0,
        }));
    }

    match main_content {
        MainContent::List(l) => {
            f.render_stateful_widget(l, inner_area, list_state);
        }
        MainContent::Paragraph(p) => {
            f.render_widget(p, inner_area);
        }
    }

    let progress_items: Vec<ListItem> = state
    .progress
    .iter()
    .map(|s| ListItem::new(s.as_str()))
    .collect();
    let progress_list = List::new(progress_items);
    f.render_widget(progress_block.clone(), chunks[1]);
    let inner_progress = progress_block.inner(chunks[1]);
    f.render_widget(progress_list, inner_progress);
}

async fn handle_key_event(
    code: KeyCode,
    state: Arc<Mutex<InstallerState>>,
    list_state: &mut ListState,
) -> Result<()> {
    let mut locked_state = state.lock().unwrap();
    match locked_state.current_step {
        InstallerStep::Welcome => {
            if code == KeyCode::Enter {
                locked_state.current_step = InstallerStep::CreateUser;
            }
        }
        InstallerStep::CreateUser => match code {
            KeyCode::Char(c) if locked_state.password.is_empty() => {
                locked_state.username.push(c);
            }
            KeyCode::Backspace if !locked_state.username.is_empty() && locked_state.password.is_empty() => {
                locked_state.username.pop();
            }
            KeyCode::Enter if !locked_state.username.is_empty() && locked_state.password.is_empty() => {
                // Move to password input
            }
            KeyCode::Char(c) if !locked_state.username.is_empty() => {
                locked_state.password.push(c);
            }
            KeyCode::Backspace if !locked_state.password.is_empty() => {
                locked_state.password.pop();
            }
            KeyCode::Enter if !locked_state.username.is_empty() && !locked_state.password.is_empty() => {
                locked_state.current_step = InstallerStep::SelectLocale;
            }
            _ => {}
        },
        InstallerStep::SelectLocale => {
            if code == KeyCode::Enter {
                locked_state.current_step = InstallerStep::PartitionDisk;
            }
        }
        InstallerStep::PartitionDisk => {
            if code == KeyCode::Char('y') {
                locked_state.auto_partition = true;
            } else if code == KeyCode::Char('n') {
                locked_state.auto_partition = false;
            } else if code == KeyCode::Enter {
                perform_partitioning(&mut locked_state)?;
                locked_state.current_step = InstallerStep::SelectDesktop;
            }
        }
        InstallerStep::SelectDesktop => match code {
            KeyCode::Up => {
                let i = list_state.selected().map_or(0, |i| if i > 0 { i - 1 } else { 0 });
                list_state.select(Some(i));
            }
            KeyCode::Down => {
                let i = list_state.selected().map_or(2, |i| if i < 2 { i + 1 } else { 2 });
                list_state.select(Some(i));
            }
            KeyCode::Enter => {
                locked_state.desktop_env = match list_state.selected().unwrap_or(0) {
                    0 => "kde".to_string(),
                    1 => "gnome".to_string(),
                    2 => "hydra".to_string(),
                    _ => "kde".to_string(),
                };
                locked_state.current_step = InstallerStep::ConfigureNetwork;
            }
            _ => {}
        },
        InstallerStep::ConfigureNetwork => {
            if code == KeyCode::Enter {
                configure_network(&mut locked_state)?;
                locked_state.current_step = InstallerStep::InstallSystem;
                drop(locked_state);
                perform_installation(state.clone()).await?;
            }
        }
        _ => {}
    }
    Ok(())
}

fn perform_partitioning(state: &mut InstallerState) -> Result<()> {
    state.progress.push("Partitioning disk...".to_string());
    if state.auto_partition {
        Command::new("sh")
        .arg("-c")
        .arg(format!(
            "echo 'o\nn\np\n1\n\n\nw' | fdisk {} && mkfs.ext4 {}1",
            state.target_disk, state.target_disk
        ))
        .output()?;
        state.progress.push("Auto partitioning done.".to_string());
    } else {
        state.progress.push("Manual partitioning: please configure externally.".to_string());
    }
    fs::create_dir_all(&state.mount_point)?;
    Command::new("mount")
    .arg(format!("{}1", state.target_disk))
    .arg(&state.mount_point)
    .output()?;
    state.progress.push("Disk mounted.".to_string());
    Ok(())
}

fn configure_network(state: &mut InstallerState) -> Result<()> {
    Command::new("dhclient").output()?;
    state.network_configured = true;
    state.progress.push("Network configured.".to_string());
    Ok(())
}

async fn perform_installation(state: Arc<Mutex<InstallerState>>) -> Result<()> {
    let mut locked_state = state.lock().unwrap();
    locked_state.progress.push("Starting installation...".to_string());
    let mount_point = locked_state.mount_point.clone();

    Command::new("rsync")
    .args(&["-aAXv", "--exclude=/dev/*", "--exclude=/proc/*", "--exclude=/sys/*", "--exclude=/tmp/*", "--exclude=/run/*", "--exclude=/mnt/*", "--exclude=/media/*", "--exclude=/lost+found", "/", &mount_point])
    .output()?;
    locked_state.progress.push("Base system copied.".to_string());

    let chroot_cmd = move |cmd: &str| -> Result<()> {
        Command::new("chroot")
        .arg(&mount_point)
        .arg("sh")
        .arg("-c")
        .arg(cmd)
        .output()?;
        Ok(())
    };

    chroot_cmd(&format!(
        "useradd -m {} && echo '{}:{}' | chpasswd",
        locked_state.username, locked_state.username, locked_state.password
    ))?;
    locked_state.progress.push("User created.".to_string());

    chroot_cmd(&format!(
        "echo '{}' > /etc/timezone && ln -sf /usr/share/zoneinfo/{} /etc/localtime",
        locked_state.timezone, locked_state.timezone
    ))?;
    locked_state.progress.push("Locale set.".to_string());

    match locked_state.desktop_env.as_str() {
        "kde" => chroot_cmd("apt install -y plasma-desktop")?,
        "gnome" => chroot_cmd("apt install -y gdm3 gnome-desktop")?,
        "hydra" => {
            chroot_cmd("apt install -y plasma-desktop")?,
            chroot_cmd("git clone https://github.com/HackerOS-Linux-System/hydra-look-and-feel.git /tmp/hydra-look-and-feel")?,
            chroot_cmd("cp -r /tmp/hydra-look-and-feel/files/* /")?,
        }
        _ => {}
    }
    locked_state.progress.push("Desktop installed.".to_string());

    chroot_cmd("HackerOS-Steam create")?;
    locked_state.progress.push("HackerOS-Steam created.".to_string());

    chroot_cmd("git clone https://github.com/HackerOS-Linux-System/gamescope-session-steam.git /tmp/gamescope-session-steam")?;
    chroot_cmd("hl run /tmp/gamescope-session-steam/unpack.hacker")?;
    locked_state.progress.push("Gamescope installed.".to_string());

    chroot_cmd("cp -r /usr/share/HackerOS/Archived/icons/ /usr/share/")?;
    chroot_cmd("rm -rf /usr/share/HackerOS/Archived/icons/")?;
    locked_state.progress.push("Icons copied.".to_string());

    locked_state.current_step = InstallerStep::DetectGPU;
    drop(locked_state);
    detect_and_install_gpu(state.clone()).await?;

    let mut locked_state = state.lock().unwrap();
    locked_state.current_step = InstallerStep::InstallKernel;
    drop(locked_state);
    install_kernel(state.clone()).await?;

    let mut locked_state = state.lock().unwrap();
    locked_state.current_step = InstallerStep::Finalize;

    Command::new("umount").arg(&locked_state.mount_point).output()?;
    locked_state.progress.push("Installation finalized.".to_string());
    locked_state.current_step = InstallerStep::Done;

    Ok(())
}

async fn detect_and_install_gpu(state: Arc<Mutex<InstallerState>>) -> Result<()> {
    let mut locked_state = state.lock().unwrap();
    let mount_point = locked_state.mount_point.clone();
    let output = Command::new("lspci").output()?;
    let lspci_str = String::from_utf8_lossy(&output.stdout);
    let chroot_cmd = move |cmd: &str| -> Result<()> {
        Command::new("chroot")
        .arg(&mount_point)
        .arg("sh")
        .arg("-c")
        .arg(cmd)
        .output()?;
        Ok(())
    };
    if lspci_str.contains("NVIDIA") {
        locked_state.gpu_type = "nvidia".to_string();
        locked_state.progress.push("Detected NVIDIA GPU.".to_string());
        chroot_cmd("apt install -y nvidia-driver nvidia-kernel-dkms nvidia-smi libnvidia-ml1 nvidia-settings nvidia-cuda-mps")?;
    } else if lspci_str.contains("AMD") {
        locked_state.gpu_type = "amd".to_string();
        locked_state.progress.push("Detected AMD GPU.".to_string());
        chroot_cmd("apt install -y firmware-amd-graphics")?;
    } else if lspci_str.contains("Intel") {
        locked_state.gpu_type = "intel".to_string();
        locked_state.progress.push("Detected Intel GPU.".to_string());
        chroot_cmd("apt install -y intel-gpu-tools")?;
    }
    locked_state.progress.push("GPU drivers installed.".to_string());
    Ok(())
}

async fn install_kernel(state: Arc<Mutex<InstallerState>>) -> Result<()> {
    let mut locked_state = state.lock().unwrap();
    let mount_point = locked_state.mount_point.clone();
    let kernel_file = format!("{}/usr/share/HackerOS/Archived/kernel.hacker", &mount_point);
    let content = fs::read_to_string(&kernel_file)?;
    let lines: Vec<String> = content.lines().map(|l| l.trim().to_string()).collect();

    if lines.contains(&"[liquorix]".to_string()) {
        locked_state.kernel_type = "liquorix".to_string();
        let chroot_cmd = |cmd: &str| -> Result<()> {
            Command::new("chroot")
            .arg(&mount_point)
            .arg("sh")
            .arg("-c")
            .arg(cmd)
            .output()?;
            Ok(())
        };
        chroot_cmd("curl -s 'https://liquorix.net/install-liquorix.sh' | bash")?;
        chroot_cmd("apt remove -y linux-image-*generic")?;
        chroot_cmd("update-grub")?;
    } else if lines.contains(&"[xanmod]".to_string()) {
        locked_state.kernel_type = "xanmod".to_string();
        let cpu_file_path = format!("{}/tmp/xanmod-cpu.hacker", &mount_point);
        Command::new("wget")
        .args(&["-O", &cpu_file_path, "https://github.com/HackerOS-Linux-System/Hacker-Lang/blob/main/hacker-packages/xanmod-cpu.hacker?raw=true"])
        .output()?;
        let cpu_content = fs::read_to_string(&cpu_file_path)?;

        let variant = if cpu_content.contains("x86-64-v3") {
            "x64v3"
        } else if cpu_content.contains("x86-64-v2") {
            "x64v2"
        } else if cpu_content.contains("x86-64") {
            "x64v1"
        } else {
            "x64v3"
        };

        let chroot_cmd = move |cmd: &str| -> Result<()> {
            Command::new("chroot")
            .arg(&mount_point)
            .arg("sh")
            .arg("-c")
            .arg(cmd)
            .output()?;
            Ok(())
        };

        chroot_cmd("wget -qO - https://dl.xanmod.org/archive.key | gpg --dearmor -vo /etc/apt/keyrings/xanmod-archive-keyring.gpg")?;
        chroot_cmd(&format!("echo 'deb [signed-by=/etc/apt/keyrings/xanmod-archive-keyring.gpg] http://deb.xanmod.org $(lsb_release -sc) main' | tee /etc/apt/sources.list.d/xanmod-release.list"))?;
        chroot_cmd("apt update")?;
        chroot_cmd(&format!("apt install -y linux-xanmod-lts-{}", variant))?;
        chroot_cmd("apt remove -y linux-image-*generic")?;
        chroot_cmd("update-grub")?;
    }
    locked_state.progress.push("Kernel installed.".to_string());
    Ok(())
}
