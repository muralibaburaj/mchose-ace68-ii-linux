#!/usr/bin/env bash
set -euo pipefail

if (( EUID != 0 )); then
	echo "Run this script with doas." >&2
	exit 1
fi

rule=/etc/udev/rules.d/82-mchose-ace68-ii-hid-bpf.rules
object=/etc/udev-hid-bpf/MCHOSE__Ace68-II.bpf.o

[[ -e "$rule" ]] || { echo "Persistent Ace68-II HID-BPF rule is not installed." >&2; exit 1; }
rm -- "$rule"
udevadm control --reload-rules

for device in /sys/bus/hid/devices/0003:41E4:2116.*; do
	[[ -d "$device" ]] || continue
	[[ "$(readlink -f "$device")" == *:1.2/* ]] || continue
	if ! udev-hid-bpf remove "$device"; then
		echo "Failed to detach HID-BPF; do not start the bridge until it is removed." >&2
		exit 1
	fi
done

rm -f -- "$object"
rc-update add mchose-adv default
rc-service mchose-adv start
echo "Restored the userspace bridge and removed the persistent HID-BPF rule."
