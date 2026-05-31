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
| _TBD_         | 16     | _planned_ | MMU register window (16 consecutive ports, aligned on a 16-port boundary). Base address not yet chosen.   |

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

### Outstanding work toward the requirements above

1. **Hardware bring-up of the SDRAM controller**: compile in Quartus,
   load the bitstream, verify the SDRAM is being initialized and
   refreshed (the controller's `chip` toggling should be observable, and
   the parts should not enter their power-down/decay regime). No
   functional test of read/write yet — that needs a client.
2. **Hardware bring-up of the front panel**: compile and load,
   confirm the WS2812 string lights up with the default identity map
   when software writes patterns to port 0x47, exercise the colour
   stream at port 0xA3 (six bytes per LED, on-G/R/B then off-G/R/B),
   confirm the brightness scaler at port 0xA0 dims/brightens, and
   confirm the framebuffer mode at port 0xA4 + 0xA6.
3. **Wire the MMU into the system** (Requirement: "Implement MMU"). The
   MMU is not currently instantiated. Once it is wired in:
   - Add `set_global_assignment -name VHDL_FILE Components/alancox/MMU.vhd`
     to **both** `MultiComp.qsf` and `MultiComp-lite.qsf` (per `AGENTS.md`).
   - Choose the base address for the 16-port I/O window (must be aligned
     on a 16-port boundary so the low 4 address bits are a clean
     in-window offset).
   - Decide whether `access_violated` needs to be re-introduced.
4. **Connect the MMU to the layered memory** (Requirement: "Implement
   SDRAM"). The MMU's physical address output picks between the existing
   64 KB block RAM (when `address_out[26:16] == 0`) and the SDRAM
   wrapper's `addr/we/rd/din/dout/ready` (otherwise). This is the step
   that actually exercises SDRAM access.
5. **Revisit the MMU reset map** once the layered memory is wired so the
   identity map points at sensible regions (frame 0 at block RAM for
   ROM/boot, etc.).
6. **Expand the front-panel capture chain**: once the basic 8-bit
   chain proves out, add a wider `Transparent_Capture_Chain` (or a
   `Universal_Capture_Chain` with `STRETCH_MASK` set on a few control
   bits) sourced from CPU/MMU/SDRAM control signals to drive a real
   blinkenlights display.
7. **Optional**: move the SDRAM to a dedicated higher-frequency clock
   (e.g. 100 MHz from a regenerated PLL) once basic operation is proven.
