# MCHOSE Ace68-II advanced keys on Linux

Minimal adaptation of [erikenz/mchose-adv](https://github.com/erikenz/mchose-adv)
for the **MCHOSE Ace68-II (`41e4:2116`)**. The C bridge reads advanced-key
reports from USB interface 2 and re-emits them through Linux `uinput`. It does
not configure the keyboard, write to it, or implement SOCD in software: the
keyboard's own firmware resolves the bound keys. The only change to the
upstream C source is the device ID (plus an explanatory comment).

Verified on Gentoo Linux 7.2.7-gentoo-dist-bin with A/D bound to last-input-wins
SOCD: A and D were both emitted as key-down/up events and worked without Fn.
Other features and hardware revisions are **not** tested here. See the
[original README](docs/UPSTREAM_README.md) and [protocol notes](docs/PROTOCOL.md)
for background; they describe a *different* USB ID and upstream packaging.

## Gentoo / OpenRC setup

1. Configure A/D last-input-wins SOCD on a Custom Profile in MCHOSE M HUB Web.
   The keyboard saves that setting onboard. Use a WebHID-capable browser.
2. Install the included `packaging/70-mchose-ace68-ii.rules` into
   `/etc/udev/rules.d/`, reload rules with `doas udevadm control --reload-rules`,
   and replug the keyboard. This rule only grants the active local session
   WebHID access to `41e4:2116`; it does **not** grant access to `/dev/uinput`.
3. Build and install the tested bridge and OpenRC service:

   ```sh
   make
   doas make install
   doas rc-service mchose-adv start
   rc-service mchose-adv status
   doas rc-update add mchose-adv default
   ```

   The OpenRC service runs as root because `/dev/uinput` is root-only by
   default; it does not expose all input devices to other users. The bridge
   automatically finds USB interface 2 by ID and reconnects after replugging.
   Its stderr is written to `/var/log/mchose-adv.log`.

To stop and remove the service:

```sh
doas rc-service mchose-adv stop
doas rc-update del mchose-adv default
doas make uninstall
doas udevadm control --reload-rules
```

Uninstalling the udev rule does not reset the keyboard's onboard SOCD binding;
remove that binding in M HUB if you want A/D to work without the bridge.

## Origin and license

Based on `erikenz/mchose-adv` (MIT license, retained in `LICENSE`). The
upstream systemd unit, vendor-wide udev rule, and Arch packaging remain in
the repository for provenance but are **not installed** by this Makefile.

An [experimental HID-BPF descriptor fixup](bpf/README.md) is also included,
but is not installed or tested on the physical keyboard. Keep the bridge
enabled until the kernel-side approach has been validated independently.
