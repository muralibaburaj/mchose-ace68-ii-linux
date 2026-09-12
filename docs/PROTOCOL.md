# MCHOSE Ace 68 — advanced-key HID protocol

Reverse-engineering notes for the MCHOSE Hall-effect keyboard line, written up
so the next person does not have to re-derive this from scratch.

Everything below was observed on a **MCHOSE Ace 68 -III, USB `3837:3003`**,
firmware as shipped in September 2026, with all three onboard profiles present
and SOCD bound to `[` and `]` in the `FPS Configuration` preset.

## 1. Device layout

The keyboard is a single USB device presenting **three HID interfaces**:

| USB interface | sysfs | hidraw | evdev | udev tags | key codes | role |
| --- | --- | --- | --- | --- | --- | --- |
| `1-4:1.0` | `…/0003:3837:3003.*/` | `hidraw2` | `event7` `MCHOSE Ace 68 -III` | `ID_INPUT_KEYBOARD=1` | 143, with modifiers | normal boot keyboard |
| `1-4:1.1` | | `hidraw3` | `event8` `MCHOSE Ace 68 -III` | — | **0** | vendor / configuration channel |
| `1-4:1.2` | | `hidraw4` | `event9` `… -III Keyboard`<br>`event10` `… -III Mouse`<br>`event11` `… -III Wireless Radio Control` | `ID_INPUT_KEY=1` only (no `ID_INPUT_KEYBOARD`) | 260, no modifiers | mouse + consumer + **advanced keys** |

Notes:

* `hidraw2` and `hidraw3` report an **identical report descriptor**, yet
  interface 1 exposes no keys at all. Interface 1 is where the vendor web
  driver (M-HUB) writes configuration.
* Interface 2 is the interesting one. It is *not* tagged `ID_INPUT_KEYBOARD`.
* The `Mouse` and `Wireless Radio Control` collections are part of the
  keyboard's own firmware, **not** a 2.4 GHz dongle — they appear even when the
  keyboard is wired.

## 2. Where advanced-key output goes

Normal typing is transmitted on **interface 0** only.

Keys resolved by the advanced-key features — **SOCD, RS (rapid switch /
"rappy snappy"), DKS, MT, TGL** — are transmitted on **interface 2** instead,
and are *not* duplicated onto interface 0.

This was confirmed by capturing both interfaces simultaneously while pressing
`P → [ → P → ] → P`:

```text
230.631  hidraw2 (if0)  len=8  0000130000000000    P   (usage 0x13)
230.736  hidraw2 (if0)  len=8  0000000000000000    P up
231.270  hidraw4 (if2)  len=16 01000000000080000000000000000000   [
231.390  hidraw4 (if2)  len=16 01000000000000000000000000000000   [ up
232.659  hidraw2 (if0)  len=8  0000130000000000    P
232.768  hidraw2 (if0)  len=8  0000000000000000    P up
234.012  hidraw4 (if2)  len=16 01000000000000010000000000000000   ]
234.157  hidraw4 (if2)  len=16 01000000000000000000000000000000   ] up
234.814  hidraw2 (if0)  len=8  0000130000000000    P
```

The two `P` presses bracketing each bracket key appear on interface 0; the
brackets appear only on interface 2. Reproduced 3/3 times for each key.

## 3. Interface 2 report format

```text
byte  0        report id, always 0x01
byte  1        bitmap byte 0  ─┐
byte  2        bitmap byte 1   │  15-byte NKRO bitmap,
…                              │  indexed by HID usage code
byte 15        bitmap byte 14 ─┘
```

Bit test:

```text
bitmap byte index = 1 + usage / 8
bit within byte   = usage % 8
```

So the bitmap covers **usages 0x00–0x77 (0–119)**. Usage codes above `0x77`
cannot be represented in this report at all.

### Verified mapping

| Key | HID usage | byte | bit | value |
| --- | --- | --- | --- | --- |
| `[` | `0x2F` = 47 | 6 | 7 | `0x80` |
| `]` | `0x30` = 48 | 7 | 0 | `0x01` |

Both were verified by pressing each key three times and observing the identical
frame each time, then cross-checked with the standard HID→evdev table
(`usage 0x2F → evdev 26 KEY_LEFTBRACE`, `usage 0x30 → evdev 27 KEY_RIGHTBRACE`).
The resulting characters in a terminal matched.

> **Trap:** byte 1 is the first bitmap byte, not a spare/report byte. It covers
> the unassigned usages `0x00–0x07`, so it is always `0x00` — which makes an
> off-by-one byte offset look plausible. Getting this wrong shifts every key by
> 8 usages (e.g. `[` decodes as `0` and `]` as `Enter`).

## 4. What Linux does with it

* `usbhid` binds interface 2 and creates `event9`, `event10`, `event11`.
* `event9` genuinely **advertises** `KEY_LEFTBRACE` and `KEY_RIGHTBRACE` in its
  key bitmap.
* Regardless, pressing `[` or `]` produces **no evdev events at all** on any of
  `event7`–`event11`.
* `dmesg` shows no HID warning or error for the frames.

So the report is delivered to the kernel (`hidraw4` hands it to userspace
verbatim) but the kernel does not turn it into input events. Whether that is a
descriptor/report-length mismatch, a report-id mismatch, or a collection the
kernel classifies but does not map, **is not yet determined** — see §6.

On Windows the same collection is parsed correctly, so the keyboard's SOCD works
there and appears broken on Linux. That OS difference is what makes this look
like a firmware bug when it is not: the firmware transmits the keys fine.

## 5. Reproducing the observation

Identify the interfaces:

```sh
lsusb -d 3837:3003
ls -l /dev/input/by-id/ | grep -i mchose
for e in /sys/class/input/event*/device/name; do cat "$e"; done
```

Raw report capture (interface 2), no root needed if your user can read hidraw:

```sh
# usbutils provides this
sudo usbhid-dump -e descriptor -d 3837:3003
```

Or read the hidraw node directly and hexdump it:

```sh
cat /dev/hidraw4 | stdbuf -o0 xxd -c 16
```

Check that the kernel is *not* translating it (should stay silent while you
press the advanced keys):

```sh
sudo evtest /dev/input/event9
```

Map a hidraw node back to its USB interface:

```sh
readlink -f /sys/class/hidraw/hidraw4/device      # … contains 1-4:1.2
```

Bind SOCD to a pair of keys you are happy to lose for the duration of the test —
this is why `[` and `]` are used in these notes rather than `A`/`D`.

## 6. Open questions

Anyone picking this up should start here:

1. **Why does the kernel drop the report?** Compare the report descriptor's
   declared report id/size/count for the keyboard collection on interface 2
   against the 16-byte frame the device actually sends. If it is a simple
   mismatch, a HID quirk or a small `hid-mchose` driver would fix this for
   everyone, with no userspace daemon needed.
2. **Do other MCHOSE models behave the same?** Ace 60, Ace 68 Air, Ace 68
   Turbo, Ace 68 GT, Jet 75, Zero 75X, Mix 87 are all in the same M-HUB family.
   Their PIDs differ; the interface role layout may not.
3. **What do RS / DKS / MT / TGL emit?** Only SOCD was characterised here. RS
   (deeper press wins) should produce the same bitmap; DKS and MT produce
   multiple actions per key and may use a different report id or length.
4. **Is there a second report id?** Only `0x01` was observed. Other ids may
   exist for lighting or configuration responses on the same interface.

## 7. Reporting this upstream

Worth doing, in rough order of impact:

* **MCHOSE** — support / Discord. The clean fix is for the firmware's interface
  2 descriptor to describe what it actually sends, or for those keys to be
  duplicated onto interface 0 like a normal keyboard.
* **Linux kernel** — `linux-input` mailing list, or a bugzilla entry. If the
  cause in §6.1 turns out to be a descriptor mismatch, a `HID_QUIRK_*` entry or
  a fixup in `hid-quirks.c` may be all that is needed.
* **This project** — issues and PRs welcome, especially captures from other
  MCHOSE models.
