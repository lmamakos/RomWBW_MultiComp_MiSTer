## Memory Map

Pages are 16K each (14 bits).   Total address space is 256MB,
with 128MB (SDRAM) followed by 64K of Block Ram at the start
of the upper 128M address space - total of 27 bits.

Address format:    (Virtual)
  26 25 24.23 22 21 20.19 18 17 16.15 14 13 12.11 10 09 08.07 06 05 04.03 02 01 00
  \--high pg#--/ \-- low order page #--/ \--- In-page low order address bits ----/

                   (Logical)       15 14 13 12.11 10 09 08.07 06 05 04.03 02 01 00
                                   \pg#/ \--------- offset in 16K page ---------/

When bit 26 is zero, the lower 128MB is the SDRAM.
When bit 26 is one, the first 64KB is the on-FPGA Block RAM memory.

| Memory Address  | Page Number |  High MMU   |   Low MMU   |
|-----------------|-------------|-------------|-------------|
| SDRAM Start     |     0       |     0       |     0       |
| SDRAM End       |    8191     |  0x1F / 31  | 0xFF / 255  |
| Block RAM Start |    8192     |  0x20 / 32  | 0x00 / 0    |
| Black RAM End   |    8195     |  0x20 / 32  | 0x03 / 3    |
| SDRAM Disk Img  |    7680     |  0x1E / 30  | 0x00 / 0    |
| SDRAM Disk End  |    8191     |  0x1F / 31  | 0xFF / 255  |


Initial default mapping has:

| 16K Page Frame  |  Page Number | Upper | Lower |
|-----------------|--------------|-------|-------|
| 0 (0000-3FFF)   |    8192      | 0x20  | 0x00  |
| 1 (4000-7FFF)   |      1       | 0x00  | 0x01  |
| 2 (8000-BFFF)   |      2       | 0x00  | 0x02  |
| 3 (C000-FFFF)   |      3       | 0x00  | 0x03  |


So the SDRAM Disk Image is at page 7680 (0x1E00), i.e. page# 7680 x 16K
(0x4000) = physical byte address 0x07800000:

      7   |     8     |    0      |    0      |    0      |    0      |    0     |
  0  1  1  1  1  0  0  0  0  0  0  0  0  0  0  0  0  0  0  0  0  0  0  0  0  0  0
  26 25 24.23 22 21 20.19 18 17 16.15 14 13 12.11 10 09 08.07 06 05 04.03 02 01 00
  \--high pg#--/ \-- low order page #--/ \--- In-page low order address bits ----/
       1E                  0

Start phys addr 0x7800000   0x07 80 00 00

This matches the download path in `MultiComp.sv`:
`dl_dsk_base = SDRAM_TOP - (slot+1)*8MB` with `SDRAM_TOP = 0x8000000` and
`DSK_IMAGE_SIZE = 0x0800000`, so the first RAM disk (slot 0) lands in the
top 8 MB at `0x7800000`.

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
| `0x38`        | 1      | CPM       | ROM-disable trigger. Any write disables the boot ROM at `0x0000-0x1FFF` and exposes the RAM beneath it.   |
| `0x47`        | 1      | CPM       | Front-panel data latch (R/W). Software writes drive the 8-bit transparent capture chain; reads return the last-written value. |
| `0x80`-`0x81` | 2      | CPM, Basic| SBCTextDisplayRGB (`n_interface1CS`). VGA/PS-2 text display.                                              |
| `0x82`-`0x83` | 2      | CPM, Basic| bufferedUART (`n_interface2CS`). Serial console.                                                          |
| `0x88`-`0x8F` | 8      | CPM, Basic| SD card controller (`n_sdCardCS`). Register offset via `cpuAddress(2 downto 0)`.                          |
| `0xA0`-`0xA7` | 8      | CPM       | Front-panel subsystem control window (`n_fpSubsysCS`). See Front-panel I/O register map below.            |
| `0xB0`-`0xBF` | 16     | CPM       | MMU register window (`n_mmuCS`). 4 frame-mapping low bytes at `+0..+3` (Z2-compatible), 4 high bytes at `+4..+7`, direct-access pointer at `+8..+11` (little-endian), direct-access data port at `+12`. |

### MMU I/O register window detail
16 consecutive ports, decoded relative to `io_cs` on the low 4 address bits, by default starting at `0xB0`:

  | Offset | Function |
  |---|---|
  | +0..+3 | Frame 0..3 mapping register, bits 7:0 (Z2-compatible) |
  | +4..+7 | Frame 0..3 mapping register, bits 15:8 (extension; reads 0 / ignores writes when `physical_page_bits = 8`) |
  | +8..+11 | Direct-access pointer bytes, little-endian (low byte at +8) |
  | +12 | Direct-access data port (R/W triggers a physical memory cycle at the pointer; pointer post-increments after the access) |
  | +13..+15 | Reserved (reads 0, writes ignored) |

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
