//
// sdram_simple.sv -- minimal 128 MB SDRAM controller for the MiSTer
// XSDS dual-AS4C32M16SB expansion module, sized for 8-bit byte access.
//
// Replaces the N64-derived Components/SDRAM/sdram.sv and the
// Components/SDRAM/sdram_z80.sv wrapper after extensive debugging
// produced consistent column-swap behaviour that could not be
// explained or fixed without observability into the original
// controller's read-capture pipeline. This rewrite uses a single
// burst-length=1 transaction per access, an explicit state machine
// with no shift-register latency tracking, and explicit per-state
// tracing in the comments so the dataflow is auditable.
//
// SDRAM organization (per AS4C32M16SB datasheet):
//   - 4 banks x 8192 rows x 1024 cols x 16 bits = 64 MB per device
//   - Two devices on the XSDS board, total 128 MB
//
// Address decode (27-bit byte address):
//   addr[26]    = chip select  (drives SDRAM_nCS; 0 = device 0, 1 = device 1)
//   addr[25:13] = row     (13 bits, drives SDRAM_A during ACTIVE)
//   addr[12:11] = bank    (2 bits, drives SDRAM_BA)
//   addr[10:1]  = column  (10 bits, drives SDRAM_A[9:0] during READ/WRITE)
//   addr[0]     = byte-within-word (selects DQ[7:0] vs DQ[15:8])
//
// SDRAM_CLK is driven via altddio_out as ~clk so the SDRAM samples
// our outputs at clk's falling edge (half-cycle setup time).
//
// Single-port 8-bit interface:
//   req       = 1 to start a transaction (sampled in S_IDLE)
//   we_in     = 1 for write, 0 for read
//   addr      = 27-bit byte address
//   din       = 8-bit data in (for writes)
//   dout      = 8-bit data out (valid when ready=1, held until next ready)
//   ready     = pulses high for one clk cycle when transaction completes
//
// Clocking: clk is the system 50 MHz clk_sys. Refresh interval:
//   AS4C32M16SB requires 8192 rows refreshed in 64 ms = 7.81 us between
//   rows. At 50 MHz: 7.81e-6 * 50e6 = ~390 cycles between auto-refreshes.
//   We round to 380 for headroom and issue refresh to BOTH chips per
//   interval (one immediately after the other).
//

module sdram_simple
(
	input              clk,         // 50 MHz system clock
	input              reset,       // active high; triggers full init

	// SDRAM physical pins (passed through to sys_top.v)
	inout      [15:0]  SDRAM_DQ,
	output reg [12:0]  SDRAM_A,
	output reg         SDRAM_DQML,
	output reg         SDRAM_DQMH,
	output reg  [1:0]  SDRAM_BA,
	output reg         SDRAM_nCS,
	output reg         SDRAM_nWE,
	output reg         SDRAM_nRAS,
	output reg         SDRAM_nCAS,
	output reg         SDRAM_CKE,
	output             SDRAM_CLK,

	// 8-bit client interface
	input      [26:0]  addr,        // 27-bit byte address
	input       [7:0]  din,
	output reg  [7:0]  dout,
	input              we_in,       // 1 = write, 0 = read
	input              req,         // pulse high to start a transaction
	output reg         ready,       // one-cycle pulse on completion

	// Status outputs for debugging/LED indication
	output reg         init_done    // 1 once init is complete and we accept requests
);

// ---------------------------------------------------------------------
// SDRAM command encoding {SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE}.
// (SDRAM_nCS is driven separately by drive_cmd.)
// ---------------------------------------------------------------------
localparam CMD_NOP          = 3'b111;
localparam CMD_ACTIVE       = 3'b011;
localparam CMD_READ         = 3'b101;
localparam CMD_WRITE        = 3'b100;
localparam CMD_PRECHARGE    = 3'b010;
localparam CMD_AUTO_REFRESH = 3'b001;
localparam CMD_LOAD_MODE    = 3'b000;

// MODE register: CAS=2, BL=1, sequential burst, single-write.
// Bits: {reserved[12:10]=000, WB[9]=1 single-write, OPmode[8:7]=00,
//        CAS[6:4]=010, BT[3]=0 sequential, BL[2:0]=000 length 1}
localparam [12:0] MODE_REG = 13'b000_1_00_010_0_000;

// ---------------------------------------------------------------------
// Timing constants at 50 MHz (period = 20 ns).
// ---------------------------------------------------------------------
localparam [13:0] INIT_WAIT_CYCLES = 14'd10000;  // 200 us at 50 MHz
localparam [13:0] REFRESH_INTERVAL = 14'd380;    // ~7.6 us between refreshes

// ---------------------------------------------------------------------
// Address decode (combinational from input addr)
// ---------------------------------------------------------------------
wire        a_chip = addr[26];
wire [12:0] a_row  = addr[25:13];
wire  [1:0] a_bank = addr[12:11];
wire  [9:0] a_col  = addr[10:1];
wire        a_byte = addr[0];

// Latched copies of the request (captured when req=1 in S_IDLE)
reg         lat_chip;
reg  [12:0] lat_row;
reg   [1:0] lat_bank;
reg   [9:0] lat_col;
reg         lat_byte;
reg         lat_we;
reg   [7:0] lat_din;

// ---------------------------------------------------------------------
// SDRAM_CLK: inverted clk via altddio_out so SDRAM samples on its
// rising edge halfway through our clk cycle.
// ---------------------------------------------------------------------
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

// ---------------------------------------------------------------------
// DQ tristate. We drive DQ during writes; otherwise tristate so the
// SDRAM can drive it during reads.
// ---------------------------------------------------------------------
reg  [15:0] dq_drive;
reg         dq_oe;
assign SDRAM_DQ = dq_oe ? dq_drive : 16'bZ;

// ---------------------------------------------------------------------
// State machine
// ---------------------------------------------------------------------
localparam [4:0]
	S_INIT_WAIT    = 5'd0,
	S_INIT_PRE     = 5'd1,
	S_INIT_PRE_W   = 5'd2,
	S_INIT_REF1    = 5'd3,
	S_INIT_REF1_W  = 5'd4,
	S_INIT_REF2    = 5'd5,
	S_INIT_REF2_W  = 5'd6,
	S_INIT_MODE    = 5'd7,
	S_INIT_MODE_W  = 5'd8,
	S_IDLE         = 5'd9,
	S_ACTIVE       = 5'd10,
	S_ACTIVE_W     = 5'd11,
	S_READ_CMD     = 5'd12,
	S_READ_W1      = 5'd13,
	S_READ_W2      = 5'd14,
	S_READ_W3      = 5'd15,  // wait one more cycle for FPGA input register to settle
	S_READ_CAP     = 5'd16,
	S_WRITE_CMD    = 5'd17,
	S_WRITE_W      = 5'd18,
	S_REFRESH0     = 5'd19,
	S_REFRESH0_W   = 5'd20,
	S_REFRESH1     = 5'd21,
	S_REFRESH1_W   = 5'd22,
	S_WAIT_REQ_LOW = 5'd23;

reg  [4:0]  state;
reg  [13:0] timer;
reg  [13:0] refresh_count;
reg         init_chip;      // 0 -> 1 during init
reg  [15:0] dq_sample;

// ---------------------------------------------------------------------
// Combinational defaults for SDRAM pins.
// Each state below overrides these explicitly when it needs to drive a
// command or modify A/BA/DQM. By default we hold NOP with nCS=1 (chip
// deselected). nCS = 1 means BOTH chips are deselected on the XSDS
// board (since chip 1's nCS is the inverse of FPGA SDRAM_nCS, but the
// CMD pins being NOP make any spurious activity a no-op anyway).
// ---------------------------------------------------------------------

always @(posedge clk) begin
	// Per-cycle defaults
	{SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE} <= CMD_NOP;
	SDRAM_nCS  <= 1'b1;
	dq_oe      <= 1'b0;
	SDRAM_DQML <= 1'b0;
	SDRAM_DQMH <= 1'b0;
	SDRAM_CKE  <= 1'b1;
	ready      <= 1'b0;

	if (reset) begin
		state         <= S_INIT_WAIT;
		timer         <= INIT_WAIT_CYCLES;
		refresh_count <= REFRESH_INTERVAL;
		init_chip     <= 1'b0;
		init_done     <= 1'b0;
		SDRAM_CKE     <= 1'b0;  // hold low during very early reset
		SDRAM_A       <= 13'd0;
		SDRAM_BA      <= 2'b00;
		dout          <= 8'h00;
	end else begin

		// Refresh interval counter -- runs only once init is done
		if (init_done && refresh_count > 0)
			refresh_count <= refresh_count - 1'b1;

		case (state)

		// =================== INIT SEQUENCE ===================

		S_INIT_WAIT: begin
			SDRAM_CKE <= 1'b1;
			if (timer == 0) begin
				state <= S_INIT_PRE;
			end else begin
				timer <= timer - 1'b1;
			end
		end

		S_INIT_PRE: begin
			// PRECHARGE ALL banks on init_chip
			{SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE} <= CMD_PRECHARGE;
			SDRAM_nCS   <= init_chip;
			SDRAM_A[10] <= 1'b1;   // PRECHARGE ALL
			SDRAM_BA    <= 2'b00;
			timer       <= 14'd5;
			state       <= S_INIT_PRE_W;
		end
		S_INIT_PRE_W: begin
			if (timer == 0) state <= S_INIT_REF1;
			else timer <= timer - 1'b1;
		end

		S_INIT_REF1: begin
			{SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE} <= CMD_AUTO_REFRESH;
			SDRAM_nCS <= init_chip;
			timer     <= 14'd10;
			state     <= S_INIT_REF1_W;
		end
		S_INIT_REF1_W: begin
			if (timer == 0) state <= S_INIT_REF2;
			else timer <= timer - 1'b1;
		end

		S_INIT_REF2: begin
			{SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE} <= CMD_AUTO_REFRESH;
			SDRAM_nCS <= init_chip;
			timer     <= 14'd10;
			state     <= S_INIT_REF2_W;
		end
		S_INIT_REF2_W: begin
			if (timer == 0) state <= S_INIT_MODE;
			else timer <= timer - 1'b1;
		end

		S_INIT_MODE: begin
			{SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE} <= CMD_LOAD_MODE;
			SDRAM_nCS <= init_chip;
			SDRAM_A   <= MODE_REG;
			SDRAM_BA  <= 2'b00;
			timer     <= 14'd5;
			state     <= S_INIT_MODE_W;
		end
		S_INIT_MODE_W: begin
			if (timer == 0) begin
				if (init_chip == 1'b0) begin
					// repeat init for chip 1
					init_chip <= 1'b1;
					state     <= S_INIT_PRE;
				end else begin
					// init complete
					init_done <= 1'b1;
					state     <= S_IDLE;
				end
			end else timer <= timer - 1'b1;
		end

		// =================== NORMAL OPERATION ===================

		S_IDLE: begin
			if (refresh_count == 0) begin
				refresh_count <= REFRESH_INTERVAL;
				state         <= S_REFRESH0;
			end else if (req) begin
				// Latch the request
				lat_chip <= a_chip;
				lat_row  <= a_row;
				lat_bank <= a_bank;
				lat_col  <= a_col;
				lat_byte <= a_byte;
				lat_we   <= we_in;
				lat_din  <= din;
				// Issue ACTIVE
				{SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE} <= CMD_ACTIVE;
				SDRAM_nCS <= a_chip;
				SDRAM_A   <= a_row;
				SDRAM_BA  <= a_bank;
				timer     <= 14'd2;     // tRCD: ACTIVE -> CMD
				state     <= S_ACTIVE_W;
			end
		end

		S_ACTIVE_W: begin
			if (timer == 0) begin
				if (lat_we) state <= S_WRITE_CMD;
				else        state <= S_READ_CMD;
			end else timer <= timer - 1'b1;
		end

		// ---------- READ ----------
		S_READ_CMD: begin
			{SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE} <= CMD_READ;
			SDRAM_nCS <= lat_chip;
			// A[10]=1 -> auto-precharge after read
			SDRAM_A   <= {3'b001, lat_col};
			SDRAM_BA  <= lat_bank;
			SDRAM_DQML <= 1'b0;
			SDRAM_DQMH <= 1'b0;
			state <= S_READ_W1;
		end
		// Read timing with CAS_LATENCY=2 and inverted SDRAM_CLK:
		//   Cycle 0 (S_READ_CMD): FPGA drives CMD_READ on bus
		//   Cycle 1 (S_READ_W1):  SDRAM has sampled CMD_READ at mid-0;
		//                         no data on DQ this cycle
		//   Cycle 2 (S_READ_W2):  still no data on DQ (CAS-1)
		//   Cycle 3 (S_READ_W3):  SDRAM drives DQ from mid-2 onwards;
		//                         at end of this cycle, dq_sample captures it
		//   Cycle 4 (S_READ_CAP): dq_sample is stable, select byte, pulse ready
		S_READ_W1: state <= S_READ_W2;
		S_READ_W2: state <= S_READ_W3;
		S_READ_W3: begin
			dq_sample <= SDRAM_DQ;
			state     <= S_READ_CAP;
		end
		S_READ_CAP: begin
			dout  <= lat_byte ? dq_sample[15:8] : dq_sample[7:0];
			ready <= 1'b1;
			state <= S_WAIT_REQ_LOW;
		end

		// ---------- WRITE ----------
		S_WRITE_CMD: begin
			{SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE} <= CMD_WRITE;
			SDRAM_nCS <= lat_chip;
			// A[10]=1 -> auto-precharge after write
			SDRAM_A   <= {3'b001, lat_col};
			SDRAM_BA  <= lat_bank;
			// DQM: 0 = enabled, 1 = masked
			//   lat_byte=0 (even/low byte) -> DQML=0, DQMH=1
			//   lat_byte=1 (odd/high byte) -> DQML=1, DQMH=0
			SDRAM_DQML <= lat_byte;
			SDRAM_DQMH <= ~lat_byte;
			// Replicate the byte on both halves; DQM picks one.
			dq_drive  <= {lat_din, lat_din};
			dq_oe     <= 1'b1;
			timer     <= 14'd2;     // tWR + tRP for auto-precharge
			state     <= S_WRITE_W;
		end
		S_WRITE_W: begin
			if (timer == 0) begin
				ready <= 1'b1;
				state <= S_WAIT_REQ_LOW;
			end else timer <= timer - 1'b1;
		end

		// Hold here until the upstream FSM has dropped req. This
		// prevents firing a second transaction while the same Z-80
		// bus cycle is still in progress.
		S_WAIT_REQ_LOW: begin
			if (!req) state <= S_IDLE;
		end

		// ---------- REFRESH ----------
		// Issue AUTO_REFRESH to chip 0, wait, then chip 1, wait,
		// then return to IDLE. Both chips get refreshed per interval.
		S_REFRESH0: begin
			{SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE} <= CMD_AUTO_REFRESH;
			SDRAM_nCS <= 1'b0;       // chip 0
			timer     <= 14'd8;      // tRFC ~ 60ns + margin
			state     <= S_REFRESH0_W;
		end
		S_REFRESH0_W: begin
			if (timer == 0) state <= S_REFRESH1;
			else timer <= timer - 1'b1;
		end
		S_REFRESH1: begin
			{SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE} <= CMD_AUTO_REFRESH;
			SDRAM_nCS <= 1'b1;       // chip 1
			timer     <= 14'd8;
			state     <= S_REFRESH1_W;
		end
		S_REFRESH1_W: begin
			if (timer == 0) state <= S_IDLE;
			else timer <= timer - 1'b1;
		end

		default: state <= S_IDLE;
		endcase
	end
end

endmodule
