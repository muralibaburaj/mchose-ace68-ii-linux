# This is a GNU Makefile, not a shell script. Shellcheck misreads make's
# $(VAR) as command substitution and flags the unquoted expansions below;
# quoting them would break the build (flags must word-split).
# shellcheck disable=SC1072,SC1073,SC2046,SC2068,SC2086,SC2035

PREFIX      ?= /usr/local
BINDIR      ?= $(PREFIX)/bin
UDEVDIR     ?= /usr/lib/udev/rules.d
INITDIR     ?= /etc/init.d
DOCDIR      ?= $(PREFIX)/share/doc/mchose-adv
LICENSEDIR  ?= $(PREFIX)/share/licenses/mchose-adv

CC      ?= cc
CFLAGS  ?= -O2 -Wall -Wextra
DESTDIR ?=

.PHONY: all clean install uninstall test

all: mchose-adv

mchose-adv: src/mchose-adv.c
	$(CC) $(CFLAGS) -o $@ src/mchose-adv.c

clean:
	rm -f mchose-adv

install: mchose-adv
	install -Dm755 mchose-adv                      $(DESTDIR)$(BINDIR)/mchose-adv-ace68-ii
	install -Dm644 packaging/70-mchose-ace68-ii.rules $(DESTDIR)$(UDEVDIR)/70-mchose-ace68-ii.rules
	install -Dm755 packaging/mchose-adv.openrc     $(DESTDIR)$(INITDIR)/mchose-adv
	install -Dm644 README.md                       $(DESTDIR)$(DOCDIR)/README.md
	install -Dm644 docs/PROTOCOL.md                $(DESTDIR)$(DOCDIR)/PROTOCOL.md
	install -Dm644 LICENSE                         $(DESTDIR)$(LICENSEDIR)/LICENSE

uninstall:
	rm -f  $(DESTDIR)$(BINDIR)/mchose-adv-ace68-ii
	rm -f  $(DESTDIR)$(UDEVDIR)/70-mchose-ace68-ii.rules
	rm -f  $(DESTDIR)$(INITDIR)/mchose-adv
	rm -rf $(DESTDIR)$(DOCDIR) $(DESTDIR)$(LICENSEDIR)
