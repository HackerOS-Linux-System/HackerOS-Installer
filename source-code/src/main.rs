use std::io::{self, BufRead, Write};
use std::process::{Command, Stdio};
use std::path::Path;
use std::fs::{self, File};
use std::env;
use std::sync::Arc;

use anyhow::{Context, Result};
use crossterm::event::{self, Event, KeyCode, KeyEventKind, KeyModifiers};
use crossterm::terminal::{disable_raw_mode, enable_raw_mode, EnterAlternateScreen, LeaveAlternateScreen};
use crossterm::{execute, ExecutableCommand};
use git2::Repository;
use indicatif::{ProgressBar, ProgressStyle};
use ratatui::backend::CrosstermBackend;
use ratatui::layout::{Alignment, Constraint, Direction, Layout, Rect};
use ratatui::style::{Color, Modifier, Style};
use ratatui::text::{Line, Span, Text};
use ratatui::widgets::{Block, Borders, List, ListItem, ListState, Paragraph, Wrap, Tabs};
use ratatui::Terminal;
use reqwest::Client;
use tokio::task;
use log::{info, error};
use env_logger;

#[derive(Debug, Clone, PartialEq)]
enum Edition {
    Official,
    Gnome,
    Xfce,
    Blue,
    Hydra,
    Cybersecurity,
    Wayfire,
    Atomic,
}

#[derive(Debug, Clone, PartialEq)]
enum DebianBranch {
    Stable,    // trixie
    Testing,   // forky
    Unstable,  // sid
}

#[derive(Debug, Clone, PartialEq)]
enum Filesystem {
    Btrfs,
    Ext4,
    Zfs,
}

#[derive(Debug, Clone)]
struct InstallerState {
    current_step: usize,
    username: String,
    password: String,
    root_password: String,
    hostname: String,
    edition: Option<Edition>,
    branch: Option<DebianBranch>,
    filesystem: Option<Filesystem>,
    manual_partition: bool,
    disk: String,
    preview_image: bool,
    quit: bool,
    error_message: Option<String>,
    timezone: String,
    locale: String,
}

impl Default for InstallerState {
    fn default() -> Self {
        InstallerState {
            current_step: 0,
            username: String::new(),
            password: String::new(),
            root_password: String::new(),
            hostname: "hackeros".to_string(),
            edition: None,
            branch: None,
            filesystem: None,
            manual_partition: false,
            disk: String::new(),
            preview_image: false,
            quit: false,
            error_message: None,
            timezone: "UTC".to_string(),
            locale: "en_US.UTF-8".to_string(),
        }
    }
}

#[tokio::main]
async fn main() -> Result<()> {
    env_logger::init();
    let mut state = InstallerState::default();
    setup_terminal()?;
    let res = run_app(&mut state).await;
    teardown_terminal()?;
    res
}

fn setup_terminal() -> Result<()> {
    enable_raw_mode()?;
    execute!(io::stdout(), EnterAlternateScreen)?;
    Ok(())
}

fn teardown_terminal() -> Result<()> {
    disable_raw_mode()?;
    execute!(io::stdout(), LeaveAlternateScreen)?;
    Ok(())
}

async fn run_app(state: &mut InstallerState) -> Result<()> {
    let stdout = io::stdout();
    let backend = CrosstermBackend::new(stdout);
    let mut terminal = Terminal::new(backend)?;

    let mut list_state = ListState::default();
    let mut input_buffer = String::new();
    let mut active_input = false;

    loop {
        terminal.draw(|f| draw_ui(f, state, &mut list_state, &input_buffer))?;

        if let Event::Key(key) = event::read()? {
            if key.kind == KeyEventKind::Press {
                match key.code {
                    KeyCode::Char('q') if key.modifiers == KeyModifiers::CONTROL => {
                        state.quit = true;
                    }
                    KeyCode::Enter => {
                        if active_input {
                            handle_input_enter(state, &mut input_buffer, &mut active_input).await?;
                        } else {
                            handle_selection_enter(state, &mut list_state, &mut active_input, &mut input_buffer).await?;
                        }
                    }
                    KeyCode::Up => {
                        if !active_input {
                            update_list_selection(&mut list_state, -1);
                        }
                    }
                    KeyCode::Down => {
                        if !active_input {
                            update_list_selection(&mut list_state, 1);
                        }
                    }
                    KeyCode::Char(c) => {
                        if active_input {
                            input_buffer.push(c);
                        }
                    }
                    KeyCode::Backspace => {
                        if active_input {
                            input_buffer.pop();
                        }
                    }
                    KeyCode::Esc => {
                        active_input = false;
                        input_buffer.clear();
                    }
                    _ => {}
                }
            }
        }

        if state.quit {
            break;
        }

        if state.current_step >= 13 { // More steps now
            if let Err(e) = perform_installation(state).await {
                state.error_message = Some(e.to_string());
            } else {
                break;
            }
        }
    }

    Ok(())
}

fn update_list_selection(list_state: &mut ListState, delta: isize) {
    if let Some(mut selected) = list_state.selected() {
        selected = (selected as isize + delta).max(0) as usize;
        list_state.select(Some(selected));
    }
}

async fn handle_selection_enter(state: &mut InstallerState, list_state: &mut ListState, active_input: &mut bool, input_buffer: &mut String) -> Result<()> {
    match state.current_step {
        0 => state.current_step += 1,
        4 => {
            if let Some(selected) = list_state.selected() {
                state.edition = Some(match selected {
                    0 => Edition::Official,
                    1 => Edition::Gnome,
                    2 => Edition::Xfce,
                    3 => Edition::Blue,
                    4 => Edition::Hydra,
                    5 => Edition::Cybersecurity,
                    6 => Edition::Wayfire,
                    7 => Edition::Atomic,
                    _ => return Ok(()),
                });
                if state.edition == Some(Edition::Atomic) {
                    state.filesystem = Some(Filesystem::Btrfs);
                }
                state.preview_image = true;
                state.current_step += 1;
            }
        }
        5 => {
            if let Some(selected) = list_state.selected() {
                state.branch = Some(match selected {
                    0 => DebianBranch::Stable,
                    1 => DebianBranch::Testing,
                    2 => DebianBranch::Unstable,
                    _ => return Ok(()),
                });
                state.current_step += 1;
            }
        }
        6 => {
            if state.edition != Some(Edition::Atomic) {
                if let Some(selected) = list_state.selected() {
                    state.filesystem = Some(match selected {
                        0 => Filesystem::Btrfs,
                        1 => Filesystem::Ext4,
                        2 => Filesystem::Zfs,
                        _ => return Ok(()),
                    });
                    state.current_step += 1;
                }
            } else {
                state.current_step += 1; // Skip for Atomic
            }
        }
        7 => {
            if let Some(selected) = list_state.selected() {
                state.manual_partition = selected == 1;
                state.current_step += 1;
            }
        }
        10 => {
            if let Some(selected) = list_state.selected() {
                state.timezone = match selected {
                    0 => "UTC".to_string(),
                    1 => "America/New_York".to_string(),
                    2 => "Europe/Warsaw".to_string(),
                    // Add more
                    _ => "UTC".to_string(),
                };
                state.current_step += 1;
            }
        }
        11 => {
            if let Some(selected) = list_state.selected() {
                state.locale = match selected {
                    0 => "en_US.UTF-8".to_string(),
                    1 => "pl_PL.UTF-8".to_string(),
                    // Add more
                    _ => "en_US.UTF-8".to_string(),
                };
                state.current_step += 1;
            }
        }
        12 => state.current_step += 1, // Proceed to install
        _ => {
            *active_input = true;
            input_buffer.clear();
        }
    }
    list_state.select(None);
    Ok(())
}

async fn handle_input_enter(state: &mut InstallerState, input_buffer: &mut String, active_input: &mut bool) -> Result<()> {
    if !input_buffer.is_empty() {
        match state.current_step {
            1 => { state.username = input_buffer.clone(); state.current_step += 1; }
            2 => { state.password = input_buffer.clone(); state.current_step += 1; }
            3 => { state.root_password = input_buffer.clone(); state.current_step += 1; }
            8 => { state.disk = input_buffer.clone(); state.current_step += 1; }
            9 => { 
                if input_buffer.is_empty() {
                    state.hostname = "hackeros".to_string();
                } else {
                    state.hostname = input_buffer.clone(); 
                }
                state.current_step += 1; 
            }
            _ => {}
        }
        *active_input = false;
        input_buffer.clear();
    }
    Ok(())
}

fn draw_ui(f: &mut ratatui::Frame<CrosstermBackend<io::Stdout>>, state: &InstallerState, list_state: &mut ListState, input_buffer: &str) {
    let main_layout = Layout::default()
        .direction(Direction::Vertical)
        .constraints([Constraint::Length(3), Constraint::Min(1), Constraint::Length(3)])
        .split(f.area());

    let header = Paragraph::new("HackerOS Installer v0.2 - Inspired by Arch Linux")
        .style(Style::default().fg(Color::LightCyan).add_modifier(Modifier::BOLD | Modifier::ITALIC))
        .alignment(Alignment::Center)
        .block(Block::default().borders(Borders::ALL).border_style(Style::default().fg(Color::Cyan)));
    f.render_widget(header, main_layout[0]);

    let body_chunk = main_layout[1];

    match state.current_step {
        0 => draw_welcome(f, body_chunk),
        1 => draw_input_field(f, body_chunk, "Enter username:", input_buffer, Color::LightYellow),
        2 => draw_input_field(f, body_chunk, "Enter user password:", &"*".repeat(input_buffer.len()), Color::LightYellow),
        3 => draw_input_field(f, body_chunk, "Enter root password:", &"*".repeat(input_buffer.len()), Color::LightYellow),
        4 => draw_edition_selection(f, body_chunk, list_state, state.edition.as_ref()),
        5 => draw_branch_selection(f, body_chunk, list_state, state.branch.as_ref()),
        6 => draw_filesystem_selection(f, body_chunk, list_state, state.filesystem.as_ref(), &state.edition),
        7 => draw_partition_mode(f, body_chunk, list_state, state.manual_partition),
        8 => draw_input_field(f, body_chunk, "Enter disk (e.g., /dev/sda):", input_buffer, Color::LightMagenta),
        9 => draw_input_field(f, body_chunk, "Enter hostname (default: hackeros):", input_buffer, Color::LightGreen),
        10 => draw_timezone_selection(f, body_chunk, list_state),
        11 => draw_locale_selection(f, body_chunk, list_state),
        12 => draw_summary(f, body_chunk, state),
        _ => {}
    }

    if state.preview_image {
        draw_image_preview(f, body_chunk, state.edition.as_ref());
    }

    if let Some(err) = &state.error_message {
        let footer = Paragraph::new(err.as_str())
            .style(Style::default().fg(Color::Red))
            .alignment(Alignment::Center)
            .block(Block::default().borders(Borders::ALL).border_style(Style::default().fg(Color::Red)));
        f.render_widget(footer, main_layout[2]);
    } else {
        let footer = Paragraph::new("Press Ctrl+Q to quit | Enter to confirm | Esc to cancel input")
            .style(Style::default().fg(Color::LightBlue))
            .alignment(Alignment::Center)
            .block(Block::default().borders(Borders::ALL).border_style(Style::default().fg(Color::Blue)));
        f.render_widget(footer, main_layout[2]);
    }
}

fn draw_welcome(f: &mut ratatui::Frame<CrosstermBackend<io::Stdout>>, area: Rect) {
    let text = Text::from(vec![
        Line::from("Welcome to the enhanced HackerOS Installer!"),
        Line::from("This installer is designed for both beginners and professionals."),
        Line::from("Press Enter to begin the installation process."),
    ]);
    let paragraph = Paragraph::new(text)
        .block(Block::default().title("Welcome").borders(Borders::ALL).border_style(Style::default().fg(Color::Green)))
        .style(Style::default().fg(Color::Green).add_modifier(Modifier::BOLD))
        .alignment(Alignment::Center)
        .wrap(Wrap::default());
    f.render_widget(paragraph, area);
}

fn draw_input_field(f: &mut ratatui::Frame<CrosstermBackend<io::Stdout>>, area: Rect, prompt: &str, input: &str, color: Color) {
    let text = format!("{} {}", prompt, input);
    let paragraph = Paragraph::new(text)
        .block(Block::default().title("Input").borders(Borders::ALL).border_style(Style::default().fg(color)))
        .style(Style::default().fg(color).add_modifier(Modifier::UNDERLINED));
    f.render_widget(paragraph, area);
}

fn draw_edition_selection(f: &mut ratatui::Frame<CrosstermBackend<io::Stdout>>, area: Rect, list_state: &mut ListState, selected: Option<&Edition>) {
    let items = vec![
        ListItem::new(Span::styled("Official (KDE Plasma + SDDM)", Style::default().fg(Color::White))),
        ListItem::new(Span::styled("Gnome (GNOME + GDM3)", Style::default().fg(Color::White))),
        ListItem::new(Span::styled("XFCE (XFCE + LightDM)", Style::default().fg(Color::White))),
        ListItem::new(Span::styled("Blue (Custom Environment)", Style::default().fg(Color::White))),
        ListItem::new(Span::styled("Hydra (Custom Look)", Style::default().fg(Color::White))),
        ListItem::new(Span::styled("Cybersecurity (With Tools)", Style::default().fg(Color::White))),
        ListItem::new(Span::styled("Wayfire (Wayfire + SDDM)", Style::default().fg(Color::White))),
        ListItem::new(Span::styled("Atomic (With Hammer, requires Btrfs)", Style::default().fg(Color::White))),
    ];
    if list_state.selected().is_none() {
        list_state.select(Some(0));
    }
    let list = List::new(items)
        .block(Block::default().title("Select Edition").borders(Borders::ALL).border_style(Style::default().fg(Color::Cyan)))
        .style(Style::default().fg(Color::White))
        .highlight_style(Style::default().bg(Color::DarkGray).fg(Color::LightGreen).add_modifier(Modifier::BOLD))
        .highlight_symbol("▶ ");
    f.render_stateful_widget(list, area, list_state);
}

fn draw_branch_selection(f: &mut ratatui::Frame<CrosstermBackend<io::Stdout>>, area: Rect, list_state: &mut ListState, selected: Option<&DebianBranch>) {
    let items = vec![
        ListItem::new("Stable (trixie)"),
        ListItem::new("Testing (forky)"),
        ListItem::new("Unstable (sid)"),
    ];
    if list_state.selected().is_none() {
        list_state.select(Some(0));
    }
    let list = List::new(items)
        .block(Block::default().title("Select Debian Branch").borders(Borders::ALL).border_style(Style::default().fg(Color::Magenta)))
        .style(Style::default().fg(Color::White))
        .highlight_style(Style::default().bg(Color::DarkGray).fg(Color::LightMagenta).add_modifier(Modifier::BOLD))
        .highlight_symbol("▶ ");
    f.render_stateful_widget(list, area, list_state);
}

fn draw_filesystem_selection(f: &mut ratatui::Frame<CrosstermBackend<io::Stdout>>, area: Rect, list_state: &mut ListState, selected: Option<&Filesystem>, edition: &Option<Edition>) {
    if edition == &Some(Edition::Atomic) {
        let text = Text::from("For Atomic edition, filesystem is automatically set to Btrfs.");
        let paragraph = Paragraph::new(text)
            .block(Block::default().title("Filesystem").borders(Borders::ALL).border_style(Style::default().fg(Color::Yellow)))
            .style(Style::default().fg(Color::Yellow))
            .alignment(Alignment::Center);
        f.render_widget(paragraph, area);
    } else {
        let items = vec![
            ListItem::new("Btrfs"),
            ListItem::new("Ext4"),
            ListItem::new("Zfs"),
        ];
        if list_state.selected().is_none() {
            list_state.select(Some(0));
        }
        let list = List::new(items)
            .block(Block::default().title("Select Filesystem").borders(Borders::ALL).border_style(Style::default().fg(Color::Yellow)))
            .style(Style::default().fg(Color::White))
            .highlight_style(Style::default().bg(Color::DarkGray).fg(Color::LightYellow).add_modifier(Modifier::BOLD))
            .highlight_symbol("▶ ");
        f.render_stateful_widget(list, area, list_state);
    }
}

fn draw_partition_mode(f: &mut ratatui::Frame<CrosstermBackend<io::Stdout>>, area: Rect, list_state: &mut ListState, manual: bool) {
    let items = vec![
        ListItem::new("Automatic Partitioning (Easy mode)"),
        ListItem::new("Manual Partitioning (Advanced)"),
    ];
    if list_state.selected().is_none() {
        list_state.select(Some(0));
    }
    let list = List::new(items)
        .block(Block::default().title("Partitioning Mode").borders(Borders::ALL).border_style(Style::default().fg(Color::Green)))
        .style(Style::default().fg(Color::White))
        .highlight_style(Style::default().bg(Color::DarkGray).fg(Color::LightGreen).add_modifier(Modifier::BOLD))
        .highlight_symbol("▶ ");
    f.render_stateful_widget(list, area, list_state);
}

fn draw_timezone_selection(f: &mut ratatui::Frame<CrosstermBackend<io::Stdout>>, area: Rect, list_state: &mut ListState) {
    let items = vec![
        ListItem::new("UTC"),
        ListItem::new("America/New_York"),
        ListItem::new("Europe/Warsaw"),
        // Add more timezones as needed
    ];
    if list_state.selected().is_none() {
        list_state.select(Some(0));
    }
    let list = List::new(items)
        .block(Block::default().title("Select Timezone").borders(Borders::ALL).border_style(Style::default().fg(Color::Blue)))
        .style(Style::default().fg(Color::White))
        .highlight_style(Style::default().bg(Color::DarkGray).fg(Color::LightBlue).add_modifier(Modifier::BOLD))
        .highlight_symbol("▶ ");
    f.render_stateful_widget(list, area, list_state);
}

fn draw_locale_selection(f: &mut ratatui::Frame<CrosstermBackend<io::Stdout>>, area: Rect, list_state: &mut ListState) {
    let items = vec![
        ListItem::new("en_US.UTF-8"),
        ListItem::new("pl_PL.UTF-8"),
        // Add more locales
    ];
    if list_state.selected().is_none() {
        list_state.select(Some(0));
    }
    let list = List::new(items)
        .block(Block::default().title("Select Locale").borders(Borders::ALL).border_style(Style::default().fg(Color::Cyan)))
        .style(Style::default().fg(Color::White))
        .highlight_style(Style::default().bg(Color::DarkGray).fg(Color::LightCyan).add_modifier(Modifier::BOLD))
        .highlight_symbol("▶ ");
    f.render_stateful_widget(list, area, list_state);
}

fn draw_summary(f: &mut ratatui::Frame<CrosstermBackend<io::Stdout>>, area: Rect, state: &InstallerState) {
    let mut lines = vec![
        Line::from(Span::styled(format!("Username: {}", state.username), Style::default().fg(Color::LightBlue))),
        Line::from(Span::styled(format!("Hostname: {}", state.hostname), Style::default().fg(Color::LightBlue))),
        Line::from(Span::styled(format!("Edition: {:?}", state.edition), Style::default().fg(Color::LightGreen))),
        Line::from(Span::styled(format!("Branch: {:?}", state.branch), Style::default().fg(Color::LightGreen))),
        Line::from(Span::styled(format!("Filesystem: {:?}", state.filesystem), Style::default().fg(Color::LightYellow))),
        Line::from(Span::styled(format!("Manual Partition: {}", state.manual_partition), Style::default().fg(Color::LightYellow))),
        Line::from(Span::styled(format!("Disk: {}", state.disk), Style::default().fg(Color::LightMagenta))),
        Line::from(Span::styled(format!("Timezone: {}", state.timezone), Style::default().fg(Color::LightCyan))),
        Line::from(Span::styled(format!("Locale: {}", state.locale), Style::default().fg(Color::LightCyan))),
        Line::from(""),
        Line::from(Span::styled("Press Enter to start installation.", Style::default().fg(Color::Red).add_modifier(Modifier::BOLD))),
    ];
    let text = Text::from(lines);
    let paragraph = Paragraph::new(text)
        .block(Block::default().title("Installation Summary").borders(Borders::ALL).border_style(Style::default().fg(Color::Magenta)))
        .style(Style::default().fg(Color::White))
        .wrap(Wrap::default());
    f.render_widget(paragraph, area);
}

fn draw_image_preview(f: &mut ratatui::Frame<CrosstermBackend<io::Stdout>>, area: Rect, edition: Option<&Edition>) {
    let image_name = match edition {
        Some(Edition::Official) => "plasma.png",
        Some(Edition::Gnome) => "gnome.png",
        Some(Edition::Xfce) => "xfce.png",
        Some(Edition::Blue) => "blue.png",
        Some(Edition::Hydra) => "hydra.png",
        Some(Edition::Cybersecurity) => "cybersecurity.png",
        Some(Edition::Wayfire) => "wayfire.png",
        Some(Edition::Atomic) => "atomic.png",
        None => return,
    };
    let path = format!("/usr/share/HackerOS-Installer/images/{}", image_name);
    let text = format!("Preview: {} (Imagine a beautiful screenshot here)", path);
    let paragraph = Paragraph::new(text)
        .block(Block::default().title("Edition Preview").borders(Borders::ALL).border_style(Style::default().fg(Color::LightBlue)))
        .style(Style::default().fg(Color::Blue).add_modifier(Modifier::ITALIC))
        .alignment(Alignment::Center);
    let preview_area = Layout::default()
        .direction(Direction::Horizontal)
        .constraints([Constraint::Percentage(50), Constraint::Percentage(50)])
        .split(area)[1];
    f.render_widget(paragraph, preview_area);
}

async fn perform_installation(state: &InstallerState) -> Result<()> {
    info!("Starting installation process...");

    // Update sources.list
    let branch_str = match state.branch.as_ref().unwrap() {
        DebianBranch::Stable => "trixie",
        DebianBranch::Testing => "forky",
        DebianBranch::Unstable => "sid",
    };
    fs::write("/etc/apt/sources.list", format!("deb http://deb.debian.org/debian {} main contrib non-free non-free-firmware", branch_str))?;

    let pb = ProgressBar::new(5);
    pb.set_style(ProgressStyle::default_bar().template("{msg} {bar:40.cyan/blue} {percent}% {eta}"));
    pb.set_message("Updating packages...");
    Command::new("apt").args(&["update", "-y"]).status()?;
    pb.inc(1);

    // Partition disk
    pb.set_message("Partitioning disk...");
    if state.manual_partition {
        info!("Launching manual partitioning tool...");
        Command::new("cfdisk").arg(&state.disk).status()?;
    } else {
        // Automatic partitioning - improved with EFI and root
        let sfdisk_input = "label: gpt\n,512M,U\n,,L\n";
        let mut child = Command::new("sfdisk").arg(&state.disk).stdin(Stdio::piped()).spawn()?;
        if let Some(mut stdin) = child.stdin.take() {
            stdin.write_all(sfdisk_input.as_bytes())?;
        }
        child.wait()?;
    }
    pb.inc(1);

    // Format filesystem
    pb.set_message("Formatting filesystem...");
    let root_part = format!("{}2", state.disk);
    let boot_part = format!("{}1", state.disk);
    Command::new("mkfs.fat").args(&["-F32", &boot_part]).status()?;
    let fs_cmd = match state.filesystem.as_ref().unwrap() {
        Filesystem::Btrfs => "mkfs.btrfs -f",
        Filesystem::Ext4 => "mkfs.ext4",
        Filesystem::Zfs => "zpool create -f hackeros",
    };
    Command::new("sh").args(&["-c", &format!("{} {}", fs_cmd, root_part)]).status()?;
    pb.inc(1);

    // Mount
    pb.set_message("Mounting partitions...");
    fs::create_dir_all("/mnt")?;
    Command::new("mount").arg(&root_part).arg("/mnt").status()?;
    fs::create_dir_all("/mnt/boot/efi")?;
    Command::new("mount").arg(&boot_part).arg("/mnt/boot/efi").status()?;
    pb.inc(1);

    // Install base system
    pb.set_message("Installing base system...");
    Command::new("debootstrap").args(&[branch_str, "/mnt", "http://deb.debian.org/debian/"]).status()?;
    pb.inc(1);

    // Bind mounts
    for dir in &["/dev", "/proc", "/sys", "/run"] {
        fs::create_dir_all(format!("/mnt{}", dir))?;
        Command::new("mount").args(&["--bind", dir, &format!("/mnt{}", dir)]).status()?;
    }

    // Chroot commands
    let chroot_cmd = |cmd: &str| -> Result<()> {
        info!("Executing in chroot: {}", cmd);
        Command::new("chroot")
            .arg("/mnt")
            .arg("/bin/bash")
            .arg("-c")
            .arg(cmd)
            .status()?
            .success()
            .then_some(())
            .ok_or(anyhow::anyhow!("Command failed: {}", cmd))
    };

    chroot_cmd("apt update -y")?;
    chroot_cmd("apt install -y linux-image-amd64 grub-efi-amd64 sudo locales tzdata")?;

    // Set locale and timezone
    chroot_cmd(&format!("echo '{}' > /etc/locale.gen", state.locale))?;
    chroot_cmd("locale-gen")?;
    chroot_cmd(&format!("ln -sf /usr/share/zoneinfo/{} /etc/localtime", state.timezone))?;
    chroot_cmd("hwclock --systohc")?;

    // Create users
    chroot_cmd("passwd root")?; // Set root password interactively? But we have it
    let mut child = Command::new("chroot").arg("/mnt").arg("passwd").arg("root").stdin(Stdio::piped()).spawn()?;
    if let Some(mut stdin) = child.stdin.take() {
        stdin.write_all(format!("{}\n{}\n", state.root_password, state.root_password).as_bytes())?;
    }
    child.wait()?;

    chroot_cmd(&format!("useradd -m -G sudo,wheel,audio,video -s /bin/bash {}", state.username))?;
    let mut child = Command::new("chroot").arg("/mnt").arg("passwd").arg(&state.username).stdin(Stdio::piped()).spawn()?;
    if let Some(mut stdin) = child.stdin.take() {
        stdin.write_all(format!("{}\n{}\n", state.password, state.password).as_bytes())?;
    }
    child.wait()?;

    // Hostname
    fs::write("/mnt/etc/hostname", &state.hostname)?;
    fs::write("/mnt/etc/hosts", format!("127.0.0.1 localhost\n127.0.1.1 {}\n", state.hostname))?;

    // Install edition
    install_edition(state.edition.as_ref().unwrap(), state).await?;

    // Grub
    chroot_cmd(&format!("grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=HackerOS {}", state.disk))?;
    chroot_cmd("update-grub")?;

    // Cleanup
    for dir in &["/dev/pts", "/dev", "/proc", "/sys", "/run"] {
        Command::new("umount").arg(format!("/mnt{}", dir)).status()?;
    }
    Command::new("umount").arg("/mnt/boot/efi").status()?;
    Command::new("umount").arg("/mnt").status()?;

    // Remove installer files
    fs::remove_dir_all("/usr/share/HackerOS-Installer")?;
    fs::remove_file("/usr/bin/HackerOS-Installer")?;
    fs::remove_file("/etc/profile.d/HackerOS-Installer.sh")?;

    info!("Installation complete. Rebooting...");
    Command::new("reboot").status()?;

    Ok(())
}

async fn install_edition(edition: &Edition, state: &InstallerState) -> Result<()> {
    let chroot_cmd = |cmd: &str| {
        Command::new("chroot")
            .arg("/mnt")
            .arg("/bin/bash")
            .arg("-c")
            .arg(cmd)
            .status()
    };

    copy_dir("/usr/share/HackerOS-Installer/official/", "/mnt/")?;

    match edition {
        Edition::Official => {
            chroot_cmd("apt install -y task-kde-desktop sddm")?;
        }
        Edition::Gnome => {
            chroot_cmd("apt install -y task-gnome-desktop gdm3")?;
        }
        Edition::Xfce => {
            chroot_cmd("apt install -y task-xfce-desktop lightdm")?;
        }
        Edition::Blue => {
            let client = Client::new();
            let home = format!("/mnt/home/{}/.hackeros/Blue-Environment/", state.username);
            fs::create_dir_all(&home)?;
            let components = vec![
                ("wm", "https://github.com/HackerOS-Linux-System/Blue-Environment/releases/download/v0.1/wm"),
                ("shell", "https://github.com/HackerOS-Linux-System/Blue-Environment/releases/download/v0.1/shell"),
                ("launcher", "https://github.com/HackerOS-Linux-System/Blue-Environment/releases/download/v0.1/launcher"),
                ("Desktop", "https://github.com/HackerOS-Linux-System/Blue-Environment/releases/download/v0.1/Desktop"),
                ("decorations", "https://github.com/HackerOS-Linux-System/Blue-Environment/releases/download/v0.1/decorations"),
                ("core", "https://github.com/HackerOS-Linux-System/Blue-Environment/releases/download/v0.1/core"),
            ];
            for (name, url) in components {
                download_file(&client, url, &format!("{}/{}", home, name)).await?;
                Command::new("chroot").arg("/mnt").arg("chmod").args(&["+x", &format!("/home/{}/.hackeros/Blue-Environment/{}", state.username, name)]).status()?;
            }
            download_file(&client, "https://github.com/HackerOS-Linux-System/Blue-Environment/releases/download/v0.1/Blue-Environment", "/mnt/usr/bin/Blue-Environment").await?;
            Command::new("chroot").arg("/mnt").arg("chmod").args(&["+x", "/usr/bin/Blue-Environment"]).status()?;
            download_file(&client, "https://raw.githubusercontent.com/HackerOS-Linux-System/Blue-Environment/main/Blue-Environment.desktop", "/mnt/usr/share/wayland-sessions/Blue-Environment.desktop").await?;
            chroot_cmd("apt install -y sddm wayland")?;
        }
        Edition::Hydra => {
            Repository::clone("https://github.com/HackerOS-Linux-System/hydra-look-and-feel.git", "/tmp/hydra-look-and-feel")?;
            copy_dir("/tmp/hydra-look-and-feel/files/", "/mnt/")?;
            fs::remove_dir_all("/tmp/hydra-look-and-feel")?;
        }
        Edition::Cybersecurity => {
            chroot_cmd("apt install -y nmap wireshark metasploit-framework burpsuite")?; // Expanded tools
        }
        Edition::Wayfire => {
            chroot_cmd("apt install -y wayfire sddm")?;
        }
        Edition::Atomic => {
            let client = Client::new();
            download_file(&client, "https://github.com/HackerOS-Linux-System/hammer/releases/download/v0.5/hammer", "/mnt/usr/bin/hammer").await?;
            Command::new("chroot").arg("/mnt").arg("chmod").args(&["+x", "/usr/bin/hammer"]).status()?;
            let lib_dir = "/mnt/usr/lib/HackerOS/hammer/";
            fs::create_dir_all(lib_dir)?;
            let hammer_components = vec![
                "https://github.com/HackerOS-Linux-System/hammer/releases/download/v0.5/hammer-updater",
                "https://github.com/HackerOS-Linux-System/hammer/releases/download/v0.5/hammer-tui",
                "https://github.com/HackerOS-Linux-System/hammer/releases/download/v0.5/hammer-core",
                "https://github.com/HackerOS-Linux-System/hammer/releases/download/v0.5/hammer-builder",
            ];
            for url in hammer_components {
                let name = url.split('/').last().unwrap();
                download_file(&client, url, &format!("{}{}", lib_dir, name)).await?;
                Command::new("chroot").arg("/mnt").arg("chmod").args(&["+x", &format!("/usr/lib/HackerOS/hammer/{}", name)]).status()?;
            }
            chroot_cmd("apt install -y task-kde-desktop sddm")?;
            chroot_cmd("hammer setup")?;
        }
    }

    Ok(())
}

async fn download_file(client: &Client, url: &str, path: &str) -> Result<()> {
    let mut resp = client.get(url).send().await?;
    let mut file = File::create(path)?;
    while let Some(chunk) = resp.chunk().await? {
        file.write_all(&chunk)?;
    }
    Ok(())
}

fn copy_dir(src: impl AsRef<Path>, dst: impl AsRef<Path>) -> io::Result<()> {
    fs::create_dir_all(&dst)?;
    for entry in fs::read_dir(src)? {
        let entry = entry?;
        let ty = entry.file_type()?;
        if ty.is_dir() {
            copy_dir(entry.path(), dst.as_ref().join(entry.file_name()))?;
        } else {
            fs::copy(entry.path(), dst.as_ref().join(entry.file_name()))?;
        }
    }
    Ok(())
}
