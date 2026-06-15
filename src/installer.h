#ifndef INSTALLER_H
#define INSTALLER_H

#include <ncurses.h>
#include <string.h>
#include <stdlib.h>
#include <stdio.h>
#include <unistd.h>
#include <sys/utsname.h>
#include <stdbool.h>
#include <ctype.h>
#include <time.h>

/* ── Color pair IDs ─────────────────────────────────────────────────── */
#define CP_NORMAL        1   /* white on black          */
#define CP_TITLE         2   /* black on orange         */
#define CP_HIGHLIGHT     3   /* black on orange         */
#define CP_BORDER        4   /* orange on black         */
#define CP_STATUS        5   /* orange on black (bold)  */
#define CP_ERROR         6   /* red on black            */
#define CP_SUCCESS       7   /* green on black          */
#define CP_DIM           8   /* dark gray on black      */
#define CP_INPUT         9   /* orange on dark gray     */
#define CP_SELECTED     10   /* black on orange         */
#define CP_UNSELECTED   11   /* white on black          */
#define CP_HEADER       12   /* bright orange on black  */

/* ── Orange approximation (terminal 256-color) ───────────────────────── */
#define COLOR_ORANGE    214  /* xterm-256: #ffaf00  */
#define COLOR_DARK_BG    16  /* true black            */
#define COLOR_DARKGRAY  236

/* ── UI constants ────────────────────────────────────────────────────── */
#define INSTALLER_VERSION   "1.0.0"
#define OS_NAME             "HackerOS"
#define OS_EDITION          "Server Edition"
#define OS_BASE             "Debian Trixie (stable)"
#define LOGO_WIDTH          52
#define MAX_INPUT           128
#define MAX_PACKAGES        32

/* ── Screens / steps ─────────────────────────────────────────────────── */
typedef enum {
    SCREEN_WELCOME = 0,
    SCREEN_LOCALE,
    SCREEN_DISK,
    SCREEN_USER,
    SCREEN_NETWORK,
    SCREEN_SERVER_ROLE,
    SCREEN_PACKAGES,
    SCREEN_EXTRA_CONFIG,
    SCREEN_SUMMARY,
    SCREEN_INSTALL,
    SCREEN_FINISH,
    SCREEN_COUNT
} Screen;

/* ── Disk partition scheme ───────────────────────────────────────────── */
typedef enum {
    PART_AUTO_FULL = 0,
    PART_AUTO_LVM,
    PART_AUTO_LUKS_LVM,
    PART_MANUAL
} PartScheme;

/* ── Server role flags ───────────────────────────────────────────────── */
typedef enum {
    ROLE_NONE        = 0,
    ROLE_WEB         = (1 << 0),
    ROLE_DATABASE    = (1 << 1),
    ROLE_MAIL        = (1 << 2),
    ROLE_DNS         = (1 << 3),
    ROLE_FILE        = (1 << 4),
    ROLE_CONTAINER   = (1 << 5),
    ROLE_MONITORING  = (1 << 6),
    ROLE_VPN         = (1 << 7),
    ROLE_SECURITY    = (1 << 8),
} ServerRole;

/* ── Global installer state ─────────────────────────────────────────── */
typedef struct {
    /* locale */
    char locale[32];
    char timezone[64];
    char keymap[32];

    /* disk */
    char disk_device[64];       /* e.g. /dev/sda */
    PartScheme part_scheme;
    bool use_swap;
    bool use_efi;               /* detected */

    /* user */
    char hostname[MAX_INPUT];
    char username[MAX_INPUT];
    char password[MAX_INPUT];
    char password2[MAX_INPUT];
    char root_password[MAX_INPUT];
    char root_password2[MAX_INPUT];
    bool disable_root;

    /* network */
    bool skip_network;
    char iface[32];
    bool use_dhcp;
    char ip[32];
    char netmask[32];
    char gateway[32];
    char dns[64];

    /* server role */
    unsigned int roles;         /* bitmask of ServerRole */
    bool skip_roles;

    /* extra packages */
    bool pkg_selected[MAX_PACKAGES];
    bool skip_extra;

    /* install */
    int  current_screen;
    bool install_done;
    bool error_occurred;
    char error_msg[256];
} InstallerState;

extern InstallerState g_state;

/* ── UI helpers ─────────────────────────────────────────────────────── */
void ui_init(void);
void ui_cleanup(void);
void ui_draw_base(const char *title, int step, int total);
void ui_draw_border(WINDOW *w);
void ui_status(const char *msg);
void ui_error_box(const char *msg);
int  ui_confirm_box(const char *question);
void ui_progress(WINDOW *w, int y, int x, int width, int percent, const char *label);

/* ── Input helpers ──────────────────────────────────────────────────── */
int  input_text(WINDOW *w, int y, int x, int width, char *buf, int maxlen, bool secret);
void draw_field(WINDOW *w, int y, int x, int width, const char *label, const char *val, bool active, bool secret);

/* ── Screens ─────────────────────────────────────────────────────────── */
int screen_welcome(void);
int screen_locale(void);
int screen_disk(void);
int screen_user(void);
int screen_network(void);
int screen_server_role(void);
int screen_packages(void);
int screen_extra_config(void);
int screen_summary(void);
int screen_install(void);
int screen_finish(void);

/* ── Install logic ──────────────────────────────────────────────────── */
int do_install(WINDOW *log_win, WINDOW *progress_win);

#endif /* INSTALLER_H */
