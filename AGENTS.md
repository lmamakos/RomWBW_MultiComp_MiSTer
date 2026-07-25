# MultiComp MiSTer FPGA

This project implements a Z-80 based system to run CP/M 2.2, CP/M 3.0 and
other operating systems at present.  The intent is to port the RomWBW
system to run on this core in the future.

## Project structure

- **Top-level entity**: `sys_top` (`sys/sys_top.v`). Wraps the MiSTer framework
  (video, audio, SD, HPS I/O) and instantiates CPU/memory components.
- **`MultiComp.sv`**: `module emu` — the MiSTer core shell. Connects to
  `sys_top` via MiSTer's standard interface. Not the top-level entity.
- **CPU cores** under `Components/` (Z80 via T80 VHD).
  Machine selection is done via OSD, wired through `MultiComp.sv`.  

## Quartus revision

`MultiComp.qpf` defines a single revision, `MultiComp`, with its settings
in `MultiComp.qsf` (USB support, Z80, SignalTap enabled, aggressive
optimization settings).

Run Analysis & Synthesis after changing `.qsf` assignments.

## How to add HDL source files

Three mechanisms, pick the right one:

1. **Files under `sys/`**: These files **MUST NEVER BE MODIFIED** and are maintained
   externally.  They are an interface to the "hard wired" ARM CPU running a
   common support application for all MiSTer cores.
2. **Files elsewhere (Components/, new dirs)**: add a direct
   `set_global_assignment -name SYSTEMVERILOG_FILE path/to/your.sv` to
   `MultiComp.qsf`.
3. **IP cores**: create a `.qip` file (same format as `sys.qip`) and add
   `set_global_assignment -name QIP_FILE path/to/core.qip` to
   `MultiComp.qsf`.

## Conditional compilation macros

All macros in `MultiComp.qsf` are **commented out**:

```
ARCADE_SYS, USE_FB, USE_SDRAM, USE_DDRAM, DEBUG_NOHDMI
```

`MISTER_DUAL_SDRAM` in `sys_dual_sdram.tcl` is unused (file is never
sourced).

There are **no active conditional compilation macros** in the current build.

## Build commands

### Using the build wrapper scripts (recommended)

Two wrapper scripts in `tools/` simplify remote Quartus invocation via SSH+Docker on `tycho`:

```sh
# Full build (analysis, synthesis, place & route):
tools/build.sh

# Synthesis only (skip place & route):
tools/build.sh synth

# Show help:
tools/build.sh help

# Custom quartus_sh arguments:
tools/quartus_build.sh --flow compile_synthesis MultiComp -c MultiComp
```

**How it works:**
- Both scripts detect the project root automatically (by finding `MultiComp.qpf`/`MultiComp.qsf`).
- `tools/quartus_build.sh`: low-level wrapper that SSH's to `tycho`, runs Docker with Quartus 17.0, and passes all arguments directly to `quartus_sh`.
- `tools/build.sh`: high-level convenience wrapper with common targets (`full`, `synth`, `help`).
- The Docker container mounts the local project directory as `/build`, so output files are written back to the local `output_files/MultiComp.rbf`.

### Manual build via Quartus GUI/CLI (advanced)

If you have Quartus installed locally:

```sh
# GUI: open MultiComp.qpf, Process → Start Compilation
# CLI (headless):
quartus_sh --flow compile MultiComp -c MultiComp
```

Output: `output_files/MultiComp.rbf`.

**Note:** Building the HDL core typically happens via the wrapper scripts above, which invoke
a containerized Quartus environment on `tycho` to avoid local tool dependencies.

## Target device

Cyclone V `5CSEBA6U23I7` (DE10-Nano / MiSTer).

## Important gotchas
- None of the files in the  `sys/` directory shall be modified or changed in any way.
  They are maintained externally and define an interface to the ARM processor running
  a support application for the FPGA core.
- **PLLs are generated IP** — `rtl/pll/`, `sys/pll_hdmi/`, `sys/pll_audio/`.
  Regenerate via MegaWizard; do not hand-edit `.v` files in these dirs.
- **No automated tests exist.** Verification is done by compiling and running
  on hardware or in ModelSim.
- **The `*.qsf~` file** and other files with a `~` suffix are a stale editor
  backup files; ignore them.
- When adding pins, add both the `set_location_assignment` and
  `set_instance_assignment` IO standard, matching the pattern of existing
  entries in the `.qsf`.
