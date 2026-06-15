# ── HackerOS Installer – Makefile ───────────────────────────────────────
CC      := gcc
TARGET  := hackeros-installer

# Source files (all .c in src/)
SRCS := src/main.c \
        src/ui.c \
        src/screen_welcome.c \
        src/screen_locale.c \
        src/screen_disk.c \
        src/screen_user.c \
        src/screen_network.c \
        src/screen_roles.c \
        src/screen_summary.c \
        src/install.c

OBJS := $(SRCS:.c=.o)

# Compiler flags
CFLAGS  := -O2 -Wall -Wextra -Wno-unused-parameter \
           -std=c11 -D_GNU_SOURCE \
           -Isrc

# ── Link mode ────────────────────────────────────────────────────────────
# Default: static link of ncursesw + tinfo, rest dynamic (libc etc.)
# For fully static: make STATIC=1
ifdef STATIC
  LDFLAGS := -static
  LIBS    := -lncursesw -ltinfo
else
  LIBS    := -lncursesw -ltinfo
  LDFLAGS :=
endif

# Static libs path (Debian/Ubuntu)
LIBNCURSESW := /usr/lib/x86_64-linux-gnu/libncursesw.a
LIBTINFO    := /usr/lib/x86_64-linux-gnu/libtinfo.a

.PHONY: all clean install strip

all: $(TARGET)

$(TARGET): $(OBJS)
ifdef STATIC
	$(CC) $(LDFLAGS) -o $@ $^ $(LIBNCURSESW) $(LIBTINFO)
else
	$(CC) $(LDFLAGS) -o $@ $^ $(LIBS)
endif
	@echo ""
	@echo "  Built: $(TARGET)"
	@file $(TARGET)
	@ls -lh $(TARGET)

%.o: %.c
	$(CC) $(CFLAGS) -c $< -o $@

strip: $(TARGET)
	strip --strip-all $(TARGET)
	@echo "  Stripped: $(TARGET)  ($$(ls -lh $(TARGET) | awk '{print $$5}'))"

install: $(TARGET)
	install -Dm755 $(TARGET) /usr/local/sbin/$(TARGET)
	@echo "  Installed to /usr/local/sbin/$(TARGET)"

clean:
	rm -f $(OBJS) $(TARGET)

# ── dependency tracking ──────────────────────────────────────────────────
-include $(SRCS:.c=.d)
%.d: %.c
	@$(CC) $(CFLAGS) -MM -MT '$(<:.c=.o)' $< > $@
