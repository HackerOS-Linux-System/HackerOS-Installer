#include "installer.h"

static const char *part_name(PartScheme p)
{
    switch (p) {
        case PART_AUTO_FULL:     return "Auto – full disk (ext4)";
        case PART_AUTO_LVM:      return "Auto – LVM";
        case PART_AUTO_LUKS_LVM: return "Auto – LUKS + LVM (encrypted)";
        case PART_MANUAL:        return "Manual";
        default:                  return "Unknown";
    }
}

int screen_summary(void)
{
    while (1) {
        int rows, cols;
        getmaxyx(stdscr, rows, cols);
        ui_draw_base("Installation Summary", SCREEN_SUMMARY, SCREEN_FINISH + 1);

        int bh = 22, bw = 66;
        int by = rows / 2 - bh / 2 + 3;
        int bx = (cols - bw) / 2;
        if (by < 13) by = 13;

        WINDOW *w = newwin(bh, bw, by, bx);
        wbkgd(w, COLOR_PAIR(CP_NORMAL));
        ui_draw_border(w);

        wattron(w, COLOR_PAIR(CP_STATUS) | A_BOLD);
        mvwaddstr(w, 1, 2, "Review your settings before installation begins");
        wattroff(w, COLOR_PAIR(CP_STATUS) | A_BOLD);

        wattron(w, COLOR_PAIR(CP_BORDER));
        mvwhline(w, 2, 1, ACS_HLINE, bw - 2);
        wattroff(w, COLOR_PAIR(CP_BORDER));

        /* helper macro for key-value row */
        #define KV(row, key, fmt, ...) \
        do { \
            wattron(w, COLOR_PAIR(CP_DIM)); \
            mvwprintw(w, row, 2, "%-18s", key); \
            wattroff(w, COLOR_PAIR(CP_DIM)); \
            wattron(w, COLOR_PAIR(CP_NORMAL)); \
            mvwprintw(w, row, 21, fmt, ##__VA_ARGS__); \
            wattroff(w, COLOR_PAIR(CP_NORMAL)); \
        } while(0)

        KV(3,  "Locale:",      "%s", g_state.locale[0]   ? g_state.locale   : "(default)");
        KV(4,  "Timezone:",    "%s", g_state.timezone[0] ? g_state.timezone : "(default)");
        KV(5,  "Keyboard:",    "%s", g_state.keymap[0]   ? g_state.keymap   : "(default)");

        wattron(w, COLOR_PAIR(CP_BORDER));
        mvwhline(w, 6, 1, ACS_HLINE, bw - 2);
        wattroff(w, COLOR_PAIR(CP_BORDER));

        KV(7,  "Target disk:", "%s", g_state.disk_device);
        KV(8,  "Partitioning:","%-30s  swap: %s", part_name(g_state.part_scheme), g_state.use_swap ? "yes" : "no");
        KV(9,  "Boot mode:",   "%s", g_state.use_efi ? "UEFI" : "BIOS/Legacy");

        wattron(w, COLOR_PAIR(CP_BORDER));
        mvwhline(w, 10, 1, ACS_HLINE, bw - 2);
        wattroff(w, COLOR_PAIR(CP_BORDER));

        KV(11, "Hostname:",    "%s", g_state.hostname);
        KV(12, "Username:",    "%s", g_state.username);
        KV(13, "Root login:",  "%s", g_state.disable_root ? "disabled (sudo only)" : "enabled");

        wattron(w, COLOR_PAIR(CP_BORDER));
        mvwhline(w, 14, 1, ACS_HLINE, bw - 2);
        wattroff(w, COLOR_PAIR(CP_BORDER));

        KV(15, "Network:",     "%s", g_state.skip_network ? "configure later" :
        (g_state.use_dhcp ? "DHCP" : g_state.ip));
        KV(16, "Server roles:","%s", g_state.skip_roles ? "base only" :
        (g_state.roles ? "(selected)" : "none"));

        wattron(w, COLOR_PAIR(CP_BORDER));
        mvwhline(w, 17, 1, ACS_HLINE, bw - 2);
        wattroff(w, COLOR_PAIR(CP_BORDER));

        wattron(w, COLOR_PAIR(CP_ERROR) | A_BOLD);
        mvwaddstr(w, 18, 2,
                  "⚠  This will ERASE the selected disk!  Proceed only if you are sure.");
        wattroff(w, COLOR_PAIR(CP_ERROR) | A_BOLD);

        /* buttons */
        wattron(w, COLOR_PAIR(CP_SELECTED) | A_BOLD);
        mvwaddstr(w, bh - 2, 4, "[ ← Back ]");
        wattroff(w, COLOR_PAIR(CP_SELECTED) | A_BOLD);
        wattron(w, COLOR_PAIR(CP_ERROR) | A_BOLD);
        mvwaddstr(w, bh - 2, bw - 22, "[ Install Now ▶ ]");
        wattroff(w, COLOR_PAIR(CP_ERROR) | A_BOLD);

        wrefresh(w);
        int ch = wgetch(w);
        delwin(w);

        if (ch == 27 || ch == KEY_LEFT || ch == 'b' || ch == 'B') return -1;
        if (ch == '\n' || ch == '\r' || ch == KEY_RIGHT || ch == 'i' || ch == 'I') return 1;
    }
}

/* ── screen_finish ───────────────────────────────────────────────────── */
int screen_finish(void)
{
    int rows, cols;
    getmaxyx(stdscr, rows, cols);
    ui_draw_base("Installation Complete", SCREEN_FINISH, SCREEN_FINISH + 1);

    int bh = 12, bw = 60;
    int by = rows / 2 - bh / 2 + 3;
    int bx = (cols - bw) / 2;
    if (by < 13) by = 13;

    WINDOW *w = newwin(bh, bw, by, bx);
    wbkgd(w, COLOR_PAIR(CP_NORMAL));
    ui_draw_border(w);

    wattron(w, COLOR_PAIR(CP_SUCCESS) | A_BOLD);
    mvwaddstr(w, 2, (bw - 32) / 2, "✓  HackerOS has been installed!");
    wattroff(w, COLOR_PAIR(CP_SUCCESS) | A_BOLD);

    wattron(w, COLOR_PAIR(CP_NORMAL));
    mvwaddstr(w, 4, 3, "The system will now reboot from the new installation.");
    mvwaddstr(w, 5, 3, "Remove installation media before the machine restarts.");
    wattroff(w, COLOR_PAIR(CP_NORMAL));

    wattron(w, COLOR_PAIR(CP_DIM));
    mvwprintw(w, 7, 3, "Hostname  :  %s", g_state.hostname);
    mvwprintw(w, 8, 3, "Username  :  %s", g_state.username);
    wattroff(w, COLOR_PAIR(CP_DIM));

    wattron(w, COLOR_PAIR(CP_SELECTED) | A_BOLD);
    mvwaddstr(w, bh - 2, (bw - 20) / 2, "[ Reboot System ]");
    wattroff(w, COLOR_PAIR(CP_SELECTED) | A_BOLD);

    wrefresh(w);
    while (1) {
        int ch = wgetch(w);
        if (ch == '\n' || ch == '\r' || ch == ' ') {
            delwin(w);
            return 1;
        }
    }
}
