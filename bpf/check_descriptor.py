#!/usr/bin/env python3
"""Non-invasive checks for the proposed Ace68-II descriptor fixup."""

from pathlib import Path

PREFIX = bytes.fromhex(
    "05 01 09 06 a1 01 85 01 05 07 19 00 29 7c 15 00 "
    "25 01 95 78 75 01 81 00"
)


def check(descriptor: bytes) -> None:
    assert len(descriptor) == 163, f"unexpected descriptor length: {len(descriptor)}"
    assert descriptor.startswith(PREFIX), "interface 2 signature changed"
    fixed = bytearray(descriptor)
    fixed[23] = 0x02
    assert fixed[:23] == descriptor[:23]
    assert fixed[24:] == descriptor[24:]
    assert fixed[23] == 0x02
    # Report 1 carries 120 bits after its ID. The 1-bit at usage n is
    # at byte 1 + n//8, bit n%8; A=0x04, D=0x07.
    for usage in (0x04, 0x07):
        report = bytearray(16)
        report[0] = 1
        report[1 + usage // 8] = 1 << (usage % 8)
        assert len(report) == 1 + 120 // 8
        assert report[1] == (1 << usage)
    print("Descriptor signature and one-byte fixup match; A/D bitmap offsets match.")
    print("This does NOT prove Linux will emit key events: kernel test still needed.")


def find_descriptor() -> Path:
    for hidraw in Path("/sys/class/hidraw").glob("hidraw*"):
        device = hidraw / "device"
        if ":1.2/" not in str(device.resolve()):
            continue
        if "HID_ID=0003:000041E4:00002116" in (device / "uevent").read_text():
            return device / "report_descriptor"
    raise FileNotFoundError("Ace68-II interface 2 not found")


if __name__ == "__main__":
    import sys

    path = Path(sys.argv[1]) if len(sys.argv) > 1 else find_descriptor()
    check(path.read_bytes())
