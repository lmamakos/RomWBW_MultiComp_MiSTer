# Feature and capability Requirements

## Background

The existing repository starts as a port of Grant Searle's "MultiComp"
project, with multiple 8 bit CPUs (Z-80, 6800, 6502, 6809) that was ported
to run on the MiSTer FPGA game emulator platform.  The MiSTer project is
based on a Cyclone V FPGA with added SDRAM memory.

The overall goal of this project to host the RomWBW Z-80/Z-180 software
platform that includes CP/M 2.2, CP/M 3.0, and related 8 bit operating
systems to run on the MiSTer hardware.   The work here started with
modifying the MiSTer HDL code to be suitable for RomWBW.  There will also
be work done at a later time to add or modify the HBIOS in RomWBW to target
the Z-80 computer system and peripherals implemented in the FPGA.

## Features and Requirements

### MMU changes

Modify the MMU VHDL (in `Components/alancox/MMU.vhd`) to implement 4 x 16
KByte pages, rather than the 16 x 4K pages that are in that module.
Initially the MMU shall handle 4 MBytes of physical address space, which
makes each of the 4 mapping registers 8 bits wide (8 bit page-number
extension + 14 bits of in-page logical address = 22 bits of physical
address, with the upper 2 bits of the CPU logical address selecting one of
the 4 mapping registers).

The MMU's mapping-register I/O interface shall be compatible with the
"Z2" MMU commonly used by RomWBW systems: the 4 mapping registers shall
appear as 4 consecutive 8-bit I/O ports that directly back the registers,
with no selector mux. These 4 ports shall sit at the start of the MMU's
decoded I/O window, aligned on a multiple-of-4 boundary.

The MMU shall also expose 4 additional I/O ports immediately following
the Z2-compatible ports, which can be used to write the *next* 8 bits of
each mapping register should the physical address space later be widened
beyond 4 MBytes. The width of the mapping registers (and therefore of the
physical address bus) shall be parameterizable so this widening can be
opted into without further source edits to the MMU. When the parameter is
set to the default value (8-bit mapping registers / 4 MBytes physical),
these extension ports shall read as 0 and ignore writes.

Per-frame read/write/execute permission bits are not required and shall be
removed.

The MMU shall retain a "direct access" capability (previously called the
"17th page" in the socz80 source) that allows code to read or write
physical memory directly through an I/O port without remapping any of the
4 logical pages. This is useful for copying data between banks without
disturbing the current mapping. The direct-access mechanism shall consist
of:

- A pointer register sized to match the physical address bus, programmed
  through dedicated I/O ports (little-endian: low byte at the lowest
  offset).
- A separate I/O port whose read or write the MMU rewrites into a physical
  memory read or write at the pointer address.
- Automatic post-increment of the pointer after each access, so block I/O
  instructions can walk forward through physical memory.

All MMU I/O port decoding shall be relative to an external chip-select
signal (`io_cs`), so the placement of the MMU's I/O window within the Z80
I/O address space is decided by the external decoder rather than baked
into the MMU.

### Implement MMU

We need to implement the MMU in the system design, rather than directly
accessing memory.

### Implement SDRAM

Use the 128 Mbytes of SDRAM (XSDS dual-AS4C32M16SB module, two 64 MB
parts wired in parallel on a shared bus with the second physical chip
select derived from board-side logic) for additional Z-80 system memory
beyond the existing 64 KB of FPGA block RAM.

Initial physical memory layout target:

| Physical address | Contents |
|---|---|
| `0x0000_0000 – 0x0000_FFFF` | Existing 64 KB FPGA block RAM (unchanged) |
| `0x0001_0000 – 0x07FF_FFFF` | 128 MB SDRAM (minus the bottom 64 KB which is shadowed by block RAM) |

This lets the system continue booting from the proven block-RAM image
while exposing SDRAM for testing. The MMU will eventually be inserted
between the Z-80 and this layout; until it is, the SDRAM controller runs
idle (no client) so that init/refresh of the parts can be verified
independently.

## I/O port map (reference)

A consolidated list of all I/O ports identified for use by this
project so far. The "Core" column shows which Z-80 wrapper(s)
currently decode the port (`CPM` = `MicrocomputerZ80CPM`,
`Basic` = `MicrocomputerZ80Basic`). Ports marked "planned" are
reserved by these requirements but not yet wired up in any wrapper.
Entries should be kept in sync with the `n_*CS` decodes in the
"CHIP SELECTS" section of each `Microcomputer*.vhd` wrapper.

| Port(s)       | Width  | Core(s)   | Function                                                                                                  |
|---------------|--------|-----------|-----------------------------------------------------------------------------------------------------------|
| `0x20`-`0x21` | 2      | CPM       | CH376S USB module (`n_ch376sCS`). `0x20` data, `0x21` command (per `cpuAddress(0)`).                      |
| `0x38`        | 1      | CPM       | ROM-disable trigger. Any write disables the boot ROM at `0x0000-0x1FFF` and exposes the RAM beneath it.   |
| `0x47`        | 1      | CPM       | Front-panel data latch (R/W). Software writes drive the 8-bit transparent capture chain; reads return the last-written value. |
| `0x80`-`0x81` | 2      | CPM, Basic| SBCTextDisplayRGB (`n_interface1CS`). VGA/PS-2 text display.                                              |
| `0x82`-`0x83` | 2      | CPM, Basic| bufferedUART (`n_interface2CS`). Serial console.                                                          |
| `0x88`-`0x8F` | 8      | CPM, Basic| SD card controller (`n_sdCardCS`). Register offset via `cpuAddress(2 downto 0)`.                          |
| `0xA0`-`0xA7` | 8      | CPM       | Front-panel subsystem control window (`n_fpSubsysCS`). See Front-panel I/O register map below.            |
| `0xB0`-`0xBF` | 16     | CPM       | MMU register window (`n_mmuCS`). 4 frame-mapping low bytes at `+0..+3` (Z2-compatible), 4 high bytes at `+4..+7`, direct-access pointer at `+8..+11` (little-endian), direct-access data port at `+12`. |

### Front-panel subsystem register map (within the `0xA0`-`0xA7` window)

Decoded by the `FrontPanel_Subsystem` block from `addr(2 downto 0)`
relative to `io_cs`. Offsets are shown against the current base of
`0xA0`; if the window is relocated later, software access addresses
shift accordingly.

| Port  | R/W | Function                                                                                                                                |
|-------|-----|-----------------------------------------------------------------------------------------------------------------------------------------|
| `0xA0`| R/W | Global brightness (0..255, 8-bit linear scale).                                                                                         |
| `0xA1`| R/W | Fade rate (step per refresh tick).                                                                                                      |
| `0xA2`| R/W | Global pointer (LED index used by `0xA3`, `0xA5`, `0xA6`).                                                                              |
| `0xA3`| W   | Colour stream. Six bytes per LED: on-G, on-R, on-B, off-G, off-R, off-B. The sixth byte auto-advances the global pointer.               |
| `0xA4`| R/W | Mode register. Bit 0: 0 = mirror capture chain, 1 = framebuffer.                                                                        |
| `0xA5`| R/W | Mapping-table entry at the global pointer. Both reads and writes auto-advance the pointer.                                              |
| `0xA6`| R/W | Framebuffer bit at the global pointer. Both reads and writes auto-advance the pointer.                                                  |
| `0xA7`| --  | Reserved (reads 0, writes ignored).                                                                                                     |

## Progress

### MMU rework (`Components/alancox/MMU.vhd`) — design complete, GHDL-verified, not yet in the build

The MMU source file has been rewritten in place to match the requirements
above. GHDL (`ghdl -a --std=08`) accepts the file with no errors.
Elaboration of the entity also passes. The file is not yet referenced from
either Quartus revision (no `.qsf` entries) and is not yet instantiated
anywhere in the system, so the build is unaffected by the change.

What the file now provides:

- **Page geometry**: 4 logical pages of 16 KB each. Top 2 bits of the
  16-bit CPU address select a mapping register; low 14 bits are the
  in-page offset.
- **Parameterizable physical address width**: VHDL generic
  `physical_page_bits` (default 8). With the default, the physical address
  bus (`address_out`) is 22 bits wide (4 MB). Larger values widen the bus
  and enable the extension I/O ports.
- **I/O register window** — 16 consecutive ports, decoded relative to
  `io_cs` on the low 4 address bits:

  | Offset | Function |
  |---|---|
  | +0..+3 | Frame 0..3 mapping register, bits 7:0 (Z2-compatible) |
  | +4..+7 | Frame 0..3 mapping register, bits 15:8 (extension; reads 0 / ignores writes when `physical_page_bits = 8`) |
  | +8..+11 | Direct-access pointer bytes, little-endian (low byte at +8) |
  | +12 | Direct-access data port (R/W triggers a physical memory cycle at the pointer; pointer post-increments after the access) |
  | +13..+15 | Reserved (reads 0, writes ignored) |

- **Direct-access window**: retained. Mechanism (address rewrite,
  `req_mem_out` forced high, `req_io_out` forced low, one-cycle `cpu_wait`
  pulse, pointer post-increment) is unchanged from the original socz80
  design, just relocated to port offset +12 and renamed.
- **Permissions removed**: the `can_read`/`can_write` record fields and
  the `access_violated` output port have been deleted.
- **Selector mux removed**: the old "write to port +0 to choose what
  ports +3..+7 mean" mechanism is gone; each register has its own port.
- **Reset map**: placeholder identity map (frame K -> physical page K for
  K = 0..3, direct-access pointer = 0). Marked in source as TODO to be
  revisited once the physical ROM/SDRAM layout is decided.

### SDRAM controller (`Components/SDRAM/sdram.sv` + `sdram_z80.sv`) — in the build, currently idle

The 128 MB dual-chip SDRAM controller from the MiSTer N64 core
(`MiSTer-devel/N64_MiSTer rtl/sdram.sv`, GPLv3, Sorgelig) has been adopted
verbatim as `Components/SDRAM/sdram.sv`. The pre-existing 32 MB controllers
that shipped in `Components/SDRAM/` (a single-port `sdram.sv` and a
multi-port `sdram.v`) are no longer suitable for the 128 MB module and
have been replaced/removed.

Key behaviour of the adopted controller:

- 27-bit byte address per channel, covering the full 128 MB.
- Drives the single FPGA `SDRAM_nCS` from an internal `chip` register;
  the XSDS board derives the two physical device chip-selects from that
  line plus board-side routing. The controller selects device 0 vs 1 by
  copying the top address bit (`chN_addr[26]`) into `chip` for each
  ACTIVE/READ/WRITE, and walks `chip` 0 -> 1 during init and refresh so
  both devices are configured and refreshed.
- Three channels: ch1 (32-bit + byte enables), ch2 (32-bit), ch3 (16-bit).

A thin 8-bit wrapper, `Components/SDRAM/sdram_z80.sv`, exposes a simple
`addr/din/dout/we/rd/ready` interface and uses the controller's ch1
channel (the only one with proper per-byte enables, allowing clean 8-bit
writes). ch2 and ch3 are tied off. The wrapper also drives `SDRAM_CLK`
via `altddio_out` since the controller intentionally leaves that to the
integrator.

The wrapper is instantiated in `MultiComp.sv` (replacing the previous
`assign {SDRAM_*} = 'Z;` tri-state at line 225). For this phase the
client side of the wrapper is held idle (`we = rd = 0`); the SDRAM is
therefore initialized and refreshed but not yet read or written by the
Z-80. The Z-80 still boots from the existing 64 KB FPGA block RAM as
before.

Both `MultiComp.qsf` and `MultiComp-lite.qsf` have been updated with
`SYSTEMVERILOG_FILE` entries for the two new files. The SDRAM controller
runs from the existing `clk_sys` (50 MHz from `rtl/pll.v`); the
AS4C32M16SB timing constants in the controller comfortably hold at this
frequency, so PLL regeneration is not required for first bring-up.

### Front-panel LED subsystem (`Components/FRONTPANEL/`) — wired into the CPM core for initial bring-up

The WS2812/SK6812-based blinkenlights front panel has been added to the
build of the Z-80 CPM core. Files are referenced from both
`MultiComp.qsf` and `MultiComp-lite.qsf`; the subsystem and capture
chain are instantiated in `MicrocomputerZ80CPM.vhd`.

Initial configuration:

- **I/O port 0x47** (`n_fpLatchCS`): 8-bit R/W latch. Software writes
  set the bit pattern displayed on the front panel; reads return the
  last-written value.
- **I/O ports 0xA0..0xA7** (`n_fpSubsysCS`): the `FrontPanel_Subsystem`
  8-port control window (brightness, fade rate, pointer, colour stream,
  mode, mapping table, framebuffer, reserved).
- **`Transparent_Capture_Chain` (8 bits wide)**: sources its
  `combined_data` from the port 0x47 latch and delivers it on the
  serial chain into `FrontPanel_Subsystem`.
- **NUM_LEDS = 16** for first bring-up. The default identity mapping
  (mapping.mif) maps LED i to chain bit i; with an 8-bit chain only
  LEDs 0..7 mirror the port-0x47 latch, while LEDs 8..15 mirror chain
  bit positions that have not been written and therefore stay at
  reset value (0 = off colour). Software can rewrite the mapping
  table at runtime to point any LED at any chain bit.
- **Refresh tick** generated locally at ~60 Hz from `clk` (50 MHz /
  833_333).
- **Physical output**: `MultiComp.sv` routes the WS2812 serial line
  through `USER_OUT[4]` of the MiSTer USER_IO port. The Basic core's
  matching pin is tied to `'0'` (no front panel in Basic mode for
  now); the existing cpu_type mux selects which core's signal reaches
  the pin.

### SDRAM controller replaced with `sdram_simple.sv`

The N64-derived `Components/SDRAM/sdram.sv` controller and its
`sdram_z80.sv` wrapper proved problematic for our use case. After
extensive debugging via BASIC test programs we observed:

- Writes consistently landed at the correct SDRAM cells.
- Reads consistently returned data from the "next" column instead of
  the addressed one (CMD_READ to col 0 returned col 1 data, etc.).
- A diagnostic 4-byte mux verified that both halves of `ch1_dout`
  ended up loaded with the same 16-bit value (the "other" column).
- Extending the controller's `data_ready_delay` shift register by
  one or two cycles had **zero effect** on what was captured,
  suggesting the bug was not the originally-suspected pipeline
  off-by-one.

Rather than continue with cycle-accurate observability (SignalTap)
on a third-party multi-channel controller, we rewrote the SDRAM
interface as a minimal, single-port, BURST_LENGTH=1 controller:
`Components/SDRAM/sdram_simple.sv`. Key properties:

- Single 8-bit byte-addressed port (`req` + `we_in` instead of
  separate `we`/`rd` strobes).
- 27-bit byte address, 128 MB capable. Address decode:
  `addr[26]` = chip, `addr[25:13]` = row, `addr[12:11]` = bank,
  `addr[10:1]` = column, `addr[0]` = byte-within-word.
- CAS=2, BURST_LENGTH=1 (no burst-ordering ambiguity).
- Explicit state machine with one state per logical step (no shift
  registers, no hidden pipeline stages).
- Dual-chip support via `SDRAM_nCS`: chip 0 selected with nCS=0,
  chip 1 selected with nCS=1 (assumes board-side inversion to
  derive the second device's CS).
- Init sequence walks both chips through PRECHARGE-all → 2x
  AUTO_REFRESH → LOAD_MODE.
- Refresh issued to both chips per refresh interval (~7.6 us).
- DDR clock output: SDRAM_CLK = ~clk via `altddio_out`
  (`datain_h=0, datain_l=1`), so SDRAM samples on its rising edge
  at our clk falling edge.
- Exposes `init_done` signal to indicate readiness.

The old `sdram.sv` and `sdram_z80.sv` files are retained in the
tree for reference but commented out of both `.qsf` files. The
upstream interface in `MultiComp.sv` adapts the CPM core's
`we`/`rd` strobes into `req`/`we_in` semantics; no change to the
CPM core's FSM was required.

`LED_USER` on the MiSTer board now indicates SDRAM init status:
solid on once `init_done` is asserted; otherwise reflects the
legacy `vsd_sel & sd_act` (virtual SD activity).

### SDRAM controller: ported CoCo3 `sdram_32r8w` (`Components/SDRAM/sdram2.sv`)

`sdram_simple.sv` worked for reads and aligned-byte writes but its
**byte-write masking (DQM) did not take effect in hardware**. The
disambiguation test wrote distinct values to the low byte (C000) and
high byte (C001) of the *same* 16-bit word:

```basic
20 POKE &HC000,&H11 : POKE &HC001,&H22
30 POKE &HC002,&H33 : POKE &HC003,&H44
```

and read back `34, 34, 68, 68` (deterministically) instead of
`17, 34, 51, 68`. That is: the high-byte write clobbered the whole
word — the DQML mask never protected the low byte. Re-analysis showed
the DQM/DQ/CMD were scheduled in the same FSM state (so they *should*
align), but the mask still did not engage in hardware. Rather than
keep chasing a half-cycle DQM timing issue, we abandoned `sdram_simple`.

We ported the SDRAM controller from the MiSTer **CoCo3** core
(`MiSTer-devel/CoCo3_MiSTer rtl/sdram/sdram2.sv`, module `sdram_32r8w`,
© Sorgelig / Stan Hodge), imported verbatim as
`Components/SDRAM/sdram2.sv`. It is written for **exactly** our board
(`Alliance AS4C32M16SB-7TIN (x2)`, 128 MB) and fixes byte writes with
a different, robust technique:

```verilog
assign {SDRAM_DQMH,SDRAM_DQML} = SDRAM_A[12:11]; // A12/A11 unused -> free for DQM
...
// fix byte writes [no new command until data is actually written]
if (~sdram_cpu_rnw)
  {cas_addr[12:9],SDRAM_BA,SDRAM_A,cas_addr[8:0]} <=
    {~sdram_cpu_addr[0], sdram_cpu_addr[0], 2'b10, sdram_cpu_addr[24:1]};
```

The DQM lanes are driven from the upper address-register bits, loaded
in the same register write as the column address. This guarantees the
mask is cycle-aligned with CAS. For `addr[0]=0` (even/low byte):
`{DQMH,DQML} = {1,0}` (write low, mask high); for `addr[0]=1`:
`{0,1}` (write high, mask low).

**Clock.** This controller runs at ~112 MHz (CAS_LATENCY=3, startup
timing assumes ~100 MHz), while the Z-80 CPM core's SDRAM client FSM
runs at 50 MHz (`clk_sys`). The controller derives the inverted
SDRAM chip clock internally via its own `altddio_out`, so only **one**
extra ~112 MHz clock (`clk_ram`) is needed.

> **PLL REGENERATION REQUIRED.** The current PLL (`rtl/pll.qip` →
> `rtl/pll/pll_0002.v`) only generates `outclk_0 = 50 MHz`
> (`number_of_clocks = 1`). It must be regenerated in MegaWizard to also
> expose `outclk_1 ≈ 112 MHz`. `MultiComp.sv` references `pll`'s
> `.outclk_1(clk_ram_112)`. The saved PLL parameter set in `rtl/pll.qip`
> already contains an `outclk_1 = 112 MHz` definition, so the
> multiply/divide is known-good. Per AGENTS.md, PLLs are generated IP and
> must be regenerated via MegaWizard rather than hand-edited.
> `derive_pll_clocks` in `sys/sys_top.sdc` will pick up the new clock
> automatically, and the existing clock-group constraint already covers
> `*|pll|pll_inst|...|divclk`.
>
> **What MegaWizard rewrites:** only files under `rtl/pll*` — `rtl/pll.v`
> (gains the `outclk_1` port), `rtl/pll.qip`/`.cmp`/`.ppf`/`.sip`/`.spd`,
> and `rtl/pll/pll_0002.*`. It does **not** modify `MultiComp.qsf`,
> `MultiComp-lite.qsf`, or `MultiComp.qpf`; the design references the PLL
> through the single `QIP_FILE rtl/pll.qip` line, which is unchanged.
> (Note: only `MultiComp.qsf` carries that `rtl/pll.qip` line;
> `MultiComp-lite.qsf` has no PLL reference at all — a pre-existing gap,
> left as-is for now.)
>
> **100 MHz fallback.** If 112 MHz fails timing closure on the SDRAM
> paths, build with the `SDRAM_CLK_100` Verilog define (uncomment the
> `` `define SDRAM_CLK_100 `` line in `MultiComp.sv`'s CLOCKS section). In
> that configuration `clk_ram` is driven by `outclk_2 ≈ 100 MHz`, and the
> PLL must be regenerated with **three** outputs (`outclk_0` = 50,
> `outclk_1` = 112, `outclk_2` = 100). With the define OFF (default) only
> two outputs (`outclk_0`, `outclk_1`) are required. The CoCo3
> `sdram_32r8w` controller is unchanged for either frequency: its refresh
> interval constant (890 cycles, tuned for ~114 MHz) merely refreshes
> slightly more often than necessary at 100 MHz, which is harmless. As an
> even simpler alternative, you may instead set `outclk_1` itself to
> 100 MHz and leave the define OFF — no third tap needed.

**Clock-domain crossing (in `MultiComp.sv`).** The CPM FSM asserts
`we`/`rd` and holds it stable until it sees `ready`. The adapter:
1. 2-FF-synchronizes the held request level (`we|rd`) into `clk_ram`.
2. On its rising edge, latches addr/din/direction and raises `ram_req`
   to the controller; holds `ram_req` until `sdram_cpu_ack`, then drops
   it (the controller's STATE_IDLE accepts only while `req & !ack`).
3. On `sdram_cpu_ready`, byte-selects `sdram_dout16` by `addr[0]` into
   `ram_byte` and toggles a `ram_done` completion level.
4. 2-FF-synchronizes `ram_done` back into `clk_sys` and edge-detects it
   to produce the single-cycle `sdram_ready_mux` pulse the CPM FSM
   expects. `sdram_dout_mux = ram_byte`.
Because the request level is held stable for the whole transaction,
simple 2-FF synchronizers are sufficient; the read data is stable
before the completion flag crosses domains.

**Address mapping.** The controller takes a 25-bit address with
`[0]` = byte-within-word and `[24:1]` = SDRAM word address. We pass the
CPM core's byte address truncated to 25 bits straight through
(`sdram_addr_mux[24:0]`), i.e. 32 MB addressable until the wider
mapping is wired. The video read port (`sdram_vid_*`) is tied off.

`LED_USER` now follows `~sdram_busy` (lit when the controller is idle /
init complete). `sdram_simple.sv`, `sdram.sv`, and `sdram_z80.sv` remain
in the tree but are commented out of both `.qsf` files.

### MMU + SDRAM integration into the CPM core — done

The MMU has been instantiated inside `MicrocomputerZ80CPM.vhd` between
the Z-80 and the memory subsystem, and the SDRAM controller's client
side is now driven from that same core. Both Quartus revisions have
been updated.

Plumbing summary:

- **MMU instantiation**: `mmu1 : entity work.MMU` with
  `physical_page_bits => 8` (22-bit / 4 MB physical address space,
  Z2-compatible). Reset is `not N_RESET` (MMU is active-high).
- **I/O window**: 16 ports at **`0xB0..0xBF`** (`n_mmuCS`). Inverted
  to active-high `mmu_io_cs` for the MMU's `io_cs` input.
- **CPU bus**: active-low Z-80 strobes are inverted into the MMU's
  active-high `req_mem_in / req_io_in / req_read / req_write`.
- **Block RAM rewiring**: `InternalRam64K` is now addressed by
  `mmu_phys_addr(15 downto 0)` (physical) instead of `cpuAddress`
  (logical). Its chip select fires when `phys_in_blockram = '1'`
  (i.e. `phys_addr(21:16) = "000000"`), regardless of the boot-ROM
  overlay; writes through the ROM-overlay region still silently
  update the underlying block RAM.
- **Boot ROM overlay**: unchanged — `Z80_CPM_BASIC_ROM` continues to
  win on the `cpuDataIn` mux at logical `0x0000..0x1FFF` while
  `n_RomActive = '0'`, ahead of the physical-memory sources. The MMU
  is invisible until the ROM unmaps itself.
- **MMU read-back**: `mmu_dataOut` is selected on the `cpuDataIn` mux
  when `mmu_io_cs = '1'` **except** for port `+12` (the direct-access
  data port), where the cycle has been promoted to a physical memory
  access and the data must come from the block RAM / SDRAM path.
- **SDRAM client FSM**: a three-state machine (`S_IDLE`, `S_REQ`,
  `S_DONE`) in `MicrocomputerZ80CPM.vhd` issues `we`/`rd` to the
  SDRAM wrapper when the MMU's `req_mem_out = '1'` and
  `phys_in_sdram = '1'`. The Z-80 is stalled via `wait_n` from
  `S_REQ` until the controller pulses `ready`; `sdram_dout` is
  latched into `sdramReadData` for the `cpuDataIn` mux. The FSM
  returns to `S_IDLE` after the CPU releases `MREQ`.
- **`wait_n` to the t80s core**: `cpu_wait_n = (not mmu_cpu_wait) and
  sdram_wait_n`. The MMU asserts its one-cycle wait pulse on
  direct-access cycles to give synchronous memory a beat to respond;
  the FSM holds it for as many beats as the SDRAM controller needs.
- **Top-level wiring** (`MultiComp.sv`): six new ports on the CPM
  core (`sdram_addr`, `sdram_din`, `sdram_we`, `sdram_rd`,
  `sdram_dout`, `sdram_ready`) are fed through per-CPU arrays
  mirroring the `_fpLED_serial` pattern. The mux on `cpu_type` picks
  the active set; `we`/`rd` are additionally masked by
  `(cpu_type == cpuZ80CPM)` so selecting the Basic core leaves the
  SDRAM idle. The previously idle `sdram_z80_inst` is now driven by
  these muxed signals (the `27'd0` / `1'b0` tie-offs are gone).

Reset map (unchanged from the MMU's placeholder): frames 0..3 map
identically to physical pages 0..3. With block RAM covering physical
0x000000..0x00FFFF, this means the Z-80's first 64 KB of logical
address space sees the same block RAM it did before — boot and CP/M
behaviour are preserved. Remapping frame 3 to physical page 4 (or
higher) is the canonical way to reach into SDRAM.

### Known issues (acknowledged, not blocking)

#### Pre-existing setup-timing violation in `SBCTextDisplayRGB`

After the MMU/SDRAM integration, Quartus reports a setup violation on
the system PLL output (`clk_sys`, 50 MHz):

- **Worst-case setup slack**: -2.359 ns
- **TNS (Total Negative Slack)**: -264.109 ns across ~20 paths
- **Failing clock**: `emu|pll|pll_inst|...|PLL_OUTPUT_COUNTER|divclk`
- **Fmax achieved**: 40.46 MHz (against 50 MHz constraint)

All failing paths are inside the legacy `SBCTextDisplayRGB` text-mode
video controller. Specifically:

- **From**: `SBCTextDisplayRGB:io1|startAddr[5..6]` — the scroll-offset
  register, updated in a `falling_edge(clk)` process (`Components/TERMINAL/SBCTextDisplayRGB.vhd:410`).
- **To**: `DisplayRam2K:\GEN_2KATTRAM:dispAttRam|...|porta_address_reg0`
  — the attribute RAM's port-A address input, clocked on the rising
  edge of `clk`.
- **Launch-to-latch budget**: 10 ns (half a 20 ns period, because the
  launch is on the falling edge and the latch is on the rising edge).
- **Combinational delay**: 12.138 ns through ~30 logic levels.

The combinational chain is dominated by `Mod0|auto_generated|divider`
— a synthesized restoring divider implementing the `mod
CHARS_PER_SCREEN` operation in this concurrent assignment at
`SBCTextDisplayRGB.vhd:401`:

```vhdl
dispAddr <= (startAddr + charHoriz + (charVert * HORIZ_CHARS)) mod CHARS_PER_SCREEN;
```

**This violation pre-dates the MMU work.** None of the failing-path
nodes touch the MMU, SDRAM client FSM, block RAM rewiring, or any
other recent additions; the path is wholly inside legacy code that
has been in the build since the initial commit. The pre-MMU baseline
(`f4d6ab2`) almost certainly fails timing in exactly the same way.

The bitstream still builds, loads, and the legacy core has been
working on real DE10-Nano silicon, which suggests the actual silicon
delay at the operating temperature is comfortably below the slow-1100mV-100C
timing-model worst case used for sign-off.

**Decision: ignore for now.** Possible future fixes if it ever causes
real-world misbehaviour:

1. Register `dispAddr` (or its inputs) in a synchronous process so
   the `mod` operation has a full clock period to settle.
2. Replace `mod CHARS_PER_SCREEN` with conditional subtraction
   (cheap since the sum naturally wraps near `CHARS_PER_SCREEN`).
3. Add a `set_multicycle_path` constraint covering this specific
   register-to-RAM path. Cannot be added to `sys/sys_top.sdc` (that
   file is externally maintained); would need a project-level SDC
   referenced from both `.qsf` files.

### Outstanding work toward the requirements above

1. **Hardware bring-up of the SDRAM controller**: compile in Quartus,
   load the bitstream, verify the SDRAM is being initialized and
   refreshed (the controller's `chip` toggling should be observable, and
   the parts should not enter their power-down/decay regime). With the
   MMU now wired in, a CPM program that remaps a frame to physical
   page >= 4 can read/write SDRAM and verify the data path end-to-end.
2. **Hardware bring-up of the front panel**: compile and load,
   confirm the WS2812 string lights up with the default identity map
   when software writes patterns to port 0x47, exercise the colour
   stream at port 0xA3 (six bytes per LED, on-G/R/B then off-G/R/B),
   confirm the brightness scaler at port 0xA0 dims/brightens, and
   confirm the framebuffer mode at port 0xA4 + 0xA6.
3. **Widen `physical_page_bits`** from 8 to 13 once SDRAM access is
   proven, to expose the full 128 MB of physical address space (the
   SDRAM controller already supports 27-bit addresses; the CPM core
   currently zero-extends the MMU's 22 bits to the controller's 27).
4. **Revisit the MMU reset map** once experience with SDRAM access
   suggests a better default than identity (e.g. frame 3 pointing
   into SDRAM as a default "high memory window").
5. **Expand the front-panel capture chain**: once the basic 8-bit
   chain proves out, add a wider `Transparent_Capture_Chain` (or a
   `Universal_Capture_Chain` with `STRETCH_MASK` set on a few control
   bits) sourced from CPU/MMU/SDRAM control signals to drive a real
   blinkenlights display.
6. **Optional**: move the SDRAM to a dedicated higher-frequency clock
   (e.g. 100 MHz from a regenerated PLL) once basic operation is proven.
