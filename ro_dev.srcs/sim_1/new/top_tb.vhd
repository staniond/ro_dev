library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity top_tb is
    -- Testbench has no ports
end top_tb;

architecture Behavioral of top_tb is

    -- Component Declaration for the Unit Under Test (UUT)
    component top
    Port (
       A14: out STD_LOGIC;
       A12: in STD_LOGIC;
       pushbutton_n: in STD_LOGIC;
       led1: out STD_LOGIC;
       led2: out STD_LOGIC;
       led3: out STD_LOGIC;
       dip_switch: in STD_LOGIC_VECTOR(3 downto 0);
       pll_clk1: in STD_LOGIC
    );
    end component;

    -- Constants
    -- 100 MHz Clock
    constant CLK_PERIOD    : time := 10.000 ns;
    -- 115200 Baud Rate
    constant BIT_PERIOD    : time := 8.680 us; 

    -- Signals
    signal clk     : std_logic := '0';
    signal dip_switch : std_logic_vector(3 downto 0) := "0000";
    signal uart_rx : std_logic := '1'; -- Idle High
    signal uart_tx : std_logic;
    signal led1, led2, led3 : std_logic;
    signal reset_n: std_logic := '1'; -- pushbutton is active 0, we attach reset_n to it

begin
    -- Instantiate the UUT
    uut: top
    port map (
        A14        => uart_tx,
        A12        => uart_rx,
        pushbutton_n => reset_n,
        led1       => led1,
        led2       => led2,
        led3       => led3,
        dip_switch => dip_switch,
        pll_clk1   => clk
    );

    -- Clock Generation
    p_clk: process
    begin
        clk <= '0';
        wait for CLK_PERIOD/2;
        clk <= '1';
        wait for CLK_PERIOD/2;
    end process;

    -- Main Stimulus Process
    p_stim: process
        
        -- Procedure to Bit-Bang a UART Byte
        procedure UART_SEND(
            data_in : in std_logic_vector(7 downto 0)
        ) is
        begin
            -- Start Bit (Low)
            uart_rx <= '0';
            wait for BIT_PERIOD;
            
            -- Data Bits (LSB First)
            for i in 0 to 7 loop
                uart_rx <= data_in(i);
                wait for BIT_PERIOD;
            end loop;
            
            -- Stop Bit (High)
            uart_rx <= '1';
            wait for BIT_PERIOD;
            
            -- Inter-byte idle time (optional, just to see gaps)
            wait for BIT_PERIOD * 5; 
        end procedure;
    
    begin
        reset_n <= '0';
        wait for 100 us;
        reset_n <= '1';
        wait for 100 us;

        report "-----------------------------------------";
        report "Starting UART Stimulus (115200 Baud)";
        report "Sending: A, B, C, \n";
        report "Expecting: A, B, C, \n";
        report "-----------------------------------------";

        -- 2. Send 4 Bytes
        -- Send 'A' (0x41) -> Expect 'B' (0x42)
        UART_SEND(x"41");
        
        -- Send 'B' (0x42) -> Expect 'C' (0x43)
        UART_SEND(x"42");
        
        -- Send 'C' (0x43) -> Expect 'D' (0x44)
        UART_SEND(x"43");
        
        -- Send '\n' (0x0A) -> Expect '\n' (0x0A)
        UART_SEND(x"0a");
        
        -- 3. Wait for response
        -- Response takes time: 4 bytes * 10 bits * 8.68us = ~350us
        wait for 10 ms;
        
        report "-----------------------------------------";
        report "Simulation Finished";
        report "-----------------------------------------";
        assert false report "End of Simulation" severity failure;
        wait;
    end process;

end Behavioral;