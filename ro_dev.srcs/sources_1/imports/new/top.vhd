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

use work.ro_pkg.all;

-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
--use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx leaf cells in this code.
--library UNISIM;
--use UNISIM.VComponents.all;


entity top is
    Port (
       tio_trigger: out STD_LOGIC;
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

    -- Ring oscillators (placement: constrs_1/new/ro_place.tcl)
    constant N_RO : integer := 256;
    signal ro_out : std_logic_vector(N_RO-1 downto 0);
    signal ro_en  : std_logic_vector(N_RO-1 downto 0);  -- one-hot from ro_ctrl

    -- Output path: selected RO -> prescaler -> tap chosen over UART -> tio_trigger
    constant PRESCALER_DIVIDE : integer := 256;          -- 8 stages
    constant MAX_STAGES       : integer := log2(PRESCALER_DIVIDE);
    signal ro_sel_out : std_logic;                       -- ro_out of the enabled RO
    signal ro_taps    : std_logic_vector(MAX_STAGES-1 downto 0);
    signal ro_running : std_logic;
    signal ro_stages  : natural range 0 to MAX_STAGES;

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
    signal tx_ena        : std_logic;
    signal tx_data       : std_logic_vector(7 downto 0);
    signal tx_fifo_full  : std_logic;
    
    signal rx_data       : std_logic_vector(7 downto 0);
    signal rx_data_read  : std_logic;
    signal rx_data_ready : std_logic;

begin
    clk <= pll_clk1;
    reset <= not pushbutton_n_sync or por_rst;   -- synchronized button OR automatic power-on reset
    led1 <= '0';
    led2 <= ro_running;
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

    -- UART commands: [stages] [id_hi] [id_lo], see ro_ctrl.vhd / README.
    -- Enables one RO at a time and selects the prescaler tap for tio_trigger.
    u_ro_ctrl: entity work.ro_ctrl
        generic map (
            N_RO           => N_RO,
            MAX_STAGES     => MAX_STAGES,
            TIMEOUT_CYCLES => CLK_FREQ / 100              -- 10 ms between bytes
        )
        port map (
            clk           => clk,
            reset         => reset,
            rx_data       => rx_data,
            rx_data_ready => rx_data_ready,
            rx_data_read  => rx_data_read,
            tx_ena        => tx_ena,
            tx_data       => tx_data,
            tx_fifo_full  => tx_fifo_full,
            en            => ro_en,
            running       => ro_running,
            stages        => ro_stages
        );

    -- Ring oscillators. Each instance is named gen_ro[i].u_ro in the netlist;
    -- ro_place.tcl maps those names to slices.
    gen_ro: for i in 0 to N_RO-1 generate
        u_ro: entity work.ro_cell(rtl)
            port map (en => ro_en(i), ro_out => ro_out(i));
    end generate;

    -- Output of the enabled RO (OR of all: stopped ROs output '0')
    u_ro_select: entity work.ro_select
        generic map (N => N_RO)
        port map (ro_out => ro_out, sel_out => ro_sel_out);

    -- Divided versions: ro_taps(k-1) = ro_sel_out / 2^k
    u_ro_prescaler: entity work.ro_prescaler
        generic map (DIVIDE => PRESCALER_DIVIDE)
        port map (clk_in => ro_sel_out, clk_out => open, taps => ro_taps);

    -- tio_trigger = ro_sel_out / 2^stages. For the 12 MHz logic analyzer use
    -- ~7-8 stages (ro_out ~110-320 MHz). f_RO = 2 * 2^stages * f(tio_trigger)
    p_tio: process(ro_stages, ro_sel_out, ro_taps)
    begin
        if ro_stages = 0 then
            tio_trigger <= ro_sel_out;
        else
            tio_trigger <= ro_taps(ro_stages-1);
        end if;
    end process;

    -- UART FIFO Instantiation
    uart_fifo_inst: entity work.uart_fifo(Behavioral)
    generic map(
        clk_freq      => CLK_FREQ,
        baud_rate     => BAUD_RATE,
        os_rate       => 8, -- needed for 12MHz for lower oversampling error, works for 100MHz fine too
        tx_fifo_depth => 4, -- one 3-byte reply
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
