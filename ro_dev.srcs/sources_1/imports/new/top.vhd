----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 07/30/2023 06:14:46 PM
-- Design Name: 
-- Module Name: top - Behavioral
-- Project Name: 
-- Target Devices: 
-- Tool Versions: 
-- Description: 
-- 
-- Dependencies: 
-- 
-- Revision:
-- Revision 0.01 - File Created
-- Additional Comments:
-- 
----------------------------------------------------------------------------------


library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;

-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
--use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx leaf cells in this code.
--library UNISIM;
--use UNISIM.VComponents.all;


entity top is
    Port (
       A14: out STD_LOGIC;
       A12: in STD_LOGIC;
       pushbutton_n: in STD_LOGIC;  -- active 0 button
       led1: out STD_LOGIC;       -- active 1 LED
       led2: out STD_LOGIC;
       led3: out STD_LOGIC;
       dip_switch: in STD_LOGIC_VECTOR(3 downto 0);
       pll_clk1: in STD_LOGIC
    );
end top;

architecture Behavioral of top is
    constant CLK_FREQ  : integer := 100_000_000; -- pll_clk1 = 100 MHz 
    constant BAUD_RATE : integer := 115200;
    
    
    constant BUFFER_SIZE: integer := 10;

    -- Ring oscillators (placement: constrs_1/new/ro_place.tcl)
    constant N_RO : integer := 4;
    signal ro_out : std_logic_vector(N_RO-1 downto 0);
    
    signal clk: std_logic;
    signal reset : std_logic;
    signal uart_tx: std_logic;
    signal uart_rx: std_logic;
    signal pushbutton_n_sync : std_logic;  -- pushbutton after 2-FF synchronizer

    -- Power-on reset: holds reset asserted for 256 clocks after configuration,
    -- then releases. Guarantees a clean startup reset (defined tx idle-high, etc.)
    -- without needing the physical pushbutton, and gives sim/hardware parity.
    signal por_cnt : unsigned(7 downto 0) := (others => '0');
    signal por_rst : std_logic := '1';
    -- Terminal count = all-ones for por_cnt's width; tracks the width automatically.
    constant POR_MAX : unsigned(por_cnt'range) := (others => '1');
    
    -- Internal signals for UART FIFO connection
    signal tx_ena        : std_logic := '0';
    signal tx_data       : std_logic_vector(7 downto 0) := (others => '0');
    signal tx_fifo_full  : std_logic;
    
    signal rx_data       : std_logic_vector(7 downto 0);
    signal rx_data_read  : std_logic := '0';
    signal rx_data_ready : std_logic;

    -- FSM Signals
    type t_state is (RECEIVING, SEND_BYTES);
    signal state : t_state := RECEIVING;
    
    type t_byte_array is array (0 to BUFFER_SIZE-1) of std_logic_vector(7 downto 0);
    signal data_buffer : t_byte_array;
    
    signal recv_index : integer range 0 to BUFFER_SIZE := 0;
    signal send_index : integer range 0 to BUFFER_SIZE := 0;

begin
    clk <= pll_clk1;
    reset <= not pushbutton_n_sync or por_rst;   -- synchronized button OR automatic power-on reset
    led1 <= pushbutton_n;
    led2 <= xor ro_out;   -- RO smoke test: lit (dimly) while dip_switch(0) = '1'
    led3 <= reset;

    A14 <= uart_tx;

    -- Synchronize asynchronous external inputs into the clk domain (2-FF, ASYNC_REG).
    -- pushbutton -> avoids a metastable reset; A12 (rx) -> avoids metastable UART sampling.
    sync_button: entity work.ff2_synchronizer
        port map (output_clock => clk, input => pushbutton_n, output => pushbutton_n_sync);

    sync_rx: entity work.ff2_synchronizer
        port map (output_clock => clk, input => A12, output => uart_rx);

    -- Power-on reset generator: count up to 255 once, then deassert por_rst.
    p_por: process(clk)
    begin
        if rising_edge(clk) then
            if por_cnt = POR_MAX then
                por_rst <= '0';
            else
                por_cnt <= por_cnt + 1;
            end if;
        end if;
    end process;

    -- Combinational FIFO read strobe: pop in the SAME cycle we capture the byte,
    -- so the FIFO advances on the same clock edge and its data/flags are coherent
    -- on the next cycle. This is what lets us drop the old RECV_PAUSE bubble state.
    rx_data_read <= '1' when (state = RECEIVING and rx_data_ready = '1') else '0';

    -- FSM Process
    p_FSM: process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                state <= RECEIVING;
                recv_index <= 0;
                send_index <= 0;
                tx_ena <= '0';
            else
                -- Default assignment
                tx_ena <= '0';

                case state is
                    when RECEIVING =>
                        if rx_data_ready = '1' then
                            -- Head word is already on rx_data (FWFT FIFO); capture it.
                            data_buffer(recv_index) <= rx_data;

                            -- Decide from rx_data directly: the buffer write above
                            -- has not committed yet this cycle.
                            if rx_data = x"0a" then
                                -- newline: strip it (don't count it), echo what we have
                                send_index <= 0;
                                state      <= SEND_BYTES;
                            elsif recv_index = BUFFER_SIZE - 1 then
                                -- this byte fills the buffer: overflow, echo everything
                                recv_index <= recv_index + 1;
                                send_index <= 0;
                                state      <= SEND_BYTES;
                            else
                                recv_index <= recv_index + 1;
                            end if;
                        end if;
                    -- 4. Process and Send Byte
                    when SEND_BYTES =>
                        tx_ena <= '1';
                        send_index <= send_index + 1;
                        if send_index = recv_index then
                            tx_data <= x"0a";
                            send_index <= 0;
                            recv_index <= 0;
                            state <= RECEIVING;
                        else
                            tx_data <= data_buffer(send_index);
                            state <= SEND_BYTES;
                        end if;
                end case;
            end if;
        end if;
    end process;


    -- Ring oscillators, all enabled by dip_switch(0). Each instance is named
    -- gen_ro[i].u_ro in the netlist; ro_place.tcl maps those names to slices.
    gen_ro: for i in 0 to N_RO-1 generate
        u_ro: entity work.ro_cell(rtl)
            port map (en => dip_switch(0), ro_out => ro_out(i));
    end generate;

    -- UART FIFO Instantiation
    uart_fifo_inst: entity work.uart_fifo(Behavioral)
    generic map(
        clk_freq      => CLK_FREQ,
        baud_rate     => BAUD_RATE,
        os_rate       => 8, -- needed for 12MHz for lower oversampling error, works for 100MHz fine too
        tx_fifo_depth => BUFFER_SIZE+1, -- +1 for newline appended in SEND_BYTES state
        rx_fifo_depth => 4
    )
    port map(
        clk           => clk,
        reset         => reset,
        tx_ena        => tx_ena,
        tx_data       => tx_data,
        tx_fifo_full  => tx_fifo_full,
        tx            => uart_tx,
        rx            => uart_rx,
        rx_data       => rx_data,
        rx_data_read  => rx_data_read,
        rx_data_ready => rx_data_ready
    );

end Behavioral;
