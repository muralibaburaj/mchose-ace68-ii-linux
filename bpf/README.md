# HID-BPF descriptor fixup for Ace68-II

The Ace68-II `41e4:2116` interface 2 has a 163-byte HID report descriptor.
Report ID 1 starts with `05 01 09 06 a1 01 85 01` and declares 120 one-bit
keyboard inputs, but the `Input` field at byte offset **23** is `81 00`
(Data, **Array**, Absolute). Hardware sends a 15-byte keyboard **bitmap**.
The candidate fix changes only descriptor byte 23 to `02` (Data,
**Variable**, Absolute), following the in-tree
[`Trust__Philips-SPK6327.bpf.c`](https://github.com/torvalds/linux/blob/master/drivers/hid/bpf/progs/Trust__Philips-SPK6327.bpf.c)
precedent. The `probe` rejects other interface descriptors and revisions.

Run `python3 bpf/check_descriptor.py` (auto-discovers interface 2), or pass
its `report_descriptor` path explicitly. It recognizes the original `81 00`
and the attached fixup's `81 02`. This is only a static assertion, not a
kernel-input test. Kernel `CONFIG_HID_BPF=y` is present on the tested Gentoo
7.2.7 kernel. On the tested machine, `udev-hid-bpf` 2.2.0 and libbpf 1.7.0
are installed. The BPF object compiles with the matching upstream 2.2.0
source tree. A temporary live attachment with the bridge stopped showed
A/D characters being produced by Linux; boot-time auto-attachment and wider
feature coverage have not yet been tested.

## Build and test on another system

1. Build with [udev-hid-bpf](https://libevdev.pages.freedesktop.org/udev-hid-bpf/getting-started.html)
   (the source includes `vmlinux.h`, `hid_bpf.h`, `hid_bpf_helpers.h`, and
   `bpf/bpf_tracing.h`). The tested build uses its 2.2.0-20251121 release,
   adding `MCHOSE__Ace68-II.bpf.c` to `src/bpf/testing/meson.build`, then
   `meson setup build -Dbpfs=testing -Dbpf-compiler=clang` and
   `ninja -C build src/bpf/0010-MCHOSE__Ace68-II.bpf.o`. Copy that object
   beside this README as `MCHOSE__Ace68-II.bpf.o` (git ignores compiled BPF).
2. A **synthetic UHID** keyboard test with both original and corrected
   descriptors would add confidence, but has not been performed. It would
   require privileged access to `/dev/uhid`. The static descriptor check
   and successful BPF compilation do not prove real kernel input behavior.
3. With that uncertainty understood, perform a **manual, temporary** test on the real
   interface-2 HID device. Keep another keyboard available. Run
   `doas bash bpf/live-test.sh` in a terminal: it stops the bridge, attaches
   the compiled object, and waits for you to test A/D and other keys. When
   you press Enter or interrupt it, it removes the fixup and restarts the
   bridge. Attaching/detaching HID-BPF temporarily reprobes that interface.
   If interrupted uncleanly (power failure or SIGKILL), manually run
   `doas udev-hid-bpf remove /sys/bus/hid/devices/0003:41E4:2116.NNNN`
   using the actual path printed by the script, then
   `doas rc-service mchose-adv start`.
4. Do not replace the OpenRC service on another system until its own live
   test passes. Reconnect and reboot remain unverified on the tested system;
   M HUB Web and other keyboard features need separate checks. No keyboard
   firmware is modified by HID-BPF.

This program is an **experimental alternative** to the working userspace
bridge and is not part of `make install`. It is currently attached and has a
persistent udev rule on the tested Gentoo machine, not automatically installed
for every checkout. See the [main README](../README.md) for the full setup,
verification, and rollback procedure.

## Persistent switch after successful live test

`doas bash bpf/install-hid-bpf.sh` temporarily re-tests the compiled object,
then installs `82-mchose-ace68-ii-hid-bpf.rules` to auto-attach on future
keyboard connections **only** for USB interface 2. Type `keep` within 120
seconds if it works; otherwise it removes the attachment and returns to the
OpenRC bridge. When kept, the bridge binary/service is retained but removed
from the default runlevel. The HID-BPF object is stored in
`/etc/udev-hid-bpf/MCHOSE__Ace68-II.bpf.o`.

To undo the persistent switch later, run `doas bash bpf/rollback-hid-bpf.sh`.
