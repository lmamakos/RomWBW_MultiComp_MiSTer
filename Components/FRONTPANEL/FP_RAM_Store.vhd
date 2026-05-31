library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity FP_RAM_Store is
    generic ( NUM_LEDS : integer := 256 );
    port (
        clk           : in  std_logic;
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
    attribute ram_init_file : string;

    type color_mem_t is array (0 to NUM_LEDS-1) of std_logic_vector(47 downto 0);
    signal color_ram : color_mem_t;
    attribute ramstyle of color_ram : signal is "M10K";
    attribute ram_init_file of color_ram : signal is "colors.mif";

    type map_mem_t is array (0 to NUM_LEDS-1) of unsigned(7 downto 0);
    signal map_ram : map_mem_t;
    attribute ramstyle of map_ram : signal is "MLAB";
    attribute ram_init_file of map_ram : signal is "mapping.mif";

    type fb_mem_t is array (0 to NUM_LEDS-1) of std_logic;
    signal fb_ram : fb_mem_t := (others => '0');
    attribute ramstyle of fb_ram : signal is "MLAB";

begin
    -- Port A: Z-80 Interface
    process(clk)
    begin
        if rising_edge(clk) then
            if we_color = '1' then color_ram(to_integer(addr_a)) <= din_color; end if;
            if we_map = '1'   then map_ram(to_integer(addr_a))   <= din_map;   end if;
            if we_fb = '1'    then fb_ram(to_integer(addr_a))    <= din_fb;    end if;
            
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
