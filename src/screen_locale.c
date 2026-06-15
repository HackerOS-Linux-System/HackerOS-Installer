#include "installer.h"

static const char *LOCALES[] = {
    "en_US.UTF-8", "en_GB.UTF-8", "de_DE.UTF-8", "fr_FR.UTF-8",
    "pl_PL.UTF-8", "es_ES.UTF-8", "it_IT.UTF-8", "pt_BR.UTF-8",
    "ru_RU.UTF-8", "zh_CN.UTF-8", "ja_JP.UTF-8", "ko_KR.UTF-8",
    NULL
};

static const char *TIMEZONES[] = {
    "UTC",
    "Europe/Warsaw", "Europe/London", "Europe/Berlin", "Europe/Paris",
    "Europe/Moscow", "Europe/Amsterdam", "Europe/Zurich",
    "America/New_York", "America/Chicago", "America/Denver",
    "America/Los_Angeles", "America/Sao_Paulo",
    "Asia/Tokyo", "Asia/Shanghai", "Asia/Seoul", "Asia/Kolkata",
    "Asia/Singapore", "Australia/Sydney",
    NULL
};

static const char *KEYMAPS[] = {
    "us", "gb", "de", "fr", "pl", "es", "it", "pt",
    "ru", "jp", "br", "dvorak", "colemak",
    NULL
};

static int count_list(const char **list)
{
    int n = 0;
    while (list[n]) n++;
    return n;
}

/* generic list picker; returns index or -1 on escape */
static int pick_from_list(const char *header, const char **items,
                          int n_items, int current,
                          int win_y, int win_x, int win_h, int win_w)
{
    int sel = current;
    int scroll = sel > win_h - 4 ? sel - (win_h - 4) : 0;

    WINDOW *w = newwin(win_h, win_w, win_y, win_x);
    wbkgd(w, COLOR_PAIR(CP_NORMAL));

    while (1) {
        werase(w);
        ui_draw_border(w);
        wattron(w, COLOR_PAIR(CP_STATUS) | A_BOLD);
        mvwprintw(w, 1, 2, "%s", header);
        wattroff(w, COLOR_PAIR(CP_STATUS) | A_BOLD);

        int list_h = win_h - 4;
        for (int i = 0; i < list_h && (i + scroll) < n_items; i++) {
            int idx = i + scroll;
            if (idx == sel) {
                wattron(w, COLOR_PAIR(CP_SELECTED) | A_BOLD);
                mvwprintw(w, 3 + i, 2, " %-*s ", win_w - 6, items[idx]);
                wattroff(w, COLOR_PAIR(CP_SELECTED) | A_BOLD);
            } else {
                wattron(w, COLOR_PAIR(CP_NORMAL));
                mvwprintw(w, 3 + i, 2, " %-*s ", win_w - 6, items[idx]);
                wattroff(w, COLOR_PAIR(CP_NORMAL));
            }
        }

        /* scrollbar hint */
        if (n_items > list_h) {
            wattron(w, COLOR_PAIR(CP_DIM));
            mvwprintw(w, win_h - 2, 2, "[↑/↓] scroll  [Enter] select  [Esc] cancel");
            wattroff(w, COLOR_PAIR(CP_DIM));
        }

        wrefresh(w);
        int ch = wgetch(w);

        if (ch == KEY_UP   && sel > 0)         { sel--; if (sel < scroll) scroll = sel; }
        if (ch == KEY_DOWN && sel < n_items-1) {
            sel++;
            if (sel >= scroll + list_h) scroll = sel - list_h + 1;
        }
        if (ch == KEY_PPAGE) { sel = sel > 5 ? sel - 5 : 0; if (sel < scroll) scroll = sel; }
        if (ch == KEY_NPAGE) {
            sel = sel + 5 < n_items ? sel + 5 : n_items - 1;
            if (sel >= scroll + list_h) scroll = sel - list_h + 1;
        }
        if (ch == '\n' || ch == '\r') { delwin(w); return sel; }
        if (ch == 27)                 { delwin(w); return -1;  }
    }
}

/* ── main locale screen ───────────────────────────────────────────────── */
int screen_locale(void)
{
    int rows, cols;
    getmaxyx(stdscr, rows, cols);

    int n_locale = count_list(LOCALES);
    int n_tz     = count_list(TIMEZONES);
    int n_km     = count_list(KEYMAPS);

    /* find current indices */
    int loc_idx = 0, tz_idx = 0, km_idx = 0;
    for (int i = 0; i < n_locale; i++)
        if (!strcmp(LOCALES[i],   g_state.locale))   { loc_idx = i; break; }
        for (int i = 0; i < n_tz;     i++)
            if (!strcmp(TIMEZONES[i], g_state.timezone)) { tz_idx  = i; break; }
            for (int i = 0; i < n_km;     i++)
                if (!strcmp(KEYMAPS[i],   g_state.keymap))   { km_idx  = i; break; }

                int sel_field = 0; /* 0=locale, 1=timezone, 2=keymap, 3=continue */

                while (1) {
                    ui_draw_base("Locale & Keyboard", SCREEN_LOCALE, SCREEN_FINISH + 1);

                    int bh = 14, bw = 62;
                    int by = rows / 2 - bh / 2 + 3;
                    int bx = (cols - bw) / 2;
                    if (by < 13) by = 13;

                    WINDOW *w = newwin(bh, bw, by, bx);
                    wbkgd(w, COLOR_PAIR(CP_NORMAL));
                    ui_draw_border(w);

                    wattron(w, COLOR_PAIR(CP_DIM));
                    mvwaddstr(w, 1, 2, "Use [Enter] to open a picker for each field.");
                    wattroff(w, COLOR_PAIR(CP_DIM));

                    const char *fields[] = { "System Locale :", "Timezone :", "Keyboard Layout :" };
                    const char *vals[]   = { LOCALES[loc_idx], TIMEZONES[tz_idx], KEYMAPS[km_idx] };

                    for (int i = 0; i < 3; i++) {
                        bool active = (sel_field == i);
                        if (active) wattron(w, COLOR_PAIR(CP_STATUS) | A_BOLD);
                        else        wattron(w, COLOR_PAIR(CP_NORMAL));
                        mvwprintw(w, 3 + i * 2, 2, "%-20s", fields[i]);
                        if (active) {
                            wattroff(w, COLOR_PAIR(CP_STATUS) | A_BOLD);
                            wattron(w, COLOR_PAIR(CP_SELECTED) | A_BOLD);
                        } else {
                            wattroff(w, COLOR_PAIR(CP_NORMAL));
                            wattron(w, COLOR_PAIR(CP_UNSELECTED));
                        }
                        mvwprintw(w, 3 + i * 2, 22, " %-*s ", bw - 26, vals[i]);
                        if (active) wattroff(w, COLOR_PAIR(CP_SELECTED) | A_BOLD);
                        else        wattroff(w, COLOR_PAIR(CP_UNSELECTED));
                    }

                    /* Continue button */
                    int btn_y = bh - 2;
                    if (sel_field == 3) {
                        wattron(w, COLOR_PAIR(CP_SELECTED) | A_BOLD);
                        mvwprintw(w, btn_y, (bw - 14) / 2, "[ Continue → ]");
                        wattroff(w, COLOR_PAIR(CP_SELECTED) | A_BOLD);
                    } else {
                        wattron(w, COLOR_PAIR(CP_BORDER));
                        mvwprintw(w, btn_y, (bw - 14) / 2, "[ Continue → ]");
                        wattroff(w, COLOR_PAIR(CP_BORDER));
                    }

                    wrefresh(w);
                    int ch = wgetch(w);
                    delwin(w);

                    if (ch == KEY_UP)   { sel_field = (sel_field + 3) % 4; continue; }
                    if (ch == KEY_DOWN || ch == '\t') { sel_field = (sel_field + 1) % 4; continue; }
                    if (ch == 27) return -1;

                    if (ch == '\n' || ch == '\r' || ch == ' ') {
                        if (sel_field == 3) {
                            strncpy(g_state.locale,   LOCALES[loc_idx],   sizeof(g_state.locale)   - 1);
                            strncpy(g_state.timezone, TIMEZONES[tz_idx],  sizeof(g_state.timezone) - 1);
                            strncpy(g_state.keymap,   KEYMAPS[km_idx],    sizeof(g_state.keymap)   - 1);
                            return 1;
                        }

                        int pw = 40, ph = 18;
                        int px = (cols - pw) / 2;
                        int py = (rows - ph) / 2;

                        if (sel_field == 0) {
                            int r = pick_from_list("Select Locale", LOCALES, n_locale, loc_idx, py, px, ph, pw);
                            if (r >= 0) loc_idx = r;
                        } else if (sel_field == 1) {
                            int r = pick_from_list("Select Timezone", TIMEZONES, n_tz, tz_idx, py, px, ph, pw);
                            if (r >= 0) tz_idx = r;
                        } else if (sel_field == 2) {
                            int r = pick_from_list("Select Keyboard Layout", KEYMAPS, n_km, km_idx, py, px, ph, pw);
                            if (r >= 0) km_idx = r;
                        }
                    }
                }
}
