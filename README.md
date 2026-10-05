# MCHOSE Ace68-II advanced keys on Linux

**Fork of [erikenz/mchose-adv](https://github.com/erikenz/mchose-adv), adapted
for the MCHOSE Ace68-II and Gentoo/OpenRC.** Credit for the original
`mchose-adv` userspace bridge and protocol documentation belongs to its upstream
contributors. This fork adds Ace68-II-specific support and a HID-BPF descriptor
fixup; it is not an official MCHOSE project.

Linux support for the **MCHOSE Ace68-II (`41e4:2116`)** advanced-key interface.
The primary solution is a small HID-BPF report-descriptor correction: no
long-running bridge process, polling loop, virtual keyboard, or firmware flash.
The keyboard itself must still be configured for A/D last-input-wins SOCD.
An adaptation of [erikenz/mchose-adv](https://github.com/erikenz/mchose-adv)
is retained as a tested userspace fallback.

## What was wrong, and what changes

The keyboard presents three USB HID interfaces. On interface 2, its 163-byte
report descriptor declares 120 one-bit keyboard inputs in report ID 1 as an
**Array** (`81 00`), even though the device sends a 15-byte **bitmap**. Linux
does not interpret those advanced-key bits as ordinary key transitions. The
[HID-BPF fixup](bpf/MCHOSE__Ace68-II.bpf.c) changes the descriptor's byte at
offset 23 from `00` to `02`, making that field **Variable** (`81 02`). It
does not change reports sent by the keyboard or implement SOCD in software.
Both the BPF program's probe and the udev rule restrict it to this USB ID and
the expected interface/descriptor; other HID interfaces are left alone.

On the tested machine (Gentoo, kernel `7.2.7-gentoo-dist-bin`), the object
compiled, attached to the physical keyboard with the bridge stopped, and A/D
characters worked without Fn during that attachment. The persistent files are
now installed, the bridge is stopped and removed from OpenRC's default
runlevel, and the fixup is attached in the kernel. **An actual reboot or
replug and a full last-input-wins sequence (hold A, press D, release D) have
not been independently verified.** Other features, firmware revisions, and
keyboards have not been validated.

## How it starts and what runs

The installed rule is
`/etc/udev/rules.d/82-mchose-ace68-ii-hid-bpf.rules`; the compiled object is
`/etc/udev-hid-bpf/MCHOSE__Ace68-II.bpf.o`. On a matching HID interface-2
**add** event, udev invokes `/usr/bin/udev-hid-bpf add` to attach the object.
On removal it invokes `udev-hid-bpf remove`. Gentoo's OpenRC `udev` and
`udev-trigger` services are in `sysinit`, and bpffs is mounted at
`/sys/fs/bpf`. This is **configured** to reattach on boot and reconnect, but
that behavior has not yet been confirmed with a reboot/replug test.

`udev-hid-bpf` runs briefly on device events; it is **not** a resident daemon.
The attached BPF code resides in the kernel, not in a process listed by `ps`.
The old `mchose-adv` binary and service files remain installed for rollback,
but its service is stopped and not enabled at boot. The BPF object on the
tested machine is about 7.7 KiB; the `udev-hid-bpf` package and build tools
do add an on-disk installation footprint.

To inspect your own system without changing it:

```sh
rc-service mchose-adv status
rc-update show default | grep mchose || true
ps -eo pid,comm,args | grep -E '[m]chose-adv|[u]dev-hid-bpf' || true
find /sys/fs/bpf/hid -maxdepth 3 -path '*41E4*' -print 2>/dev/null
ls -l /etc/udev/rules.d/82-mchose-ace68-ii-hid-bpf.rules \
  /etc/udev-hid-bpf/MCHOSE__Ace68-II.bpf.o
```

The `ps` check may include a matching command shell on some systems; check
the process name/PID before interpreting its output. A pinned BPF path proves
an attachment exists **now**, not that a future boot will succeed.

## Set up the keyboard

1. In MCHOSE M HUB Web, use a WebHID-capable browser to configure A/D as
   last-input-wins SOCD on a Custom Profile. The setting is stored on the
   keyboard. No Linux userspace bridge or BPF program configures SOCD.
2. For WebHID access on Gentoo, install
   [`packaging/70-mchose-ace68-ii.rules`](packaging/70-mchose-ace68-ii.rules)
   in `/etc/udev/rules.d/`, reload udev rules, then reconnect the keyboard.
   It grants the active local session access to this device's `hidraw` nodes;
   it does **not** grant access to `/dev/uinput` or set mouse polling rates.

## Build and install HID-BPF on Gentoo/OpenRC

The `.bpf.o` file is deliberately **not committed**: compile it locally with
the [udev-hid-bpf](https://libevdev.pages.freedesktop.org/udev-hid-bpf/getting-started.html)
source/toolchain. This procedure describes the tested `2.2.0-20251121`
source and Gentoo packaging, not a prebuilt release artifact. Keep another
keyboard available while testing: attaching or removing HID-BPF reprobes the
advanced-key interface.

1. Check for kernel `CONFIG_HID_BPF=y` and an available bpffs mount. On the
   tested Gentoo installation, `sys-kernel/udev-hid-bpf` needs a per-package
   `~amd64` keyword:

   ```sh
   printf '%s\n' 'sys-kernel/udev-hid-bpf ~amd64' | \
     doas tee /etc/portage/package.accept_keywords/udev-hid-bpf
   doas emerge -av sys-kernel/udev-hid-bpf
   ```

   Its ebuild pulls in the required build/runtime dependencies (including
   clang with BPF support, bpftool, and libbpf). Check `emerge -pv` before
   accepting changes on a different Gentoo system.

2. Build the object from the matching source release. The tested source was
   the Gentoo distfile
   `/var/cache/distfiles/udev-hid-bpf-2.2.0-20251121.tar.bz2`:

   ```sh
   mkdir -p /tmp/opencode
   tar -xjf /var/cache/distfiles/udev-hid-bpf-2.2.0-20251121.tar.bz2 -C /tmp/opencode
   cd /tmp/opencode/udev-hid-bpf-2.2.0-20251121
   cp ~/code/src/peripheral-udev/mchose-adv-ace68-ii/bpf/MCHOSE__Ace68-II.bpf.c \
     src/bpf/testing/0010-MCHOSE__Ace68-II.bpf.c
   ```

   Add `'0010-MCHOSE__Ace68-II.bpf.c',` inside the `sources = [ ... ]` list
   in `src/bpf/testing/meson.build` (not the `tracing_sources` list). Then:

   ```sh
   meson setup build -Dbpfs=testing -Dbpf-compiler=clang
   ninja -C build src/bpf/0010-MCHOSE__Ace68-II.bpf.o
   cp build/src/bpf/0010-MCHOSE__Ace68-II.bpf.o \
     ~/code/src/peripheral-udev/mchose-adv-ace68-ii/bpf/MCHOSE__Ace68-II.bpf.o
   cd ~/code/src/peripheral-udev/mchose-adv-ace68-ii
   python3 bpf/check_descriptor.py
   ```

   The descriptor check is non-invasive; it does not prove key events work.
   See [BPF test details](bpf/README.md). If your checkout lives elsewhere,
   adjust the paths above. The installer intentionally refuses to overwrite
   existing target files or to switch a machine without the running fallback.

3. With the bridge running, do a **temporary** live test:

   ```sh
   doas bash bpf/live-test.sh
   ```

   It stops the bridge, attaches the object, and restores the bridge when
   you press Enter or after 120 seconds. Test A, D, held-key transitions,
   normal typing, and any special keys you use **during the test window**.
   Do not conclude that BPF worked from keys typed after the bridge restarts.

4. If the live test succeeds, perform the guarded persistent switch:

   ```sh
   doas bash bpf/install-hid-bpf.sh
   ```

   It tests again, then waits up to 120 seconds. Type `keep` **only if it
   works**. It installs the interface-specific udev rule and removes the old
   bridge from the default runlevel; otherwise it detaches BPF and restarts
   the bridge. The installer is **not** an upgrade tool: it refuses if its
   target files already exist. Do not run it again over an existing install.

After installing, verify the rule/object and attachment with the commands
above. To establish actual persistence, test a reconnect and a reboot while
another keyboard or a rollback path is available. Observe that the bridge
remains stopped and that A/D and SOCD behavior work after each event. Rule
presence and `udevadm test` alone are not a successful boot test.

## Roll back to the userspace bridge

From this repository, run:

```sh
doas bash bpf/rollback-hid-bpf.sh
```

This removes the persistent rule, reloads udev, detaches the live BPF
attachment, removes its installed object, and restores/enables the OpenRC
bridge. **Do not start the bridge while the BPF fixup remains attached:** that
can produce duplicate keys. If an interrupted install leaves an attachment,
detach it with `doas udev-hid-bpf remove /sys/bus/hid/devices/0003:41E4:2116.NNNN`
(replace `NNNN` with the current interface-2 HID instance) before starting
the bridge. The script refuses to start the bridge if detaching fails.

The fallback bridge reads interface-2 reports and re-emits keys through
`uinput`. To build and enable it on a machine without an HID-BPF install:

```sh
make
doas make install
doas rc-service mchose-adv start
doas rc-update add mchose-adv default
```

Its service runs as root because `/dev/uinput` is root-only by default;
stderr goes to `/var/log/mchose-adv.log`. Do not run this bridge at the same
time as the attached BPF fixup. Removing either Linux solution does not reset
the keyboard's onboard SOCD binding: change that in M HUB Web if desired.

## Provenance and scope

The userspace fallback is adapted from `erikenz/mchose-adv` (MIT license in
[`LICENSE`](LICENSE)); its original documentation is preserved in
[`docs/UPSTREAM_README.md`](docs/UPSTREAM_README.md) and
[`docs/PROTOCOL.md`](docs/PROTOCOL.md). Those documents describe a different
USB ID. The BPF descriptor approach follows the Linux
[`Trust__Philips-SPK6327.bpf.c`](https://github.com/torvalds/linux/blob/master/drivers/hid/bpf/progs/Trust__Philips-SPK6327.bpf.c)
precedent. Neither solution flashes keyboard firmware. This repository does
not set the HyperX mouse's 8000 Hz polling rate; that setting is selected
with the mouse's onboard DPI-button combination.
