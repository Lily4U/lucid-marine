CC      ?= cc
CFLAGS  ?= -O2 -g
override CFLAGS += -std=gnu11 -Wall -Wextra -Wno-unused-parameter -Igen \
                   $(shell pkg-config --cflags wayland-client)
LDLIBS  += $(shell pkg-config --libs wayland-client) -lm

PREFIX  ?= /usr/local
SCANNER ?= wayland-scanner

# Onde procurar os XMLs dos protocolos
WLP_DIR := $(shell pkg-config --variable=pkgdatadir wayland-protocols 2>/dev/null)
vpath %.xml protocols \
    $(WLP_DIR)/stable/xdg-shell \
    $(WLP_DIR)/stable/viewporter \
    /usr/share/wlr-protocols/unstable \
    /usr/local/share/wlr-protocols/unstable

PROTOS := xdg-shell viewporter wlr-layer-shell-unstable-v1 wlr-screencopy-unstable-v1
HDRS   := $(PROTOS:%=gen/%-client-protocol.h)
SRCS   := $(PROTOS:%=gen/%-protocol.c)

WLR_URL := https://gitlab.freedesktop.org/wlroots/wlr-protocols/-/raw/master/unstable

.PHONY: all clean install uninstall fetch

all: colorpicker

colorpicker: colorpicker.c $(HDRS) $(SRCS)
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ colorpicker.c $(SRCS) $(LDLIBS)

gen:
	mkdir -p $@

gen/%-client-protocol.h: %.xml | gen
	$(SCANNER) client-header $< $@

gen/%-protocol.c: %.xml | gen
	$(SCANNER) private-code $< $@

# Baixa os XMLs wlr-* caso sua distro não tenha o pacote wlr-protocols
fetch:
	mkdir -p protocols
	curl -fL -o protocols/wlr-layer-shell-unstable-v1.xml $(WLR_URL)/wlr-layer-shell-unstable-v1.xml
	curl -fL -o protocols/wlr-screencopy-unstable-v1.xml  $(WLR_URL)/wlr-screencopy-unstable-v1.xml

install: colorpicker
	install -Dm755 colorpicker $(DESTDIR)$(PREFIX)/bin/colorpicker

uninstall:
	rm -f $(DESTDIR)$(PREFIX)/bin/colorpicker

clean:
	rm -rf gen colorpicker
