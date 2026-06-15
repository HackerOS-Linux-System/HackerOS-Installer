#include "installer.h"
#include <dirent.h>

#define MAX_IFACES 12
#define N_NET_FIELDS 4  /* ip, netmask, gateway, dns */

static int scan_ifaces(char ifaces[MAX_IFACES][32])
{
    int n = 0;
    DIR *d = opendir("/sys/class/net");
    if (!d) {
        strncpy(ifaces[0], "eth0", 31);
        return 1;
    }
    struct dirent *ent;
    while ((ent = readdir(d)) && n < MAX_IFACES) {
        if (ent->d_name[0] == '.') continue;
        if (!strcmp(ent->d_name, "lo")) continue;
        strncpy(ifaces[n], ent->d_name, 31);
        n++;
    }
    closedir(d);
    if (n == 0) { strncpy(ifaces[0], "eth0", 31); n = 1; }
    return n;
}

int screen_network(void)
{
    char ifaces[MAX_IFACES][32];
    int n_ifaces = scan_ifaces(ifaces);
    int sel_iface = 0;

    /* match current */
    for (int i = 0; i < n_ifaces; i++)
        if (!strcmp(ifaces[i], g_state.iface)) { sel_iface = i; break; }

        bool use_dhcp   = g_state.use_dhcp;
    bool skip_net   = g_state.skip_network;

    char ip[32], netmask[32], gateway[32], dns[64];
    strncpy(ip,      g_state.ip,      sizeof(ip)      - 1);
    strncpy(netmask, g_state.netmask, sizeof(netmask) - 1);
    strncpy(gateway, g_state.gateway, sizeof(gateway) - 1);
    strncpy(dns,     g_state.dns,     sizeof(dns)     - 1);

    /* defaults */
    if (!ip[0])      strncpy(ip,      "192.168.1.10",  sizeof(ip)      - 1);
    if (!netmask[0]) strncpy(netmask, "255.255.255.0", sizeof(netmask) - 1);
    if (!gateway[0]) strncpy(gateway, "192.168.1.1",   sizeof(gateway) - 1);
    if (!dns[0])     strncpy(dns,     "1.1.1.1 8.8.8.8", sizeof(dns)  - 1);

    /* field 0=iface 1=dhcp 2..5=manual fields 6=skip 7=continue */
    int sel = 0;

    char *manual_bufs[N_NET_FIELDS] = { ip, netmask, gateway, dns };
    const char *manual_labels[N_NET_FIELDS] = {
        "IP Address:", "Netmask:", "Gateway:", "DNS Servers:",
    };

    while (1) {
        int rows, cols;
        getmaxyx(stdscr, rows, cols);
        ui_draw_base("Network Configuration  [optional]", SCREEN_NETWORK, SCREEN_FINISH + 1);

        int bh = 22, bw = 64;
        int by = rows / 2 - bh / 2 + 3;
        int bx = (cols - bw) / 2;
        if (by < 13) by = 13;

        WINDOW *w = newwin(bh, bw, by, bx);
        wbkgd(w, COLOR_PAIR(CP_NORMAL));
        ui_draw_border(w);

        /* skip toggle at top */
        {
            bool act = (sel == 6);
            if (act) wattron(w, COLOR_PAIR(CP_SELECTED) | A_BOLD);
            else if (skip_net) wattron(w, COLOR_PAIR(CP_BORDER));
            else wattron(w, COLOR_PAIR(CP_NORMAL));
            mvwprintw(w, 1, 2, " [%s] Skip network config (configure later)", skip_net ? "✓" : " ");
            if (act) wattroff(w, COLOR_PAIR(CP_SELECTED) | A_BOLD);
            else if (skip_net) wattroff(w, COLOR_PAIR(CP_BORDER));
            else wattroff(w, COLOR_PAIR(CP_NORMAL));
        }

        wattron(w, COLOR_PAIR(CP_BORDER));
        mvwhline(w, 2, 1, ACS_HLINE, bw - 2);
        wattroff(w, COLOR_PAIR(CP_BORDER));

        bool dim = skip_net;

        /* interface selector */
        wattron(w, (sel == 0 && !dim) ? COLOR_PAIR(CP_STATUS) | A_BOLD : (dim ? COLOR_PAIR(CP_DIM) : COLOR_PAIR(CP_NORMAL)));
        mvwaddstr(w, 3, 2, "Network Interface:");
        wattroff(w, (sel == 0 && !dim) ? COLOR_PAIR(CP_STATUS) | A_BOLD : (dim ? COLOR_PAIR(CP_DIM) : COLOR_PAIR(CP_NORMAL)));

        for (int i = 0; i < n_ifaces && i < 4; i++) {
            bool act = (i == sel_iface) && (sel == 0) && !dim;
            bool mark = (i == sel_iface);
            if (act)        wattron(w, COLOR_PAIR(CP_SELECTED) | A_BOLD);
            else if (mark && !dim) wattron(w, COLOR_PAIR(CP_BORDER));
            else            wattron(w, COLOR_PAIR(CP_DIM));
            mvwprintw(w, 4 + i, 4, " %s %-12s", mark ? "◉" : "○", ifaces[i]);
            if (act)        wattroff(w, COLOR_PAIR(CP_SELECTED) | A_BOLD);
            else if (mark && !dim) wattroff(w, COLOR_PAIR(CP_BORDER));
            else            wattroff(w, COLOR_PAIR(CP_DIM));
        }

        /* DHCP toggle */
        wattron(w, COLOR_PAIR(CP_BORDER));
        mvwhline(w, 8, 1, ACS_HLINE, bw - 2);
        wattroff(w, COLOR_PAIR(CP_BORDER));

        {
            bool act = (sel == 1) && !dim;
            if (act)          wattron(w, COLOR_PAIR(CP_SELECTED) | A_BOLD);
            else if (!dim)    wattron(w, COLOR_PAIR(CP_NORMAL));
            else              wattron(w, COLOR_PAIR(CP_DIM));
            mvwprintw(w, 9, 2, " [%s] Use DHCP (automatic IP)", use_dhcp ? "✓" : " ");
            if (act)          wattroff(w, COLOR_PAIR(CP_SELECTED) | A_BOLD);
            else if (!dim)    wattroff(w, COLOR_PAIR(CP_NORMAL));
            else              wattroff(w, COLOR_PAIR(CP_DIM));
        }

        /* static IP fields */
        for (int i = 0; i < N_NET_FIELDS; i++) {
            bool field_dim = dim || use_dhcp;
            bool act = (sel == 2 + i) && !field_dim;
            draw_field(w, 11 + i * 2, 2, bw - 4,
                       manual_labels[i], manual_bufs[i], act, false);
            if (field_dim) {
                wattron(w, COLOR_PAIR(CP_DIM));
                mvwprintw(w, 11 + i * 2, 2, "%-20s", manual_labels[i]);
                wattroff(w, COLOR_PAIR(CP_DIM));
            }
        }

        /* continue / skip buttons */
        bool btn_act = (sel == 7);
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

        /* ── input on static fields ───────────────────────────── */
        if (sel >= 2 && sel <= 5 && !dim && !use_dhcp) {
            int fi = sel - 2;
            int fx = 2 + 19 + 1;
            int fw = bw - 4 - 19 - 2;
            int fy = 11 + fi * 2;
            int ret = input_text(w, fy, fx, fw, manual_bufs[fi], MAX_INPUT - 1, false);
            delwin(w);
            if (ret == 1)  { sel = (sel + 1) % 8; continue; }
            if (ret == -1) { if (sel > 0) sel--; else return -1; continue; }
            sel = (sel + 1) % 8;
            continue;
        }

        int ch = wgetch(w);
        delwin(w);

        if (ch == KEY_UP)   { sel = (sel + 7) % 8; continue; }
        if (ch == KEY_DOWN || ch == '\t') { sel = (sel + 1) % 8; continue; }
        if (ch == 27) return -1;

        if (ch == ' ' || ch == '\n' || ch == '\r') {
            if (sel == 6) { skip_net = !skip_net; continue; }
            if (sel == 1 && !skip_net) { use_dhcp = !use_dhcp; continue; }
            if (sel == 0 && !skip_net) {
                sel_iface = (sel_iface + 1) % n_ifaces;
                continue;
            }
            if (sel == 7) {
                g_state.skip_network = skip_net;
                if (!skip_net) {
                    strncpy(g_state.iface,   ifaces[sel_iface], sizeof(g_state.iface)   - 1);
                    g_state.use_dhcp = use_dhcp;
                    if (!use_dhcp) {
                        strncpy(g_state.ip,      ip,      sizeof(g_state.ip)      - 1);
                        strncpy(g_state.netmask, netmask, sizeof(g_state.netmask) - 1);
                        strncpy(g_state.gateway, gateway, sizeof(g_state.gateway) - 1);
                        strncpy(g_state.dns,     dns,     sizeof(g_state.dns)     - 1);
                    }
                }
                return 1;
            }
        }
    }
}
