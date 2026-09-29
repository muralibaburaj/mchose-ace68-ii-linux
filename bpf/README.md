# Experimental HID-BPF descriptor fixup (not installed)

The Ace68-II `41e4:2116` interface 2 has a 163-byte HID report descriptor.
Report ID 1 starts with `05 01 09 06 a1 01 85 01` and declares 120 one-bit
keyboard inputs, but the `Input` field at byte offset **23** is `81 00`
(Data, **Array**, Absolute). Hardware sends a 15-byte keyboard **bitmap**.
The candidate fix changes only descriptor byte 23 to `02` (Data,
**Variable**, Absolute), following the in-tree
[`Trust__Philips-SPK6327.bpf.c`](https://github.com/torvalds/linux/blob/master/drivers/hid/bpf/progs/Trust__Philips-SPK6327.bpf.c)
precedent. The `probe` rejects other interface descriptors and revisions.

Run `python3 bpf/check_descriptor.py` (auto-discovers interface 2), or pass
its `report_descriptor` path explicitly. This is only a static assertion, not a
kernel-input test. Kernel `CONFIG_HID_BPF=y` is present on the tested Gentoo
7.2.7 kernel, but `udev-hid-bpf`/libbpf development tools are not yet installed.

## Next, before applying to the real keyboard

1. Build with [udev-hid-bpf](https://libevdev.pages.freedesktop.org/udev-hid-bpf/getting-started.html)
   (the source includes `vmlinux.h`, `hid_bpf.h`, `hid_bpf_helpers.h`, and
   `bpf/bpf_tracing.h`). Add `MCHOSE__Ace68-II.bpf.c` to its `src/bpf/testing/`
   Meson sources; compile and inspect its ELF and the udev-hid-bpf loader.
2. Test a **synthetic UHID** keyboard with both original and corrected
   descriptors and identical A/D input reports, ensuring Linux emits no
   duplicate/unrelated keys. This will require privileged access to `/dev/uhid`.
3. Only after that, test a **manual, temporary** attachment to the real
   interface-2 HID device. Keep another keyboard available. First stop the
   userspace bridge with `doas rc-service mchose-adv stop`; while the BPF
   fixup is attached, running the bridge too may double the keystrokes.
   Attaching/detaching HID-BPF temporarily reprobes that interface. If it
   fails, remove the BPF attachment, then `doas rc-service mchose-adv start`.
4. Do not replace the OpenRC service, auto-install udev rules, or claim this
   fixes the hardware until the live test passes (including reconnect and
   M HUB Web access). No keyboard firmware is modified by HID-BPF.

This program is an **experimental alternative** to the working userspace
bridge, not part of `make install` and not yet validated on physical hardware.
