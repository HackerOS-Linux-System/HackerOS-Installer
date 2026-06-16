#define _POSIX_C_SOURCE 200809L
#include "installer.h"

/* ── global state ────────────────────────────────────────────────────── */
InstallerState g_state = {
    .locale        = "en_US.UTF-8",
    .timezone      = "UTC",
    .keymap        = "us",
    .disk_device   = "",
    .part_scheme   = PART_AUTO_FULL,
    .use_swap      = true,
    .use_efi       = false,
    .hostname      = "hackeros-server",
    .username      = "",
    .password      = "",
    .password2     = "",
    .root_password = "",
    .root_password2= "",
    .disable_root  = true,
    .skip_network  = false,
    .iface         = "eth0",
    .use_dhcp      = true,
    .ip            = "",
    .netmask       = "",
    .gateway       = "",
    .dns           = "",
    .roles         = 0,
    .skip_roles    = false,
    .pkg_selected  = {0},
    .skip_extra    = false,
    .current_screen= 0,
    .install_done  = false,
    .error_occurred= false,
    .error_msg     = "",
};

/* ── screen dispatch ─────────────────────────────────────────────────── */
typedef int (*ScreenFn)(void);

static const ScreenFn SCREENS[SCREEN_COUNT] = {
    [SCREEN_WELCOME]      = screen_welcome,
    [SCREEN_LOCALE]       = screen_locale,
    [SCREEN_DISK]         = screen_disk,
    [SCREEN_USER]         = screen_user,
    [SCREEN_NETWORK]      = screen_network,
    [SCREEN_SERVER_ROLE]  = screen_server_role,
    [SCREEN_PACKAGES]     = screen_packages,
    [SCREEN_EXTRA_CONFIG] = screen_extra_config,
    [SCREEN_SUMMARY]      = screen_summary,
    [SCREEN_INSTALL]      = screen_install,
    [SCREEN_FINISH]       = screen_finish,
};

/* ── signal handler ──────────────────────────────────────────────────── */
static void handle_sigwinch(int sig)
{
    (void)sig;
    endwin();
    refresh();
    clear();
}

/* ── main ────────────────────────────────────────────────────────────── */
int main(void)
{
    /* must run as root */
    if (geteuid() != 0) {
        fprintf(stderr,
            "\nHackerOS Installer must be run as root.\n"
            "Try:  sudo hackeros-installer\n\n");
        return 1;
    }

    signal(SIGWINCH, handle_sigwinch);

    ui_init();

    int cur = SCREEN_WELCOME;

    while (cur >= 0 && cur < SCREEN_COUNT) {
        if (!SCREENS[cur]) { cur++; continue; }

        int ret = SCREENS[cur]();

        if (ret > 0) {
            /* forward */
            if (cur == SCREEN_FINISH) break; /* done */
            cur++;
        } else if (ret < 0) {
            /* back – don't go before LOCALE */
            if (cur > SCREEN_LOCALE) cur--;
        }
        /* ret == 0  →  stay on same screen (shouldn't happen but safe) */
    }

    ui_cleanup();

    if (g_state.install_done) {
        printf("\n\033[1;32m"
               "  HackerOS Server Edition installed successfully.\n"
               "  Please reboot your system.\033[0m\n\n");
        /* actual reboot */
        execlp("reboot", "reboot", NULL);
    }

    return 0;
}
