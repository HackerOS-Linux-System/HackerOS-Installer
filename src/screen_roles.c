#include "installer.h"

/* ── Server role definitions ─────────────────────────────────────────── */
typedef struct {
    ServerRole  flag;
    const char *name;
    const char *desc;
} RoleDef;

static const RoleDef ROLES[] = {
    { ROLE_WEB,       "Web Server",        "nginx / Apache + PHP-FPM + certbot" },
    { ROLE_DATABASE,  "Database",          "PostgreSQL + MySQL/MariaDB"         },
    { ROLE_MAIL,      "Mail Server",       "Postfix + Dovecot + SpamAssassin"   },
    { ROLE_DNS,       "DNS Server",        "BIND9 / Unbound recursive resolver" },
    { ROLE_FILE,      "File Server",       "Samba + NFS + vsftpd"               },
    { ROLE_CONTAINER, "Container Host",    "Docker + Podman + containerd"       },
    { ROLE_MONITORING,"Monitoring",        "Prometheus + Grafana + node_exporter"},
    { ROLE_VPN,       "VPN Gateway",       "WireGuard + OpenVPN"                },
    { ROLE_SECURITY,  "Security / Audit",  "fail2ban + auditd + ufw + lynis"    },
};
#define N_ROLES ((int)(sizeof(ROLES)/sizeof(ROLES[0])))

/* ── Extra optional packages ─────────────────────────────────────────── */
typedef struct {
    const char *name;
    const char *desc;
} PkgDef;

static const PkgDef PKGS[] = {
    { "htop / btop",        "Interactive process viewer"                      },
    { "tmux",               "Terminal multiplexer"                             },
    { "vim / neovim",       "Text editors"                                     },
    { "git",                "Version control system"                           },
    { "rsync",              "File sync / backup utility"                       },
    { "curl / wget",        "HTTP/HTTPS transfer tools"                        },
    { "net-tools / iproute2","Network diagnostic tools"                        },
    { "python3 + pip",      "Python 3 runtime + package manager"               },
    { "unattended-upgrades","Automatic security updates"                       },
    { "logrotate",          "Log rotation and management"                      },
    { "lvm2",               "Logical volume manager"                           },
    { "snapd",              "Snap package support"                             },
    { "qemu-guest-agent",   "QEMU/KVM guest agent (for VMs)"                  },
    { "open-vm-tools",      "VMware guest utilities (for VMware VMs)"          },
    { "nfs-client",         "NFS client utilities"                             },
};
#define N_PKGS ((int)(sizeof(PKGS)/sizeof(PKGS[0])))

/* ── screen_server_role ───────────────────────────────────────────────── */
int screen_server_role(void)
{
    unsigned int roles = g_state.roles;
    bool skip_roles   = g_state.skip_roles;
    int cursor = 0; /* which role row is highlighted */

    while (1) {
        int rows, cols;
        getmaxyx(stdscr, rows, cols);
        ui_draw_base("Server Role", SCREEN_SERVER_ROLE, SCREEN_FINISH + 1);

        int bh = N_ROLES + 8, bw = 70;
        int by = rows / 2 - bh / 2 + 3;
        int bx = (cols - bw) / 2;
        if (by < 13) by = 13;

        WINDOW *w = newwin(bh, bw, by, bx);
        wbkgd(w, COLOR_PAIR(CP_NORMAL));
        ui_draw_border(w);

        wattron(w, COLOR_PAIR(CP_STATUS) | A_BOLD);
        mvwaddstr(w, 1, 2, "What will this server be used for?");
        wattroff(w, COLOR_PAIR(CP_STATUS) | A_BOLD);

        wattron(w, COLOR_PAIR(CP_DIM));
        mvwaddstr(w, 2, 2, "[SPACE] toggle   [ENTER] confirm   optional: can be skipped");
        wattroff(w, COLOR_PAIR(CP_DIM));

        for (int i = 0; i < N_ROLES; i++) {
            bool checked = (roles & ROLES[i].flag) != 0;
            bool active  = (cursor == i) && !skip_roles;

            if (active)
                wattron(w, COLOR_PAIR(CP_SELECTED) | A_BOLD);
            else if (checked)
                wattron(w, COLOR_PAIR(CP_BORDER));
            else if (skip_roles)
                wattron(w, COLOR_PAIR(CP_DIM));
            else
                wattron(w, COLOR_PAIR(CP_NORMAL));

            mvwprintw(w, 4 + i, 2, " [%s] %-20s %s",
                      checked ? "✓" : " ",
                      ROLES[i].name,
                      ROLES[i].desc);

            if (active)       wattroff(w, COLOR_PAIR(CP_SELECTED) | A_BOLD);
            else if (checked) wattroff(w, COLOR_PAIR(CP_BORDER));
            else if (skip_roles) wattroff(w, COLOR_PAIR(CP_DIM));
            else              wattroff(w, COLOR_PAIR(CP_NORMAL));
        }

        wattron(w, COLOR_PAIR(CP_BORDER));
        mvwhline(w, 4 + N_ROLES, 1, ACS_HLINE, bw - 2);
        wattroff(w, COLOR_PAIR(CP_BORDER));

        /* skip toggle */
        {
            bool act = (cursor == N_ROLES);
            if (act)       wattron(w, COLOR_PAIR(CP_SELECTED) | A_BOLD);
            else if (skip_roles) wattron(w, COLOR_PAIR(CP_BORDER));
            else           wattron(w, COLOR_PAIR(CP_NORMAL));
            mvwprintw(w, bh - 3, 2, " [%s] Skip – install base system only (configure roles later)",
                      skip_roles ? "✓" : " ");
            if (act)       wattroff(w, COLOR_PAIR(CP_SELECTED) | A_BOLD);
            else if (skip_roles) wattroff(w, COLOR_PAIR(CP_BORDER));
            else           wattroff(w, COLOR_PAIR(CP_NORMAL));
        }

        /* continue button */
        bool btn_act = (cursor == N_ROLES + 1);
        if (btn_act) {
            wattron(w, COLOR_PAIR(CP_SELECTED) | A_BOLD);
            mvwprintw(w, bh - 2, (bw - 14) / 2, "[ Continue → ]");
            wattroff(w, COLOR_PAIR(CP_SELECTED) | A_BOLD);
        } else {
            wattron(w, COLOR_PAIR(CP_BORDER));
            mvwprintw(w, bh - 2, (bw - 14) / 2, "[ Continue → ]");
            wattroff(w, COLOR_PAIR(CP_BORDER));
        }

        wrefresh(w);
        int ch = wgetch(w);
        delwin(w);

        int n_total = N_ROLES + 2; /* roles + skip + btn */
        if (ch == KEY_UP)   { cursor = (cursor + n_total - 1) % n_total; continue; }
        if (ch == KEY_DOWN || ch == '\t') { cursor = (cursor + 1) % n_total; continue; }
        if (ch == 27) return -1;

        if (ch == ' ' || ch == '\n' || ch == '\r') {
            if (cursor < N_ROLES && !skip_roles) {
                roles ^= ROLES[cursor].flag;
            } else if (cursor == N_ROLES) {
                skip_roles = !skip_roles;
            } else if (cursor == N_ROLES + 1) {
                g_state.roles      = skip_roles ? 0 : roles;
                g_state.skip_roles = skip_roles;
                return 1;
            }
        }
    }
}

/* ── screen_packages ─────────────────────────────────────────────────── */
int screen_packages(void)
{
    bool sel[MAX_PACKAGES] = {0};
    for (int i = 0; i < N_PKGS && i < MAX_PACKAGES; i++)
        sel[i] = g_state.pkg_selected[i];

    bool skip_extra = g_state.skip_extra;
    int cursor = 0;
    int n_total = N_PKGS + 2; /* pkgs + skip + btn */

    while (1) {
        int rows, cols;
        getmaxyx(stdscr, rows, cols);
        ui_draw_base("Extra Packages  [optional]", SCREEN_PACKAGES, SCREEN_FINISH + 1);

        int bh = N_PKGS + 8, bw = 70;
        if (bh > rows - 16) bh = rows - 16;
        int by = rows / 2 - bh / 2 + 3;
        int bx = (cols - bw) / 2;
        if (by < 13) by = 13;

        WINDOW *w = newwin(bh, bw, by, bx);
        wbkgd(w, COLOR_PAIR(CP_NORMAL));
        ui_draw_border(w);

        wattron(w, COLOR_PAIR(CP_STATUS) | A_BOLD);
        mvwaddstr(w, 1, 2, "Select additional packages to install");
        wattroff(w, COLOR_PAIR(CP_STATUS) | A_BOLD);
        wattron(w, COLOR_PAIR(CP_DIM));
        mvwaddstr(w, 2, 2, "[SPACE] toggle   optional – can be skipped");
        wattroff(w, COLOR_PAIR(CP_DIM));

        int list_h = bh - 6;
        int scroll = 0;
        if (cursor < N_PKGS && cursor >= scroll + list_h) scroll = cursor - list_h + 1;
        if (cursor < scroll) scroll = cursor;

        for (int i = 0; i < list_h && (i + scroll) < N_PKGS; i++) {
            int idx = i + scroll;
            bool checked = sel[idx];
            bool active  = (cursor == idx) && !skip_extra;

            if (active)
                wattron(w, COLOR_PAIR(CP_SELECTED) | A_BOLD);
            else if (checked)
                wattron(w, COLOR_PAIR(CP_BORDER));
            else if (skip_extra)
                wattron(w, COLOR_PAIR(CP_DIM));
            else
                wattron(w, COLOR_PAIR(CP_NORMAL));

            mvwprintw(w, 4 + i, 2, " [%s] %-22s %s",
                      checked ? "✓" : " ",
                      PKGS[idx].name, PKGS[idx].desc);

            if (active)        wattroff(w, COLOR_PAIR(CP_SELECTED) | A_BOLD);
            else if (checked)  wattroff(w, COLOR_PAIR(CP_BORDER));
            else if (skip_extra) wattroff(w, COLOR_PAIR(CP_DIM));
            else               wattroff(w, COLOR_PAIR(CP_NORMAL));
        }

        wattron(w, COLOR_PAIR(CP_BORDER));
        mvwhline(w, bh - 4, 1, ACS_HLINE, bw - 2);
        wattroff(w, COLOR_PAIR(CP_BORDER));

        /* skip */
        {
            bool act = (cursor == N_PKGS);
            if (act)          wattron(w, COLOR_PAIR(CP_SELECTED) | A_BOLD);
            else if (skip_extra) wattron(w, COLOR_PAIR(CP_BORDER));
            else              wattron(w, COLOR_PAIR(CP_NORMAL));
            mvwprintw(w, bh - 3, 2, " [%s] Skip – no extra packages", skip_extra ? "✓" : " ");
            if (act)          wattroff(w, COLOR_PAIR(CP_SELECTED) | A_BOLD);
            else if (skip_extra) wattroff(w, COLOR_PAIR(CP_BORDER));
            else              wattroff(w, COLOR_PAIR(CP_NORMAL));
        }

        bool btn_act = (cursor == N_PKGS + 1);
        if (btn_act) {
            wattron(w, COLOR_PAIR(CP_SELECTED) | A_BOLD);
            mvwprintw(w, bh - 2, (bw - 14) / 2, "[ Continue → ]");
            wattroff(w, COLOR_PAIR(CP_SELECTED) | A_BOLD);
        } else {
            wattron(w, COLOR_PAIR(CP_BORDER));
            mvwprintw(w, bh - 2, (bw - 14) / 2, "[ Continue → ]");
            wattroff(w, COLOR_PAIR(CP_BORDER));
        }

        wrefresh(w);
        int ch = wgetch(w);
        delwin(w);

        if (ch == KEY_UP)   { cursor = (cursor + n_total - 1) % n_total; continue; }
        if (ch == KEY_DOWN || ch == '\t') { cursor = (cursor + 1) % n_total; continue; }
        if (ch == 27) return -1;

        if (ch == ' ' || ch == '\n' || ch == '\r') {
            if (cursor < N_PKGS && !skip_extra) {
                sel[cursor] = !sel[cursor];
            } else if (cursor == N_PKGS) {
                skip_extra = !skip_extra;
            } else if (cursor == N_PKGS + 1) {
                g_state.skip_extra = skip_extra;
                for (int i = 0; i < N_PKGS && i < MAX_PACKAGES; i++)
                    g_state.pkg_selected[i] = skip_extra ? false : sel[i];
                return 1;
            }
        }
    }
}

/* ── screen_extra_config ─────────────────────────────────────────────── */
int screen_extra_config(void)
{
    /* checkboxes: auto-updates, ssh hardening, firewall, banner */
    bool auto_updates = true;
    bool ssh_harden   = true;
    bool firewall     = true;
    bool motd_banner  = true;
    bool ntp          = true;

    const char *labels[] = {
        "Enable unattended security updates",
        "Harden SSH (disable password auth, root login)",
        "Enable & configure UFW firewall",
        "Install HackerOS MOTD banner",
        "Configure NTP time synchronisation",
    };
    bool *vals[] = { &auto_updates, &ssh_harden, &firewall, &motd_banner, &ntp };
    int n_opts = 5;
    int cursor = 0;

    while (1) {
        int rows, cols;
        getmaxyx(stdscr, rows, cols);
        ui_draw_base("Extra Configuration  [optional]", SCREEN_EXTRA_CONFIG, SCREEN_FINISH + 1);

        int bh = n_opts + 9, bw = 68;
        int by = rows / 2 - bh / 2 + 3;
        int bx = (cols - bw) / 2;
        if (by < 13) by = 13;

        WINDOW *w = newwin(bh, bw, by, bx);
        wbkgd(w, COLOR_PAIR(CP_NORMAL));
        ui_draw_border(w);

        wattron(w, COLOR_PAIR(CP_STATUS) | A_BOLD);
        mvwaddstr(w, 1, 2, "Post-install configuration options");
        wattroff(w, COLOR_PAIR(CP_STATUS) | A_BOLD);
        wattron(w, COLOR_PAIR(CP_DIM));
        mvwaddstr(w, 2, 2, "Recommended settings pre-selected. Toggle with [SPACE].");
        wattroff(w, COLOR_PAIR(CP_DIM));

        for (int i = 0; i < n_opts; i++) {
            bool act = (cursor == i);
            if (act)          wattron(w, COLOR_PAIR(CP_SELECTED) | A_BOLD);
            else if (*vals[i]) wattron(w, COLOR_PAIR(CP_BORDER));
            else              wattron(w, COLOR_PAIR(CP_NORMAL));
            mvwprintw(w, 4 + i, 2, " [%s] %s", *vals[i] ? "✓" : " ", labels[i]);
            if (act)          wattroff(w, COLOR_PAIR(CP_SELECTED) | A_BOLD);
            else if (*vals[i]) wattroff(w, COLOR_PAIR(CP_BORDER));
            else              wattroff(w, COLOR_PAIR(CP_NORMAL));
        }

        wattron(w, COLOR_PAIR(CP_BORDER));
        mvwhline(w, 4 + n_opts, 1, ACS_HLINE, bw - 2);
        wattroff(w, COLOR_PAIR(CP_BORDER));

        wattron(w, COLOR_PAIR(CP_DIM));
        mvwaddstr(w, bh - 3, 2, "These settings can be changed anytime after install.");
        wattroff(w, COLOR_PAIR(CP_DIM));

        bool btn_act = (cursor == n_opts);
        if (btn_act) {
            wattron(w, COLOR_PAIR(CP_SELECTED) | A_BOLD);
            mvwprintw(w, bh - 2, (bw - 14) / 2, "[ Continue → ]");
            wattroff(w, COLOR_PAIR(CP_SELECTED) | A_BOLD);
        } else {
            wattron(w, COLOR_PAIR(CP_BORDER));
            mvwprintw(w, bh - 2, (bw - 14) / 2, "[ Continue → ]");
            wattroff(w, COLOR_PAIR(CP_BORDER));
        }

        wrefresh(w);
        int ch = wgetch(w);
        delwin(w);

        int n_total = n_opts + 1;
        if (ch == KEY_UP)   { cursor = (cursor + n_total - 1) % n_total; continue; }
        if (ch == KEY_DOWN || ch == '\t') { cursor = (cursor + 1) % n_total; continue; }
        if (ch == 27) return -1;

        if (ch == ' ') {
            if (cursor < n_opts) *vals[cursor] = !*vals[cursor];
        } else if (ch == '\n' || ch == '\r') {
            if (cursor < n_opts) *vals[cursor] = !*vals[cursor];
            else if (cursor == n_opts) return 1;
        }
    }
}
