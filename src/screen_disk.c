#include "installer.h"
#include <dirent.h>
#include <sys/stat.h>

#define MAX_DISKS 16

typedef struct {
    char dev[64];    /* e.g. sda */
    char size[32];   /* human-readable */
    char model[64];
} DiskInfo;

static int scan_disks(DiskInfo disks[MAX_DISKS])
{
    int n = 0;
    DIR *d = opendir("/sys/block");
    if (!d) {
        /* fallback: fake entries for demo/offline env */
        strncpy(disks[0].dev, "/dev/sda", sizeof(disks[0].dev) - 1);
        strncpy(disks[0].size, "~64 GB", sizeof(disks[0].size) - 1);
        strncpy(disks[0].model, "Virtual Disk", sizeof(disks[0].model) - 1);
        return 1;
    }

    struct dirent *ent;
    while ((ent = readdir(d)) != NULL && n < MAX_DISKS) {
        const char *nm = ent->d_name;
        if (nm[0] == '.') continue;
        /* skip loop, ram, sr devices */
        if (strncmp(nm, "loop", 4) == 0 ||
            strncmp(nm, "ram",  3) == 0 ||
            strncmp(nm, "sr",   2) == 0) continue;

        /* must have a size > 0 */
        char size_path[128];
        snprintf(size_path, sizeof(size_path), "/sys/block/%s/size", nm);
        FILE *sf = fopen(size_path, "r");
        if (!sf) continue;
        unsigned long long sectors = 0;
        fscanf(sf, "%llu", &sectors);
        fclose(sf);
        if (sectors == 0) continue;

        snprintf(disks[n].dev, sizeof(disks[n].dev), "/dev/%s", nm);

        unsigned long long bytes = sectors * 512ULL;
        if (bytes >= (1ULL << 40))
            snprintf(disks[n].size, sizeof(disks[n].size), "%.1f TB", (double)bytes / (1ULL<<40));
        else if (bytes >= (1ULL << 30))
            snprintf(disks[n].size, sizeof(disks[n].size), "%.1f GB", (double)bytes / (1ULL<<30));
        else
            snprintf(disks[n].size, sizeof(disks[n].size), "%.1f MB", (double)bytes / (1ULL<<20));

        /* model */
        char model_path[128];
        snprintf(model_path, sizeof(model_path), "/sys/block/%s/device/model", nm);
        FILE *mf = fopen(model_path, "r");
        if (mf) {
            if (!fgets(disks[n].model, sizeof(disks[n].model), mf))
                disks[n].model[0] = '\0';
            /* trim newline */
            char *nl = strchr(disks[n].model, '\n');
            if (nl) *nl = '\0';
            fclose(mf);
        } else {
            strncpy(disks[n].model, "Unknown", sizeof(disks[n].model) - 1);
        }

        n++;
    }
    closedir(d);

    if (n == 0) {
        strncpy(disks[0].dev, "/dev/sda", sizeof(disks[0].dev) - 1);
        strncpy(disks[0].size, "~64 GB", sizeof(disks[0].size) - 1);
        strncpy(disks[0].model, "Virtual Disk", sizeof(disks[0].model) - 1);
        n = 1;
    }
    return n;
}

static const char *PART_LABELS[] = {
    "Auto  –  Erase entire disk (ext4)",
    "Auto  –  Erase disk with LVM",
    "Auto  –  Erase disk with LUKS + LVM (encrypted)",
    "Manual  –  Open shell for manual partitioning",
};

int screen_disk(void)
{
    DiskInfo disks[MAX_DISKS];
    int n_disks = scan_disks(disks);
    int sel_disk = 0;
    int sel_scheme = (int)g_state.part_scheme;
    int sel_field = 0; /* 0=disk, 1=scheme, 2=swap, 3=continue */

    /* try to pre-select previously chosen disk */
    for (int i = 0; i < n_disks; i++)
        if (!strcmp(disks[i].dev, g_state.disk_device)) { sel_disk = i; break; }

        /* detect EFI */
        g_state.use_efi = (access("/sys/firmware/efi", F_OK) == 0);

    while (1) {
        int rows, cols;
        getmaxyx(stdscr, rows, cols);
        ui_draw_base("Disk & Partitioning", SCREEN_DISK, SCREEN_FINISH + 1);

        int bh = 20, bw = 64;
        int by = rows / 2 - bh / 2 + 3;
        int bx = (cols - bw) / 2;
        if (by < 13) by = 13;

        WINDOW *w = newwin(bh, bw, by, bx);
        wbkgd(w, COLOR_PAIR(CP_NORMAL));
        ui_draw_border(w);

        wattron(w, COLOR_PAIR(CP_DIM));
        mvwprintw(w, 1, 2, "EFI mode: %s", g_state.use_efi ? "Yes" : "No (BIOS/Legacy)");
        wattroff(w, COLOR_PAIR(CP_DIM));

        /* ── disk list ───────────────────────────────────────── */
        wattron(w, sel_field == 0 ? COLOR_PAIR(CP_STATUS) | A_BOLD : COLOR_PAIR(CP_NORMAL));
        mvwaddstr(w, 2, 2, "Installation target disk:");
        wattroff(w, sel_field == 0 ? COLOR_PAIR(CP_STATUS) | A_BOLD : COLOR_PAIR(CP_NORMAL));

        for (int i = 0; i < n_disks && i < 5; i++) {
            bool active = (i == sel_disk) && (sel_field == 0);
            bool mark   = (i == sel_disk);
            if (active)
                wattron(w, COLOR_PAIR(CP_SELECTED) | A_BOLD);
            else if (mark)
                wattron(w, COLOR_PAIR(CP_BORDER));
            else
                wattron(w, COLOR_PAIR(CP_NORMAL));

            mvwprintw(w, 3 + i, 3, " %s %-6s  %-24s %s",
                      mark ? "●" : "○",
                      disks[i].dev, disks[i].model, disks[i].size);

            if (active)   wattroff(w, COLOR_PAIR(CP_SELECTED) | A_BOLD);
            else if (mark) wattroff(w, COLOR_PAIR(CP_BORDER));
            else           wattroff(w, COLOR_PAIR(CP_NORMAL));
        }

        /* ── partition scheme ────────────────────────────────── */
        wattron(w, COLOR_PAIR(CP_BORDER));
        mvwhline(w, 8, 1, ACS_HLINE, bw - 2);
        wattroff(w, COLOR_PAIR(CP_BORDER));

        wattron(w, sel_field == 1 ? COLOR_PAIR(CP_STATUS) | A_BOLD : COLOR_PAIR(CP_NORMAL));
        mvwaddstr(w, 9, 2, "Partition scheme:");
        wattroff(w, sel_field == 1 ? COLOR_PAIR(CP_STATUS) | A_BOLD : COLOR_PAIR(CP_NORMAL));

        for (int i = 0; i < 4; i++) {
            bool active = (i == sel_scheme) && (sel_field == 1);
            bool mark   = (i == sel_scheme);
            if (active)
                wattron(w, COLOR_PAIR(CP_SELECTED) | A_BOLD);
            else if (mark)
                wattron(w, COLOR_PAIR(CP_BORDER));
            else
                wattron(w, COLOR_PAIR(CP_NORMAL));

            mvwprintw(w, 10 + i, 3, " %s %s",
                      mark ? "◉" : "○",
                      PART_LABELS[i]);

            if (active)   wattroff(w, COLOR_PAIR(CP_SELECTED) | A_BOLD);
            else if (mark) wattroff(w, COLOR_PAIR(CP_BORDER));
            else           wattroff(w, COLOR_PAIR(CP_NORMAL));
        }

        /* ── swap toggle ─────────────────────────────────────── */
        wattron(w, COLOR_PAIR(CP_BORDER));
        mvwhline(w, 14, 1, ACS_HLINE, bw - 2);
        wattroff(w, COLOR_PAIR(CP_BORDER));

        bool sw_active = (sel_field == 2);
        if (sw_active) wattron(w, COLOR_PAIR(CP_STATUS) | A_BOLD);
        else           wattron(w, COLOR_PAIR(CP_NORMAL));
        mvwaddstr(w, 15, 2, "Create swap partition:");
        wattroff(sw_active ? COLOR_PAIR(CP_STATUS) | A_BOLD : COLOR_PAIR(CP_NORMAL));

        if (sw_active) wattron(w, COLOR_PAIR(CP_SELECTED) | A_BOLD);
        else if (g_state.use_swap) wattron(w, COLOR_PAIR(CP_BORDER));
        else wattron(w, COLOR_PAIR(CP_NORMAL));
        mvwprintw(w, 15, 27, " [%s] ", g_state.use_swap ? "✓" : " ");
        if (sw_active) wattroff(w, COLOR_PAIR(CP_SELECTED) | A_BOLD);
        else if (g_state.use_swap) wattroff(w, COLOR_PAIR(CP_BORDER));
        else wattroff(w, COLOR_PAIR(CP_NORMAL));

        /* ── continue button ─────────────────────────────────── */
        if (sel_field == 3) {
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

        if (ch == KEY_UP) {
            if (sel_field == 0 && sel_disk > 0) sel_disk--;
            else if (sel_field == 1 && sel_scheme > 0) sel_scheme--;
            else sel_field = (sel_field + 3) % 4;
            continue;
        }
        if (ch == KEY_DOWN || ch == '\t') {
            if (sel_field == 0 && sel_disk < n_disks - 1) sel_disk++;
            else if (sel_field == 1 && sel_scheme < 3) sel_scheme++;
            else sel_field = (sel_field + 1) % 4;
            continue;
        }

        if (ch == 27) return -1;

        if (ch == '\n' || ch == '\r' || ch == ' ') {
            if (sel_field == 2) {
                g_state.use_swap = !g_state.use_swap;
            } else if (sel_field == 3) {
                strncpy(g_state.disk_device, disks[sel_disk].dev,
                        sizeof(g_state.disk_device) - 1);
                g_state.part_scheme = (PartScheme)sel_scheme;
                return 1;
            } else if (sel_field == 0) {
                sel_field = 1; /* move to scheme */
            } else if (sel_field == 1) {
                sel_field = 2;
            }
        }
    }
}
