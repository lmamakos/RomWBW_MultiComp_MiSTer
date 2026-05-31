-- =====================================================================
-- FrontPanel_Subsystem
--
-- Top level of the front-panel LED subsystem. Owns the Z-80 I/O port
-- decoder, the dual-port LED-state RAMs, the per-LED interpolation /
-- brightness math, and the WS2812/SK6812 PHY that shifts the final
-- pixel data out on a single GPIO pin.
--
-- Clocking: a single clk (frequency = SYS_CLK Hz) clocks everything.
-- The PHY bit-time constants are derived from SYS_CLK so the WS2812
-- 1.25 us bit period is preserved regardless of clock frequency.
--
-- I/O register map (8 consecutive ports, aligned on a multiple-of-8
-- boundary, decoded relative to the io_cs chip-select input that the
-- external decoder drives):
--   +0   R/W  global brightness (0..255, 8-bit linear scale)
--   +1   R/W  fade rate (0..255, step per refresh tick)
--   +2   R/W  global pointer (LED index for +3, +5, +6)
--   +3   W    colour stream: 6 bytes per LED (on-G, on-R, on-B,
--                    off-G, off-R, off-B); auto-advances pointer.
--   +4   R/W  mode register (bit 0: 0 = mirror chain, 1 = framebuffer)
--   +5   R/W  mapping table entry at global_ptr (read or write
--              auto-advances the pointer).
--   +6   R/W  framebuffer bit at global_ptr (read or write
--              auto-advances the pointer).
--   +7   --   reserved (reads 0, writes ignored)
--
-- This module looks only at the low 3 bits of addr to pick a register
-- within the 8-port window. The integrator decides where the window
-- lives in the Z-80 I/O space via io_cs (same pattern as the MMU's I/O
-- decoder).
-- =====================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity FrontPanel_Subsystem is
    generic (
        NUM_LEDS : integer := 256;
        SYS_CLK  : integer := 50000000 -- 50MHz default
    );
    port (
        clk          : in  std_logic;
        reset        : in  std_logic;
        refresh_tick : in  std_logic; -- ~60Hz Pulse, kicks off a frame

        -- Z80 Bus Interface. io_cs is asserted by the external I/O
        -- decoder when an I/O cycle targets this block's 8-port
        -- window; this module then uses addr(2 downto 0) as the
        -- in-window offset.
        iorq_n       : in  std_logic;
        wr_n         : in  std_logic;
        rd_n         : in  std_logic;
        io_cs        : in  std_logic;
        addr         : in  std_logic_vector(7 downto 0);
        din          : in  std_logic_vector(7 downto 0);
        dout         : out std_logic_vector(7 downto 0);

        -- Z80 PISO Chain Interface (to Universal_Capture_Chain instances)
        latch        : out std_logic;
        shift_en     : out std_logic;
        chain_in     : in  std_logic;

        -- Physical LED Output (WS2812/SK6812 single-wire)
        led_serial   : out std_logic
    );
end entity;

architecture rtl of FrontPanel_Subsystem is
    -- -----------------------------------------------------------------
    -- PHY timing constants derived from SYS_CLK. WS2812/SK6812 use a
    -- 1.25 us bit period (800 kHz); within each bit period the line is
    -- held high for either ~340 ns (T0H, encodes a '0') or ~700 ns
    -- (T1H, encodes a '1') and low for the remainder. Rounding to the
    -- nearest integer count of clk cycles is more than precise enough
    -- for the WS2812's >150 ns timing tolerance.
    -- -----------------------------------------------------------------
    constant T_BIT : integer := SYS_CLK / 800000;   -- ~1.25 us
    constant T_T0H : integer := SYS_CLK / 2941176;  -- ~340 ns
    constant T_T1H : integer := SYS_CLK / 1428571;  -- ~700 ns

    -- I/O Streaming Registers
    signal global_ptr    : unsigned(7 downto 0) := (others => '0');
    signal sub_ptr       : integer range 0 to 5 := 0;
    signal global_bright : unsigned(7 downto 0) := x"80";
    signal fade_rate     : unsigned(7 downto 0) := x"08";
    signal mode_reg      : std_logic := '0';
    signal color_buf     : std_logic_vector(47 downto 0);

    -- RAM Wrapper Interface
    signal we_col, we_map, we_fb : std_logic := '0';
    signal dout_map : unsigned(7 downto 0);
    signal dout_fb  : std_logic;
    signal ctrl_idx : unsigned(7 downto 0) := (others => '0');
    signal r_col_b  : std_logic_vector(47 downto 0);
    signal r_map_b  : unsigned(7 downto 0);
    signal r_fb_b   : std_logic;

    -- Master Controller State Machine
    type state_t is (IDLE, LATCH_ST, SHADOW_SHIFT, FETCH_MEM, WAIT_MEM, MATH_INIT, MATH_CHANNEL, MATH_BRIGHT, SEND_PHY);
    signal state : state_t := IDLE;

    signal bit_counter : integer range 0 to NUM_LEDS-1 := 0;
    signal shadow_reg  : std_logic_vector(NUM_LEDS-1 downto 0);

    -- Alpha RAM (Internal MLAB)
    type alpha_mem_t is array (0 to NUM_LEDS-1) of unsigned(7 downto 0);
    signal alpha_ram : alpha_mem_t := (others => x"00");
    attribute ramstyle : string;
    attribute ramstyle of alpha_ram : signal is "MLAB";

    -- DSP / Math Engine Signals
    signal cur_alpha  : unsigned(7 downto 0);
    signal target_bit : std_logic;
    signal mult_op1, mult_op2 : signed(8 downto 0);
    signal product            : signed(16 downto 0);
    signal interp_rgb         : unsigned(23 downto 0);
    signal final_rgb          : std_logic_vector(23 downto 0);
    signal ch_idx             : integer range 0 to 2 := 0;

    -- PHY Signals
    signal phy_start, phy_busy : std_logic := '0';
    signal phy_timer   : integer range 0 to T_BIT := 0;
    signal phy_bit_idx : integer range 0 to 23 := 23;
    signal phy_shift   : std_logic_vector(23 downto 0);

begin
    -- 1. RAM Store Instance
    U_RAM : entity work.FP_RAM_Store
        generic map (NUM_LEDS => NUM_LEDS)
        port map (
            clk => clk,
            addr_a => global_ptr,
            we_color => we_col, we_map => we_map, we_fb => we_fb,
            din_color => color_buf, din_map => unsigned(din), din_fb => din(0),
            dout_map => dout_map, dout_fb => dout_fb,
            addr_b => ctrl_idx,
            dout_color_b => r_col_b, dout_map_b => r_map_b, dout_fb_b => r_fb_b
        );

    -- 2. Z80 I/O Streaming Port Decoder
    process(clk, reset)
    begin
        if reset = '1' then
            global_ptr <= (others => '0');
            sub_ptr <= 0;
            global_bright <= x"80";
            fade_rate <= x"08";
            mode_reg <= '0';
            color_buf <= (others => '0');
            we_col <= '0';
            we_map <= '0';
            we_fb <= '0';
            dout <= (others => '0');
        elsif rising_edge(clk) then
            we_col <= '0'; we_map <= '0'; we_fb <= '0';

            -- Always-defined dout default: outside of an I/O read cycle
            -- we drive zero so the bus consumer never sees stale data.
            dout <= x"00";

            -- Write path. Offsets within the 8-port window:
            --   +3 collects 6 colour bytes per LED before committing
            --      and advancing the pointer.
            --   +5 / +6 auto-advance the pointer on every write.
            if io_cs = '1' and iorq_n = '0' and wr_n = '0' then
                case addr(2 downto 0) is
                    when "000" => global_bright <= unsigned(din);
                    when "001" => fade_rate <= unsigned(din);
                    when "010" => global_ptr <= unsigned(din); sub_ptr <= 0;
                    when "011" =>
                        color_buf <= color_buf(39 downto 0) & din;
                        if sub_ptr = 5 then
                            we_col <= '1'; sub_ptr <= 0; global_ptr <= global_ptr + 1;
                        else sub_ptr <= sub_ptr + 1; end if;
                    when "100" => mode_reg <= din(0);
                    when "101" => we_map <= '1'; global_ptr <= global_ptr + 1;
                    when "110" => we_fb  <= '1'; global_ptr <= global_ptr + 1;
                    when others => null; -- +7 reserved
                end case;
            end if;

            -- Read path. Offsets +5 and +6 auto-increment global_ptr
            -- on read as well as on write so software can stream
            -- contents out without managing the pointer manually.
            if io_cs = '1' and iorq_n = '0' and rd_n = '0' then
                case addr(2 downto 0) is
                    when "000" => dout <= std_logic_vector(global_bright);
                    when "001" => dout <= std_logic_vector(fade_rate);
                    when "010" => dout <= std_logic_vector(global_ptr);
                    when "100" => dout <= (0 => mode_reg, others => '0');
                    when "101" => dout <= std_logic_vector(dout_map); global_ptr <= global_ptr + 1;
                    when "110" => dout <= (0 => dout_fb, others => '0'); global_ptr <= global_ptr + 1;
                    when others => null; -- +3 (write-only) and +7 (reserved) read 0
                end case;
            end if;
        end if;
    end process;

    -- 3. Master Controller & Math Engine
    product <= mult_op1 * mult_op2; -- Shared DSP Multiplier

    process(clk, reset)
        variable on_val, off_val : unsigned(7 downto 0);
        variable step_res : signed(8 downto 0);
    begin
        if reset = '1' then
            state       <= IDLE;
            bit_counter <= 0;
            ctrl_idx    <= (others => '0');
            shadow_reg  <= (others => '0');
            ch_idx      <= 0;
            target_bit  <= '0';
            cur_alpha   <= (others => '0');
            mult_op1    <= (others => '0');
            mult_op2    <= (others => '0');
            interp_rgb  <= (others => '0');
            final_rgb   <= (others => '0');
            latch       <= '0';
            shift_en    <= '0';
            phy_start   <= '0';
            -- alpha_ram is left to its declared initial value (others => x"00").
        elsif rising_edge(clk) then
            latch <= '0'; shift_en <= '0'; phy_start <= '0';

            case state is
                when IDLE =>
                    if refresh_tick = '1' then
                        state <= LATCH_ST; bit_counter <= 0;
                    end if;

                when LATCH_ST =>
                    latch <= '1'; state <= SHADOW_SHIFT;

                when SHADOW_SHIFT =>
                    shift_en <= '1';
                    shadow_reg <= shadow_reg(NUM_LEDS-2 downto 0) & chain_in;
                    if bit_counter = NUM_LEDS-1 then
                        ctrl_idx <= (others => '0'); state <= FETCH_MEM;
                    else bit_counter <= bit_counter + 1; end if;

                when FETCH_MEM =>
                    -- Address was driven into the RAM in the previous
                    -- state via ctrl_idx; the synchronous RAM presents
                    -- valid r_col_b/r_map_b/r_fb_b on the next clock.
                    state <= WAIT_MEM;

                when WAIT_MEM =>
                    cur_alpha <= alpha_ram(to_integer(ctrl_idx));
                    state <= MATH_INIT;

                when MATH_INIT =>
                    -- Select Target Bit (Mirror vs Software Mode)
                    if mode_reg = '0' then target_bit <= shadow_reg(to_integer(r_map_b));
                    else target_bit <= r_fb_b; end if;

                    -- Alpha Fade Logic
                    if target_bit = '1' then
                        if cur_alpha <= (255 - fade_rate) then alpha_ram(to_integer(ctrl_idx)) <= cur_alpha + fade_rate;
                        else alpha_ram(to_integer(ctrl_idx)) <= x"FF"; end if;
                    else
                        if cur_alpha >= fade_rate then alpha_ram(to_integer(ctrl_idx)) <= cur_alpha - fade_rate;
                        else alpha_ram(to_integer(ctrl_idx)) <= x"00"; end if;
                    end if;

                    ch_idx <= 0; state <= MATH_CHANNEL;

                when MATH_CHANNEL =>
                    -- Interpolation: Off + ((On-Off)*Alpha)/256
                    case ch_idx is
                        when 0 => on_val := unsigned(r_col_b(47 downto 40)); off_val := unsigned(r_col_b(23 downto 16));
                        when 1 => on_val := unsigned(r_col_b(39 downto 32)); off_val := unsigned(r_col_b(15 downto 8));
                        when 2 => on_val := unsigned(r_col_b(31 downto 24)); off_val := unsigned(r_col_b(7 downto 0));
                    end case;

                    mult_op1 <= signed('0' & on_val) - signed('0' & off_val);
                    mult_op2 <= signed('0' & cur_alpha);

                    step_res := signed('0' & off_val) + product(15 downto 8);
                    interp_rgb( (2-ch_idx)*8+7 downto (2-ch_idx)*8 ) <= unsigned(step_res(7 downto 0));

                    if ch_idx = 2 then state <= MATH_BRIGHT; ch_idx <= 0;
                    else ch_idx <= ch_idx + 1; end if;

                when MATH_BRIGHT =>
                    -- Brightness Scaling
                    case ch_idx is
                        when 0 => mult_op1 <= signed('0' & interp_rgb(23 downto 16));
                        when 1 => mult_op1 <= signed('0' & interp_rgb(15 downto 8));
                        when 2 => mult_op1 <= signed('0' & interp_rgb(7 downto 0));
                    end case;
                    mult_op2 <= signed('0' & global_bright);

                    final_rgb( (2-ch_idx)*8+7 downto (2-ch_idx)*8 ) <= std_logic_vector(product(15 downto 8));

                    if ch_idx = 2 then state <= SEND_PHY;
                    else ch_idx <= ch_idx + 1; end if;

                when SEND_PHY =>
                    if phy_busy = '0' then
                        phy_start <= '1';
                        if ctrl_idx = NUM_LEDS-1 then state <= IDLE;
                        else ctrl_idx <= ctrl_idx + 1; state <= FETCH_MEM; end if;
                    end if;
            end case;
        end if;
    end process;

    -- 4. WS2812/SK6812 PHY. Counts in clk cycles using SYS_CLK-derived
    -- constants T_T0H, T_T1H, T_BIT so the protocol timing holds at
    -- any clock frequency >= ~10 MHz.
    process(clk, reset)
    begin
        if reset = '1' then
            led_serial  <= '0';
            phy_busy    <= '0';
            phy_timer   <= 0;
            phy_bit_idx <= 23;
            phy_shift   <= (others => '0');
        elsif rising_edge(clk) then
            if phy_busy = '0' then
                led_serial <= '0';
                if phy_start = '1' then
                    phy_shift <= final_rgb; phy_bit_idx <= 23;
                    phy_timer <= 0; phy_busy <= '1';
                end if;
            else
                phy_timer <= phy_timer + 1;
                if phy_shift(phy_bit_idx) = '1' then
                    -- "1" bit: high for T_T1H, low for the remainder
                    if phy_timer < T_T1H then led_serial <= '1';
                    else led_serial <= '0'; end if;
                else
                    -- "0" bit: high for T_T0H, low for the remainder
                    if phy_timer < T_T0H then led_serial <= '1';
                    else led_serial <= '0'; end if;
                end if;

                if phy_timer >= T_BIT - 1 then
                    phy_timer <= 0;
                    if phy_bit_idx = 0 then phy_busy <= '0';
                    else phy_bit_idx <= phy_bit_idx - 1; end if;
                end if;
            end if;
        end if;
    end process;
end architecture;
