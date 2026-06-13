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

### Z-80 custom FORTH `NEXT` instruction

To support the CamelFORTH implementation distributed with RomWBW, add a
custom Z-80 instruction that implements the FORTH direct-threaded `NEXT`
inner-interpreter primitive in a single opcode, replacing the 7-byte
inline macro emitted at the end of every CamelFORTH CODE word. The goal is
to shrink the FORTH dictionary and speed up inner-interpreter dispatch.

The instruction shall use the Z-80 register conventions of CamelFORTH:

- `BC` = TOS (top parameter-stack item)
- `HL` = W (working register)
- `DE` = IP (interpreter pointer)
- `SP` = PSP, `IX` = RSP, `IY` = UP

It shall be encoded in the `0xED` ("Misc. Instructions") prefix space at
opcode **`ED 27`**, a previously-unused (NOP/undocumented) slot. Its
operation shall be equivalent to the macro:

```
ex de,hl / ld e,(hl) / inc hl / ld d,(hl) / inc hl / ex de,hl / jp (hl)
```

i.e. read the 16-bit cell `W` from memory at `(IP)`, advance `IP` by 2,
load `W` into `HL`, and jump (`PC := W`). `HL = W` is required because the
direct-threaded runtime words (`DOLIST`/`ENTER`, `DOVAR`, `DOCON`,
`DODOES`, `EXECUTE`) derive the parameter-field address from `W` in `HL`.

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


### Loadable Boot ROM and RAM disk images from the MiSTer OSD

We want the user to be able to specify two types of files in the MiSTer OSD
interface.

1. A binary files (with a `.BIN` extension) that will be loaded into
SDRAM memory, starting at physical address 0x0000.  This file can be
as long as 512KB.  This would replace the 8KB ROM image that overlays
the bottom of the address space, and when this file is loaded, the ROM
should be disabled and the 64KB of block RAM should also be disabled.
When this file is loaded, it is essentially the "Boot" image that's
started when the Z-80 CPU comes out of reset and starts executing at
address 0x0000.

2. One or more "RAM Disk" images, which would be 8MB in length and be
accessed as a memory/RAM disk device by RomWBW.  Minimally, we should
support one of these images, and it would be loaded (by default) in
the top 8MB of the 128MB SDRAM address space.  It should be possible
to easily extend this implementation to load additiona 8MB RAM disk
images at other starting addresses.  These RAM disk images would have
the file extension `.DSK` in their names.

Having this capability means that software upgrades no long require
regenerating an FPGA core with, e.g., updated boot monitor, etc.

The anticipated uses of this "boot ROM" capability are:

- load RomWBW 
- load the existing 8KB boot ROM that's part of the FPGA core so far.
- build alternative Boot ROMs and easily test and use them
- boot a standalone FORTH-based monitor capability

The 8MB RAM Disk file image would be used by RomWBW after it is loaded
and started.

This feature should use the MiSTer configuration string to specify the
options to load the Boot ROM and RAM disk images.


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

`MultiComp.qsf` has been updated with `SYSTEMVERILOG_FILE` entries for
the two new files. The SDRAM controller
runs from the existing `clk_sys` (50 MHz from `rtl/pll.v`); the
AS4C32M16SB timing constants in the controller comfortably hold at this
frequency, so PLL regeneration is not required for first bring-up.

### Front-panel LED subsystem (`Components/FRONTPANEL/`) — wired into the CPM core for initial bring-up

The WS2812/SK6812-based blinkenlights front panel has been added to the
build of the Z-80 CPM core. Files are referenced from `MultiComp.qsf`;
the subsystem and capture chain are instantiated in
`MicrocomputerZ80CPM.vhd`.

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


### SDRAM controller: ported CoCo3 `sdram_32r8w` (`Components/SDRAM/sdram2.sv`)

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
> and `rtl/pll/pll_0002.*`. It does **not** modify `MultiComp.qsf` or
> `MultiComp.qpf`; the design references the PLL through the single
> `QIP_FILE rtl/pll.qip` line in `MultiComp.qsf`, which is unchanged.
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

**Address mapping (full 128 MB).** The controller now takes the full
27-bit byte address and reaches the entire 128 MB module. The XSDS board
carries two AS4C32M16SB devices on a single shared 16-bit bus; device 1's
chip-select is the inverted copy of device 0's, so the single `SDRAM_nCS`
pin selects between them. (Note: `SDRAM2_*` in the MiSTer framework is a
separate physical expansion board, not the second device on this module.)
The 27-bit byte address decomposes as:

```
addr[26]    = chip   -> SDRAM_nCS (device 0 / 1)
addr[25:13] = row    (13 bits, 8192 rows)
addr[12:11] = bank   (2 bits, 4 banks)
addr[10:1]  = column (10 bits, 1024 columns)
addr[0]     = byte within the 16-bit word (DQM select)
```

Controller changes (`Components/SDRAM/sdram2.sv`, all marked `LOCAL MOD`):
- Address ports widened to `[26:0]`; the column/bank/row packing was
  rewritten from upstream's 24-bit (32 MB, wrong split) to the correct
  per-device decomposition above.
- `SDRAM_nCS` driven from a `chip` register loaded with `addr[26]` at
  command time (was hardcoded 0).
- **Two-pass init**: `STATE_STARTUP` runs the precharge/refresh/load-mode
  sequence once per device (driven by an `init_chip` bit) before entering
  `STATE_IDLE`.
- **Alternating refresh**: the refresh logic toggles `chip` each interval
  so both devices are refreshed. Because each device is then refreshed
  every *other* interval, `cycles_per_refresh` is halved to `14'd390`
  (`(64ms/8192 @ 100MHz)/2`) to keep each device within its 7.8 us row
  refresh period.

The CDC adapter in `MultiComp.sv` passes the full `sdram_addr_mux[26:0]`
(no truncation) into a 27-bit `ram_addr` and the controller's widened
`sdram_cpu_addr`. The video read port (`sdram_vid_*`) is tied off.

The 32 MB single-device configuration is preserved at git tag
`sdram-32mb-working` (commit `ff7a1a0`) as a rollback point.

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

### MMU widened to 13 bits (128 MB)

With the SDRAM data path proven on hardware, the MMU was widened from
`physical_page_bits = 8` (22-bit / 4 MB) to `physical_page_bits = 13`
(27-bit / 128 MB), covering the full XSDS module.

Changes (`MicrocomputerZ80CPM.vhd`):
- `mmu1` generic `physical_page_bits => 13`.
- `mmu_phys_addr` widened to `std_logic_vector(26 downto 0)` (27 bits).
- `sdram_addr <= mmu_phys_addr;` directly — no more zero-extension; the
  27-bit physical address now fills the controller's address port.
- Block-RAM decode tightened to `mmu_phys_addr(26 downto 16) =
  "00000000000"`, so high SDRAM pages cannot alias into the low-64 KB
  block RAM.

The MMU module itself needed no width edits — it is parameterised by the
generic. 8192 pages x 16 KB = 128 MB; pages 0..3 (physical
0x000000..0x00FFFF) remain block RAM, pages 4..8191 are SDRAM.

#### Z2-compatible low-byte write (MMU.vhd)

Writing a frame's low byte (ports +0..+3) now clears the entire mapping
register first, forcing the high byte (bits 15:8) to 0. Rationale: Z2 MMU
software only ever writes the 8-bit page number via the low-byte ports;
without this, a stale high byte left by 128 MB-aware code could leave such
a write pointing at an unexpected high page. Clearing on low-byte write
guarantees a low-byte-only write always lands in the low 256 pages,
regardless of prior state. To select a page >= 256, write the low byte
first, then the high byte (+4..+7); the high-byte write does not disturb
the low byte. Implemented as two sequential signal assignments in the
register process (whole-register clear, then low-byte overwrite — the
later slice assignment wins for bits 7:0).

#### Stale-read-by-one fix (SDRAM client FSM, `MicrocomputerZ80CPM.vhd`)

The first SDRAM read after any change initially returned the *previous*
transaction's byte; the second/third reads were correct. Root cause: in
`S_REQ` the FSM latched `sdramReadData <= sdram_dout` **and** released the
CPU wait (`sdram_wait_n <= '1'`) on the *same* clock edge. Because
`sdramReadData` is a registered assignment, its new value is not visible
until after that edge, so the Z-80 sampled `cpuDataIn` (→ `sdramReadData`)
while it still held the previous value. Fix: hold the wait through `S_REQ`
and release it one cycle later in `S_DONE`, after `sdramReadData` is
stable (matching the FSM's own documented intent). This also explains the
earlier intermittent `FLAKY-READ` failures — retries "passed" because the
second read caught up. Verified by the 3-read and A/B/C/D BASIC tests and
a clean soak.

### SDRAM controller extended to full 128 MB (dual-device shared bus)

Commit `98bb963`. The XSDS expansion board carries two AS4C32M16SB devices
on a single shared 16-bit bus; **device 1's chip-select is the inverted
copy of device 0's**, so the single FPGA `SDRAM_nCS` pin selects between
them. (`SDRAM2_*` in the MiSTer framework is a *separate* expansion board,
not the second device on this module — an easy and important point to get
wrong.) The CoCo3 `sdram_32r8w` controller, which upstream reached only
32 MB of one device with the wrong row/bank/col split, was extended:

- Address ports widened 25 → 27 bits.
- Correct per-device decomposition (AS4C32M16SB = 4 banks × 8192 rows ×
  1024 cols × 16 bit = 64 MB/device):
  ```
  addr[26]    = chip   -> SDRAM_nCS (device 0 / 1)
  addr[25:13] = row    (13 bits)
  addr[12:11] = bank   (2 bits)
  addr[10:1]  = column (10 bits)
  addr[0]     = byte within the 16-bit word (DQM select)
  ```
- `SDRAM_nCS` driven from a `chip` register loaded with `addr[26]` at
  command time (was hardcoded 0).
- **Two-pass init**: `STATE_STARTUP` runs the precharge/refresh/load-mode
  sequence once per device (via an `init_chip` bit) before entering IDLE.
- **Alternating refresh**: refresh toggles `chip` each interval so both
  devices are refreshed; `cycles_per_refresh` halved to `14'd390`
  (`(64ms/8192 @ 100MHz)/2`) so each device still meets its 7.8 µs row
  refresh period.
- `MultiComp.sv` CDC adapter passes the full `sdram_addr_mux[26:0]` (no
  longer truncated to 25 bits) into a 27-bit `ram_addr` and the widened
  `sdram_cpu_addr`.

All `sdram2.sv` divergences from upstream are marked `LOCAL MOD`. The
prior 32 MB single-device config is preserved at git tag
`sdram-32mb-working` (`ff7a1a0`) as a rollback point.

### MMU direct-access window — verified on hardware

The MMU's "direct access" window (ports `0xB8..0xBC`: a 4-byte
little-endian physical-address pointer at `+8..+11` plus a data port at
`+12`) is now **proven on real DE10-Nano silicon**, covering the full
128 MB address space. The feature itself was already in the build
(committed in `ff7a1a0`); this entry records its hardware verification.

Verification was done with the BASIC test program
`testing/directaccess.bas` (a scratch test, not tracked in git), which
exercises:

1. **Single-byte R/W** — write a byte through `OUT &HBC`, reload the
   pointer, read it back through `INP(&HBC)`.
2. **Pointer post-increment** — write four consecutive bytes with a
   single pointer setup (relying on the auto-increment), reload, and read
   four bytes back. Confirms the post-increment fires on **both** reads
   and writes (it is triggered by the `+12` access ending, independent of
   direction).
3. **Direct write vs windowed read** — direct-write at a page's physical
   base, then read the same bytes through the normal frame-3 `PEEK`
   window. Confirms both paths address the same physical cells.
4. **Windowed write vs direct read** — the reverse cross-check (`POKE`
   through the window, `INP` through direct access).
5. **High address / upper device** — direct R/W at physical `0x04E20000`
   (page 5000, > 64 MB), exercising pointer bit 26 and the second
   AS4C32M16SB device.

All subtests pass. This validates the direct-access address rewrite
(`req_mem_out` forced high, `req_io_out` low, `address_out` driven from
the pointer), the one-cycle `cpu_wait` pulse for synchronous memory, the
exclusion of port `+12` from the MMU read-back mux (so data flows through
the block-RAM/SDRAM path rather than the MMU register file), and the
27-bit pointer reaching the upper SDRAM device.

### Z-80 custom FORTH `NEXT` instruction (`ED 27`) — HDL implemented, GHDL-verified, hardware test pending

The CamelFORTH `NEXT` primitive has been implemented as a new Z-80
instruction in the T80 core, entirely within
`Components/Z80/T80_MCode.vhd` (the microcode decode table). No other
core files (`T80.vhd`, `T80_Reg.vhd`, `T80_Pack.vhd`, `T80_ALU.vhd`,
`T80s.vhd`) and no `.qsf` entries needed changes — the instruction is
composed solely from existing control signals, so the core's port
interface is unchanged.

**Encoding:** `ED 27` (ED-prefix, opcode `0x27` / `00100111`), previously
a NOP/undocumented slot. Removed `00100111` from the ED NOP list and added
a dedicated decode arm.

**Operation** (DE = IP, HL = W), equivalent to the 7-byte CamelFORTH
`next` macro `ex de,hl / ld e,(hl) / inc hl / ld d,(hl) / inc hl /
ex de,hl / jp (hl)`:

- **MCycle 2**: address ← DE (IP); read low byte → `L` (and into
  `TmpAddr(7:0)` via `LDZ`); `DE := DE + 1`.
- **MCycle 3**: address ← DE (IP+1); read high byte → `H`; `DE := DE + 2`;
  `PC := DI_Reg & TmpAddr(7:0)` via the `Jump` path.

Net effect: `HL := W = mem[IP]`, `IP := IP + 2`, `PC := W`. The `Jump`
datapath sources `PC` from the freshly-read bytes (`DI_Reg & TmpAddr`),
exactly as `RET`/`JP nn` do, avoiding any register-file read hazard, while
the cell is also committed to the `H`/`L` register pair using the proven
`LD HL,(nn)` writeback pattern (so `HL = W`).

**Why `HL = W`:** direct-threaded CamelFORTH runtime words (`DOLIST`/
`ENTER`, `DOVAR`, `DOCON`, `DODOES`, `EXECUTE`) compute the parameter-field
address from `W` held in `HL`. A jump-only instruction would break them.

**Size/speed benefit:** replaces the 7-byte inline macro at the end of
every CODE word with a 2-byte `ED 27` (≈5 bytes saved per primitive, and
CamelFORTH has 150+ CODE words → ≈750+ bytes saved), collapsing 7
instructions into one.

**Verification status:** `ghdl -a --std=08 -fsynopsys` accepts the
modified sources with no errors (only a pre-existing, unrelated `is_cc_true`
hide-warning remains). Not yet exercised on hardware. **Open item for
hardware bring-up:** the `H`-byte write commits in TState 1 of the
following M1 fetch (standard `LD HL,(nn)` timing); confirm via FORTH
execution that `HL = W` is observable before the next CODE word reads it.

**CamelFORTH side (not done here, HDL-only):** the CamelFORTH `next` macro
must be redefined to emit the single opcode (`DB 0EDh,27h`) instead of the
7-instruction sequence. CamelFORTH source is not yet present in this repo
(the RomWBW/FORTH port is future work).

### Loadable Boot ROM (`.BIN`) and RAM-disk (`.DSK`) images from the OSD — HDL implemented, hardware test pending

The OSD file-download feature is implemented across `MultiComp.sv` (top
level) and `MicrocomputerZ80CPM.vhd` (CPM core). The user can select a
`.BIN` boot image and one or more `.DSK` RAM-disk images in the MiSTer OSD;
both are streamed into SDRAM via the HPS `ioctl` download interface. No
`sys/` files and no `.qsf`/IP changes were needed (both edited files are
already in the build; `hps_io` is part of `sys.qip`).

**Config string (`MultiComp.sv`):** two generic load entries added —
`"F1,BIN;"` (load index 1) and `"F2,DSK;"` (load index 2). The explicit
index digits give deterministic `ioctl_index[5:0]` values for HDL decode.

**`hps_io` ioctl ports wired:** `ioctl_download`, `ioctl_index`,
`ioctl_wr`, `ioctl_addr` (27-bit byte offset within the file),
`ioctl_dout` (8-bit), and `ioctl_wait`. None were connected before.

**Target physical address mapping (`MultiComp.sv`):**
- `.BIN` (index 1): SDRAM physical `0x000000 + ioctl_addr` (≤512 KB). Boots
  at `0x0000`.
- `.DSK` (index 2): SDRAM physical `base + ioctl_addr`, where
  `base = 128MB - (slot+1)*8MB` and `slot = ioctl_index[15:6]`. The first
  RAM disk lands in the **top 8 MB** (`0x7800000`); each additional image
  is placed 8 MB lower. With the single `"F2,DSK;"` entry the slot is 0;
  adding more `F,DSK` entries (or HPS multi-load) increments the slot
  automatically — this is the **multi-DSK index decode** (`localparam`s
  `SDRAM_TOP`/`DSK_IMAGE_SIZE`, wires `dl_dsk_slot`/`dl_dsk_base`).

**Write path:** downloads reuse the **existing CPU-port SDRAM CDC adapter**.
During any download the whole CPM core is held in reset (the top-level
`reset` wire now includes `ioctl_download`), so the adapter is otherwise
idle and there is no contention. A small `clk_sys` handshake FSM latches
each byte on a synchronized `ioctl_wr` edge, drives the muxed
`sdram_addr_mux`/`sdram_din_mux`/`sdram_we_mux` (overriding the CPU client
while `ioctl_download` is high), **holds** the write-request level until the
adapter pulses `sdram_ready_mux`, and asserts `ioctl_wait` for the whole
in-flight window so HPS throttles the byte stream until each byte is
committed.

**Boot-source latch + auto-reset (`MultiComp.sv`):** a `bin_loaded`
register is set on the falling edge of a `.BIN` download and persists until
a genuine hard reset (`RESET`/OSD Reset/`status[0]`). A `dl_reset_stretch`
counter pulses the CPU reset for ~65 k cycles after any download completes
so the Z-80 restarts cleanly into the new image; this stretch does **not**
clear `bin_loaded`, so the freshly-loaded BIN boots.

**Critical detail — separate SDRAM init reset:** the SDRAM controller's
`.init` is driven by a **new, narrower** `sdram_init_reset` wire
(`RESET | status[0] | buttons[1] | reset_from_mount`) — explicitly NOT the
expanded `reset` — so the controller is not re-initialized during a
download (which would wipe the bytes being streamed in) or during the
post-download CPU-reset stretch.

**CPM core changes (`MicrocomputerZ80CPM.vhd`):** new input port
`bin_loaded` (defaulted `'0'`). When high:
- the boot ROM overlay decode (`n_basRomCS`) is forced inactive, and
- `phys_in_blockram` is forced low so the low 64 KB is served from SDRAM
  (where the BIN was written) rather than block RAM; `n_internalRam1CS`
  follows `phys_in_blockram`, so block RAM is deselected automatically and
  the `cpuDataIn` mux returns `sdramReadData` for `0x0000+`.

Net effect: with a BIN loaded, ROM and block RAM are disabled and the Z-80
boots the loaded image from physical/logical `0x0000` out of SDRAM, exactly
as required. With no BIN loaded (`bin_loaded = 0`) behaviour is unchanged
(built-in 8 KB ROM boot, block RAM at `0x0000`).

**Debug option — `.BIN` into block RAM (OSD `status[13]`).** Early
hardware testing showed a loaded `.BIN` printing its initial prompt but then
behaving unpredictably, suggesting either a faulty load or an SDRAM-path
problem. To isolate the two, a new OSD toggle `"OD,Boot Load Target,SDRAM,
Block RAM;"` (`status[13]`) routes a `.BIN` into the on-chip 64 KB block RAM
instead of SDRAM:
- `MultiComp.sv`: `dl_to_bram = ioctl_download & dl_is_bin & status[13]`.
  When set, the SDRAM download FSM is idled and a one-cycle-per-byte
  block-RAM write strobe (`dl_bram_we_r`/`dl_bram_addr_r`/`dl_bram_data_r`,
  address = `ioctl_addr[15:0]`) is driven into the CPM core. DSK images
  (8 MB) ignore this and always go to SDRAM.
- `MicrocomputerZ80CPM.vhd`: new inputs `boot_to_blockram`,
  `dl_bram_addr/data/we`. The block RAM's `address/data/wren` are muxed to
  the download port while `dl_bram_we = '1'` (CPU is in reset then, so no
  contention). When `boot_to_blockram = '1'`, `phys_in_blockram` is NOT
  forced off by `bin_loaded`, so block RAM stays enabled and serves the low
  64 KB; only the ROM overlay is disabled, so the BIN runs from `0x0000` out
  of block RAM. Note the BIN's low 64 KB only fits block RAM, so images
  larger than 64 KB cannot be fully tested this way — it is purely a
  diagnostic to confirm the load mechanics and CPU execution independent of
  SDRAM.

**Hardware test results (current state):**
- **Block RAM target (`status[13]=1`): WORKS reliably.** A `.BIN` loaded
  into block RAM boots and runs as expected. This confirms the OSD download
  mechanics (file streaming, `ioctl_*` decode, `bin_loaded` latch,
  auto-reset, ROM-overlay disable, and Z-80 execution from `0x0000`) are all
  correct, and isolates the remaining fault to the **SDRAM data path**.
- **SDRAM target (`status[13]=0`): DOES NOT WORK.** The same `.BIN` routed
  into SDRAM does not run correctly. Because the block-RAM path proves the
  load/decode/boot machinery is sound, the problem is specifically in
  reading and/or writing SDRAM (controller, CDC adapter handshake, address
  mapping, or byte lane/timing) — not in the download or boot logic.

**Next diagnostic step — SDRAM memory-test program.** To characterize the
SDRAM fault independently of the boot image, a standalone Z-80 SDRAM memory
test (`testing/sdramtest.asm`) is booted from **block RAM** (the known-good
path) and exercises the SDRAM through the CPU's normal MMU window. It writes
and reads back known patterns and reports pass/fail and the failing
address/bit, so we can tell whether the SDRAM is dead, stuck, mis-addressed,
or bit-laned wrong. See "SDRAM memory-test program" below.

**Verification status:** HDL edits are concurrent-assignment / FSM logic;
no local simulator is available for this design (`MicrocomputerZ80CPM.vhd`
pulls in Quartus IP and Synopsys `std_logic_arith`/`std_logic_unsigned`,
which the installed GHDL cannot analyze; `MultiComp.sv` has no SV linter in
the environment). Verification is via Quartus compile + DE10-Nano hardware.

**Open items for hardware bring-up:**
1. ~~Confirm a known-good `.BIN` boots from `0x0000`~~ — **done for block
   RAM; SDRAM path confirmed broken (see test results above).**
2. **Diagnose the SDRAM data path** using the block-RAM-booted memory test
   (`testing/sdramtest.asm`).
3. Confirm `.DSK` bytes land at physical `0x7800000` (e.g. via the verified
   MMU direct-access port / a BASIC PEEK through the frame-3 window). Likely
   blocked behind the SDRAM-path fix.
4. CDC nicety: `ioctl_wait`/`dl_busy` is generated in `clk_sys` and consumed
   in hps_io's `CLK_50M` domain (both ~50 MHz PLL taps). It is a slow level
   and held for the whole transaction, so a direct connection is acceptable
   for bring-up; revisit with an explicit synchronizer if any
   write-throttle glitches appear.
5. **Software (RomWBW side, not HDL):** the RAM-disk driver must access the
   8 MB image at physical `0x7800000` via the MMU (paging the window) or the
   MMU direct-access port. Out of scope for this HDL change.

### SDRAM memory-test program (`testing/sdramtest.asm`)

A standalone Z-80 diagnostic that exercises SDRAM independently of the boot
image, to localize the SDRAM-path fault described above. It is assembled to a
flat binary and **loaded into block RAM** (OSD "Boot Load Target = Block RAM",
the known-good path), then run from `0x0000`. It runs **two phases** that reach
SDRAM by the two different routes the hardware provides, so a pass/fail split
between them localizes the fault.

Results are printed on the serial console (6850 ACIA, `io2`): status/control
at `0x82` (bit1 `0x02` = TX-ready/TDRE), data at `0x83`.

#### Phase 1 — direct-access port (small region) — PASSES on hardware

The CPU's low 64 KB of *physical* space is the on-chip block RAM, where the
test itself runs; SDRAM only exists at physical `0x010000`+. Phase 1 touches
SDRAM through the **MMU direct-access port** so it never disturbs its own code:
- `0xB8..0xBB` — 27-bit physical pointer, little-endian (write low byte first).
- `0xBC` — data port: each `IN`/`OUT` performs a physical memory cycle at the
  pointer and then **post-increments** the pointer by 1. The CPU is auto
  wait-stated until the access completes, so no polling is needed.

Region: configurable via `SDB0..SDB3` (base) and `TEST_PAGES`; default 256
256-byte pages from physical `0x010000` → the first **64 KB** of SDRAM, kept
small so it finishes quickly. **This phase PASSES on hardware** — the raw SDRAM
array and the direct-access read/write path are good.

#### Phase 2 — MMU-paged sweep (the path real software uses)

Because Phase 1 passes, the remaining suspect is the **normal paged-access
path** that CP/M / RomWBW actually use. Phase 2 maps each 16 KB *physical*
SDRAM page, in turn, into the unused top 16 KB of the Z-80's logical space
(**frame 3, logical `0xC000..0xFFFF`**) via the MMU mapping registers, then
tests that page with ordinary CPU memory accesses (`LD (HL),A` / `LD A,(HL)`):
- Map page `N` into frame 3: `OUT (0xB3),N_lo` (low byte — clears the whole
  map register first, then sets page bits 7:0) then `OUT (0xB7),N_hi` (high
  byte — page bits 12:8; `physical_page_bits = 13`).
- Sweeps every 16 KB SDRAM page above the block-RAM overlap, `PAGE_FIRST=4`
  (physical `0x010000`) .. `PAGE_LAST=8191` (top of the 128 MB / 27-bit space).
  Both configurable.
- Prints a **running per-page progress line** `page NNNN  errs=EEEE` ending in
  a bare CR so it overwrites in place on a serial terminal, plus a **running
  16-bit byte-error tally** (`perrcount`).

The program runs from frames 0–2 (`≤0xBFFF`) and the stack/scratch live in
frame 0, so remapping frame 3 never touches its own code.

#### Tests (comprehensive pattern set, used by both phases)

Each writes the whole region/window then reads it back and verifies:
1. **Stuck-data fills** `0x00`, `0xFF`, `0xAA`, `0x55` — stuck-at / shorted
   data bits.
2. **Address-in-data** — Phase 1: byte = `addr_lo XOR addr_mid`. Phase 2: byte
   = `logaddr_lo XOR logaddr_hi XOR page_lo`, mixing in the page number so it
   also catches **page-to-page aliasing** (a page wrongly mapped to another
   page's storage reads back the wrong value).
3. **Walking-ones** `01,02,04,…,80` repeating — bit-to-bit shorts / swapped
   bit lanes.

On the first mismatch of each Phase-1 test it prints
`MISMATCH @XXXXXX exp=EE got=GG` (physical address, low 24 bits). On the first
mismatch *per page* in Phase 2 it prints
`PAGE pppp @LLLL exp=EE got=GG` (physical page number and the LOGICAL window
address `0xC000..`), then suppresses further detail lines for that page (the
tally still counts every bad byte). A combined summary prints the Phase-1
failed-test count and the Phase-2 byte-error count.

#### Build

```sh
pasmo --bin testing/sdramtest.asm testing/sdramtest.bin
```
Produces a ~1.8 KB flat binary (entry `DI; LD SP,0x0A00; …` at `0x0000`).
`pasmo` is the assembler used (installed from the distro package); no Z-80
assembler ships in this repo's toolchain otherwise.

#### Interpreting the output

- *Phase 1 passes (confirmed) but Phase 2 fails* → the fault is in the
  **paged-access path**, i.e. the MMU frame-map → `sdram_addr` translation or
  the read mux for paged (non-direct) cycles — NOT the raw SDRAM array. This is
  the same path the boot-from-SDRAM image uses, so it is the prime suspect for
  the original failure.
- *Both phases pass* → SDRAM and both access paths are good; the boot-from-
  SDRAM failure is then most likely in the **download write FSM / CDC
  handshake** (`dl_we` hold vs `sdram_ready_mux`), the
  **`bin_loaded`/`phys_in_blockram` switch-over** that re-routes `0x0000` to
  SDRAM, or **timing** of the streamed write vs the auto-reset.
- *Stuck-data fails (all same bit)* → dead/stuck data lane or the controller
  never completing the cycle.
- *Address-in-data fails but fills pass* → address-line / decode / aliasing
  fault (within a page, or page-to-page in Phase 2).
- *Walking-ones fails* → adjacent data-bit short or swapped byte lanes.

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

1. **Hardware bring-up of the SDRAM controller**: **DONE.** The full
   128 MB is verified on real DE10-Nano silicon — byte-accurate writes,
   correct reads (after the stale-read fix), both devices initialised and
   refreshed. Verified via BASIC POKE/PEEK soak tests: a full-range soak
   (pages 4–2047) ran 76+ clean passes, and a 128 MB soak (pages 4–8191,
   crossing the device boundary at page 4096) plus a device-1 retention
   test all passed.
2. **Hardware bring-up of the front panel**: compile and load,
   confirm the WS2812 string lights up with the default identity map
   when software writes patterns to port 0x47, exercise the colour
   stream at port 0xA3 (six bytes per LED, on-G/R/B then off-G/R/B),
   confirm the brightness scaler at port 0xA0 dims/brightens, and
   confirm the framebuffer mode at port 0xA4 + 0xA6.
3. **Widen `physical_page_bits`** from 8 to 13 once SDRAM access is
   proven, to expose the full 128 MB of physical address space.
   **DONE** — see "MMU widened to 13 bits (128 MB)" below.
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
   **DONE** — the SDRAM controller runs on a dedicated `clk_ram`. 112 MHz
   showed marginal read-data capture (occasional first-read bit flips on
   DQ 7/3/1, data stored correctly); 100 MHz (`SDRAM_CLK_100` define) is
   clean over 356+ soak passes and is the shipping configuration.
7. **Clean-up legacy memory device** in `MicrocomputerZ80CPM.vhd` - 
   remove references to externalRam (`n_externalRamCS` and varous 
   `internalRam2` related signals.
8. **FORTH `NEXT` instruction (`ED 27`) hardware bring-up**: the T80
   microcode is implemented and GHDL-verified, but not yet tested on
   silicon. Confirm `HL = W`, `IP += 2`, and `PC := W` behave correctly,
   then redefine the CamelFORTH `next` macro to emit `DB 0EDh,27h` and
   re-run the FORTH test suite.
9. **Loadable Boot ROM (`.BIN`) / RAM-disk (`.DSK`) from OSD hardware
   bring-up**: HDL implemented across `MultiComp.sv` and
   `MicrocomputerZ80CPM.vhd` (see the progress entry above). Quartus-compile
   and test on silicon: (a) load a known `.BIN`, confirm it boots from
   `0x0000` after the auto-reset and that `bin_loaded` clears on OSD Reset;
   (b) load a `.DSK`, confirm bytes land at physical `0x7800000`; (c) wire
   the RomWBW RAM-disk driver to that physical base (software).

---

## Session summary / current state (end of 2026-06 SDRAM bring-up)

This captures where the project stands after the SDRAM bring-up and MMU
widening work, for whoever picks it up next.

### What works (verified on hardware)

- **128 MB SDRAM** fully functional: byte writes, reads, both AS4C32M16SB
  devices initialised and refreshed. See the soak-test results above.
- **MMU** widened to `physical_page_bits = 13` (27-bit / 128 MB physical
  address). Pages 0–3 = on-chip block RAM, pages 4–8191 = SDRAM.
- **Z2-compatible** low-byte mapping-register writes (clears the high
  byte).
- **MMU direct-access window** (ports `0xB8..0xBC`) verified on hardware:
  pointer R/W, post-increment on both reads and writes, agreement with
  the windowed `PEEK`/`POKE` path, and access to the upper SDRAM device
  via the 27-bit pointer. See "MMU direct-access window" above.
- **Front-panel LED subsystem** is in the build and instantiated, but
  **not yet bring-up-tested on hardware** (item 2 above).
- **CP/M 2.2 / 3.0 and BASIC** run as before (block RAM boot path
  unchanged).

### Build configuration

- **Single Quartus revision** `MultiComp` (the stale `MultiComp-lite`
  revision was removed — commit `bfd0cbc`).
- Build: `quartus_sh --flow compile MultiComp -c MultiComp` →
  `output_files/MultiComp.rbf`.
- **Clocks**: `clk_sys` = 50 MHz (Z-80 + CPM FSM); `clk_ram` = **100 MHz**
  (SDRAM controller), selected by the `SDRAM_CLK_100` define in
  `MultiComp.sv` (currently **enabled** — this is the shipping config).
  The PLL emits outclk_0=50, outclk_1=112, outclk_2=100 MHz. 112 MHz was
  rejected for marginal SDRAM read-capture timing.
- The SDRAM controller runs in its own clock domain; a 2-FF-synchronizer
  CDC adapter in `MultiComp.sv` bridges the 50 ↔ 100 MHz boundary.

### Key facts / gotchas for the next session

- **Dual-SDRAM topology**: one shared 16-bit bus, device 1's CS = inverted
  device 0 CS, so `SDRAM_nCS` (single pin) selects the device.
  `SDRAM2_*` = a *different* expansion board, NOT the second chip.
- **`SBCTextDisplayRGB` setup-timing violation** is pre-existing and
  ignored (see Known Issues) — not caused by any recent work.
- `sys/` files must never be modified (externally maintained ARM
  interface).
- PLLs are generated IP — regenerate via MegaWizard, never hand-edit.
  Regeneration touches only `rtl/pll*` files, not the `.qsf`/`.qpf`.
- Rollback tag `sdram-32mb-working` (`ff7a1a0`) = last 32 MB single-device
  config.

### Git state at session end

- Branch `louie`. The SDRAM/MMU bring-up commits are pushed to
  `origin/louie` (notable: `bfd0cbc` remove lite, `98bb963` 128 MB SDRAM,
  `ff7a1a0` MMU 128 MB + Z2 + stale-read fix, `cfcc8fc` 100 MHz, `2a88f1c`
  PLL regen, `c531ead` SDRAM bring-up summary).
- This direct-access verification update is committed on top and tagged
  `mmu-direct-access-working`.
- Incidental Quartus housekeeping churn (`MultiComp.qsf`, `build_id.v`)
  remains uncommitted by design.

### Suggested next steps (priority order)

1. **Front-panel hardware bring-up** (outstanding item 2) — the subsystem
   is wired but never lit on real hardware.
2. **MMU reset map** (item 4) — decide on a sensible default beyond the
   placeholder identity map now that SDRAM is real.
3. **Legacy memory cleanup** (item 7) — remove dead `externalRam` /
   `internalRam2` signals from `MicrocomputerZ80CPM.vhd`.
4. **Begin the RomWBW port** — the original project goal. The 128 MB
   paged-memory foundation (MMU + SDRAM, with a verified direct-access
   window for inter-bank copies) is now in place to host it.

