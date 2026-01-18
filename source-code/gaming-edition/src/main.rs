use anyhow::Result;
use crossterm::{
    event::{self, DisableMouseCapture, EnableMouseCapture, Event, KeyCode, KeyEventKind},
    execute,
    terminal::{disable_raw_mode, enable_raw_mode, EnterAlternateScreen, LeaveAlternateScreen},
};
use ratatui::{
    backend::{Backend, CrosstermBackend},
    layout::{Constraint, Direction, Layout},
    style::{Color, Modifier, Style},
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

#[derive(Clone, Copy, PartialEq)]
enum ActiveField {
    None,
    Username,
    Password,
    Country,
    Timezone,
}

#[derive(Clone)]
struct InstallerState {
    current_step: InstallerStep,
    active_field: ActiveField,
    username: String,
    password: String,
    country: String,
    timezone: String,
    is_uefi: bool,
    auto_partition: bool,
    disks: Vec<String>,
    selected_disk: usize,
    disk_selected: bool,
    target_disk: String,
    mount_point: String,
    desktop_env: String,
    network_configured: bool,
    gpu_type: String,
    kernel_type: String,
    progress: Vec<String>,
}

impl Default for InstallerState {
    fn default() -> Self {
        InstallerState {
            current_step: InstallerStep::Welcome,
            active_field: ActiveField::None,
            username: String::new(),
            password: String::new(),
            country: String::from("Poland"),
            timezone: String::from("Europe/Warsaw"),
            is_uefi: fs::metadata("/sys/firmware/efi").is_ok(),
            auto_partition: true,
            disks: Vec::new(),
            selected_disk: 0,
            disk_selected: false,
            target_disk: String::new(),
            mount_point: String::from("/mnt"),
            desktop_env: String::from("kde"),
            network_configured: false,
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
        .title_style(Style::default().fg(Color::Cyan))
        .borders(Borders::ALL)
        .style(Style::default().fg(Color::White));

    let progress_block = Block::default()
        .title("Progress")
        .title_style(Style::default().fg(Color::Green))
        .borders(Borders::ALL)
        .style(Style::default().fg(Color::White));

    let main_content = match state.current_step {
        InstallerStep::Welcome => MainContent::Paragraph(
            Paragraph::new(Text::from("Welcome to HackerOS Installer. Press Enter to start."))
                .style(Style::default().fg(Color::Yellow))
                .wrap(Wrap::default()),
        ),
        InstallerStep::CreateUser => MainContent::Paragraph(Paragraph::new(Text::from(format!(
            "Enter username: {}\nEnter password: {}",
            state.username,
            "*".repeat(state.password.len())
        )))
        .style(Style::default().fg(if state.active_field == ActiveField::Username { Color::Green } else { Color::White })),
        ),
        InstallerStep::SelectLocale => MainContent::Paragraph(Paragraph::new(Text::from(format!(
            "Enter country: {}\nEnter timezone: {}",
            state.country, state.timezone
        )))
        .style(Style::default().fg(if state.active_field == ActiveField::Country { Color::Green } else { Color::White })),
        ),
        InstallerStep::PartitionDisk => {
            if !state.disk_selected {
                let items: Vec<ListItem> = state
                    .disks
                    .iter()
                    .map(|d| ListItem::new(d.as_str()).style(Style::default().fg(Color::White)))
                    .collect();
                MainContent::List(
                    List::new(items)
                        .block(
                            Block::default()
                                .title("Select Target Disk")
                                .borders(Borders::ALL)
                                .style(Style::default().fg(Color::LightBlue)),
                        )
                        .highlight_style(
                            Style::default()
                                .fg(Color::Black)
                                .bg(Color::LightCyan)
                                .add_modifier(Modifier::BOLD),
                        )
                        .highlight_symbol("> "),
                )
            } else {
                MainContent::Paragraph(
                    Paragraph::new(Text::from(format!(
                        "Target disk: {}\nAuto partition? (y/n): {}",
                        state.target_disk,
                        if state.auto_partition { "Yes" } else { "No" }
                    )))
                    .style(Style::default().fg(Color::White)),
                )
            }
        }
        InstallerStep::SelectDesktop => {
            let items = vec![
                ListItem::new("KDE Plasma").style(Style::default().fg(Color::White)),
                ListItem::new("GNOME").style(Style::default().fg(Color::White)),
                ListItem::new("Hydra").style(Style::default().fg(Color::White)),
            ];
            MainContent::List(
                List::new(items)
                    .block(
                        Block::default()
                            .title("Select Desktop Environment")
                            .borders(Borders::ALL)
                            .style(Style::default().fg(Color::LightBlue)),
                    )
                    .highlight_style(
                        Style::default()
                            .fg(Color::Black)
                            .bg(Color::LightCyan)
                            .add_modifier(Modifier::BOLD),
                    )
                    .highlight_symbol("> "),
            )
        }
        InstallerStep::ConfigureNetwork => MainContent::Paragraph(
            Paragraph::new(Text::from(
                "Configure network. Press Enter to attempt connection (DHCP). If fails, nmtui will launch for manual config.",
            ))
            .style(Style::default().fg(Color::Yellow)),
        ),
        InstallerStep::InstallSystem => MainContent::Paragraph(
            Paragraph::new(Text::from("Installing system..."))
                .style(Style::default().fg(Color::Magenta)),
        ),
        InstallerStep::DetectGPU => MainContent::Paragraph(
            Paragraph::new(Text::from("Detecting GPU and installing drivers..."))
                .style(Style::default().fg(Color::Magenta)),
        ),
        InstallerStep::InstallKernel => MainContent::Paragraph(
            Paragraph::new(Text::from("Installing kernel..."))
                .style(Style::default().fg(Color::Magenta)),
        ),
        InstallerStep::Finalize => MainContent::Paragraph(
            Paragraph::new(Text::from("Finalizing installation..."))
                .style(Style::default().fg(Color::Magenta)),
        ),
        InstallerStep::Done => MainContent::Paragraph(
            Paragraph::new(Text::from("Installation complete. Press Enter to reboot."))
                .style(Style::default().fg(Color::Green)),
        ),
    };

    f.render_widget(main_block.clone(), chunks[0]);
    let inner_area = main_block.inner(chunks[0]);

    match state.current_step {
        InstallerStep::SelectDesktop => {
            list_state.select(Some(match state.desktop_env.as_str() {
                "kde" => 0,
                "gnome" => 1,
                "hydra" => 2,
                _ => 0,
            }));
        }
        InstallerStep::PartitionDisk if !state.disk_selected => {
            list_state.select(Some(state.selected_disk));
        }
        _ => {}
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
        .map(|s| ListItem::new(s.as_str()).style(Style::default().fg(Color::LightGreen)))
        .collect();
    let progress_list = List::new(progress_items).highlight_style(Style::default().fg(Color::Yellow));

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
                locked_state.active_field = ActiveField::Username;
                locked_state.current_step = InstallerStep::CreateUser;
            }
        }
        InstallerStep::CreateUser => match code {
            KeyCode::Char(c) if locked_state.active_field == ActiveField::Username => {
                locked_state.username.push(c);
            }
            KeyCode::Backspace if locked_state.active_field == ActiveField::Username && !locked_state.username.is_empty() => {
                locked_state.username.pop();
            }
            KeyCode::Enter if !locked_state.username.is_empty() && locked_state.active_field == ActiveField::Username => {
                locked_state.active_field = ActiveField::Password;
            }
            KeyCode::Char(c) if locked_state.active_field == ActiveField::Password => {
                locked_state.password.push(c);
            }
            KeyCode::Backspace if locked_state.active_field == ActiveField::Password && !locked_state.password.is_empty() => {
                locked_state.password.pop();
            }
            KeyCode::Enter if !locked_state.password.is_empty() && locked_state.active_field == ActiveField::Password => {
                locked_state.active_field = ActiveField::Country;
                locked_state.current_step = InstallerStep::SelectLocale;
            }
            _ => {}
        },
        InstallerStep::SelectLocale => match code {
            KeyCode::Char(c) if locked_state.active_field == ActiveField::Country => {
                locked_state.country.push(c);
            }
            KeyCode::Backspace if locked_state.active_field == ActiveField::Country && !locked_state.country.is_empty() => {
                locked_state.country.pop();
            }
            KeyCode::Enter if !locked_state.country.is_empty() && locked_state.active_field == ActiveField::Country => {
                locked_state.active_field = ActiveField::Timezone;
            }
            KeyCode::Char(c) if locked_state.active_field == ActiveField::Timezone => {
                locked_state.timezone.push(c);
            }
            KeyCode::Backspace if locked_state.active_field == ActiveField::Timezone && !locked_state.timezone.is_empty() => {
                locked_state.timezone.pop();
            }
            KeyCode::Enter if !locked_state.timezone.is_empty() && locked_state.active_field == ActiveField::Timezone => {
                fetch_disks(&mut locked_state);
                locked_state.active_field = ActiveField::None;
                locked_state.current_step = InstallerStep::PartitionDisk;
            }
            _ => {}
        },
        InstallerStep::PartitionDisk => {
            if !locked_state.disk_selected {
                match code {
                    KeyCode::Up => {
                        locked_state.selected_disk = locked_state.selected_disk.saturating_sub(1);
                    }
                    KeyCode::Down => {
                        if locked_state.selected_disk < locked_state.disks.len() - 1 {
                            locked_state.selected_disk += 1;
                        }
                    }
                    KeyCode::Enter => {
                        if !locked_state.disks.is_empty() {
                            let selected = &locked_state.disks[locked_state.selected_disk];
                            locked_state.target_disk = selected.split(' ').next().unwrap().to_string();
                            locked_state.disk_selected = true;
                        }
                    }
                    _ => {}
                }
            } else {
                match code {
                    KeyCode::Char('y') => {
                        locked_state.auto_partition = true;
                    }
                    KeyCode::Char('n') => {
                        locked_state.auto_partition = false;
                    }
                    KeyCode::Enter => {
                        perform_partitioning(&mut locked_state)?;
                        locked_state.current_step = InstallerStep::SelectDesktop;
                    }
                    _ => {}
                }
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
        InstallerStep::Done => {
            if code == KeyCode::Enter {
                Command::new("reboot").output()?;
            }
        }
        _ => {}
    }
    Ok(())
}

fn fetch_disks(state: &mut InstallerState) {
    let output = Command::new("lsblk")
        .args(&["-d", "-o", "NAME,SIZE", "-n"])
        .output()
        .unwrap();
    let out = String::from_utf8_lossy(&output.stdout);
    state.disks = out
        .lines()
        .map(|l| {
            let parts: Vec<&str> = l.split_whitespace().collect();
            format!("/dev/{} ({})", parts[0], parts[1])
        })
        .collect();
    if !state.disks.is_empty() {
        let first = &state.disks[0];
        state.target_disk = first.split(' ').next().unwrap().to_string();
    }
}

fn perform_partitioning(state: &mut InstallerState) -> Result<()> {
    state.progress.push("Partitioning disk...".to_string());
    if state.auto_partition {
        if state.is_uefi {
            Command::new("parted")
                .arg("-s")
                .arg(&state.target_disk)
                .arg("mklabel")
                .arg("gpt")
                .output()?;
            Command::new("parted")
                .arg("-s")
                .arg(&state.target_disk)
                .arg("mkpart")
                .arg("ESP")
                .arg("fat32")
                .arg("1MiB")
                .arg("513MiB")
                .output()?;
            Command::new("parted")
                .arg("-s")
                .arg(&state.target_disk)
                .arg("set")
                .arg("1")
                .arg("esp")
                .arg("on")
                .output()?;
            Command::new("parted")
                .arg("-s")
                .arg(&state.target_disk)
                .arg("mkpart")
                .arg("root")
                .arg("ext4")
                .arg("513MiB")
                .arg("100%")
                .output()?;
            Command::new("mkfs.fat")
                .arg("-F32")
                .arg(format!("{}1", state.target_disk))
                .output()?;
            Command::new("mkfs.ext4")
                .arg(format!("{}2", state.target_disk))
                .output()?;
            fs::create_dir_all(format!("{}/boot", state.mount_point))?;
            Command::new("mount")
                .arg(format!("{}2", state.target_disk))
                .arg(&state.mount_point)
                .output()?;
            Command::new("mount")
                .arg(format!("{}1", state.target_disk))
                .arg(format!("{}/boot", state.mount_point))
                .output()?;
        } else {
            Command::new("parted")
                .arg("-s")
                .arg(&state.target_disk)
                .arg("mklabel")
                .arg("msdos")
                .output()?;
            Command::new("parted")
                .arg("-s")
                .arg(&state.target_disk)
                .arg("mkpart")
                .arg("primary")
                .arg("ext4")
                .arg("1MiB")
                .arg("100%")
                .output()?;
            Command::new("parted")
                .arg("-s")
                .arg(&state.target_disk)
                .arg("set")
                .arg("1")
                .arg("boot")
                .arg("on")
                .output()?;
            Command::new("mkfs.ext4")
                .arg(format!("{}1", state.target_disk))
                .output()?;
            Command::new("mount")
                .arg(format!("{}1", state.target_disk))
                .arg(&state.mount_point)
                .output()?;
        }
        state.progress.push("Auto partitioning done.".to_string());
    } else {
        state.progress.push("Manual partitioning: please configure externally.".to_string());
    }
    state.progress.push("Disk mounted.".to_string());
    Ok(())
}

fn is_connected() -> bool {
    Command::new("ping")
        .args(&["-c1", "8.8.8.8"])
        .status()
        .map_or(false, |s| s.success())
}

fn configure_network(state: &mut InstallerState) -> Result<()> {
    Command::new("dhclient").output()?;
    if !is_connected() {
        Command::new("nmtui").output()?;
    }
    state.network_configured = is_connected();
    state.progress.push("Network configured.".to_string());
    Ok(())
}

async fn perform_installation(state: Arc<Mutex<InstallerState>>) -> Result<()> {
    let mut locked_state = state.lock().unwrap();
    locked_state.progress.push("Starting installation...".to_string());
    let mount_point = locked_state.mount_point.clone();
    Command::new("rsync")
        .args(&[
            "-aAXv",
            "--exclude=/dev/*",
            "--exclude=/proc/*",
            "--exclude=/sys/*",
            "--exclude=/tmp/*",
            "--exclude=/run/*",
            "--exclude=/mnt/*",
            "--exclude=/media/*",
            "--exclude=/lost+found",
            "/",
            &mount_point,
        ])
        .output()?;
    locked_state.progress.push("Base system copied.".to_string());

    // Mount binds for chroot
    let binds = vec!["/dev", "/proc", "/sys", "/run"];
    for bind in &binds {
        Command::new("mount")
            .args(&["--bind", bind, &format!("{}{}", mount_point, bind)])
            .output()?;
    }

    let chroot_cmd = |cmd: &str| -> Result<()> {
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
            chroot_cmd("apt install -y plasma-desktop")?;
            chroot_cmd("git clone https://github.com/HackerOS-Linux-System/hydra-look-and-feel.git /tmp/hydra-look-and-feel")?;
            chroot_cmd("cp -r /tmp/hydra-look-and-feel/files/* /")?;
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

    // Install bootloader
    locked_state.progress.push("Installing bootloader.".to_string());
    let target = locked_state.target_disk.clone();
    let efi_opt = if locked_state.is_uefi {
        "--target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB"
    } else {
        ""
    };
    chroot_cmd(&format!("grub-install {} {}", efi_opt, target))?;
    chroot_cmd("grub-mkconfig -o /boot/grub/grub.cfg")?;
    locked_state.progress.push("Bootloader installed.".to_string());

    // Unmount binds
    for bind in binds.iter().rev() {
        Command::new("umount")
            .arg(format!("{}{}", mount_point, bind))
            .output()?;
    }

    Command::new("umount")
        .arg("-R")
        .arg(&locked_state.mount_point)
        .output()?;
    locked_state.progress.push("Installation finalized.".to_string());
    locked_state.current_step = InstallerStep::Done;
    Ok(())
}

async fn detect_and_install_gpu(state: Arc<Mutex<InstallerState>>) -> Result<()> {
    let mut locked_state = state.lock().unwrap();
    let mount_point = locked_state.mount_point.clone();
    let output = Command::new("lspci").output()?;
    let lspci_str = String::from_utf8_lossy(&output.stdout);
    let chroot_cmd = |cmd: &str| -> Result<()> {
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
    let chroot_cmd = |cmd: &str| -> Result<()> {
        Command::new("chroot")
            .arg(&mount_point)
            .arg("sh")
            .arg("-c")
            .arg(cmd)
            .output()?;
        Ok(())
    };
    if lines.contains(&"[liquorix]".to_string()) {
        locked_state.kernel_type = "liquorix".to_string();
        chroot_cmd("curl -s 'https://liquorix.net/install-liquorix.sh' | bash")?;
        chroot_cmd("apt remove -y linux-image-*generic")?;
        chroot_cmd("update-grub")?;
    } else if lines.contains(&"[xanmod]".to_string()) {
        locked_state.kernel_type = "xanmod".to_string();
        let cpu_file_path = format!("{}/tmp/xanmod-cpu.hacker", &mount_point);
        Command::new("wget")
            .args(&[
                "-O",
                &cpu_file_path,
                "https://github.com/HackerOS-Linux-System/Hacker-Lang/blob/main/hacker-packages/xanmod-cpu.hacker?raw=true",
            ])
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
        chroot_cmd("wget -qO - https://dl.xanmod.org/archive.key | gpg --dearmor -vo /etc/apt/keyrings/xanmod-archive-keyring.gpg")?;
        chroot_cmd(&format!(
            "echo 'deb [signed-by=/etc/apt/keyrings/xanmod-archive-keyring.gpg] http://deb.xanmod.org $(lsb_release -sc) main' | tee /etc/apt/sources.list.d/xanmod-release.list"
        ))?;
        chroot_cmd("apt update")?;
        chroot_cmd(&format!("apt install -y linux-xanmod-lts-{}", variant))?;
        chroot_cmd("apt remove -y linux-image-*generic")?;
        chroot_cmd("update-grub")?;
    }
    locked_state.progress.push("Kernel installed.".to_string());
    Ok(())
}
