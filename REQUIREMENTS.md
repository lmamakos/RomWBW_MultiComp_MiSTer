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

Use the 128 Mbytes of SDRAM for the Z-80 system memory (via the MMU),
rather than FPGA block ram.

## Progress

### MMU rework (`Components/alancox/MMU.vhd`) — design complete, not yet in the build

The MMU source file has been rewritten in place to match the requirements
above. The file is not yet referenced from either Quartus revision (no
`.qsf` entries) and is not yet instantiated anywhere in the system, so the
build is unaffected by the change.

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

### Outstanding work toward the requirements above

1. **Verify the rewritten MMU compiles** under Quartus (Analysis &
   Elaboration). This has not been run yet.
2. **Wire the MMU into the system** (Requirement: "Implement MMU"). The
   MMU is not currently instantiated. Once it is wired in:
   - Add `set_global_assignment -name VHDL_FILE
     Components/alancox/MMU.vhd` to **both** `MultiComp.qsf` and
     `MultiComp-lite.qsf` (per `AGENTS.md`).
   - Choose the base address for the 16-port I/O window (must be aligned
     on a 16-port boundary so the low 4 address bits are a clean
     in-window offset).
   - Decide whether `access_violated` needs to be re-introduced.
3. **Use SDRAM as Z-80 system memory** (Requirement: "Implement SDRAM").
   Route the MMU's physical address bus to the MiSTer SDRAM controller in
   place of FPGA block RAM.
4. **Revisit the reset map** once ROM and SDRAM physical placement is
   fixed.
