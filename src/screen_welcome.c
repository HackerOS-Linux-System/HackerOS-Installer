#include "installer.h"

int screen_welcome(void)
{
    int rows, cols;
    getmaxyx(stdscr, rows, cols);

    ui_draw_base("Welcome", SCREEN_WELCOME, SCREEN_FINISH + 1);

    /* content box */
    int bh = 14, bw = 66;
    int by = (rows - bh) / 2 + 2;
    int bx = (cols - bw) / 2;
    if (by < 13) by = 13;

    WINDOW *box_w = newwin(bh, bw, by, bx);
    wbkgd(box_w, COLOR_PAIR(CP_NORMAL));
    ui_draw_border(box_w);

    wattron(box_w, COLOR_PAIR(CP_STATUS) | A_BOLD);
    mvwaddstr(box_w, 1, (bw - 36) / 2, "Welcome to HackerOS Server Installer");
    wattroff(box_w, COLOR_PAIR(CP_STATUS) | A_BOLD);

    wattron(box_w, COLOR_PAIR(CP_NORMAL));
    mvwaddstr(box_w, 3, 3,
              "This installer will guide you through the setup of");
    mvwaddstr(box_w, 4, 3,
              "HackerOS Server Edition on your machine.");

    wattron(box_w, COLOR_PAIR(CP_DIM));
    mvwaddstr(box_w, 6, 3,  "Base system  :  Debian Trixie (stable)");
    mvwaddstr(box_w, 7, 3,  "Edition      :  Server Edition");
    mvwaddstr(box_w, 8, 3,  "Installer    :  v" INSTALLER_VERSION);
    wattroff(box_w, COLOR_PAIR(CP_DIM));

    wattron(box_w, COLOR_PAIR(CP_NORMAL));
    mvwaddstr(box_w, 10, 3,
              "Press  ENTER  to begin  or  ESC  to quit.");
    wattroff(box_w, COLOR_PAIR(CP_NORMAL));

    wattron(box_w, COLOR_PAIR(CP_BORDER));
    mvwaddch(box_w, bh - 2, (bw - 16) / 2, '[');
    wattron(box_w, COLOR_PAIR(CP_SELECTED) | A_BOLD);
    waddstr(box_w, "  START  ");
    wattroff(box_w, COLOR_PAIR(CP_SELECTED) | A_BOLD);
    wattron(box_w, COLOR_PAIR(CP_BORDER));
    waddch(box_w, ']');
    wattroff(box_w, COLOR_PAIR(CP_BORDER));

    wrefresh(box_w);

    int ch;
    while (1) {
        ch = getch();
        if (ch == '\n' || ch == '\r' || ch == ' ') { delwin(box_w); return 1; }
        if (ch == 27) {
            delwin(box_w);
            if (ui_confirm_box("Quit the HackerOS installer?")) {
                ui_cleanup();
                exit(0);
            }
            return 0;
        }
    }
}
