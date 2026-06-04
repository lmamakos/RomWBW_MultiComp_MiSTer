-- This file is copyright by Grant Searle 2014
-- You are free to use this file in your own projects but must never charge for it nor use it without
-- acknowledgement.
-- Please ask permission from Grant Searle before republishing elsewhere.
-- If you use this file or any part of it, please add an acknowledgement to myself and
-- a link back to my main web site http://searle.hostei.com/grant/    
-- and to the "multicomp" page at http://searle.hostei.com/grant/Multicomp/index.html
--
-- Please check on the above web pages to see if there are any updates before using this file.
-- If for some reason the page is no longer available, please search for "Grant Searle"
-- on the internet to see if I have moved to another web hosting service.
--
-- Grant Searle
-- eMail address available on my main web page link above.

library ieee;
use ieee.std_logic_1164.all;
use  IEEE.STD_LOGIC_ARITH.all;
use  IEEE.STD_LOGIC_UNSIGNED.all;

entity MicrocomputerZ80CPM is
	port(
		N_RESET	   		: in std_logic;
		clk				: in std_logic;
		baud_increment	: in std_logic_vector(15 downto 0);

		sramData		: inout std_logic_vector(7 downto 0);
		sramAddress		: out std_logic_vector(15 downto 0);
		n_sRamWE		: out std_logic;
		n_sRamCS		: out std_logic;
		n_sRamOE		: out std_logic;
		n_sRamLB		: out std_logic;
		n_sRamUB		: out std_logic;
		
		rxd1			: in std_logic;
		txd1			: out std_logic;
		rts1			: out std_logic;
		cts1			: in std_logic;  -- Added CTS input

		rxd2			: in std_logic;
		txd2			: out std_logic;
		rts2			: out std_logic;
		
		videoSync		: out std_logic;
		video			: out std_logic;

		R       		: out std_logic_vector(1 downto 0);
		G       		: out std_logic_vector(1 downto 0);
		B       		: out std_logic_vector(1 downto 0);
		HS		  		: out std_logic;
		VS 				: out std_logic;
		hBlank			: out std_logic;
		vBlank			: out std_logic;
		cepix  			: out std_logic;

		ps2Clk			: in std_logic;
		ps2Data			: in std_logic;

		sdCS			: out std_logic;
		sdMOSI			: out std_logic;
		sdMISO			: in std_logic;
		sdSCLK			: out std_logic;
		driveLED		: out std_logic :='1';

		usbCS			: out std_logic;
		usbMOSI			: out std_logic;
		usbMISO			: in std_logic;
		usbSCLK			: out std_logic;

		-- Front-panel WS2812/SK6812 single-wire serial output. Initial
		-- integration: 8 bits latched from I/O port 0x47 drive an 8-bit
		-- transparent capture chain into the FrontPanel_Subsystem,
		-- which then shifts a single-wire colour stream out to the LED
		-- string.
		fpLED_serial	: out std_logic;

		-- SDRAM client interface. The Z-80's logical address is
		-- translated by the on-core MMU; any physical address that
		-- does not fall inside the low 64 KB block-RAM region exits
		-- through these ports to the SDRAM controller in MultiComp.sv.
		sdram_addr		: out std_logic_vector(26 downto 0);
		sdram_din		: out std_logic_vector(7 downto 0);
		sdram_we		: out std_logic;
		sdram_rd		: out std_logic;
		sdram_dout		: in  std_logic_vector(7 downto 0);
		sdram_ready		: in  std_logic
		);
end MicrocomputerZ80CPM;

architecture struct of MicrocomputerZ80CPM is

    signal reset_counter : unsigned(15 downto 0) := (others => '0');
    signal reset_n_internal : std_logic := '0';  -- Active low internal reset

	signal n_WR						: std_logic;
	signal n_RD						: std_logic;
	signal cpuAddress				: std_logic_vector(15 downto 0);
	signal cpuDataOut				: std_logic_vector(7 downto 0);
	signal cpuDataIn				: std_logic_vector(7 downto 0);

	signal basRomData				: std_logic_vector(7 downto 0);
	signal internalRam1DataOut		: std_logic_vector(7 downto 0);
	signal internalRam2DataOut		: std_logic_vector(7 downto 0);
	signal interface1DataOut		: std_logic_vector(7 downto 0);
	signal interface2DataOut		: std_logic_vector(7 downto 0);
	signal ch376sDataOut			: std_logic_vector(7 downto 0);
	signal sdCardDataOut			: std_logic_vector(7 downto 0);
	signal fpLatchDataOut			: std_logic_vector(7 downto 0);
	signal fpSubsysDataOut			: std_logic_vector(7 downto 0);

	signal n_memWR					: std_logic :='1';
	signal n_memRD 					: std_logic :='1';

	signal n_ioWR					: std_logic :='1';
	signal n_ioRD 					: std_logic :='1';
	
	signal n_MREQ					: std_logic :='1';
	signal n_IORQ					: std_logic :='1';	

	signal n_int1					: std_logic :='1';	
	signal n_int2					: std_logic :='1';	
	
	signal n_externalRamCS			: std_logic :='1';
	signal n_internalRam1CS			: std_logic :='1';
	signal n_internalRam2CS			: std_logic :='1';
	signal n_basRomCS				: std_logic :='1';
	signal n_interface1CS			: std_logic :='1';
	signal n_interface2CS			: std_logic :='1';
	signal n_ch376sCS				: std_logic :='1';
	signal n_sdCardCS				: std_logic :='1';
	signal n_fpLatchCS				: std_logic :='1';   -- I/O port 0x47 latch
	signal n_fpSubsysCS				: std_logic :='1';   -- FrontPanel_Subsystem 8-port window at 0xA0..0xA7
	signal n_mmuCS					: std_logic :='1';   -- MMU 16-port window at 0xB0..0xBF

	-- MMU plumbing. The MMU translates the Z-80's 16-bit logical address
	-- into a 27-bit physical address (physical_page_bits = 13), covering
	-- the full 128 MB of SDRAM (8192 pages x 16 KB). The same block
	-- exposes the four mapping registers, a direct-access pointer, and a
	-- direct-access data port, all through an external chip-select
	-- (mmu_io_cs) tied to the 0xB0..0xBF window.
	signal mmu_phys_addr			: std_logic_vector(26 downto 0);
	signal mmu_dataOut				: std_logic_vector(7 downto 0);
	signal mmu_io_cs				: std_logic;
	signal mmu_req_mem_in			: std_logic;
	signal mmu_req_io_in			: std_logic;
	signal mmu_req_read				: std_logic;
	signal mmu_req_write			: std_logic;
	signal mmu_req_mem_out			: std_logic;
	signal mmu_req_io_out			: std_logic;
	signal mmu_cpu_wait				: std_logic;
	signal mmu_reset				: std_logic;

	-- Physical-memory decode: the low 64 KB of physical address space
	-- (phys_addr(21:16) = "000000") is covered by the on-chip block RAM.
	-- Everything else routes to SDRAM.
	signal phys_in_blockram			: std_logic;
	signal phys_in_sdram			: std_logic;

	-- SDRAM client FSM. The CPU is stalled via wait_n until the SDRAM
	-- controller pulses `ready`. Reads latch dout into sdramReadData
	-- for the cpuDataIn mux.
	type sdram_state_t is (S_IDLE, S_REQ, S_DONE);
	signal sdram_state				: sdram_state_t := S_IDLE;
	signal sdram_we_reg				: std_logic := '0';
	signal sdram_rd_reg				: std_logic := '0';
	signal sdramReadData			: std_logic_vector(7 downto 0) := (others => '0');
	signal sdram_wait_n				: std_logic := '1';

	-- Combined wait_n into the t80s core: AND of MMU's wait request and
	-- the SDRAM FSM's stall.
	signal cpu_wait_n				: std_logic;

	-- Front-panel latch holding the 8 bits driven onto the capture chain.
	signal fpLatch					: std_logic_vector(7 downto 0) := (others => '0');

	-- Front-panel refresh tick: ~60 Hz pulse (one clk-wide) generated
	-- from the 50 MHz system clock to drive a frame of LED updates.
	-- 50_000_000 / 60 = 833_333 cycles per tick.
	signal fpRefreshCount			: unsigned(19 downto 0) := (others => '0');
	signal fpRefreshTick			: std_logic := '0';

	-- Capture-chain wires from the Transparent_Capture_Chain back to
	-- the FrontPanel_Subsystem.
	signal fpChainSerial			: std_logic;
	signal fpChainLatch				: std_logic;
	signal fpChainShiftEn			: std_logic;

    signal serialClkCount           : unsigned(15 downto 0);
	signal cpuClkCount				: std_logic_vector(5 downto 0); 
	signal sdClkCount				: std_logic_vector(5 downto 0); 	
	signal cpuClock					: std_logic;
	signal serialClock				: std_logic;
	signal sdClock					: std_logic;

	--CPM
	signal n_RomActive 				: std_logic := '0';

	component ch376s_module is
		port (
			-- interface
			clk : 	in std_logic;
			rd : 	in std_logic;
			wr : 	in std_logic;
			reset : in std_logic;
			a0 : 	in std_logic;
			
			-- SPI wires
			sck : 	out std_logic;
			sdcs : 	out std_logic;
			sdo : 	out std_logic; -- reg
			sdi : 	in std_logic;
			
			-- data
			din : 	in std_logic_vector (7 downto 0);
			dout : 	out std_logic_vector (7 downto 0) -- reg
		);
	end component;
	
	
begin
	--CPM
	-- Disable ROM if out 38. Re-enable when (asynchronous) reset pressed
	process (n_ioWR, N_RESET) begin
		if (N_RESET = '0') then
			n_RomActive <= '0';
		elsif (rising_edge(n_ioWR)) then
			if cpuAddress(7 downto 0) = "00111000" then -- $38
				n_RomActive <= '1';
			end if;
		end if;
	end process;

process(clk)
begin
	if rising_edge(clk) then
		if N_RESET = '0' then
			reset_counter <= (others => '0');
			reset_n_internal <= '0';
		else
			if reset_counter /= unsigned'(X"FFFF") then
				reset_counter <= reset_counter + 1;
				reset_n_internal <= '0';
			else
				reset_n_internal <= '1';
			end if;
		end if;
	end if;
end process;

-- ____________________________________________________________________________________
-- CPU CHOICE GOES HERE

cpu1 : entity work.t80s
generic map(mode => 1, t2write => 1, iowait => 0)
port map(
	reset_n => reset_n_internal,
	clk_n => cpuClock,
	wait_n => cpu_wait_n,
	int_n => '1',
	nmi_n => '1',
	busrq_n => '1',
	mreq_n => n_MREQ,
	iorq_n => n_IORQ,
	rd_n => n_RD,
	wr_n => n_WR,
	a => cpuAddress,
	di => cpuDataIn,
	do => cpuDataOut
);

-- ____________________________________________________________________________________
-- MMU GOES HERE

-- Active-high request signals for the MMU. The MMU uses synchronous,
-- active-high request semantics; the Z-80 native signals are active-low.
-- A separate `mmu_reset` signal is used because VHDL-93 (Quartus default)
-- does not allow expressions in port associations.
mmu_req_mem_in <= not n_MREQ;
mmu_req_io_in  <= not n_IORQ;
mmu_req_read   <= not n_RD;
mmu_req_write  <= not n_WR;
mmu_reset      <= not N_RESET;

mmu1 : entity work.MMU
generic map(physical_page_bits => 13)
port map(
	clk            => clk,
	reset          => mmu_reset,
	address_in     => cpuAddress,
	address_out    => mmu_phys_addr,
	cpu_data_in    => cpuDataOut,
	cpu_data_out   => mmu_dataOut,
	cpu_wait       => mmu_cpu_wait,
	req_mem_in     => mmu_req_mem_in,
	req_mem_out    => mmu_req_mem_out,
	req_io_in      => mmu_req_io_in,
	req_io_out     => mmu_req_io_out,
	io_cs          => mmu_io_cs,
	req_read       => mmu_req_read,
	req_write      => mmu_req_write
);

-- Physical-memory decode. Block RAM covers the low 64 KB of physical
-- memory (the first four 16 KB pages). Everything else is SDRAM.
-- All physical bits above bit 15 must be zero to hit block RAM, so high
-- SDRAM pages never alias into it.
phys_in_blockram <= '1' when mmu_phys_addr(26 downto 16) = "00000000000" else '0';
phys_in_sdram    <= not phys_in_blockram;

-- Combined wait_n into the CPU. cpu_wait_n = '0' stalls the Z-80.
cpu_wait_n <= (not mmu_cpu_wait) and sdram_wait_n;
-- ____________________________________________________________________________________
-- ROM GOES HERE	

rom1 : entity work.Z80_CPM_BASIC_ROM
port map(
	address => cpuAddress(12 downto 0),
	clock => clk,
	q => basRomData
);

-- ____________________________________________________________________________________
-- RAM GOES HERE

-- Block RAM is now addressed by the MMU's physical output (low 16 bits).
-- It is the backing store for physical pages 0..3 (physical 0x000000..0x00FFFF).
-- Writes are qualified by both the memory-write strobe and the physical
-- decode (phys_in_blockram); the ROM overlay at logical 0x0000-0x1FFF
-- still wins on the cpuDataIn mux while n_RomActive = '0'.
ram1: entity work.InternalRam64K
port map
(
	address => mmu_phys_addr(15 downto 0),
	clock => clk,
	data => cpuDataOut,
	wren => not(n_memWR or n_internalRam1CS),
	q => internalRam1DataOut
);

-- ____________________________________________________________________________________
-- INPUT/OUTPUT DEVICES GO HERE	


io1 : entity work.SBCTextDisplayRGB
port map (
	n_reset => N_RESET,
	clk => clk,

	-- RGB video signals
	hSync => HS,
	vSync => VS,
   	videoR0 => R(1),
   	videoR1 => R(0),
   	videoG0 => G(1),
   	videoG1 => G(0),
   	videoB0 => B(1),
   	videoB1 => B(0),
	hBlank => hBlank,
	vBlank => vBlank,
	cepix => cepix,

	-- Monochrome video signals (when using TV timings only)
	sync => videoSync,
	video => video,

	n_wr => n_interface1CS or n_ioWR,
	n_rd => n_interface1CS or n_ioRD,
	n_int => n_int1,
	regSel => cpuAddress(0),
	dataIn => cpuDataOut,
	dataOut => interface1DataOut,
	ps2Clk => ps2Clk,
	ps2Data => ps2Data
);

io2 : entity work.bufferedUART
port map(
	clk => clk,
	n_wr => n_interface2CS or n_ioWR,
	n_rd => n_interface2CS or n_ioRD,
	n_int => n_int2,
	regSel => cpuAddress(0),
	dataIn => cpuDataOut,
	dataOut => interface2DataOut,
	rxClock => serialClock,
	txClock => serialClock,
	rxd => rxd1,
	txd => txd1,
	n_cts => cts1,  -- Connect CTS signal
	n_dcd => '0',
	n_rts => rts1
);

    sd1 : entity work.sd_controller
    port map(
        sdCS => sdCS,
        sdMOSI => sdMOSI,
        sdMISO => sdMISO,
        sdSCLK => sdSCLK,
        n_wr => n_sdCardCS or n_ioWR,
        n_rd => n_sdCardCS or n_ioRD,
        n_reset => N_RESET,
        dataIn => cpuDataOut,
        dataOut => sdCardDataOut,
        regAddr => cpuAddress(2 downto 0),
        driveLED => driveLED,
        clk => clk
    );

usb : ch376s_module
port map (
	sdcs	=> 	usbCS,
	sdo 	=> 	usbMOSI,
	sdi 	=> 	usbMISO,
	sck 	=> 	usbSCLK,

	wr 		=> 	not (n_ch376sCS or n_ioWR),
	rd 		=> 	not (n_ch376sCS or n_ioRD),

	dout 	=> 	ch376sDataOut,
	din 	=> 	cpuDataOut,
	
	a0 		=> 	cpuAddress (0),
	reset 	=> 	not (N_RESET),
	clk 	=> 	sdClock -- twice the spi clk
);

-- ____________________________________________________________________________________
-- FRONT PANEL GOES HERE

-- Port 0x47: 8-bit R/W latch. Software writes set the bit pattern
-- driven onto the front-panel transparent capture chain. Reads return
-- the last-written value.
process(clk)
begin
	if rising_edge(clk) then
		if N_RESET = '0' then
			fpLatch <= (others => '0');
		elsif n_fpLatchCS = '0' and n_ioWR = '0' then
			fpLatch <= cpuDataOut;
		end if;
	end if;
end process;
fpLatchDataOut <= fpLatch;

-- ~60 Hz refresh tick (one clk cycle wide) from the 50 MHz system
-- clock. 50_000_000 / 60 = 833_333. The fpRefreshCount comparison
-- against the integer literal works under the std_logic_arith
-- package family used throughout this wrapper.
process(clk)
begin
	if rising_edge(clk) then
		if N_RESET = '0' then
			fpRefreshCount <= (others => '0');
			fpRefreshTick  <= '0';
		elsif fpRefreshCount = 833333-1 then
			fpRefreshCount <= (others => '0');
			fpRefreshTick  <= '1';
		else
			fpRefreshCount <= fpRefreshCount + 1;
			fpRefreshTick  <= '0';
		end if;
	end if;
end process;

-- 8-bit transparent capture chain sourced from the fpLatch register.
fpChain : entity work.Transparent_Capture_Chain
	generic map (
		TOTAL_WIDTH => 8
	)
	port map (
		clk           => clk,
		reset         => not N_RESET,
		latch         => fpChainLatch,
		shift_en      => fpChainShiftEn,
		combined_data => fpLatch,
		chain_in      => '0',
		chain_out     => fpChainSerial
	);

-- Front-panel controller. The 8-port window lives at $A0..$A7 in the
-- Z-80 I/O space (n_fpSubsysCS). NUM_LEDS is set to 16 for the initial
-- bring-up so the entire string is reachable by the default identity
-- mapping while leaving headroom to test the software framebuffer
-- mode through ports +5/+6.
fpSubsys : entity work.FrontPanel_Subsystem
	generic map (
		NUM_LEDS => 16,
		SYS_CLK  => 50000000
	)
	port map (
		clk          => clk,
		reset        => not N_RESET,
		refresh_tick => fpRefreshTick,

		iorq_n       => n_IORQ,
		wr_n         => n_WR,
		rd_n         => n_RD,
		io_cs        => not n_fpSubsysCS,
		addr         => cpuAddress(7 downto 0),
		din          => cpuDataOut,
		dout         => fpSubsysDataOut,

		latch        => fpChainLatch,
		shift_en     => fpChainShiftEn,
		chain_in     => fpChainSerial,

		led_serial   => fpLED_serial
	);

-- ____________________________________________________________________________________
-- MEMORY READ/WRITE LOGIC GOES HERE

n_ioWR 	<= n_WR or n_IORQ;
n_memWR <= n_WR or n_MREQ;
n_ioRD 	<= n_RD or n_IORQ;
n_memRD <= n_RD or n_MREQ;

-- ____________________________________________________________________________________
-- CHIP SELECTS GO HERE

-- Boot ROM still overlays logical 0x0000-0x1FFF before MMU translation.
-- The ROM data wins on the cpuDataIn mux while n_RomActive = '0'; this is
-- how the bootloader runs before it has had a chance to set up the MMU
-- or copy code into RAM.
n_basRomCS <= '0' when cpuAddress(15 downto 13) = "000" and n_RomActive = '0' else '1'; --8K at bottom of memory
n_interface1CS <= '0' when cpuAddress(7 downto 1) = "1000000" and (n_ioWR='0' or n_ioRD = '0') else '1'; -- 2 Bytes $80-$81
n_interface2CS <= '0' when cpuAddress(7 downto 1) = "1000001" and (n_ioWR='0' or n_ioRD = '0') else '1'; -- 2 Bytes $82-$83
n_ch376sCS <= '0' when cpuAddress(7 downto 1) = "0010000" and (n_ioWR='0' or n_ioRD = '0') else '1'; -- 2 Bytes $20-$21
n_sdCardCS <= '0' when cpuAddress(7 downto 3) = "10001" and (n_ioWR='0' or n_ioRD = '0') else '1'; -- 8 Bytes $88-$8F
n_fpLatchCS <= '0' when cpuAddress(7 downto 0) = x"47" and (n_ioWR='0' or n_ioRD = '0') else '1'; -- 1 Byte $47 (front-panel data latch)
n_fpSubsysCS <= '0' when cpuAddress(7 downto 3) = "10100" and (n_ioWR='0' or n_ioRD = '0') else '1'; -- 8 Bytes $A0-$A7 (front-panel subsystem)
n_mmuCS <= '0' when cpuAddress(7 downto 4) = "1011" and (n_ioWR='0' or n_ioRD = '0') else '1'; -- 16 Bytes $B0-$BF (MMU)

-- MMU.io_cs is active-high.
mmu_io_cs <= '1' when n_mmuCS = '0' else '0';

-- Block-RAM chip-select: assert whenever the MMU's physical address
-- lands in the low 64 KB region. The ROM overlay still wins on the
-- cpuDataIn mux for logical 0x0000-0x1FFF, but the underlying RAM
-- is kept selected so writes into the ROM region silently update
-- the backing RAM (matching legacy bootloader behaviour).
n_internalRam1CS <= '0' when phys_in_blockram = '1' else '1';

-- ____________________________________________________________________________________
-- BUS ISOLATION GOES HERE

    -- CPU data input mux. Order is significant:
    --   * Per-port I/O peripherals at the top (legacy entries).
    --   * MMU's own register file, only when the I/O cycle is NOT the
    --     direct-access data port at +12 (offset "1100"); on +12 the MMU
    --     promotes the cycle to a memory access and the data must come
    --     from the physical-memory path below.
    --   * ROM overlay at logical 0x0000-0x1FFF wins over RAM.
    --   * Physical-memory path: block RAM for phys < 0x010000, SDRAM
    --     otherwise.
    cpuDataIn <= interface1DataOut when (n_interface1CS = '0') else
                 interface2DataOut when (n_interface2CS = '0') else
                 ch376sDataOut when (n_ch376sCS = '0') else
                 sdCardDataOut when (n_sdCardCS = '0') else
                 fpLatchDataOut when (n_fpLatchCS = '0') else
                 fpSubsysDataOut when (n_fpSubsysCS = '0') else
                 mmu_dataOut when (mmu_io_cs = '1' and cpuAddress(3 downto 0) /= "1100") else
                 basRomData when (n_basRomCS = '0') else
                 internalRam1DataOut when (phys_in_blockram = '1') else
                 sdramReadData when (phys_in_sdram = '1') else
                 sramData when (n_externalRamCS = '0') else
                 x"FF";

-- ____________________________________________________________________________________
-- SDRAM CLIENT FSM
--
-- When the MMU promotes the current cycle into a physical memory access
-- (req_mem_out = '1') and the physical address lives in SDRAM, we hand
-- the access to sdram_z80_inst (in MultiComp.sv) and stall the Z-80 via
-- wait_n until the controller pulses `ready`.
--
-- State graph:
--   S_IDLE: idle, sdram_wait_n='1'. On an SDRAM memory access, latch
--           the address/data/strobes and move to S_REQ.
--   S_REQ : drive sdram_we/rd asserted, stall the CPU. When the
--           controller pulses sdram_ready, latch sdramReadData (for
--           reads) and move to S_DONE.
--   S_DONE: deassert sdram_we/rd, release wait_n, hold one cycle so the
--           Z-80 captures the read data on the next clock edge. Return
--           to S_IDLE once the CPU drops MREQ/IORQ.
sdram_addr <= mmu_phys_addr;  -- 27-bit physical address spans all 128 MB
sdram_din  <= cpuDataOut;
sdram_we   <= sdram_we_reg;
sdram_rd   <= sdram_rd_reg;

sdram_fsm: process(clk)
begin
	if rising_edge(clk) then
		if N_RESET = '0' then
			sdram_state   <= S_IDLE;
			sdram_we_reg  <= '0';
			sdram_rd_reg  <= '0';
			sdram_wait_n  <= '1';
			sdramReadData <= (others => '0');
		else
			case sdram_state is
				when S_IDLE =>
					sdram_we_reg <= '0';
					sdram_rd_reg <= '0';
					sdram_wait_n <= '1';
					-- Kick off a request when MMU has promoted the
					-- cycle to a physical memory access targeting SDRAM.
					if mmu_req_mem_out = '1' and phys_in_sdram = '1' then
						if mmu_req_write = '1' then
							sdram_we_reg <= '1';
							sdram_wait_n <= '0';
							sdram_state  <= S_REQ;
						elsif mmu_req_read = '1' then
							sdram_rd_reg <= '1';
							sdram_wait_n <= '0';
							sdram_state  <= S_REQ;
						end if;
					end if;

				when S_REQ =>
					-- Hold strobes (and the CPU wait) until the controller
					-- acknowledges. When it does, latch the read data but
					-- KEEP sdram_wait_n low for one more cycle: sdramReadData
					-- is a registered assignment and does not present the new
					-- value until after this clock edge. Releasing wait here
					-- would let the Z-80 sample cpuDataIn -> sdramReadData on
					-- the same edge, capturing the PREVIOUS transaction's
					-- byte (observed as a stale "read-by-one" error). The
					-- wait is released in S_DONE instead.
					if sdram_ready = '1' then
						sdramReadData <= sdram_dout;
						sdram_we_reg  <= '0';
						sdram_rd_reg  <= '0';
						sdram_state   <= S_DONE;
					end if;

				when S_DONE =>
					-- sdramReadData is now stable. Release the CPU wait so
					-- the Z-80 captures the correct read byte, then wait for
					-- it to drop MREQ before accepting a new request (this
					-- keeps the FSM from re-triggering on the same bus cycle).
					sdram_wait_n <= '1';
					if mmu_req_mem_out = '0' then
						sdram_state <= S_IDLE;
					end if;
			end case;
		end if;
	end if;
end process;

-- ____________________________________________________________________________________
-- SYSTEM CLOCKS GO HERE


-- SUB-CIRCUIT CLOCK SIGNALS 
serialClock <= serialClkCount(15);
--sdClock <= clk;

process (clk)
begin
	if rising_edge(clk) then

		if cpuClkCount < 4 then -- 4 = 10MHz, 3 = 12.5MHz, 2=16.6MHz, 1=25MHz
			cpuClkCount <= cpuClkCount + 1;
		else
			cpuClkCount <= (others=>'0');
		end if;
		
		if cpuClkCount < 2 then -- 2 when 10MHz, 2 when 12.5MHz, 2 when 16.6MHz, 1 when 25MHz
			cpuClock <= '0';
		else
			cpuClock <= '1';
		end if; 

		if sdClkCount < 16 then -- 5MHz
			sdClkCount <= sdClkCount + 1;
		else
			sdClkCount <= (others=>'0');
		end if;

		sdClock <= sdClkCount (3); -- divide by 8 = 6.25 Mhz
		--usbCS <= sdClkCount (4);
		--usbMOSI <= sdClkCount (3);
		--usbSCLK <= sdClkCount (2);

		-- Serial clock DDS
		-- 50MHz master input clock:
		-- Baud Increment
		-- 115200 2416
		-- 38400 805
		-- 19200 403
		-- 9600 201
		-- 4800 101
		-- 2400 50
		serialClkCount <= serialClkCount + unsigned(baud_increment);
	end if;
end process;

end;
