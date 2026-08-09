# Hardware — MultiComp MiSTer Front Panel Interface

## Overview

This directory contains KiCad 10 projects for a hardware interface board that connects the MiSTer SNAC port to front panel elements of the MultiComp system (WS2812 addressable LEDs, shift-register-driven displays, and switch inputs).

## Hardware-Specific Goals

- Provide a clean, manufacturable FPGA-to-front-panel bridge replacing breadboard wiring.
- Translate 3.3V signals from the FPGA to 5V TTL levels using 74AHCT125 buffers.
- Generate a single 3.3V rail from the 5V SNAC connector supply for all logic on the board.
- Support future expansion: ESP32-based telnet console, additional parallel-to-serial shift registers, and latch signal generation for switch states.

## Work Items

### Architectural Overview

The board connects the MiSTer SNAC port signals to front panel elements, serving as the bridge between the FPGA logic and external displays and switches. The primary data path goes from front panel toggle switches through parallel-to-serial shift registers into a latch one-shot that captures switch states when clock activity ceases, then shifts the captured state serially to the FPGA. Additional data flows back from the FPGA through 74AHCT125 level shifters driving WS2812 addressable LEDs for status and diagnostics display.

### MVP: Breadboard Schematic

- Minimal breadboard schematic capturing the FPGA-to-WS2812 and FPGA-to-level-converter connections.
- 3.3V LDO from the SNAC 5V rail with bulk and decoupling caps.
- 74AHCT125 level shifters on all outgoing signals to the FPGA.

### Shift Register + Latch Circuit

- One or more parallel-in/serial-out shift registers (e.g., 74HC165) to read front panel toggle switches.
- Active-low clock disable and latch circuit that watches the clock lines for inactivity and generates a one-shot pulse to capture switch states and shift them to the FPGA serially.

### Front Panel PCB (Future)

- Board with all of the above functions integrated, replacing the breadboard prototype.
- Header or footprint for an ESP32 module enabling telnet-based console access.
- Selectable input source: FTDI USB/serial module  or direct ESP32 TX/RX for the console serial link.

### Future Enhancements

- Additional front panel I/O (LEDs, push buttons, dip switches) routed through the same shift register chain or a dedicated SPI interface.
- Optional SD-card socket for boot media on the front panel board edge.
- Power monitoring and optional over-current protection.
