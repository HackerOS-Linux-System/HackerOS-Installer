#include "installer.h"
#include <sys/wait.h>
#include <fcntl.h>
#include <errno.h>
#include <signal.h>

/* ── task list ──────────────────────────────────────────────────────── */
typedef struct {
    const char *label;
    int         weight;   /* relative progress weight */
} Task;

static const Task TASKS[] = {
    { "Verifying disk access",              2  },
    { "Partitioning disk",                  8  },
    { "Formatting partitions",              5  },
    { "Mounting target filesystem",         2  },
    { "Installing base system (debootstrap)",40 },
    { "Configuring apt sources",            2  },
    { "Installing kernel & bootloader",     15 },
    { "Configuring locale & timezone",      3  },
    { "Configuring network interfaces",     3  },
    { "Creating user accounts",             3  },
    { "Installing role packages",           10 },
    { "Installing extra packages",          5  },
    { "Applying security configuration",    3  },
    { "Generating initramfs",               5  },
    { "Installing GRUB bootloader",         5  },
    { "Finalising installation",            3  },
    { "Unmounting filesystems",             2  },
};
#define N_TASKS ((int)(sizeof(TASKS)/sizeof(TASKS[0])))

/* ── helpers ────────────────────────────────────────────────────────── */
static int total_weight(void)
{
    int t = 0;
    for (int i = 0; i < N_TASKS; i++) t += TASKS[i].weight;
    return t;
}

/* Run a shell command, append stdout+stderr to log_win.
 * Returns exit code. */
static int run_cmd(WINDOW *log_win, const char *cmd)
{
    char line[256];
    FILE *fp = popen(cmd, "r");
    if (!fp) return -1;

    int log_h, log_w;
    getmaxyx(log_win, log_h, log_w);
    (void)log_h;

    while (fgets(line, sizeof(line), fp)) {
        /* trim newline */
        char *nl = strchr(line, '\n');
        if (nl) *nl = '\0';

        wattron(log_win, COLOR_PAIR(CP_DIM));
        waddstr(log_win, line);
        waddch(log_win, '\n');
        wattroff(log_win, COLOR_PAIR(CP_DIM));
        wrefresh(log_win);

        /* keep scroll at bottom */
        int cy, cx;
        getyx(log_win, cy, cx);
        (void)cx;
        if (cy >= log_h - 1) scroll(log_win);
    }
    return pclose(fp);
}

/* Write text to a file in the chroot */
static void chroot_write(const char *path, const char *content)
{
    char full[256];
    snprintf(full, sizeof(full), "/mnt/hackeros%s", path);
    FILE *f = fopen(full, "w");
    if (f) { fputs(content, f); fclose(f); }
}

/* Append text to a file in the chroot */
static void chroot_append(const char *path, const char *content)
{
    char full[256];
    snprintf(full, sizeof(full), "/mnt/hackeros%s", path);
    FILE *f = fopen(full, "a");
    if (f) { fputs(content, f); fclose(f); }
}

/* ── role -> package mapping ─────────────────────────────────────────── */
static const char *role_pkgs(unsigned int roles)
{
    /* static buffer – fine for installer use */
    static char buf[1024];
    buf[0] = '\0';

    if (roles & ROLE_WEB)       strncat(buf, "nginx php-fpm certbot python3-certbot-nginx ", sizeof(buf)-strlen(buf)-1);
    if (roles & ROLE_DATABASE)  strncat(buf, "postgresql mariadb-server ", sizeof(buf)-strlen(buf)-1);
    if (roles & ROLE_MAIL)      strncat(buf, "postfix dovecot-imapd spamassassin ", sizeof(buf)-strlen(buf)-1);
    if (roles & ROLE_DNS)       strncat(buf, "bind9 unbound ", sizeof(buf)-strlen(buf)-1);
    if (roles & ROLE_FILE)      strncat(buf, "samba nfs-kernel-server vsftpd ", sizeof(buf)-strlen(buf)-1);
    if (roles & ROLE_CONTAINER) strncat(buf, "docker.io podman containerd ", sizeof(buf)-strlen(buf)-1);
    if (roles & ROLE_MONITORING)strncat(buf, "prometheus grafana node-exporter ", sizeof(buf)-strlen(buf)-1);
    if (roles & ROLE_VPN)       strncat(buf, "wireguard openvpn ", sizeof(buf)-strlen(buf)-1);
    if (roles & ROLE_SECURITY)  strncat(buf, "fail2ban auditd ufw lynis ", sizeof(buf)-strlen(buf)-1);

    return buf;
}

/* ── extra package names ─────────────────────────────────────────────── */
static const char *EXTRA_PKG_DEBS[MAX_PACKAGES] = {
    "htop btop",
    "tmux",
    "vim neovim",
    "git",
    "rsync",
    "curl wget",
    "net-tools iproute2",
    "python3 python3-pip",
    "unattended-upgrades",
    "logrotate",
    "lvm2",
    "snapd",
    "qemu-guest-agent",
    "open-vm-tools",
    "nfs-common",
};

/* ── main install logic ─────────────────────────────────────────────── */
int do_install(WINDOW *log_win, WINDOW *prog_win)
{
    char cmd[1024];
    int  rc;
    int  prog_w, prog_h;
    getmaxyx(prog_win, prog_h, prog_w);
    (void)prog_h;

    int done_weight = 0;
    int tw = total_weight();

    #define STEP(idx) \
    do { \
        int pct = (done_weight * 100) / tw; \
        werase(prog_win); \
        ui_progress(prog_win, 1, 1, prog_w - 4, pct, TASKS[idx].label); \
        wrefresh(prog_win); \
    } while(0)

    #define ADVANCE(idx) \
    do { done_weight += TASKS[idx].weight; } while(0)

        #define RUN(idx, command) \
        do { \
            STEP(idx); \
            rc = run_cmd(log_win, command); \
            if (rc != 0) { \
                snprintf(g_state.error_msg, sizeof(g_state.error_msg), \
                "Step '%s' failed (exit %d)", TASKS[idx].label, rc); \
                return -1; \
            } \
            ADVANCE(idx); \
        } while(0)

        const char *disk = g_state.disk_device;

        /* Determine partition suffix: nvme uses 'p', others don't */
        char p1[16], p2[16], p3[16];
        bool is_nvme = (strstr(disk, "nvme") != NULL || strstr(disk, "mmcblk") != NULL);
        snprintf(p1, sizeof(p1), "%s%s1", disk, is_nvme ? "p" : "");
        snprintf(p2, sizeof(p2), "%s%s2", disk, is_nvme ? "p" : "");
        snprintf(p3, sizeof(p3), "%s%s3", disk, is_nvme ? "p" : "");

        /* ── 0: verify ─────────────────────────────────────────────────── */
        STEP(0);
        snprintf(cmd, sizeof(cmd), "test -b '%s' && echo 'disk ok' 2>&1", disk);
        rc = run_cmd(log_win, cmd);
        if (rc != 0) {
            snprintf(g_state.error_msg, sizeof(g_state.error_msg),
                     "Disk %s not found or not a block device", disk);
            return -1;
        }
        ADVANCE(0);

        /* ── 1: partition ──────────────────────────────────────────────── */
        STEP(1);
        /* Wipe existing partition table */
        snprintf(cmd, sizeof(cmd), "wipefs -a '%s' 2>&1", disk);
        run_cmd(log_win, cmd);

        if (g_state.use_efi) {
            /* GPT: 512MB EFI + optional swap + root */
            if (g_state.use_swap) {
                snprintf(cmd, sizeof(cmd),
                         "parted -s '%s' mklabel gpt "
                         "mkpart ESP fat32 1MiB 513MiB "
                         "set 1 esp on "
                         "mkpart swap linux-swap 513MiB 4609MiB "
                         "mkpart root ext4 4609MiB 100%% 2>&1", disk);
            } else {
                snprintf(cmd, sizeof(cmd),
                         "parted -s '%s' mklabel gpt "
                         "mkpart ESP fat32 1MiB 513MiB "
                         "set 1 esp on "
                         "mkpart root ext4 513MiB 100%% 2>&1", disk);
            }
        } else {
            /* MBR: optional swap + root */
            if (g_state.use_swap) {
                snprintf(cmd, sizeof(cmd),
                         "parted -s '%s' mklabel msdos "
                         "mkpart primary linux-swap 1MiB 4097MiB "
                         "mkpart primary ext4 4097MiB 100%% "
                         "set 2 boot on 2>&1", disk);
            } else {
                snprintf(cmd, sizeof(cmd),
                         "parted -s '%s' mklabel msdos "
                         "mkpart primary ext4 1MiB 100%% "
                         "set 1 boot on 2>&1", disk);
            }
        }
        RUN(1, cmd);

        /* ── 2: format ─────────────────────────────────────────────────── */
        STEP(2);
        if (g_state.use_efi) {
            snprintf(cmd, sizeof(cmd), "mkfs.fat -F32 '%s' 2>&1", p1);
            run_cmd(log_win, cmd);
            if (g_state.use_swap) {
                snprintf(cmd, sizeof(cmd), "mkswap '%s' 2>&1", p2);
                run_cmd(log_win, cmd);
                snprintf(cmd, sizeof(cmd), "mkfs.ext4 -F '%s' 2>&1", p3);
            } else {
                snprintf(cmd, sizeof(cmd), "mkfs.ext4 -F '%s' 2>&1", p2);
            }
        } else {
            if (g_state.use_swap) {
                snprintf(cmd, sizeof(cmd), "mkswap '%s' 2>&1", p1);
                run_cmd(log_win, cmd);
                snprintf(cmd, sizeof(cmd), "mkfs.ext4 -F '%s' 2>&1", p2);
            } else {
                snprintf(cmd, sizeof(cmd), "mkfs.ext4 -F '%s' 2>&1", p1);
            }
        }
        RUN(2, cmd);
        ADVANCE(2); /* already incremented above via RUN, but weight is fine */

        /* ── 3: mount ──────────────────────────────────────────────────── */
        STEP(3);
        run_cmd(log_win, "mkdir -p /mnt/hackeros 2>&1");

        const char *root_part;
        if (g_state.use_efi) {
            root_part = g_state.use_swap ? p3 : p2;
        } else {
            root_part = g_state.use_swap ? p2 : p1;
        }
        snprintf(cmd, sizeof(cmd), "mount '%s' /mnt/hackeros 2>&1", root_part);
        RUN(3, cmd);

        if (g_state.use_efi) {
            run_cmd(log_win, "mkdir -p /mnt/hackeros/boot/efi 2>&1");
            snprintf(cmd, sizeof(cmd), "mount '%s' /mnt/hackeros/boot/efi 2>&1", p1);
            run_cmd(log_win, cmd);
        }
        if (g_state.use_swap) {
            const char *swap_part = g_state.use_efi ? p2 : p1;
            snprintf(cmd, sizeof(cmd), "swapon '%s' 2>&1", swap_part);
            run_cmd(log_win, cmd);
        }

        /* ── 4: debootstrap ─────────────────────────────────────────────── */
        snprintf(cmd, sizeof(cmd),
                 "debootstrap --arch=amd64 trixie /mnt/hackeros "
                 "http://deb.debian.org/debian 2>&1");
        RUN(4, cmd);

        /* ── 5: apt sources ─────────────────────────────────────────────── */
        STEP(5);
        chroot_write("/etc/apt/sources.list",
                     "deb http://deb.debian.org/debian trixie main contrib non-free non-free-firmware\n"
                     "deb http://deb.debian.org/debian trixie-updates main contrib non-free non-free-firmware\n"
                     "deb http://security.debian.org/debian-security trixie-security main contrib non-free non-free-firmware\n");
        ADVANCE(5);

        /* bind mounts for chroot */
        run_cmd(log_win, "mount --bind /dev  /mnt/hackeros/dev  2>&1");
        run_cmd(log_win, "mount --bind /proc /mnt/hackeros/proc 2>&1");
        run_cmd(log_win, "mount --bind /sys  /mnt/hackeros/sys  2>&1");

        /* ── 6: kernel + bootloader ─────────────────────────────────────── */
        STEP(6);
        run_cmd(log_win,
                "chroot /mnt/hackeros apt-get update -qq 2>&1");
        snprintf(cmd, sizeof(cmd),
                 "chroot /mnt/hackeros apt-get install -y "
                 "linux-image-amd64 linux-headers-amd64 grub-pc %s 2>&1",
                 g_state.use_efi ? "grub-efi-amd64 efibootmgr" : "grub-pc");
        RUN(6, cmd);

        /* ── 7: locale & timezone ───────────────────────────────────────── */
        STEP(7);
        {
            char lc_conf[128];
            snprintf(lc_conf, sizeof(lc_conf), "%s UTF-8\n", g_state.locale);
            chroot_write("/etc/locale.gen", lc_conf);

            char locale_conf[128];
            snprintf(locale_conf, sizeof(locale_conf), "LANG=%s\n", g_state.locale);
            chroot_write("/etc/locale.conf", locale_conf);

            run_cmd(log_win, "chroot /mnt/hackeros locale-gen 2>&1");

            char tz_cmd[256];
            snprintf(tz_cmd, sizeof(tz_cmd),
                     "ln -sf /usr/share/zoneinfo/%s /mnt/hackeros/etc/localtime 2>&1",
                     g_state.timezone);
            run_cmd(log_win, tz_cmd);
            chroot_write("/etc/timezone", g_state.timezone);
            chroot_append("/etc/timezone", "\n");

            /* keyboard */
            char kbd[256];
            snprintf(kbd, sizeof(kbd),
                     "XKBMODEL=\"pc105\"\nXKBLAYOUT=\"%s\"\n"
                     "XKBVARIANT=\"\"\nXKBOPTIONS=\"\"\n", g_state.keymap);
            chroot_write("/etc/default/keyboard", kbd);
        }
        ADVANCE(7);

        /* ── 8: network config ──────────────────────────────────────────── */
        STEP(8);
        {
            /* hostname */
            chroot_write("/etc/hostname", g_state.hostname);
            chroot_append("/etc/hostname", "\n");

            char hosts[512];
            snprintf(hosts, sizeof(hosts),
                     "127.0.0.1\tlocalhost\n"
                     "127.0.1.1\t%s\n"
                     "::1\t\tlocalhost ip6-localhost ip6-loopback\n"
                     "ff02::1\t\tip6-allnodes\n"
                     "ff02::2\t\tip6-allrouters\n",
                     g_state.hostname);
            chroot_write("/etc/hosts", hosts);

            if (!g_state.skip_network) {
                char ifaces_conf[512];
                if (g_state.use_dhcp) {
                    snprintf(ifaces_conf, sizeof(ifaces_conf),
                             "auto lo\niface lo inet loopback\n\n"
                             "auto %s\niface %s inet dhcp\n",
                             g_state.iface, g_state.iface);
                } else {
                    snprintf(ifaces_conf, sizeof(ifaces_conf),
                             "auto lo\niface lo inet loopback\n\n"
                             "auto %s\niface %s inet static\n"
                             "    address %s\n"
                             "    netmask %s\n"
                             "    gateway %s\n"
                             "    dns-nameservers %s\n",
                             g_state.iface, g_state.iface,
                             g_state.ip, g_state.netmask, g_state.gateway, g_state.dns);
                }
                chroot_write("/etc/network/interfaces", ifaces_conf);
            }
        }
        ADVANCE(8);

        /* ── 9: user accounts ───────────────────────────────────────────── */
        STEP(9);
        /* install sudo first */
        run_cmd(log_win, "chroot /mnt/hackeros apt-get install -y sudo 2>&1");

        /* create user */
        snprintf(cmd, sizeof(cmd),
                 "chroot /mnt/hackeros useradd -m -s /bin/bash -G sudo '%s' 2>&1",
                 g_state.username);
        run_cmd(log_win, cmd);

        /* set user password via chpasswd */
        snprintf(cmd, sizeof(cmd),
                 "echo '%s:%s' | chroot /mnt/hackeros chpasswd 2>&1",
                 g_state.username, g_state.password);
        run_cmd(log_win, cmd);

        if (g_state.disable_root) {
            run_cmd(log_win, "chroot /mnt/hackeros passwd -l root 2>&1");
        } else {
            snprintf(cmd, sizeof(cmd),
                     "echo 'root:%s' | chroot /mnt/hackeros chpasswd 2>&1",
                     g_state.root_password);
            run_cmd(log_win, cmd);
        }
        ADVANCE(9);

        /* ── 10: role packages ──────────────────────────────────────────── */
        STEP(10);
        if (!g_state.skip_roles && g_state.roles) {
            const char *rpkgs = role_pkgs(g_state.roles);
            if (rpkgs[0]) {
                snprintf(cmd, sizeof(cmd),
                         "chroot /mnt/hackeros apt-get install -y %s 2>&1", rpkgs);
                run_cmd(log_win, cmd);
            }
        }
        ADVANCE(10);

        /* ── 11: extra packages ─────────────────────────────────────────── */
        STEP(11);
        if (!g_state.skip_extra) {
            char extra[1024] = "";
            for (int i = 0; i < MAX_PACKAGES; i++) {
                if (g_state.pkg_selected[i] && EXTRA_PKG_DEBS[i]) {
                    strncat(extra, EXTRA_PKG_DEBS[i], sizeof(extra) - strlen(extra) - 2);
                    strncat(extra, " ",                sizeof(extra) - strlen(extra) - 1);
                }
            }
            if (extra[0]) {
                snprintf(cmd, sizeof(cmd),
                         "chroot /mnt/hackeros apt-get install -y %s 2>&1", extra);
                run_cmd(log_win, cmd);
            }
        }
        ADVANCE(11);

        /* ── 12: security config ────────────────────────────────────────── */
        STEP(12);
        /* SSH hardening */
        chroot_append("/etc/ssh/sshd_config",
                      "\n# HackerOS hardening\n"
                      "PermitRootLogin no\n"
                      "PasswordAuthentication no\n"
                      "X11Forwarding no\n"
                      "AllowTcpForwarding no\n"
                      "MaxAuthTries 3\n");

        /* HackerOS MOTD banner */
        chroot_write("/etc/motd",
                     "\n"
                     "  ██╗  ██╗ █████╗  ██████╗██╗  ██╗███████╗██████╗ \n"
                     "  ██║  ██║██╔══██╗██╔════╝██║ ██╔╝██╔════╝██╔══██╗\n"
                     "  ███████║███████║██║     █████╔╝ █████╗  ██████╔╝\n"
                     "  ██╔══██║██╔══██║██║     ██╔═██╗ ██╔══╝  ██╔══██╗\n"
                     "  ██║  ██║██║  ██║╚██████╗██║  ██╗███████╗██║  ██║\n"
                     "  ╚═╝  ╚═╝╚═╝  ╚═╝ ╚═════╝╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝\n"
                     "       Server Edition  –  Debian Trixie base\n\n");

        /* UFW */
        run_cmd(log_win,
                "chroot /mnt/hackeros apt-get install -y ufw 2>&1 && "
                "chroot /mnt/hackeros ufw --force enable 2>&1 && "
                "chroot /mnt/hackeros ufw allow ssh 2>&1");
        ADVANCE(12);

        /* ── 13: initramfs ──────────────────────────────────────────────── */
        STEP(13);
        run_cmd(log_win, "chroot /mnt/hackeros update-initramfs -u -k all 2>&1");
        ADVANCE(13);

        /* ── 14: GRUB ───────────────────────────────────────────────────── */
        STEP(14);
        /* GRUB theme: orange */
        chroot_write("/etc/default/grub",
                     "GRUB_DEFAULT=0\n"
                     "GRUB_TIMEOUT=5\n"
                     "GRUB_DISTRIBUTOR=\"HackerOS\"\n"
                     "GRUB_CMDLINE_LINUX_DEFAULT=\"quiet\"\n"
                     "GRUB_CMDLINE_LINUX=\"\"\n"
                     "GRUB_COLOR_NORMAL=\"light-yellow/black\"\n"
                     "GRUB_COLOR_HIGHLIGHT=\"black/light-yellow\"\n");

        if (g_state.use_efi) {
            run_cmd(log_win,
                    "chroot /mnt/hackeros grub-install --target=x86_64-efi "
                    "--efi-directory=/boot/efi --bootloader-id=HackerOS 2>&1");
        } else {
            snprintf(cmd, sizeof(cmd),
                     "chroot /mnt/hackeros grub-install '%s' 2>&1", disk);
            run_cmd(log_win, cmd);
        }
        run_cmd(log_win, "chroot /mnt/hackeros update-grub 2>&1");
        ADVANCE(14);

        /* ── 15: finalise ───────────────────────────────────────────────── */
        STEP(15);
        /* fstab */
        run_cmd(log_win,
                "genfstab -U /mnt/hackeros >> /mnt/hackeros/etc/fstab 2>&1 || "
                "chroot /mnt/hackeros bash -c 'mount | grep /mnt/hackeros' 2>&1");
        ADVANCE(15);

        /* ── 16: unmount ────────────────────────────────────────────────── */
        STEP(16);
        run_cmd(log_win, "umount -R /mnt/hackeros 2>&1");
        if (g_state.use_swap) {
            const char *swap_part = g_state.use_efi ? p2 : p1;
            snprintf(cmd, sizeof(cmd), "swapoff '%s' 2>&1", swap_part);
            run_cmd(log_win, cmd);
        }
        ADVANCE(16);

        /* ── done ──────────────────────────────────────────────────────── */
        werase(prog_win);
        ui_progress(prog_win, 1, 1, prog_w - 4, 100, "Installation complete!");
        wrefresh(prog_win);

        return 0;
}

/* ── screen_install ──────────────────────────────────────────────────── */
int screen_install(void)
{
    int rows, cols;
    getmaxyx(stdscr, rows, cols);
    ui_draw_base("Installing HackerOS", SCREEN_INSTALL, SCREEN_FINISH + 1);

    /* progress window */
    int prog_h = 5, prog_w = cols - 8;
    int prog_y = 13;
    int prog_x = 4;

    WINDOW *prog_win = newwin(prog_h, prog_w, prog_y, prog_x);
    wbkgd(prog_win, COLOR_PAIR(CP_NORMAL));
    ui_draw_border(prog_win);
    wrefresh(prog_win);

    /* log window – scrollable */
    int log_y = prog_y + prog_h + 1;
    int log_h = rows - log_y - 3;
    if (log_h < 4) log_h = 4;
    int log_w = cols - 8;

    WINDOW *log_win = newwin(log_h, log_w, log_y, prog_x);
    wbkgd(log_win, COLOR_PAIR(CP_NORMAL));
    ui_draw_border(log_win);
    scrollok(log_win, TRUE);
    idlok(log_win, TRUE);
    wmove(log_win, 1, 1);

    wattron(log_win, COLOR_PAIR(CP_STATUS) | A_BOLD);
    mvwaddstr(log_win, 0, 2, " Installation log ");
    wattroff(log_win, COLOR_PAIR(CP_STATUS) | A_BOLD);
    wrefresh(log_win);

    int ret = do_install(log_win, prog_win);

    if (ret != 0) {
        /* show error */
        wattron(log_win, COLOR_PAIR(CP_ERROR) | A_BOLD);
        mvwprintw(log_win, log_h - 2, 2, "✗ FAILED: %s", g_state.error_msg);
        wattroff(log_win, COLOR_PAIR(CP_ERROR) | A_BOLD);
        wrefresh(log_win);

        wattron(stdscr, COLOR_PAIR(CP_DIM));
        mvwaddstr(stdscr, rows - 1, 1, "  Press any key to return to the summary …  ");
        wattroff(stdscr, COLOR_PAIR(CP_DIM));
        wrefresh(stdscr);
        getch();
        delwin(prog_win);
        delwin(log_win);
        return -1;
    }

    g_state.install_done = true;
    delwin(prog_win);
    delwin(log_win);
    return 1;
}
