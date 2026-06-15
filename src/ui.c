#include "installer.h"

/* ──────────────────────────────────────────────────────────────────────
 * ASCII logo split into lines – 52 chars wide
 * ────────────────────────────────────────────────────────────────────── */
static const char *LOGO[] = {
    "  ██╗  ██╗ █████╗  ██████╗██╗  ██╗███████╗██████╗ ",
    "  ██║  ██║██╔══██╗██╔════╝██║ ██╔╝██╔════╝██╔══██╗",
    "  ███████║███████║██║     █████╔╝ █████╗  ██████╔╝",
    "  ██╔══██║██╔══██║██║     ██╔═██╗ ██╔══╝  ██╔══██╗",
    "  ██║  ██║██║  ██║╚██████╗██║  ██╗███████╗██║  ██║",
    "  ╚═╝  ╚═╝╚═╝  ╚═╝ ╚═════╝╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝",
    "        ┌─ Server Edition ─ Based on Debian Trixie ─┐",
};
static const int LOGO_LINES = 7;

/* ──────────────────────────────────────────────────────────────────────
 * Step names shown in header breadcrumb
 * ────────────────────────────────────────────────────────────────────── */
static const char *STEP_NAMES[SCREEN_COUNT] = {
    "Welcome",
    "Locale",
    "Disk",
    "User",
    "Network",
    "Server Role",
    "Packages",
    "Extra Config",
    "Summary",
    "Installing",
    "Finish",
};

/* ──────────────────────────────────────────────────────────────────────
 * ui_init  –  start ncurses, define color pairs
 * ────────────────────────────────────────────────────────────────────── */
void ui_init(void)
{
    initscr();
    cbreak();
    noecho();
    keypad(stdscr, TRUE);
    curs_set(0);
    set_escdelay(50);

    if (!has_colors()) {
        endwin();
        fprintf(stderr, "HackerOS Installer requires a color terminal.\n");
        exit(1);
    }
    start_color();
    use_default_colors();

    /* Try 256-color orange; fall back to COLOR_YELLOW on 8-color terms */
    if (can_change_color() && COLORS >= 256) {
        init_pair(CP_NORMAL,    COLOR_WHITE,     COLOR_BLACK);
        init_pair(CP_TITLE,     COLOR_BLACK,     COLOR_ORANGE);
        init_pair(CP_HIGHLIGHT, COLOR_BLACK,     COLOR_ORANGE);
        init_pair(CP_BORDER,    COLOR_ORANGE,    COLOR_BLACK);
        init_pair(CP_STATUS,    COLOR_ORANGE,    COLOR_BLACK);
        init_pair(CP_ERROR,     COLOR_RED,       COLOR_BLACK);
        init_pair(CP_SUCCESS,   COLOR_GREEN,     COLOR_BLACK);
        init_pair(CP_DIM,       COLOR_DARKGRAY,  COLOR_BLACK);
        init_pair(CP_INPUT,     COLOR_ORANGE,    COLOR_DARKGRAY);
        init_pair(CP_SELECTED,  COLOR_BLACK,     COLOR_ORANGE);
        init_pair(CP_UNSELECTED,COLOR_WHITE,     COLOR_BLACK);
        init_pair(CP_HEADER,    COLOR_ORANGE,    COLOR_BLACK);
    } else {
        init_pair(CP_NORMAL,    COLOR_WHITE,   COLOR_BLACK);
        init_pair(CP_TITLE,     COLOR_BLACK,   COLOR_YELLOW);
        init_pair(CP_HIGHLIGHT, COLOR_BLACK,   COLOR_YELLOW);
        init_pair(CP_BORDER,    COLOR_YELLOW,  COLOR_BLACK);
        init_pair(CP_STATUS,    COLOR_YELLOW,  COLOR_BLACK);
        init_pair(CP_ERROR,     COLOR_RED,     COLOR_BLACK);
        init_pair(CP_SUCCESS,   COLOR_GREEN,   COLOR_BLACK);
        init_pair(CP_DIM,       COLOR_BLACK,   COLOR_BLACK);
        init_pair(CP_INPUT,     COLOR_YELLOW,  COLOR_BLACK);
        init_pair(CP_SELECTED,  COLOR_BLACK,   COLOR_YELLOW);
        init_pair(CP_UNSELECTED,COLOR_WHITE,   COLOR_BLACK);
        init_pair(CP_HEADER,    COLOR_YELLOW,  COLOR_BLACK);
    }

    bkgd(COLOR_PAIR(CP_NORMAL));
    refresh();
}

void ui_cleanup(void)
{
    endwin();
}

/* ──────────────────────────────────────────────────────────────────────
 * ui_draw_base  –  full-screen chrome: logo area + header bar + step bar
 * ────────────────────────────────────────────────────────────────────── */
void ui_draw_base(const char *title, int step, int total)
{
    int rows, cols;
    getmaxyx(stdscr, rows, cols);

    /* Black background */
    wbkgd(stdscr, COLOR_PAIR(CP_NORMAL));
    werase(stdscr);

    /* ── Top bar ─────────────────────────────────────────────────── */
    wattron(stdscr, COLOR_PAIR(CP_TITLE) | A_BOLD);
    for (int x = 0; x < cols; x++) mvwaddch(stdscr, 0, x, ' ');
    char top[256];
    snprintf(top, sizeof(top), "  %s %s  │  Installer v%s  ",
             OS_NAME, OS_EDITION, INSTALLER_VERSION);
    mvwaddstr(stdscr, 0, 1, top);
    wattroff(stdscr, COLOR_PAIR(CP_TITLE) | A_BOLD);

    /* ── Logo (centered) ─────────────────────────────────────────── */
    int logo_start_col = (cols - LOGO_WIDTH) / 2;
    if (logo_start_col < 0) logo_start_col = 0;

    wattron(stdscr, COLOR_PAIR(CP_HEADER) | A_BOLD);
    for (int i = 0; i < LOGO_LINES; i++) {
        mvwaddstr(stdscr, 2 + i, logo_start_col, LOGO[i]);
    }
    wattroff(stdscr, COLOR_PAIR(CP_HEADER) | A_BOLD);

    /* ── Separator ───────────────────────────────────────────────── */
    wattron(stdscr, COLOR_PAIR(CP_BORDER));
    for (int x = 0; x < cols; x++)
        mvwaddch(stdscr, 2 + LOGO_LINES, x, ACS_HLINE);
    wattroff(stdscr, COLOR_PAIR(CP_BORDER));

    /* ── Breadcrumb step bar ─────────────────────────────────────── */
    int bar_y = 2 + LOGO_LINES + 1;
    wmove(stdscr, bar_y, 0);
    for (int x = 0; x < cols; x++) mvwaddch(stdscr, bar_y, x, ' ');

    /* render each step name */
    int sx = 2;
    for (int i = 0; i < total && i < SCREEN_COUNT; i++) {
        if (sx >= cols - 4) break;
        bool active = (i == step);

        if (active) {
            wattron(stdscr, COLOR_PAIR(CP_SELECTED) | A_BOLD);
            mvwprintw(stdscr, bar_y, sx, " %s ", STEP_NAMES[i]);
            wattroff(stdscr, COLOR_PAIR(CP_SELECTED) | A_BOLD);
        } else if (i < step) {
            wattron(stdscr, COLOR_PAIR(CP_DIM));
            mvwprintw(stdscr, bar_y, sx, " %s ", STEP_NAMES[i]);
            wattroff(stdscr, COLOR_PAIR(CP_DIM));
        } else {
            wattron(stdscr, COLOR_PAIR(CP_UNSELECTED));
            mvwprintw(stdscr, bar_y, sx, " %s ", STEP_NAMES[i]);
            wattroff(stdscr, COLOR_PAIR(CP_UNSELECTED));
        }
        sx += strlen(STEP_NAMES[i]) + 3;

        if (i < total - 1 && sx < cols - 4) {
            wattron(stdscr, COLOR_PAIR(CP_BORDER));
            mvwaddch(stdscr, bar_y, sx, ACS_VLINE);
            wattroff(stdscr, COLOR_PAIR(CP_BORDER));
            sx += 2;
        }
    }

    /* ── Section title ───────────────────────────────────────────── */
    int title_y = bar_y + 2;
    wattron(stdscr, COLOR_PAIR(CP_STATUS) | A_BOLD);
    mvwprintw(stdscr, title_y, 3, "▶  %s", title);
    wattroff(stdscr, COLOR_PAIR(CP_STATUS) | A_BOLD);

    /* ── Bottom nav bar ──────────────────────────────────────────── */
    wattron(stdscr, COLOR_PAIR(CP_DIM));
    for (int x = 0; x < cols; x++) mvwaddch(stdscr, rows - 1, x, ' ');
    mvwaddstr(stdscr, rows - 1, 1,
              " [SPACE] Select/Toggle   [ENTER] Confirm   [TAB] Next field   [ESC] Back ");
    wattroff(stdscr, COLOR_PAIR(CP_DIM));

    wrefresh(stdscr);
}

/* ──────────────────────────────────────────────────────────────────────
 * ui_draw_border  –  orange box border around a sub-window
 * ────────────────────────────────────────────────────────────────────── */
void ui_draw_border(WINDOW *w)
{
    wattron(w, COLOR_PAIR(CP_BORDER));
    box(w, 0, 0);
    wattroff(w, COLOR_PAIR(CP_BORDER));
}

/* ──────────────────────────────────────────────────────────────────────
 * ui_status  –  one-line status on row rows-2
 * ────────────────────────────────────────────────────────────────────── */
void ui_status(const char *msg)
{
    int rows, cols;
    getmaxyx(stdscr, rows, cols);
    wattron(stdscr, COLOR_PAIR(CP_STATUS));
    mvwprintw(stdscr, rows - 2, 1, "%-*s", cols - 2, msg);
    wattroff(stdscr, COLOR_PAIR(CP_STATUS));
    wrefresh(stdscr);
}

/* ──────────────────────────────────────────────────────────────────────
 * ui_error_box  –  centered modal with error message
 * ────────────────────────────────────────────────────────────────────── */
void ui_error_box(const char *msg)
{
    int rows, cols;
    getmaxyx(stdscr, rows, cols);

    int bw = (int)strlen(msg) + 8;
    if (bw > cols - 4) bw = cols - 4;
    int bh = 5;
    int by = (rows - bh) / 2;
    int bx = (cols - bw) / 2;

    WINDOW *w = newwin(bh, bw, by, bx);
    wbkgd(w, COLOR_PAIR(CP_NORMAL));
    wattron(w, COLOR_PAIR(CP_ERROR) | A_BOLD);
    box(w, 0, 0);
    mvwaddstr(w, 1, 2, "  ERROR  ");
    wattroff(w, COLOR_PAIR(CP_ERROR) | A_BOLD);
    wattron(w, COLOR_PAIR(CP_NORMAL));
    mvwprintw(w, 2, 2, "%.*s", bw - 4, msg);
    mvwaddstr(w, 3, (bw - 20) / 2, "[ Press any key ]");
    wattroff(w, COLOR_PAIR(CP_NORMAL));
    wrefresh(w);
    wgetch(w);
    delwin(w);
    touchwin(stdscr);
    wrefresh(stdscr);
}

/* ──────────────────────────────────────────────────────────────────────
 * ui_confirm_box  –  Yes/No modal; returns 1 = yes, 0 = no
 * ────────────────────────────────────────────────────────────────────── */
int ui_confirm_box(const char *question)
{
    int rows, cols;
    getmaxyx(stdscr, rows, cols);

    int bw = (int)strlen(question) + 10;
    if (bw < 36) bw = 36;
    if (bw > cols - 4) bw = cols - 4;
    int bh = 7;
    int by = (rows - bh) / 2;
    int bx = (cols - bw) / 2;

    WINDOW *w = newwin(bh, bw, by, bx);
    wbkgd(w, COLOR_PAIR(CP_NORMAL));

    int sel = 0; /* 0 = No, 1 = Yes */
    int ch;

    while (1) {
        werase(w);
        wattron(w, COLOR_PAIR(CP_BORDER));
        box(w, 0, 0);
        wattroff(w, COLOR_PAIR(CP_BORDER));

        wattron(w, COLOR_PAIR(CP_STATUS) | A_BOLD);
        mvwaddstr(w, 1, 2, "Confirm");
        wattroff(w, COLOR_PAIR(CP_STATUS) | A_BOLD);

        mvwprintw(w, 3, 2, "%.*s", bw - 4, question);

        int btn_y = bh - 2;
        int yes_x = bw / 2 - 10;
        int no_x  = bw / 2 + 2;

        if (sel == 1) {
            wattron(w, COLOR_PAIR(CP_SELECTED) | A_BOLD);
            mvwaddstr(w, btn_y, yes_x, "[ Yes ]");
            wattroff(w, COLOR_PAIR(CP_SELECTED) | A_BOLD);
            wattron(w, COLOR_PAIR(CP_UNSELECTED));
            mvwaddstr(w, btn_y, no_x, "[ No  ]");
            wattroff(w, COLOR_PAIR(CP_UNSELECTED));
        } else {
            wattron(w, COLOR_PAIR(CP_UNSELECTED));
            mvwaddstr(w, btn_y, yes_x, "[ Yes ]");
            wattroff(w, COLOR_PAIR(CP_UNSELECTED));
            wattron(w, COLOR_PAIR(CP_SELECTED) | A_BOLD);
            mvwaddstr(w, btn_y, no_x, "[ No  ]");
            wattroff(w, COLOR_PAIR(CP_SELECTED) | A_BOLD);
        }

        wrefresh(w);
        ch = wgetch(w);

        if (ch == KEY_LEFT || ch == KEY_RIGHT || ch == '\t')
            sel = !sel;
        else if (ch == '\n' || ch == '\r') break;
        else if (ch == 27) { sel = 0; break; }
        else if (ch == 'y' || ch == 'Y') { sel = 1; break; }
        else if (ch == 'n' || ch == 'N') { sel = 0; break; }
    }

    delwin(w);
    touchwin(stdscr);
    wrefresh(stdscr);
    return sel;
}

/* ──────────────────────────────────────────────────────────────────────
 * ui_progress  –  orange progress bar
 * ────────────────────────────────────────────────────────────────────── */
void ui_progress(WINDOW *w, int y, int x, int width, int percent, const char *label)
{
    if (percent < 0) percent = 0;
    if (percent > 100) percent = 100;

    int filled = (width * percent) / 100;

    wattron(w, COLOR_PAIR(CP_BORDER));
    mvwaddch(w, y, x, '[');
    mvwaddch(w, y, x + width + 1, ']');
    wattroff(w, COLOR_PAIR(CP_BORDER));

    wattron(w, COLOR_PAIR(CP_SELECTED) | A_BOLD);
    for (int i = 0; i < filled; i++)
        mvwaddch(w, y, x + 1 + i, ACS_BLOCK);
    wattroff(w, COLOR_PAIR(CP_SELECTED) | A_BOLD);

    wattron(w, COLOR_PAIR(CP_DIM));
    for (int i = filled; i < width; i++)
        mvwaddch(w, y, x + 1 + i, ACS_CKBOARD);
    wattroff(w, COLOR_PAIR(CP_DIM));

    wattron(w, COLOR_PAIR(CP_STATUS) | A_BOLD);
    char pct_str[16];
    snprintf(pct_str, sizeof(pct_str), " %3d%%  %s", percent, label ? label : "");
    mvwaddstr(w, y + 1, x, pct_str);
    wattroff(w, COLOR_PAIR(CP_STATUS) | A_BOLD);
}

/* ──────────────────────────────────────────────────────────────────────
 * draw_field  –  labelled input field
 * ────────────────────────────────────────────────────────────────────── */
void draw_field(WINDOW *w, int y, int x, int width,
                const char *label, const char *val,
                bool active, bool secret)
{
    wattron(w, COLOR_PAIR(CP_NORMAL));
    mvwprintw(w, y, x, "%-18s", label);
    wattroff(w, COLOR_PAIR(CP_NORMAL));

    int fx = x + 19;
    int fw = width - 19;

    if (active)
        wattron(w, COLOR_PAIR(CP_INPUT) | A_BOLD);
    else
        wattron(w, COLOR_PAIR(CP_DIM));

    mvwaddch(w, y, fx - 1, '[');
    if (secret) {
        int len = (int)strlen(val);
        for (int i = 0; i < fw; i++)
            mvwaddch(w, y, fx + i, i < len ? '*' : ' ');
    } else {
        mvwprintw(w, y, fx, "%-*.*s", fw, fw, val);
    }
    mvwaddch(w, y, fx + fw, ']');

    if (active)
        wattroff(w, COLOR_PAIR(CP_INPUT) | A_BOLD);
    else
        wattroff(w, COLOR_PAIR(CP_DIM));
}

/* ──────────────────────────────────────────────────────────────────────
 * input_text  –  inline text input inside a window
 * Returns:  0 = confirmed (Enter),  1 = Tab/next,  -1 = Escape/back
 * ────────────────────────────────────────────────────────────────────── */
int input_text(WINDOW *w, int y, int x, int width,
               char *buf, int maxlen, bool secret)
{
    int len = (int)strlen(buf);
    int cursor = len;
    int ch;

    curs_set(1);
    wattron(w, COLOR_PAIR(CP_INPUT) | A_BOLD);

    while (1) {
        /* redraw field */
        wmove(w, y, x);
        for (int i = 0; i < width; i++) {
            char c = ' ';
            if (i < len) c = secret ? '*' : buf[i];
            waddch(w, c);
        }
        /* position cursor */
        wmove(w, y, x + cursor);
        wrefresh(w);

        ch = wgetch(w);

        if (ch == '\n' || ch == '\r') break;
        if (ch == '\t') { curs_set(0); wattroff(w, COLOR_PAIR(CP_INPUT) | A_BOLD); return 1; }
        if (ch == 27)   { curs_set(0); wattroff(w, COLOR_PAIR(CP_INPUT) | A_BOLD); return -1; }

        if (ch == KEY_BACKSPACE || ch == 127 || ch == 8) {
            if (cursor > 0) {
                memmove(buf + cursor - 1, buf + cursor, len - cursor + 1);
                cursor--;
                len--;
            }
        } else if (ch == KEY_DC) {
            if (cursor < len) {
                memmove(buf + cursor, buf + cursor + 1, len - cursor);
                len--;
            }
        } else if (ch == KEY_LEFT  && cursor > 0)   cursor--;
        else if (ch == KEY_RIGHT && cursor < len)   cursor++;
        else if (ch == KEY_HOME) cursor = 0;
        else if (ch == KEY_END)  cursor = len;
        else if (isprint(ch) && len < maxlen - 1) {
            memmove(buf + cursor + 1, buf + cursor, len - cursor + 1);
            buf[cursor] = (char)ch;
            cursor++;
            len++;
        }
    }

    curs_set(0);
    wattroff(w, COLOR_PAIR(CP_INPUT) | A_BOLD);
    return 0;
}
