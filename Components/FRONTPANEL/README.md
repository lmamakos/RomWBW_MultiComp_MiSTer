# Front Panel Interface

> **Status (2026-05):** Initial integration done. The front-panel
> subsystem is now wired into the `MicrocomputerZ80CPM` core with a
> single 8-bit `Transparent_Capture_Chain` sourced from a new R/W
> latch at I/O port 0x47, and the subsystem's 8-port control window
> occupies I/O ports 0xA0..0xA7. The WS2812 serial line emerges on
> `USER_OUT[4]` of the MiSTer USER_IO port. The two new VHDL files
> (`FP_RAM_Store`, `Transparent_Capture_Chain`, `Universal_Capture_Chain`,
> `FrontPanel_Subsystem`) are referenced from `MultiComp.qsf`. All four
> files analyze cleanly under GHDL
> VHDL-2008. The PHY timing tracks the `SYS_CLK` generic, the I/O
> port-decoder process has a full reset clause, `STRETCH_MASK` is
> explicitly width-checked, and the I/O port window is decoded
> relative to an external `io_cs` chip-select (same pattern as the
> MMU). Hardware bring-up not yet attempted.

## Ultimate front panel light display

The premise for this is: if you have a CPU implemented in an FPGA,
then you have access to _all_ of the internal signals inside the CPU
that are normally inaccessible.  Given that, why not implement the
ultimate in blinkenlights front panel!

Sure, like an IMSAI you can show the data and address bus.  But
wouldn't it be interesting to see what the current value of the A
register is?  Why stop there; how about having **ALL** the registers
displayed, each with their own LEDs?  And likewise for control
signals, too.

The implementation approach is to use RGB addressable LEDs (like the
WS2812 devices) for the indicators.  In this way, only a single output
line from the FPGA is required to operate all of the LEDs.  There's
also the opportunity to use different colors, either for grouping
signals/registers, or to denote some alternate function (e.g.,
physical vs. mapped logical address.)

### Features

1. Each LED indicator should have a configurable and programmable ON
and OFF color (8 bits each, RGB).  The idea is that when the LED
changes state to OFF, it doesn't go completely dark, but is just
another (likely much dimmer) color.

2. The individual LED ON and OFF RGB values should be settable from the software
running on the Z-80 CPU by accessing some I/O ports.  

3. It should be possible to configure a gradual fade between the ON
and OFF transition as well as the OFF to ON transition.  This would be
used to simulate effecs such as the behavior of incandescent lamps.

4. It should be possible to select some LEDs to capture brief ON
conditions and stretch them so the brief ON state is visible to the
naked eye.  This would be used to indicate certain signals that do not
occur frequently, such as interrupt requests or other signals.

5. Some of the LEDs are just connected to latched I/O port output
values.  This is similar to port 0xFF on IMSAI computers which allow
programs to set indications.  In this system, we'll have enough LEDs
to have more than one 8 bit "register" for this purpose.

6. The implementation should have a component that connects to the
signals we want to monitor and indicate on the LEDs.   One or more
of these would be chained together in a long shift-register.


## I/O register map

The `FrontPanel_Subsystem` exposes a window of 8 consecutive I/O ports.
The base address of that window is set entirely by the external I/O
decoder that drives the `io_cs` input; this module only looks at the
low 3 bits of `addr` to pick a register within the window. The
integrator should align the window on a multiple-of-8 boundary so the
three low address bits are a clean offset into the window.

| Offset | R/W | Function                                                       |
|--------|-----|----------------------------------------------------------------|
| +0     | R/W | Global brightness (0..255, 8-bit linear scale).                |
| +1     | R/W | Fade rate (step per refresh tick).                             |
| +2     | R/W | Global pointer (LED index used by +3, +5, +6).                 |
| +3     | W   | Colour stream. Six bytes per LED: on-G, on-R, on-B, off-G, off-R, off-B. On the sixth byte the global pointer advances by 1. |
| +4     | R/W | Mode register (bit 0: 0 = mirror capture chain, 1 = framebuffer). |
| +5     | R/W | Mapping-table entry at the global pointer. Both reads and writes auto-advance the pointer by 1. |
| +6     | R/W | Framebuffer bit at the global pointer. Both reads and writes auto-advance the pointer. |
| +7     | --  | Reserved (reads 0, writes ignored).                            |

## Capture-chain variants

Two interoperable PISO capture components are provided. Both share the
same `chain_in` / `chain_out` / `latch` / `shift_en` handshake, so any
mix of them can be daisy-chained to form one logical chain.

- **`Universal_Capture_Chain`** — supports both transparent and
  stretched bits in a single instance. `STRETCH_MASK` is a per-bit
  mask: `'1'` enables stretching, `'0'` is transparent. A VHDL-2008
  `if-generate` emits a per-bit hold counter only for bits where
  `STRETCH_MASK(i) = '1'`, so resource cost scales with the number of
  stretched bits, not with `TOTAL_WIDTH`.

- **`Transparent_Capture_Chain`** — no stretching, no per-bit
  conditional logic, no counters. Recommended for the bulk of signals
  (address bus, data bus, register contents) that don't need
  stretching. Use `Universal_Capture_Chain` only for blocks that
  actually mix transparent and stretched bits.

## Example integration/usage

In this example we wire two capture chains in series: one transparent
chain for the address/data/status bus signals, and one universal chain
for the few control signals that need pulse stretching.

VHDL

    -- 24-bit transparent chain for bus signals
    --   [23..16] = Address bus high (Transparent)
    --   [15..8]  = Address bus low  (Transparent)
    --   [7..0]   = Data bus         (Transparent)
    U_BUS : entity work.Transparent_Capture_Chain
        generic map (
            TOTAL_WIDTH => 24
        )
        port map (
            clk           => sys_clk,
            reset         => sys_rst,
            latch         => fp_latch,
            shift_en      => fp_shift,
            combined_data => z_addr & z_dout,
            chain_in      => '0',
            chain_out     => bus_chain_to_ctrl
        );

    -- 8-bit mixed chain for control signals; bits 1 and 0 are stretched
    --   [7..2]   = Status flags (Transparent)
    --   [1]      = IACK         (Stretched)
    --   [0]      = INT          (Stretched)
    U_CTRL : entity work.Universal_Capture_Chain
        generic map (
            TOTAL_WIDTH  => 8,
            HOLD_CYCLES  => 2500000,
            STRETCH_MASK => "00000011" -- Only bits 0 and 1 are stretched
        )
        port map (
            clk           => sys_clk,
            reset         => sys_rst,
            latch         => fp_latch,
            shift_en      => fp_shift,
            combined_data => cpu_status,
            chain_in      => bus_chain_to_ctrl,
            chain_out     => serial_state
        );

Why this split is useful:

    Resource Efficiency: Transparent_Capture_Chain instantiates no
    counters at all, so the 24 bus signals cost only their shift-
    register flops. Universal_Capture_Chain's if-generate emits hold
    counters only for the two control bits that need stretching.

    Synchronous Capture: All capture and stretching happen on the same
    clock, so latch/shift handshake is consistent across chain
    segments.
    or jitter between external modules.

This gives you a powerful, software-like "Config" at the top of your
VHDL file that determines the visual behavior of every single bit on
your front panel.


## LED String Update Rate

1. The Protocol Bottleneck

The WS2812/SK6812 protocol uses a fixed timing where each bit takes
exactly 1.25µs to transmit.

    Bits per LED: Each RGB LED requires 24 bits (8 bits Red+8 bits
    Green+8 bits Blue).

    Total Bits: For 256 LEDs, you must transmit 256×24=6,144 bits.

    Transmission Time: 6,144 bits×1.25μs/bit=7.68ms.

    Reset Time: After the data, the line must stay low for a "Reset"
    period (typically >80μs for SK6812).

Total time to update the entire 256-LED string once is approximately
7.76ms.

2. Maximum Theoretical Frame Rate

If you were to push the string as fast as the physical wire allows:
Max Frequency=0.00776s1​≈128.8Hz

Conclusion: target 100 Hz update rate, derived from the 50 MHz system clock
