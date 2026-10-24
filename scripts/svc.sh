#!/bin/sh
# Init-system abstraction for the mchose-adv bridge service.
#
#   scripts/svc.sh detect                 print the running init system
#   scripts/svc.sh ACTION [SERVICE]       start|stop|status|enable|disable|is-enabled
#
# Can also be sourced (`. scripts/svc.sh`) to use svc_detect / svc_ACTION.
# Supported: systemd, openrc, runit, s6 (s6-rc), dinit, sysvinit.
# Set MCHOSE_INIT to override detection.

svc_detect() {
	if [ -n "${MCHOSE_INIT-}" ]; then
		echo "$MCHOSE_INIT"
		return
	fi
	if [ -d /run/systemd/system ]; then
		echo systemd
		return
	fi
	# OpenRC usually runs under sysvinit's PID 1, so check it before PID 1.
	if [ -e /run/openrc/softlevel ] || [ -d /run/openrc/started ]; then
		echo openrc
		return
	fi
	pid1=$(cat /proc/1/comm 2>/dev/null)
	case "$pid1" in
	runit*) echo runit ;;
	s6-svscan | s6-linux-init*) echo s6 ;;
	dinit) echo dinit ;;
	*)
		if command -v dinitctl >/dev/null 2>&1 && dinitctl list >/dev/null 2>&1; then
			echo dinit
		elif [ -d /run/s6-rc ] && command -v s6-rc >/dev/null 2>&1; then
			echo s6
		elif command -v sv >/dev/null 2>&1 && [ -d /run/runit ]; then
			echo runit
		else
			echo sysvinit
		fi
		;;
	esac
}

# Where runit looks for enabled services, and where definitions live.
runit_svdir() {
	for d in /run/runit/service /var/service /etc/service; do
		[ -d "$d" ] && { echo "$d"; return; }
	done
	echo /var/service
}
runit_defdir() {
	if [ -d /etc/runit/sv ]; then echo /etc/runit/sv; else echo /etc/sv; fi
}

svc_status() {
	s=${1:-mchose-adv}
	case $(svc_detect) in
	systemd) systemctl is-active --quiet "$s" ;;
	openrc) rc-service "$s" status >/dev/null 2>&1 ;;
	runit) sv status "$(runit_svdir)/$s" 2>/dev/null | grep -q '^run:' ;;
	s6) s6-rc -a list 2>/dev/null | grep -qx "$s" ;;
	dinit) dinitctl is-started "$s" >/dev/null 2>&1 ;;
	*) /etc/init.d/"$s" status >/dev/null 2>&1 ;;
	esac
}

svc_start() {
	s=${1:-mchose-adv}
	case $(svc_detect) in
	systemd) systemctl start "$s" ;;
	openrc) rc-service "$s" start ;;
	runit)
		# A not-yet-enabled runit service has no supervisor to talk to.
		[ -e "$(runit_svdir)/$s" ] || svc_enable "$s"
		sv up "$(runit_svdir)/$s"
		;;
	s6) s6-rc -u change "$s" ;;
	dinit) dinitctl start "$s" ;;
	*) /etc/init.d/"$s" start ;;
	esac
}

svc_stop() {
	s=${1:-mchose-adv}
	case $(svc_detect) in
	systemd) systemctl stop "$s" ;;
	openrc) rc-service "$s" stop ;;
	runit) [ ! -e "$(runit_svdir)/$s" ] || sv down "$(runit_svdir)/$s" ;;
	s6) s6-rc -d change "$s" ;;
	dinit) dinitctl stop "$s" ;;
	*) /etc/init.d/"$s" stop ;;
	esac
}

svc_enable() {
	s=${1:-mchose-adv}
	case $(svc_detect) in
	systemd) systemctl enable "$s" ;;
	openrc) rc-update add "$s" default ;;
	runit) ln -sfn "$(runit_defdir)/$s" "$(runit_svdir)/$s" ;;
	s6)
		if command -v s6-service >/dev/null 2>&1; then
			s6-service add default "$s" && s6-db-reload
		else
			echo "Add $s to your s6-rc default bundle and recompile the database." >&2
			return 1
		fi
		;;
	dinit) dinitctl enable "$s" ;;
	*)
		if command -v update-rc.d >/dev/null 2>&1; then
			update-rc.d "$s" defaults
		elif command -v chkconfig >/dev/null 2>&1; then
			chkconfig --add "$s"
		else
			echo "Link /etc/init.d/$s into your runlevel directories (rcN.d) or rc.local." >&2
			return 1
		fi
		;;
	esac
}

svc_disable() {
	s=${1:-mchose-adv}
	case $(svc_detect) in
	systemd) systemctl disable "$s" ;;
	openrc) rc-update del "$s" default ;;
	runit) rm -f "$(runit_svdir)/$s" ;;
	s6)
		if command -v s6-service >/dev/null 2>&1; then
			s6-service delete default "$s" && s6-db-reload
		else
			echo "Remove $s from your s6-rc default bundle and recompile the database." >&2
			return 1
		fi
		;;
	dinit) dinitctl disable "$s" ;;
	*)
		if command -v update-rc.d >/dev/null 2>&1; then
			update-rc.d -f "$s" remove
		elif command -v chkconfig >/dev/null 2>&1; then
			chkconfig --del "$s"
		fi
		;;
	esac
}

svc_is_enabled() {
	s=${1:-mchose-adv}
	case $(svc_detect) in
	systemd) systemctl is-enabled --quiet "$s" ;;
	openrc) rc-update show default 2>/dev/null | grep -qw "$s" ;;
	runit) [ -e "$(runit_svdir)/$s" ] ;;
	s6) s6-rc-db contents default 2>/dev/null | grep -qx "$s" ;;
	dinit) [ -e /etc/dinit.d/boot.d/"$s" ] ;;
	*) ls /etc/rc[2-5].d/S*"$s" >/dev/null 2>&1 ;;
	esac
}

# Run as a command unless sourced. $0 is the sourcing shell when sourced.
case "${0##*/}" in
svc.sh)
	action=${1-}
	[ $# -gt 0 ] && shift
	case "$action" in
	detect) svc_detect ;;
	start | stop | status | enable | disable) "svc_$action" "$@" ;;
	is-enabled) svc_is_enabled "$@" ;;
	*)
		echo "usage: $0 detect | {start|stop|status|enable|disable|is-enabled} [service]" >&2
		exit 2
		;;
	esac
	;;
esac
