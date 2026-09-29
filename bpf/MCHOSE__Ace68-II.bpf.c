// SPDX-License-Identifier: GPL-2.0-only
/* Ace68-II interface 2 (41e4:2116): the report with ID 1 is a 120-bit
 * keyboard bitmap, but the device describes it as Input(Array) rather than
 * Input(Variable). Change only that field; never touch the boot keyboard or
 * configuration interface. Based on the in-tree Trust__Philips-SPK6327 fix.
 *
 * EXPERIMENTAL: not yet attached to physical hardware.
 */
#include "vmlinux.h"
#include "hid_bpf.h"
#include "hid_bpf_helpers.h"
#include <bpf/bpf_tracing.h>

#define ACE68_II_RDESC_SIZE 163
#define INPUT_FLAGS_OFFSET 23

HID_BPF_CONFIG(
	HID_DEVICE(BUS_USB, HID_GROUP_GENERIC, 0x41e4, 0x2116)
);

static __always_inline int is_ace68_ii_advanced_rdesc(const __u8 *rdesc)
{
	/* The three HID interfaces share the same USB ID. Match the report-1
	 * keyboard bitmap's complete 24-byte prefix, not just the USB ID. */
	return rdesc[0] == 0x05 && rdesc[1] == 0x01 &&
	       rdesc[2] == 0x09 && rdesc[3] == 0x06 &&
	       rdesc[4] == 0xa1 && rdesc[5] == 0x01 &&
	       rdesc[6] == 0x85 && rdesc[7] == 0x01 &&
	       rdesc[8] == 0x05 && rdesc[9] == 0x07 &&
	       rdesc[10] == 0x19 && rdesc[11] == 0x00 &&
	       rdesc[12] == 0x29 && rdesc[13] == 0x7c &&
	       rdesc[14] == 0x15 && rdesc[15] == 0x00 &&
	       rdesc[16] == 0x25 && rdesc[17] == 0x01 &&
	       rdesc[18] == 0x95 && rdesc[19] == 0x78 &&
	       rdesc[20] == 0x75 && rdesc[21] == 0x01 &&
	       rdesc[22] == 0x81 && rdesc[23] == 0x00;
}

SEC(HID_BPF_RDESC_FIXUP)
int BPF_PROG(ace68_ii_fix_rdesc, struct hid_bpf_ctx *hctx)
{
	__u8 *data;

	if (hctx->size != ACE68_II_RDESC_SIZE)
		return 0;
	data = hid_bpf_get_data(hctx, 0, HID_MAX_DESCRIPTOR_SIZE);
	if (data && is_ace68_ii_advanced_rdesc(data))
		data[INPUT_FLAGS_OFFSET] = 0x02; /* Data, Variable, Absolute */
	return 0;
}

HID_BPF_OPS(ace68_ii) = {
	.hid_rdesc_fixup = (void *)ace68_ii_fix_rdesc,
};

SEC("syscall")
int probe(struct hid_bpf_probe_args *ctx)
{
	/* Reject a firmware update with a changed descriptor, and both of the
	 * other interfaces, instead of applying a possibly incorrect fix. */
	ctx->retval = -EINVAL;
	if (ctx->rdesc_size == ACE68_II_RDESC_SIZE &&
	    is_ace68_ii_advanced_rdesc(ctx->rdesc))
		ctx->retval = 0;
	return 0;
}

char _license[] SEC("license") = "GPL";
