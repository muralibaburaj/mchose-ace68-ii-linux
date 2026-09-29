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

Confirmed working through the bridge so far: **SOCD** and **RS** — both resolve
to a single bit per pair, which is exactly what the bitmap in §3 carries — plus
hotplug (unplugging while a key is held releases it cleanly, and reconnecting
restores the keys). Everything below is still open.

Anyone picking this up should start here:

1. **Why does the kernel drop the report?** Compare the report descriptor's
   declared report id/size/count for the keyboard collection on interface 2
   against the 16-byte frame the device actually sends. If it is a simple
   mismatch, a HID quirk or a small `hid-mchose` driver would fix this for
   everyone, with no userspace daemon needed.
2. **Do other MCHOSE models behave the same?** Ace 60, Ace 68 Air, Ace 68
   Turbo, Ace 68 GT, Jet 75, Zero 75X, Mix 87 are all in the same M-HUB family.
   Their PIDs differ; the interface role layout may not.
3. **What do DKS / MT / TGL emit?** SOCD and RS are confirmed to use the report
   format in §3. DKS and MT produce multiple actions per key and may use a
   different report id or length. **MT is the most likely to fail**: mod-tap
   usually emits a *modifier* on hold, and modifiers are HID usages `0xE0–0xE7`,
   well outside the 15-byte bitmap, which stops at usage `0x77`. If MT does fail
   that is a format limitation of the device, not a bug in the bridge.
4. **Is there a second report id?** Only `0x01` was observed. Other ids may
   exist for lighting or configuration responses on the same interface.
5. **Do modifiers combine across interfaces?** Shift / Ctrl / Alt still arrive
   on interface 0 while advanced keys arrive on interface 2 — that is, from two
   *different* input devices. Holding Shift and pressing an advanced key bound
   to `1` should produce `!`. This is untested; it normally works because the
   compositor merges devices, but it is worth confirming.

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

## 8. Firmware quirks confirmed by testing

Both of the following were measured on hardware **and reproduced by MCHOSE's own
web driver (M-HUB)**. That second part matters: it means they are host-agnostic,
not Linux problems, not `mchose-adv` problems, and not something a driver can
work around. They will behave the same on Windows.

### 8.1 The advanced-key engine does not start on a fresh USB enumeration

After a cold boot or a replug, with a preset containing SOCD bound to `A`/`D` as
the **active** onboard profile, SOCD does not resolve. The keys still type,
because they fall back to the plain boot keyboard on **interface 0**:

```text
after replug, no profile switch:
  interface 2 : no A/D activity at all
  interface 0 : 87.287  ['A']
                88.338  ['A', 'D']   <-- both keys in ONE report, no arbitration
                89.099  ['A']

after switching profiles away and back:
  interface 2 bitmap decoded:
    58.747  A=X D=.   A
    59.351  A=. D=.   none     <-- A released...
    59.353  A=. D=X    D        <-- ...the instant D is pressed
    59.931  A=. D=.   none     <-- D released...
    59.932  A=X D=.   A        <-- ...and A returns (it was still held)
```

The second block is textbook last-input-wins — `A` and `D` are never set
together. The first is a raw 6-key boot report with no arbitration layer at all,
which is precisely why the keys still type while SOCD appears "broken".

**The engine starts on a profile *change*, never on the initial profile
*load*.** Cycling the onboard profile and returning to the same one restores it.

Host-side detection is impossible: interface 2 has no idle/keepalive stream
(0 reports in 20 s while untouched), so "engine off" and "nothing pressed" are
indistinguishable. USB autosuspend and a stale `hidraw` handle were both ruled
out — the device sits at `power/control=on`, and the bridge's file descriptor
inode matches the live node.

### 8.2 Macros also emit on interface 2

Macros are authored in the **Key Remap** tab, but they are transmitted the same
way as advanced keys — on interface 2, not duplicated to interface 0. Measured
while holding a macro key bound to spam `K`:

```text
5  manual K presses  -> interface 0   (native)
40 macro K presses   -> interface 2   (only the bridge sees these)
raw HID: 5 K-reports on if0, 95 on if2
```

So **on Linux a MCHOSE macro only works while `mchose-adv` is running.** On a
stock system it is entirely invisible.

This also means a macro cannot be an MT (mod-tap) hold or tap action: the MT
catalogue offers keys only, and assigning a macro in Key Remap *replaces* the
key rather than leaving a keycode for an advanced key to reference.

### 8.3 Macro timing — watch the release window

Game input is typically sampled per tick or per frame — 8.3 ms at 120 Hz. A
macro that reproduces a working input pattern at the same *rate* can still fail
if its release window is shorter than one sample:

```text
before:  cycle 93.8-94.2 ms   hold 88.5 ms   RELEASE GAP  3.9-4.2 ms   sub-tick
 after:  cycle 89.9-90.1 ms   hold 45.0 ms   RELEASE GAP 44.9-45.1 ms   works
```

With a sub-tick release the key-up is never reliably observed, so the consumer
never sees a *new* press — anything the macro is meant to drive repeatedly will
not start, or will fire at the wrong moment. Any release window of roughly
15 ms or more is safe.

### 8.4 Macro execution flushes the advanced-key report

Running a macro disturbs any key bound to an advanced-key function (SOCD, RS,
DKS, MT, TGL) that is **physically held at the same time** — regardless of what
the macro emits, and regardless of how it loops.

With such a key held while a macro runs and is then released:

```text
   58.7  if2   [W]            <- held advanced key, present in the bitmap
   ...
  370.3  MOUSE DOWN M2         <- the macro's own output
  370.4  if2   [idle]          <- macro engine goes idle -> all-clear frame
  370.4  bridge UP   W         <- the bridge correctly applies it
         (no further frame ever contains W)
```

The all-clear frame drops the held key from the report. Because the firmware's
own key state has not changed, it never re-asserts it, and the two sides
**desynchronise permanently**: the firmware believes the key is down, the host
believes it is up. That key stops being reported until it is physically released
and pressed again. Any state change on it restores the link — including pressing
its opposing pair partner, which the SOCD engine resolves into a fresh frame.

Crucially, the flush is **global to the macro engine**, not specific to one
report. Three different macro outputs were measured, with identical results:

| macro output                        | held advanced key survives |
| ----------------------------------- | -------------------------- |
| keyboard key                        | no                         |
| mouse button                        | no                         |
| a sequence including the held key   | no                         |

The mouse-button case is the informative one: its output travels on the *mouse*
collection, which Linux delivers natively with no bridge involved, while the
keyboard bitmap was still cleared. So the engine rewrites the keyboard report on
every idle whatever the macro produces — it is not a per-report effect, and it
cannot be side-stepped by changing the macro's output type.

**There is no firmware-side configuration that avoids this.** A host-side macro
(evdev level, uinput output) avoids it completely, because it produces no
interface-2 frames and therefore has nothing to flush. See §8.2 for why a macro
cannot simply be moved to a different report.

**Workaround:** after releasing the macro, tap and release each advanced key
that was being held, to force the firmware to re-emit its state.
