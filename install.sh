#!/usr/bin/env bash
#
# Installer for the mchose-adv userspace bridge, on any init system.
#
#   ./install.sh                  build, install system-wide, enable + start the
#                                 service for the running init system
#   ./install.sh --init NAME      force systemd, openrc, runit, s6, dinit,
#                                 sysvinit or none instead of detecting it
#   ./install.sh --user           systemd *user* service in ~/.local (old mode)
#   ./install.sh --no-udev        skip the udev rules (you manage access yourself)
#   ./install.sh --no-build       use an existing ./mchose-adv binary
#   ./install.sh --uninstall      remove everything this script installed
#
# System-wide mode uses sudo or doas for the root steps. Do not run the bridge
# while the HID-BPF fixup is attached (see README).
#
set -euo pipefail

SRC_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/svc.sh
. "$SRC_DIR/scripts/svc.sh"

PREFIX="${PREFIX:-/usr/local}"
BIN_DIR="${XDG_BIN_HOME:-$HOME/.local/bin}"
UNIT_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
USER_BIN="$BIN_DIR/mchose-adv"
UNIT="$UNIT_DIR/mchose-adv.service"
UDEV_DIR=/etc/udev/rules.d
RULES=(70-mchose-ace68-ii.rules 70-mchose-adv.rules)

mode=system
init=""
do_udev=1
do_build=1
do_uninstall=0

while (($#)); do
    case "$1" in
    --user) mode=user ;;
    --init)
        [[ $# -ge 2 ]] || {
            echo "--init needs a value" >&2
            exit 2
        }
        init=$2
        shift
        ;;
    --init=*) init=${1#--init=} ;;
    --no-udev) do_udev=0 ;;
    --no-build) do_build=0 ;;
    --uninstall) do_uninstall=1 ;;
    -h | --help)
        sed -n '3,16p' "$0"
        exit 0
        ;;
    *)
        echo "unknown option: $1" >&2
        exit 2
        ;;
    esac
    shift
done

if ((EUID == 0)); then
    as_root() { "$@"; }
elif command -v sudo >/dev/null 2>&1; then
    as_root() { sudo "$@"; }
elif command -v doas >/dev/null 2>&1; then
    as_root() { doas "$@"; }
else
    as_root() {
        echo "error: need root for: $*  (install sudo or doas, or run as root)" >&2
        return 1
    }
fi

# Runs a svc.sh action as root under the chosen init system.
svc_root() {
    as_root env MCHOSE_INIT="$init" sh "$SRC_DIR/scripts/svc.sh" "$@" mchose-adv
}

reload_udev() {
    command -v udevadm >/dev/null 2>&1 || {
        echo "    note: no udevadm; reload your device manager's rules manually."
        return 0
    }
    as_root udevadm control --reload-rules
    as_root udevadm trigger
}

install_udev() {
    ((do_udev)) || return 0
    local changed=0 rule
    for rule in "${RULES[@]}"; do
        if [[ -f "$UDEV_DIR/$rule" ]] && cmp -s "$SRC_DIR/packaging/$rule" "$UDEV_DIR/$rule"; then
            continue
        fi
        echo "==> installing $UDEV_DIR/$rule (needs root)"
        as_root install -Dm644 "$SRC_DIR/packaging/$rule" "$UDEV_DIR/$rule"
        changed=1
    done
    if ((changed)); then reload_udev; else echo "==> udev rules already up to date"; fi
}

uninstall_udev() {
    local removed=0 rule
    for rule in "${RULES[@]}"; do
        if [[ -f "$UDEV_DIR/$rule" ]]; then
            echo "==> removing $UDEV_DIR/$rule (needs root)"
            as_root rm -f "$UDEV_DIR/$rule"
            removed=1
        fi
    done
    ((removed == 0)) || reload_udev
}

# ── Uninstall ─────────────────────────────────────────────────────────────
if ((do_uninstall)); then
    if [[ -f "$UNIT" ]]; then
        echo "==> removing the systemd user service"
        systemctl --user disable --now mchose-adv.service 2>/dev/null || true
        rm -f "$UNIT" "$USER_BIN"
        systemctl --user daemon-reload 2>/dev/null || true
    fi
    if [[ -x "$PREFIX/bin/mchose-adv-ace68-ii" ]]; then
        init=${init:-$(svc_detect)}
        echo "==> removing the system service ($init)"
        svc_root stop 2>/dev/null || true
        svc_root disable 2>/dev/null || true
        as_root make -C "$SRC_DIR" PREFIX="$PREFIX" INIT="$init" uninstall uninstall-init
        [[ $init != systemd ]] || as_root systemctl daemon-reload
    fi
    uninstall_udev
    echo "==> done"
    exit 0
fi

# ── Build ─────────────────────────────────────────────────────────────────
if ((do_build)); then
    echo "==> building"
    make -C "$SRC_DIR"
fi
if [[ ! -x "$SRC_DIR/mchose-adv" ]]; then
    echo "error: $SRC_DIR/mchose-adv not found; run without --no-build" >&2
    exit 1
fi

# ── systemd user service (--user) ─────────────────────────────────────────
if [[ $mode == user ]]; then
    echo "==> installing $USER_BIN"
    install -Dm755 "$SRC_DIR/mchose-adv" "$USER_BIN"

    echo "==> installing user unit $UNIT"
    mkdir -p "$UNIT_DIR"
    sed "s|@BIN@|$USER_BIN|g" "$SRC_DIR/packaging/init/systemd-user/mchose-adv.service" >"$UNIT"

    install_udev

    if ! id -nG "$USER" | tr ' ' '\n' | grep -qx input; then
        echo
        echo "NOTE: you are not in the 'input' group. The udev rules grant access"
        echo "      via uaccess, which covers an active local session, but a"
        echo "      systemd user service may not see that ACL. Consider:"
        echo "          sudo usermod -aG input $USER    # then log out and back in"
        echo
    fi

    echo "==> enabling the user service"
    # Tolerate having no systemd user session yet: this is normal when the script
    # runs from a TTY during machine bootstrap, and must not abort the caller.
    if ! systemctl --user daemon-reload 2>/dev/null; then
        echo "    note: no systemd user session available yet."
        echo "          After logging in, run: systemctl --user enable --now mchose-adv"
    else
        systemctl --user enable --now mchose-adv.service ||
            echo "    note: could not start it now; it will start on next login."
        sleep 1
        systemctl --user --no-pager --lines=0 status mchose-adv.service || true
    fi
    logs="journalctl --user -u mchose-adv -f"
    where="$USER_BIN, $UNIT"

# ── System-wide service (default) ─────────────────────────────────────────
else
    init=${init:-$(svc_detect)}
    echo "==> installing to $PREFIX for init system: $init"
    as_root make -C "$SRC_DIR" PREFIX="$PREFIX" INIT="$init" install install-init

    install_udev

    if [[ $init != none ]]; then
        [[ $init != systemd ]] || as_root systemctl daemon-reload
        echo "==> enabling and starting mchose-adv ($init)"
        svc_root enable || echo "    note: enable it at boot manually (see above)."
        svc_root start || echo "    note: could not start it now; check its log."
    fi

    case "$init" in
    systemd) logs="journalctl -u mchose-adv -f" ;;
    runit | s6) logs="your syslog (tag mchose-adv)" ;;
    none) logs="wherever your supervisor sends stderr" ;;
    *) logs="/var/log/mchose-adv.log" ;;
    esac
    where="$PREFIX/bin/mchose-adv-ace68-ii"
fi

cat <<EOF

Installed.

  files    $where
  logs     $logs

If the keyboard was already plugged in, the daemon will find it within a couple
of seconds. Verify with:

  ls /dev/input/by-id/ | grep -i 'advanced'      # the virtual keyboard
  evtest /dev/input/eventN                       # press an advanced key

EOF
