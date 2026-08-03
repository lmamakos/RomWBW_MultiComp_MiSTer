library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity FP_RAM_Store is
    generic ( NUM_LEDS : integer := 256 );
    port (
        clk           : in  std_logic;
        -- Synchronous reset. In addition to the usual meaning, this
        -- also (re-)triggers the post-reset RAM initialization
        -- sequence below, so color_ram/map_ram/fb_ram come back to a
        -- known, reproducible state every time the Z-80 system
        -- resets, not just once at FPGA power-up.
        reset         : in  std_logic;
        -- '0' while the post-reset initialization sequence is
        -- running (see below), '1' once color_ram/map_ram/fb_ram are
        -- known-good. Consumers should hold off reading Port B until
        -- this is asserted.
        init_done     : out std_logic;

        -- Port A: Z80 Access (Read/Write)
        addr_a        : in  unsigned(7 downto 0);
        we_color      : in  std_logic;
        we_map        : in  std_logic;
        we_fb         : in  std_logic;
        din_color     : in  std_logic_vector(47 downto 0);
        din_map       : in  unsigned(7 downto 0);
        din_fb        : in  std_logic;
        dout_map      : out unsigned(7 downto 0);
        dout_fb       : out std_logic;

        -- Port B: Controller Access (Read Only)
        addr_b        : in  unsigned(7 downto 0);
        dout_color_b  : out std_logic_vector(47 downto 0);
        dout_map_b    : out unsigned(7 downto 0);
        dout_fb_b     : out std_logic
    );
end entity;

architecture rtl of FP_RAM_Store is
    attribute ramstyle : string;

    -- Default reset content for color_ram/map_ram/fb_ram. Applied by
    -- the init sequencer below, which runs for NUM_LEDS clk cycles
    -- immediately after every reset (not just at FPGA power-up),
    -- since a real M10K/MLAB block has no synchronous "clear every
    -- location" input. This is the single, authoritative source for
    -- the RAMs' default content; there is no external .mif file (see
    -- HISTORY.md/REQUIREMENTS.md for why: Quartus was found to prefer
    -- a VHDL default over `ram_init_file` whenever both are present,
    -- making a separate .mif redundant and easy to let drift out of
    -- sync).
    --
    -- Colours are stored here in R,G,B byte order -- matching the
    -- software-facing +3 colour-stream port exactly. The GRB reorder
    -- needed for the WS2812/SK6812 wire protocol happens only in
    -- FrontPanel_Subsystem, immediately before the PHY, so this
    -- storage format and the +3 write format agree and the GRB
    -- quirk of the physical LEDs is never visible to software.
    -- Default: on = bright green (R=0x01,G=0xFF,B=0x01), off = dim
    -- green (R=0x01,G=0x10,B=0x01).
    constant DEFAULT_COLOR : std_logic_vector(47 downto 0) := x"01FF01011001";

    type color_mem_t is array (0 to NUM_LEDS-1) of std_logic_vector(47 downto 0);
    signal color_ram : color_mem_t;
    attribute ramstyle of color_ram : signal is "M10K";

    type map_mem_t is array (0 to NUM_LEDS-1) of unsigned(7 downto 0);
    signal map_ram : map_mem_t;
    attribute ramstyle of map_ram : signal is "MLAB";

    type fb_mem_t is array (0 to NUM_LEDS-1) of std_logic;
    signal fb_ram : fb_mem_t;
    attribute ramstyle of fb_ram : signal is "MLAB";

    -- Post-reset RAM initialization sequencer: steps init_addr from 0
    -- to NUM_LEDS-1, writing DEFAULT_COLOR / an identity map entry /
    -- '0' into every location. init_done is held low for the
    -- NUM_LEDS clk cycles this takes.
    signal init_active : std_logic := '1';
    signal init_addr    : unsigned(7 downto 0) := (others => '0');

begin
    init_done <= not init_active;

    -- Port A: Z-80 Interface. Also owns the post-reset init
    -- sequencer, since it's the only writer of these arrays.
    process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                init_active <= '1';
                init_addr   <= (others => '0');
            elsif init_active = '1' then
                color_ram(to_integer(init_addr)) <= DEFAULT_COLOR;
                map_ram(to_integer(init_addr))   <= init_addr;
                fb_ram(to_integer(init_addr))    <= '0';
                if init_addr = NUM_LEDS-1 then
                    init_active <= '0';
                else
                    init_addr <= init_addr + 1;
                end if;
            else
                if we_color = '1' then color_ram(to_integer(addr_a)) <= din_color; end if;
                if we_map = '1'   then map_ram(to_integer(addr_a))   <= din_map;   end if;
                if we_fb = '1'    then fb_ram(to_integer(addr_a))    <= din_fb;    end if;
            end if;

            dout_map <= map_ram(to_integer(addr_a));
            dout_fb  <= fb_ram(to_integer(addr_a));
        end if;
    end process;

    -- Port B: Front Panel Controller Interface
    process(clk)
    begin
        if rising_edge(clk) then
            dout_color_b <= color_ram(to_integer(addr_b));
            dout_map_b   <= map_ram(to_integer(addr_b));
            dout_fb_b    <= fb_ram(to_integer(addr_b));
        end if;
    end process;
end architecture;
