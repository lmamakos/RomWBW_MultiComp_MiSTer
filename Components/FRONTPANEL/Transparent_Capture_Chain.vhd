-- =====================================================================
-- Transparent_Capture_Chain
--
-- Minimal-footprint PISO shift register for the front-panel LED chain.
-- Identical interface to Universal_Capture_Chain but with no stretching
-- capability at all -- every bit of combined_data is captured
-- transparently. Use this for the bulk of signals (address bus, data
-- bus, register contents, etc.) that don't need pulse stretching, and
-- reserve Universal_Capture_Chain for the few blocks that mix
-- transparent and stretched bits.
--
-- Synthesizes to just TOTAL_WIDTH input registers + TOTAL_WIDTH shift
-- registers + an output mux. No counters, no STRETCH_MASK indexing,
-- no per-bit conditional logic.
--
-- Multiple instances of Transparent_Capture_Chain and
-- Universal_Capture_Chain can be daisy-chained interchangeably via
-- chain_in / chain_out as long as they share the same clk, reset,
-- latch and shift_en signals.
--
-- Handshake (same semantics as Universal_Capture_Chain):
--   * latch = '1'      Snap captured_bits into shift_reg.
--   * shift_en = '1'   Advance shift_reg one bit, importing chain_in
--                      into the high end and exporting bit 0 as
--                      chain_out.
-- latch takes priority over shift_en if both are asserted.
-- =====================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity Transparent_Capture_Chain is
    generic (
        TOTAL_WIDTH : integer := 64
    );
    port (
        clk           : in  std_logic;
        reset         : in  std_logic;
        latch         : in  std_logic;
        shift_en      : in  std_logic;
        combined_data : in  std_logic_vector(TOTAL_WIDTH-1 downto 0);
        chain_in      : in  std_logic;
        chain_out     : out std_logic
    );
end entity;

architecture rtl of Transparent_Capture_Chain is
    signal captured_bits : std_logic_vector(TOTAL_WIDTH-1 downto 0);
    signal shift_reg     : std_logic_vector(TOTAL_WIDTH-1 downto 0);
begin

    -- Capture stage: one register per bit, transparent passthrough.
    -- This matches the timing of Universal_Capture_Chain's transparent
    -- path so the two can be safely interleaved in one logical chain.
    process(clk, reset)
    begin
        if reset = '1' then
            captured_bits <= (others => '0');
        elsif rising_edge(clk) then
            captured_bits <= combined_data;
        end if;
    end process;

    -- Shift register stage. latch takes priority over shift_en.
    process(clk, reset)
    begin
        if reset = '1' then
            shift_reg <= (others => '0');
        elsif rising_edge(clk) then
            if latch = '1' then
                shift_reg <= captured_bits;
            elsif shift_en = '1' then
                shift_reg <= chain_in & shift_reg(TOTAL_WIDTH-1 downto 1);
            end if;
        end if;
    end process;

    chain_out <= shift_reg(0);

end architecture;
