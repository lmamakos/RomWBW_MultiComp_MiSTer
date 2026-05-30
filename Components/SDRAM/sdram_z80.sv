//
// sdram_z80.sv
//
// 8-bit byte-addressed wrapper around the MiSTer 128 MB dual-chip SDRAM
// controller (Components/SDRAM/sdram.sv). Presents a simple
//
//     addr / din / dout / we / rd / ready
//
// interface intended for an 8-bit CPU client (the Z-80, eventually via the
// MMU). Internally the wrapper drives the controller's 32-bit ch1 channel
// because that channel supports per-byte enables (ch1_be) which is what we
// need for clean 8-bit writes; ch2/ch3 are tied off and unused.
//
// A burst write on ch1 issues two 16-bit beats with auto-precharge on the
// second beat. We arrange the byte enables so that only the byte at the
// requested address is actually written; the second beat is fully masked
// and harmless. For reads we take the addressed byte out of ch1_dout's
// first 16-bit beat.
//
// SDRAM_CLK is generated locally with altddio_out, mirroring `clk` so the
// SDRAM sees a clock edge aligned with the FPGA's data drive cycle. The
// upstream sdram.sv has its own DDR clock-out block commented out for
// exactly this reason: it expects the integrator to provide the clock.
//
// Phase 1 use: this wrapper is instantiated with no client connected
// (we=rd=0). It serves only to put the SDRAM into a refreshed, operational
// state so that hardware bring-up of the controller and pin assignments
// can be verified independently of the MMU. Phase 2 will wire the MMU's
// physical address bus to {addr,we,rd,din} and consume dout/ready.
//
// Clock note: initial bring-up runs at the existing clk_sys (50 MHz). The
// AS4C32M16SB timing constants in sdram.sv are sized for 64-100 MHz; at
// 50 MHz tRP/tRFC/tRCD all comfortably hold and CAS_LATENCY=2 is safe.
// We can move to a dedicated 100 MHz SDRAM clock later (requires PLL
// regeneration via MegaWizard).
//
// Copyright (c) 2026 - GPLv3 (matches the upstream sdram.sv).
//

module sdram_z80
(
	input             init,         // pulse to (re)initialize the SDRAM
	input             clk,          // SDRAM clock (drives controller + DDR clock out)

	// SDRAM physical pins (pass-through to MultiComp.sv/sys_top.v)
	inout      [15:0] SDRAM_DQ,
	output     [12:0] SDRAM_A,
	output            SDRAM_DQML,
	output            SDRAM_DQMH,
	output      [1:0] SDRAM_BA,
	output            SDRAM_nCS,
	output            SDRAM_nWE,
	output            SDRAM_nRAS,
	output            SDRAM_nCAS,
	output            SDRAM_CKE,
	output            SDRAM_CLK,

	// 8-bit client interface (byte address, byte data)
	input      [26:0] addr,         // 27-bit byte address (128 MB)
	input       [7:0] din,
	output      [7:0] dout,
	input             we,           // assert with addr/din to request a write
	input             rd,           // assert with addr to request a read
	output            ready         // pulses when the access completes
);

// -----------------------------------------------------------------------
// Single client uses ch1. We translate a byte address into the controller's
// 16-bit-word address by clearing bit 0 (the controller requires addr[0]=0
// for 16-bit-mode operation per its header comment) and use the original
// addr[0] to pick the byte within the 16-bit word for byte_en / readback.
// -----------------------------------------------------------------------

wire        ch1_req  = we | rd;
wire        ch1_rnw  = rd;        // 1 = read, 0 = write
wire [26:0] ch1_addr = {addr[26:1], 1'b0};

// Byte enable layout (4 bits, low byte first beat, high byte second beat).
// First beat covers the addressed 16-bit word at addr[26:1]; second beat
// (auto-precharge to addr[0]=1 within the same row) we want fully masked.
//   addr[0]==0 -> write low byte only:  ch1_be = 4'b0001
//   addr[0]==1 -> write high byte only: ch1_be = 4'b0010
wire [3:0] ch1_be = we ? (addr[0] ? 4'b0010 : 4'b0001) : 4'b0000;

// For 8-bit writes we replicate the byte into both halves of the 32-bit
// din. Only the byte selected by ch1_be will actually be driven onto DQ.
wire [31:0] ch1_din = {din, din, din, din};

wire [31:0] ch1_dout;
wire        ch1_ready;
wire        ch1_reqprocessed;

// Read data: take the byte from the first 16-bit beat of ch1_dout based
// on addr[0]. The second beat (ch1_dout[31:16]) is discarded.
assign dout  = addr[0] ? ch1_dout[15:8] : ch1_dout[7:0];
assign ready = ch1_ready;

// -----------------------------------------------------------------------
// Instantiate the 128 MB SDRAM controller. ch2/ch3 are tied off (no
// request, zero address/data) so they cost only the input registers
// inside the controller.
// -----------------------------------------------------------------------
sdram sdram_ctrl
(
	.init    (init),
	.clk     (clk),

	.SDRAM_DQ   (SDRAM_DQ),
	.SDRAM_A    (SDRAM_A),
	.SDRAM_DQML (SDRAM_DQML),
	.SDRAM_DQMH (SDRAM_DQMH),
	.SDRAM_BA   (SDRAM_BA),
	.SDRAM_nCS  (SDRAM_nCS),
	.SDRAM_nWE  (SDRAM_nWE),
	.SDRAM_nRAS (SDRAM_nRAS),
	.SDRAM_nCAS (SDRAM_nCAS),
	.SDRAM_CKE  (SDRAM_CKE),

	// ch1: 8-bit Z-80 client (via this wrapper)
	.ch1_addr         (ch1_addr),
	.ch1_dout         (ch1_dout),
	.ch1_din          (ch1_din),
	.ch1_req          (ch1_req),
	.ch1_rnw          (ch1_rnw),
	.ch1_be           (ch1_be),
	.ch1_ready        (ch1_ready),
	.ch1_reqprocessed (ch1_reqprocessed),

	// ch2: unused, tied off
	.ch2_addr (27'd0),
	.ch2_dout (),
	.ch2_din  (32'd0),
	.ch2_req  (1'b0),
	.ch2_rnw  (1'b1),
	.ch2_ready(),

	// ch3: unused, tied off
	.ch3_addr (27'd0),
	.ch3_dout (),
	.ch3_din  (16'd0),
	.ch3_req  (1'b0),
	.ch3_rnw  (1'b1),
	.ch3_ready()
);

// -----------------------------------------------------------------------
// DDR clock output: mirror `clk` to SDRAM_CLK. This matches the pattern
// used by the bundled MiSTer SDRAM controllers and gives a well-defined
// phase relationship between the FPGA-driven control/data signals and
// the SDRAM's sampling edge.
// -----------------------------------------------------------------------
altddio_out
#(
	.extend_oe_disable("OFF"),
	.intended_device_family("Cyclone V"),
	.invert_output("OFF"),
	.lpm_hint("UNUSED"),
	.lpm_type("altddio_out"),
	.oe_reg("UNREGISTERED"),
	.power_up_high("OFF"),
	.width(1)
)
sdramclk_ddr
(
	.datain_h    (1'b0),
	.datain_l    (1'b1),
	.outclock    (clk),
	.dataout     (SDRAM_CLK),
	.aclr        (1'b0),
	.aset        (1'b0),
	.oe          (1'b1),
	.outclocken  (1'b1),
	.sclr        (1'b0),
	.sset        (1'b0)
);

endmodule
