#include "installer.h"
#include <ctype.h>

#define N_FIELDS 7

/* field indices */
#define F_HOSTNAME  0
#define F_USERNAME  1
#define F_PASSWORD  2
#define F_PASSWORD2 3
#define F_ROOTPW    4
#define F_ROOTPW2   5
#define F_DISROOT   6

static bool validate_hostname(const char *s)
{
    if (!s || !*s) return false;
    int len = (int)strlen(s);
    if (len > 63) return false;
    for (int i = 0; i < len; i++) {
        char c = s[i];
        if (!isalnum(c) && c != '-') return false;
    }
    if (s[0] == '-' || s[len-1] == '-') return false;
    return true;
}

static bool validate_username(const char *s)
{
    if (!s || !*s) return false;
    if (strlen(s) > 32) return false;
    if (!islower((unsigned char)s[0])) return false;
    for (int i = 0; s[i]; i++) {
        char c = s[i];
        if (!islower((unsigned char)c) && !isdigit(c) && c != '_' && c != '-') return false;
    }
    return true;
}

int screen_user(void)
{
    /* local copies for editing */
    char hostname[MAX_INPUT], username[MAX_INPUT];
    char pw1[MAX_INPUT], pw2[MAX_INPUT];
    char rpw1[MAX_INPUT], rpw2[MAX_INPUT];
    bool disable_root = g_state.disable_root;

    strncpy(hostname, g_state.hostname,     sizeof(hostname)  - 1);
    strncpy(username, g_state.username,     sizeof(username)  - 1);
    strncpy(pw1,      g_state.password,     sizeof(pw1)       - 1);
    strncpy(pw2,      g_state.password2,    sizeof(pw2)       - 1);
    strncpy(rpw1,     g_state.root_password,  sizeof(rpw1)    - 1);
    strncpy(rpw2,     g_state.root_password2, sizeof(rpw2)    - 1);

    int sel = 0;
    char *bufs[N_FIELDS] = { hostname, username, pw1, pw2, rpw1, rpw2, NULL };
    const char *labels[N_FIELDS] = {
        "Hostname:",
        "Username:",
        "Password:",
        "Confirm Password:",
        "Root Password:",
        "Confirm Root PW:",
        "Disable root login:",
    };
    bool secret[N_FIELDS] = { false, false, true, true, true, true, false };

    char errmsg[128] = "";

    while (1) {
        int rows, cols;
        getmaxyx(stdscr, rows, cols);
        ui_draw_base("Create User", SCREEN_USER, SCREEN_FINISH + 1);

        int bh = 22, bw = 62;
        int by = rows / 2 - bh / 2 + 3;
        int bx = (cols - bw) / 2;
        if (by < 13) by = 13;

        WINDOW *w = newwin(bh, bw, by, bx);
        wbkgd(w, COLOR_PAIR(CP_NORMAL));
        ui_draw_border(w);

        wattron(w, COLOR_PAIR(CP_STATUS) | A_BOLD);
        mvwaddstr(w, 1, 2, "Configure system user & root account");
        wattroff(w, COLOR_PAIR(CP_STATUS) | A_BOLD);

        for (int i = 0; i < N_FIELDS - 1; i++) {
            draw_field(w, 3 + i * 2, 2, bw - 4,
                       labels[i], bufs[i], sel == i, secret[i]);
        }

        /* disable root toggle */
        {
            bool act = (sel == F_DISROOT);
            if (act) wattron(w, COLOR_PAIR(CP_STATUS) | A_BOLD);
            else     wattron(w, COLOR_PAIR(CP_NORMAL));
            mvwprintw(w, 3 + (N_FIELDS - 1) * 2, 2, "%-20s", labels[F_DISROOT]);
            if (act) wattroff(w, COLOR_PAIR(CP_STATUS) | A_BOLD);
            else     wattroff(w, COLOR_PAIR(CP_NORMAL));

            if (act) wattron(w, COLOR_PAIR(CP_SELECTED) | A_BOLD);
            else if (disable_root) wattron(w, COLOR_PAIR(CP_BORDER));
            else wattron(w, COLOR_PAIR(CP_DIM));
            mvwprintw(w, 3 + (N_FIELDS - 1) * 2, 22, " [%s] ", disable_root ? "✓" : " ");
            if (act) wattroff(w, COLOR_PAIR(CP_SELECTED) | A_BOLD);
            else if (disable_root) wattroff(w, COLOR_PAIR(CP_BORDER));
            else wattroff(w, COLOR_PAIR(CP_DIM));

            wattron(w, COLOR_PAIR(CP_DIM));
            mvwaddstr(w, 3 + (N_FIELDS - 1) * 2, 30, "(use sudo instead)");
            wattroff(w, COLOR_PAIR(CP_DIM));
        }

        /* error message */
        if (errmsg[0]) {
            wattron(w, COLOR_PAIR(CP_ERROR) | A_BOLD);
            mvwprintw(w, bh - 3, 2, "⚠ %.*s", bw - 6, errmsg);
            wattroff(w, COLOR_PAIR(CP_ERROR) | A_BOLD);
        }

        /* continue button */
        bool btn_active = (sel == N_FIELDS);
        if (btn_active) {
            wattron(w, COLOR_PAIR(CP_SELECTED) | A_BOLD);
            mvwprintw(w, bh - 2, (bw - 14) / 2, "[ Continue → ]");
            wattroff(w, COLOR_PAIR(CP_SELECTED) | A_BOLD);
        } else {
            wattron(w, COLOR_PAIR(CP_BORDER));
            mvwprintw(w, bh - 2, (bw - 14) / 2, "[ Continue → ]");
            wattroff(w, COLOR_PAIR(CP_BORDER));
        }

        wrefresh(w);

        /* ── handle input on a text field ──────────────────────── */
        if (sel < F_DISROOT) {
            int fx = 2 + 19 + 1; /* after label */
            int fw = bw - 4 - 19 - 2;
            int fy = 3 + sel * 2;
            int ret = input_text(w, fy, fx, fw, bufs[sel], MAX_INPUT - 1, secret[sel]);
            delwin(w);
            if (ret == 1)  { sel = (sel + 1) % (N_FIELDS + 1); continue; }
            if (ret == -1) { if (sel > 0) sel--; else return -1; continue; }
            sel = (sel + 1) % (N_FIELDS + 1);
            continue;
        }

        /* ── non-text field navigation ──────────────────────────── */
        int ch = wgetch(w);
        delwin(w);

        if (ch == KEY_UP)   { sel = (sel + N_FIELDS) % (N_FIELDS + 1); errmsg[0] = '\0'; continue; }
        if (ch == KEY_DOWN || ch == '\t') { sel = (sel + 1) % (N_FIELDS + 1); errmsg[0] = '\0'; continue; }
        if (ch == 27) return -1;

        if (ch == ' ' && sel == F_DISROOT) { disable_root = !disable_root; continue; }

        if ((ch == '\n' || ch == '\r') && sel == N_FIELDS) {
            /* validate */
            errmsg[0] = '\0';
            if (!validate_hostname(hostname))
                snprintf(errmsg, sizeof(errmsg), "Hostname must be lowercase a-z, 0-9, hyphens (no leading/trailing -)");
            else if (!validate_username(username))
                snprintf(errmsg, sizeof(errmsg), "Username: lowercase letters, digits, _ or - only, must start with letter");
            else if (strlen(pw1) < 8)
                snprintf(errmsg, sizeof(errmsg), "Password must be at least 8 characters");
            else if (strcmp(pw1, pw2))
                snprintf(errmsg, sizeof(errmsg), "Passwords do not match");
            else if (!disable_root && strlen(rpw1) < 8)
                snprintf(errmsg, sizeof(errmsg), "Root password must be at least 8 characters");
            else if (!disable_root && strcmp(rpw1, rpw2))
                snprintf(errmsg, sizeof(errmsg), "Root passwords do not match");

            if (!errmsg[0]) {
                /* save */
                strncpy(g_state.hostname,       hostname, sizeof(g_state.hostname)       - 1);
                strncpy(g_state.username,        username, sizeof(g_state.username)       - 1);
                strncpy(g_state.password,        pw1,      sizeof(g_state.password)       - 1);
                strncpy(g_state.password2,       pw2,      sizeof(g_state.password2)      - 1);
                strncpy(g_state.root_password,   rpw1,     sizeof(g_state.root_password)  - 1);
                strncpy(g_state.root_password2,  rpw2,     sizeof(g_state.root_password2) - 1);
                g_state.disable_root = disable_root;
                return 1;
            }
        }
    }
}
