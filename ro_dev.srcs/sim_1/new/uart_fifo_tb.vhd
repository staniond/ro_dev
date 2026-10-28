library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity uart_fifo_tb is
    -- Testbench has no ports
end uart_fifo_tb;

architecture Behavioral of uart_fifo_tb is

    -- Component Declaration for the Unit Under Test (UUT)
    component uart_fifo
    generic(
        clk_freq      : INTEGER;
        baud_rate     : INTEGER;
        os_rate       : INTEGER;
        d_width       : INTEGER;
        parity        : INTEGER;
        parity_eo     : STD_LOGIC;
        tx_fifo_depth : INTEGER;
        rx_fifo_depth : INTEGER
    );
    port(
        clk           : IN  STD_LOGIC;
        reset         : IN  STD_LOGIC;
        tx_ena        : IN  STD_LOGIC;
        tx_data       : IN  STD_LOGIC_VECTOR(7 DOWNTO 0);
        tx_fifo_full  : OUT STD_LOGIC;
        rx_data       : OUT STD_LOGIC_VECTOR(7 DOWNTO 0);
        rx_data_read  : IN  STD_LOGIC;
        rx_data_ready : OUT STD_LOGIC;
        tx            : OUT STD_LOGIC;
        rx            : IN  STD_LOGIC
    );
    end component;

    -- Constants
    constant CLK_FREQ_VAL  : integer := 100_000_000; -- 100 MHz (matches top.vhd / cw305 pll_clk1)
    constant CLK_PERIOD    : time    := 10 ns;        -- 1/100MHz
    constant BAUD_RATE_VAL : integer := 115_200;   
    
    -- Signals
    signal clk           : std_logic := '0';
    signal reset         : std_logic := '0';
    
    -- User Interface Signals
    signal tx_ena        : std_logic := '0';
    signal tx_data       : std_logic_vector(7 downto 0) := (others => '0');
    signal tx_fifo_full  : std_logic;
    
    signal rx_data       : std_logic_vector(7 downto 0);
    signal rx_data_read  : std_logic := '0';
    signal rx_data_ready : std_logic;
    
    -- Physical Interface Signals
    signal tx_line       : std_logic;
    signal rx_line       : std_logic;

begin

    -- Instantiate the Unit Under Test (UUT)
    uut: uart_fifo
    generic map (
        clk_freq      => CLK_FREQ_VAL,
        baud_rate     => BAUD_RATE_VAL,
        os_rate       => 8,
        d_width       => 8,
        parity        => 0,
        parity_eo     => '0',
        tx_fifo_depth => 8,
        rx_fifo_depth => 8
    )
    port map (
        clk           => clk,
        reset         => reset,
        tx_ena        => tx_ena,
        tx_data       => tx_data,
        tx_fifo_full  => tx_fifo_full,
        rx_data       => rx_data,
        rx_data_read  => rx_data_read,
        rx_data_ready => rx_data_ready,
        tx            => tx_line,
        rx            => rx_line -- Loopback connection (TX connected to RX)
    );

    -- Loopback Connection: What goes out TX comes in RX
    rx_line <= tx_line;

    -- Clock Process
    clk_process : process
    begin
        clk <= '0';
        wait for CLK_PERIOD/2;
        clk <= '1';
        wait for CLK_PERIOD/2;
    end process;

    -- Stimulus Process
    stim_proc: process
        variable timeout_counter : integer := 0;
    begin
        -- 1. Reset System
        reset <= '1';
        wait for 100 ns;
        reset <= '0';
        wait for 100 ns;

        report "------------------------------------------------";
        report "Test 1: Single Byte Loopback (0xA5)";
        report "------------------------------------------------";
        
        wait until rising_edge(clk);
        tx_data <= x"A5";
        tx_ena  <= '1';
        wait until rising_edge(clk);
        tx_ena  <= '0';
        
        -- Wait for data to be received (TX time + RX time)
        -- Max wait time safety break
        while rx_data_ready = '0' loop
            wait until rising_edge(clk);
            timeout_counter := timeout_counter + 1;
            -- ~40 bit-periods (~4 bytes) of margin; scales with clk_freq so it stays valid
            if timeout_counter > (CLK_FREQ_VAL / BAUD_RATE_VAL) * 40 then
                report "Timeout waiting for RX data" severity failure;
            end if;
        end loop;
        timeout_counter := 0;

        -- Check Data
        wait for 1 ns; -- delta cycle wait
        assert rx_data = x"A5" 
            report "Error: Expected 0xA5, got " & integer'image(to_integer(unsigned(rx_data))) 
            severity error;

        -- Acknowledge Read
        rx_data_read <= '1';
        wait until rising_edge(clk);
        rx_data_read <= '0';
        
        wait for 500 ns;

        report "------------------------------------------------";
        report "Test 2: FIFO Burst (Full Depth Check)";
        report "------------------------------------------------";
        -- We configured FIFO depth to 8 in generic map. 
        -- Let's fill it up completely.
        
        -- Byte 1
        wait until rising_edge(clk); tx_data <= x"10"; tx_ena <= '1';
        wait until rising_edge(clk); tx_data <= x"20";
        wait until rising_edge(clk); tx_data <= x"30";
        wait until rising_edge(clk); tx_data <= x"40";
        wait until rising_edge(clk); tx_data <= x"50";
        wait until rising_edge(clk); tx_data <= x"60";
        wait until rising_edge(clk); tx_data <= x"70";
        wait until rising_edge(clk); tx_data <= x"80";
        wait until rising_edge(clk); tx_data <= x"90"; -- beyond depth-8: only 0x10..0x80 survive
        wait until rising_edge(clk); tx_data <= x"a0";
        wait until rising_edge(clk); 
        tx_ena <= '0';
        
        report "Transmission Burst Started...";
        
        wait for 900us; -- wait until bytes are received
        wait until rising_edge(clk);

        -- Now we verify receiving all 8 bytes (FIFO depth) in order: 0x10, 0x20, ... 0x80
        for i in 1 to 8 loop
            -- Wait for Ready
            while rx_data_ready = '0' loop
                wait until rising_edge(clk);
            end loop;

            wait for 1 ns; -- Signal settle

            assert rx_data = std_logic_vector(to_unsigned(i*16, 8))
                report "FIFO Order Error at byte " & integer'image(i) &
                       ": expected " & integer'image(i*16) &
                       ", got " & integer'image(to_integer(unsigned(rx_data)))
                severity error;

            -- Pop from RX FIFO
            rx_data_read <= '1';
            wait until rising_edge(clk);
            rx_data_read <= '0';
            wait until rising_edge(clk); -- let rx_data_ready settle back
        end loop;

        wait for 500 ns;
        report "------------------------------------------------";
        report "Simulation Completed Successfully";
        report "------------------------------------------------";
        
        -- Stop simulation
        assert false report "End of Testbench" severity failure;
        wait;
    end process;

end Behavioral;