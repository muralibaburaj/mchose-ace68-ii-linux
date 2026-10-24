# This is a GNU Makefile, not a shell script. Shellcheck misreads make's
# $(VAR) as command substitution and flags the unquoted expansions below;
# quoting them would break the build (flags must word-split).
# shellcheck disable=SC1072,SC1073,SC2046,SC2068,SC2086,SC2035

PREFIX      ?= /usr/local
BINDIR      ?= $(PREFIX)/bin
UDEVDIR     ?= /usr/lib/udev/rules.d
SYSCONFDIR  ?= /etc
DOCDIR      ?= $(PREFIX)/share/doc/mchose-adv
LICENSEDIR  ?= $(PREFIX)/share/licenses/mchose-adv

CC      ?= cc
CFLAGS  ?= -O2 -Wall -Wextra
DESTDIR ?=

# Init system for install-init: auto (detect the running one), systemd,
# systemd-user, openrc, runit, s6, dinit, sysvinit, or none.
INIT        ?= auto
ifeq ($(INIT),auto)
override INIT := $(shell sh scripts/svc.sh detect)
endif

SYSTEMDUNITDIR ?= $(SYSCONFDIR)/systemd/system
SYSTEMDUSERDIR ?= $(PREFIX)/lib/systemd/user
RUNITDIR       ?= $(if $(wildcard /etc/runit/sv),/etc/runit/sv,$(SYSCONFDIR)/sv)
S6DIR          ?= $(SYSCONFDIR)/s6/sv
DINITDIR       ?= $(SYSCONFDIR)/dinit.d

BIN   = $(BINDIR)/mchose-adv-ace68-ii
SUBST = sed 's|@BIN@|$(BIN)|g'

.PHONY: all clean install install-init uninstall uninstall-init

all: mchose-adv

mchose-adv: src/mchose-adv.c
	$(CC) $(CFLAGS) -o $@ src/mchose-adv.c

clean:
	rm -f mchose-adv

install: mchose-adv
	install -Dm755 mchose-adv                      $(DESTDIR)$(BINDIR)/mchose-adv-ace68-ii
	install -Dm644 packaging/70-mchose-ace68-ii.rules $(DESTDIR)$(UDEVDIR)/70-mchose-ace68-ii.rules
	install -Dm644 README.md                       $(DESTDIR)$(DOCDIR)/README.md
	install -Dm644 docs/PROTOCOL.md                $(DESTDIR)$(DOCDIR)/PROTOCOL.md
	install -Dm644 LICENSE                         $(DESTDIR)$(LICENSEDIR)/LICENSE

uninstall:
	rm -f  $(DESTDIR)$(BINDIR)/mchose-adv-ace68-ii
	rm -f  $(DESTDIR)$(UDEVDIR)/70-mchose-ace68-ii.rules
	rm -rf $(DESTDIR)$(DOCDIR) $(DESTDIR)$(LICENSEDIR)

# Installs the bridge's service for one init system. It does not enable or
# start it: do that with `scripts/svc.sh enable` / `scripts/svc.sh start`.
install-init:
ifeq ($(INIT),systemd)
	install -d $(DESTDIR)$(SYSTEMDUNITDIR)
	$(SUBST) packaging/init/systemd/mchose-adv.service > $(DESTDIR)$(SYSTEMDUNITDIR)/mchose-adv.service
	chmod 644 $(DESTDIR)$(SYSTEMDUNITDIR)/mchose-adv.service
else ifeq ($(INIT),systemd-user)
	install -d $(DESTDIR)$(SYSTEMDUSERDIR)
	$(SUBST) packaging/init/systemd-user/mchose-adv.service > $(DESTDIR)$(SYSTEMDUSERDIR)/mchose-adv.service
	chmod 644 $(DESTDIR)$(SYSTEMDUSERDIR)/mchose-adv.service
else ifeq ($(INIT),openrc)
	install -d $(DESTDIR)$(SYSCONFDIR)/init.d
	$(SUBST) packaging/init/openrc/mchose-adv > $(DESTDIR)$(SYSCONFDIR)/init.d/mchose-adv
	chmod 755 $(DESTDIR)$(SYSCONFDIR)/init.d/mchose-adv
else ifeq ($(INIT),runit)
	install -d $(DESTDIR)$(RUNITDIR)/mchose-adv/log
	$(SUBST) packaging/init/runit/run > $(DESTDIR)$(RUNITDIR)/mchose-adv/run
	install -m755 packaging/init/runit/log/run $(DESTDIR)$(RUNITDIR)/mchose-adv/log/run
	chmod 755 $(DESTDIR)$(RUNITDIR)/mchose-adv/run
else ifeq ($(INIT),s6)
	install -d $(DESTDIR)$(S6DIR)/mchose-adv
	install -m644 packaging/init/s6/type $(DESTDIR)$(S6DIR)/mchose-adv/type
	$(SUBST) packaging/init/s6/run > $(DESTDIR)$(S6DIR)/mchose-adv/run
	chmod 755 $(DESTDIR)$(S6DIR)/mchose-adv/run
else ifeq ($(INIT),dinit)
	install -d $(DESTDIR)$(DINITDIR)
	$(SUBST) packaging/init/dinit/mchose-adv > $(DESTDIR)$(DINITDIR)/mchose-adv
	chmod 644 $(DESTDIR)$(DINITDIR)/mchose-adv
else ifeq ($(INIT),sysvinit)
	install -d $(DESTDIR)$(SYSCONFDIR)/init.d
	$(SUBST) packaging/init/sysvinit/mchose-adv > $(DESTDIR)$(SYSCONFDIR)/init.d/mchose-adv
	chmod 755 $(DESTDIR)$(SYSCONFDIR)/init.d/mchose-adv
else ifeq ($(INIT),none)
	@echo "INIT=none: no service installed; run $(BIN) from your own supervisor."
else
	$(error unknown INIT '$(INIT)'; use systemd, systemd-user, openrc, runit, s6, dinit, sysvinit or none)
endif

uninstall-init:
	rm -f  $(DESTDIR)$(SYSTEMDUNITDIR)/mchose-adv.service
	rm -f  $(DESTDIR)$(SYSTEMDUSERDIR)/mchose-adv.service
	rm -f  $(DESTDIR)$(SYSCONFDIR)/init.d/mchose-adv
	rm -rf $(DESTDIR)$(RUNITDIR)/mchose-adv
	rm -rf $(DESTDIR)$(S6DIR)/mchose-adv
	rm -f  $(DESTDIR)$(DINITDIR)/mchose-adv
