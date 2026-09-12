# mchose-adv

**Brings MCHOSE hall-effect keyboard advanced keys — SOCD, RS, DKS, MT, TGL — to Linux.**

If your MCHOSE keyboard's SOCD (or RS / DKS) works on Windows but the bound keys
do nothing on Linux, this is why, and this fixes it.

```text
the keys ARE sent by the keyboard — Linux just never turns them into input
```

No firmware flashing, no driver installation, no patching the kernel. It is
strictly read-only with respect to the keyboard: it never writes to the device
and never grabs it, so the vendor web driver and everything else keeps working.

## The problem

These keyboards are composite HID devices with three USB interfaces:

| Interface | Role | Linux support |
| --- | --- | --- |
| 0 | normal boot keyboard | ✅ works out of the box |
| 1 | vendor / configuration | n/a (no keys) |
| 2 | mouse + consumer + **advanced keys** | ❌ keys arrive, but the kernel ignores them |

Normal typing goes out on interface 0. But keys resolved by **SOCD, RS, DKS,
MT, TGL** are sent on **interface 2** as a 16-byte report:

```text
01 00 00 00 00 00 80 00 00 00 00 00 00 00 00 00
│  └──────────── NKRO bitmap, indexed by HID usage ────┘
└ report id 0x01
```

Linux binds that interface and even advertises `KEY_LEFTBRACE`/`KEY_RIGHTBRACE`
on the resulting event device — it just never emits events for the report the
device actually sends. Windows parses it correctly. That OS difference is
exactly why this looks like a firmware bug when it isn't.

`mchose-adv` reads that report and re-emits the keys as a normal virtual
keyboard.

Full byte-level write-up: [`docs/PROTOCOL.md`](docs/PROTOCOL.md).

## Requirements

* Linux with `uinput` (any modern kernel)
* Read access to the keyboard's `hidraw` node, and write access to `/dev/uinput`
* A C compiler to build

On Arch and most desktops both already work for a logged-in user. Otherwise the
shipped udev rule handles it.

## Tested on

* **MCHOSE Ace 68 -III** (`3837:3003`) — SOCD, on Linux 6.x and 7.x

Other MCHOSE models in the same M-HUB family (Ace 60, Ace 68 Air, Ace 68 Turbo,
Ace 68 GT, Jet 75, Zero 75X, Mix 87) very likely behave the same, but have not
been tested. Reports welcome — see [`docs/PROTOCOL.md` §6](docs/PROTOCOL.md).

## Quick start

```sh
git clone https://github.com/CHANGEME/mchose-adv
cd mchose-adv
./install.sh
```

That builds it, installs the binary to `~/.local/bin`, installs a systemd
**user** service, offers to install the udev rule (the only step needing root),
and enables the service.

Verify:

```sh
ls /dev/input/by-id/ | grep -i advanced     # the virtual keyboard
systemctl --user status mchose-adv
journalctl --user -u mchose-adv -f
```

Then press one of your SOCD-bound keys. It should type.

### Manual

```sh
make
sudo make install                          # /usr/local, systemd user unit, udev rule
./mchose-adv -v                            # or run it in the foreground
```

### Uninstall

```sh
./install.sh --uninstall
# or
sudo make uninstall
```

## Usage

```text
mchose-adv [-v] [--retry SECONDS] [hidraw-device]

  -v, --verbose     log every key change
      --retry SEC   seconds to wait before reconnecting (default 2)
  -h, --help
```

With no device argument the correct `hidraw` node is found automatically by USB
id **and interface number** (never a hardcoded `/dev/hidrawN`), so it survives
replugging and will not attach to your mouse.

## Behaviour worth knowing

* **It reconnects.** If the keyboard disappears — for example while passed
  through to a VM — it releases any held keys, waits, and reconnects when the
  keyboard comes back. The systemd unit also has `Restart=always`.
* **It is inert when unused.** Turn SOCD off in the firmware and it simply emits
  nothing; the keys go back to arriving through interface 0 as normal.
* **Auto-repeat is the kernel's job.** It enables `EV_REP` and lets the input
  layer handle held keys, exactly like a real keyboard.
* **Only HID usages 0x00–0x77 can be carried.** That is all 15 bitmap bytes can
  hold. Fine for letters, digits, punctuation, F-keys and arrows; media keys
  above usage `0x77` cannot appear in this report format at all — a firmware
  limitation, not this program's.
* **Advanced keys are not duplicated.** Because they only travel on interface 2,
  there is no double input.

## Troubleshooting

**Nothing types.** Check the daemon is running and found the device:

```sh
journalctl --user -u mchose-adv -n 30
./mchose-adv -v            # foreground; should print "connected: /dev/hidrawN"
```

**`cannot open /dev/hidrawN: Permission denied`.** Your user cannot read the
device. Install the udev rule (`./install.sh`, or copy
`packaging/70-mchose-adv.rules` to `/etc/udev/rules.d/`, re-run
`udevadm control --reload-rules && udevadm trigger`, then replug), or add
yourself to `input`: `sudo usermod -aG input $USER` and log back in.

**Wrong characters.** You are probably running a build with the wrong bitmap
offset. See the "Trap" note in [`docs/PROTOCOL.md` §3](docs/PROTOCOL.md).

**Keys are stuck after killing it.** It releases everything on `SIGINT`/`SIGTERM`
and on device removal. If it was `SIGKILL`ed, unplug and replug the keyboard.

**It works but my compositor ignores the virtual keyboard.** It is registered as
a normal keyboard — check `hyprctl devices` / `libinput list-devices` and make
sure it is not excluded by a per-device config.

## Related work

Other userspace drivers for hall-effect keyboards on Linux, for context and
prior art:

* [mechlands-m75-linux](https://github.com/MaxGiuP/mechlands-m75-linux) — MIT,
  configuration driver for the MechLands M75 (actuation, RT, RGB)
* [ratkbd-linux](https://github.com/snayzy-del/ratkbd-linux) — MAD60HE + VXE R1
  Pro, C/C++ ⚠️ *proprietary, not reusable*
* [HallEffectAnalogMapper](https://github.com/Richard121292/HallEffectAnalogMapper)
  — turns an HE keyboard (incl. MCHOSE Jet 75) into an analog gamepad
* [doubletap](https://github.com/zakack/doubletap) ·
  [KeyResolve](https://github.com/Antosser/KeyResolve) — implement SOCD in
  software, if you would rather not use the keyboard's own implementation

Those all either configure the keyboard or implement SOCD from scratch. To our
knowledge nothing else reads the keyboard's **own** advanced-key output, which
is what this project does.

## Contributing

Especially welcome:

* `hidraw` captures from other MCHOSE models (see `docs/PROTOCOL.md` §5)
* characterisation of **RS**, **DKS**, **MT** and **TGL** output
* anything that gets this fixed in the kernel instead — that would make this
  whole project unnecessary, which would be a good outcome

## Disclaimer

Not affiliated with, endorsed by, or supported by MCHOSE. This is a userspace
workaround for a gap in Linux's handling of the device. It reads from the
keyboard only; it never writes to it, so it cannot alter or damage your
keyboard's configuration.

Note that some competitive games and anti-cheat systems take a dim view of
SOCD/"snap tap". Using your keyboard's own feature is your call — Rocket League
permits it, CS2 explicitly bans it.

## License

MIT
