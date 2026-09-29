#!/usr/bin/env bash
# Temporary physical-keyboard test. This does not install a persistent rule.
set -euo pipefail

if (( EUID != 0 )); then
	echo "Run this script with doas (root is needed to attach HID-BPF)." >&2
	exit 1
fi

object="$(dirname "$(readlink -f "$0")")/MCHOSE__Ace68-II.bpf.o"
if [[ ! -r "$object" ]]; then
	echo "Missing compiled HID-BPF object: $object" >&2
	exit 1
fi

device=""
for candidate in /sys/bus/hid/devices/0003:41E4:2116.*; do
	[[ -d "$candidate" ]] || continue
	[[ "$(readlink -f "$candidate")" == *:1.2/* ]] || continue
	[[ -z "$device" ]] || { echo "Multiple Ace68-II advanced interfaces found; refusing." >&2; exit 1; }
	device="$candidate"
done
[[ -n "$device" ]] || { echo "Ace68-II USB interface 2 not found." >&2; exit 1; }

echo "Temporary HID-BPF test on: $device"
echo "The interface will briefly re-probe; A/D may stop working during the test."
echo "Press Enter at the end to REMOVE the fixup and restore the OpenRC bridge."
read -r -p "Type 'test' to proceed: " confirm
[[ "$confirm" == test ]] || exit 0

bridge_stopped=0
attached=0
restore() {
	set +e
	if (( attached )); then
		udev-hid-bpf remove "$device" || echo "BPF removal failed: run 'doas udev-hid-bpf remove $device'" >&2
	fi
	if (( bridge_stopped )); then
		rc-service mchose-adv start || echo "Bridge restart failed: run 'doas rc-service mchose-adv start'" >&2
	fi
}
trap restore EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

rc-service mchose-adv stop
bridge_stopped=1

# Set before attaching so even a partially successful add is removed.
attached=1
udev-hid-bpf add "$device" "$object"

echo "Fixup attached. Test A, D, holding A then pressing D, and normal typing."
echo "Also test the keyboard's mouse/media controls if you use them."
echo "The test will end automatically after 120 seconds."
read -r -t 120 -p "Press Enter to remove the fixup and restore the working bridge: " _ || true
