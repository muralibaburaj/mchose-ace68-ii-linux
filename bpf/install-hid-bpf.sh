#!/usr/bin/env bash
# Interactive install. Keeps the old bridge available as a rollback.
set -euo pipefail

if (( EUID != 0 )); then
	echo "Run this script with doas." >&2
	exit 1
fi

here="$(dirname "$(readlink -f "$0")")"
object="$here/MCHOSE__Ace68-II.bpf.o"
rule_source="$here/82-mchose-ace68-ii-hid-bpf.rules"
object_target=/etc/udev-hid-bpf/MCHOSE__Ace68-II.bpf.o
rule_target=/etc/udev/rules.d/82-mchose-ace68-ii-hid-bpf.rules

[[ -r "$object" && -r "$rule_source" ]] || { echo "Build object and rule are missing." >&2; exit 1; }
[[ ! -e "$object_target" && ! -e "$rule_target" ]] || {
	echo "Target files already exist; refusing to overwrite them." >&2
	exit 1
}

device=""
for candidate in /sys/bus/hid/devices/0003:41E4:2116.*; do
	[[ -d "$candidate" ]] || continue
	[[ "$(readlink -f "$candidate")" == *:1.2/* ]] || continue
	[[ -z "$device" ]] || { echo "Multiple matching keyboards; refusing." >&2; exit 1; }
	device="$candidate"
done
[[ -n "$device" ]] || { echo "Ace68-II interface 2 not found." >&2; exit 1; }

rc-service mchose-adv status >/dev/null || { echo "Working OpenRC bridge is not running; refusing." >&2; exit 1; }
rc-update show default | grep -q 'mchose-adv' || { echo "Bridge is not in default runlevel; refusing." >&2; exit 1; }

echo "Install a persistent HID-BPF rule for $device and disable the old bridge at boot?"
echo "You will get a 120-second A/D test before you decide to keep it."
read -r -p "Type 'install' to proceed: " confirm
[[ "$confirm" == install ]] || exit 0

object_created=0
rule_created=0
bridge_stopped=0
attached=0
keep=0
rollback() {
	(( keep )) && return 0
	set +e
	if (( rule_created )); then
		rm -f -- "$rule_target"
		udevadm control --reload-rules
	fi
	if (( attached )); then
		udev-hid-bpf remove "$device" || echo "BPF detach failed; remove it before restarting the bridge." >&2
	fi
	if (( bridge_stopped )); then
		rc-update add mchose-adv default
		rc-service mchose-adv start
	fi
	if (( object_created )); then
		rm -f -- "$object_target"
	fi
}
trap rollback EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

install -Dm644 "$object" "$object_target"
object_created=1
bridge_stopped=1
rc-service mchose-adv stop
attached=1
udev-hid-bpf add "$device" "$object_target"

echo "HID-BPF attached. Test A, D, last-input-wins, and normal typing."
echo "The old bridge will be restored automatically unless you type 'keep'."
if ! read -r -t 120 -p "Type 'keep' within 120 seconds if it works: " confirm; then
	exit 1
fi
[[ "$confirm" == keep ]] || exit 1

install -Dm644 "$rule_source" "$rule_target"
rule_created=1
udevadm control --reload-rules
rc-update del mchose-adv default
keep=1
echo "HID-BPF rule installed for future reconnects and boots; old bridge disabled but retained."
