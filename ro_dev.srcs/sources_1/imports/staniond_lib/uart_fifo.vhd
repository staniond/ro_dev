library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity uart_fifo is
  generic(
    clk_freq      : INTEGER   := 100_000_000; 
    baud_rate     : INTEGER   := 19_200;      
    os_rate       : INTEGER   := 16;          
    d_width       : INTEGER   := 8;    
    parity        : INTEGER   := 0;           
    parity_eo     : STD_LOGIC := '0';          
    tx_fifo_depth : INTEGER   := 8;
    rx_fifo_depth : INTEGER   := 8
  );
  port (
    clk           : IN  STD_LOGIC;
    reset         : IN  STD_LOGIC;
    -- User Interface
    tx_ena        : IN  STD_LOGIC;                             -- Write to FIFO
    tx_data       : IN  STD_LOGIC_VECTOR(d_width-1 DOWNTO 0);  
    tx_fifo_full  : OUT STD_LOGIC;                             
    rx_data       : OUT STD_LOGIC_VECTOR(d_width-1 DOWNTO 0);  
    rx_data_read  : IN  STD_LOGIC;                             -- Ack/Read from FIFO
    rx_data_ready : OUT STD_LOGIC;                             -- Valid data exists
    -- Physical Interface
    tx            : OUT STD_LOGIC;                         
    rx            : IN  STD_LOGIC                              
  );
end uart_fifo;

architecture Behavioral of uart_fifo is

    -- Internal Signals
    signal tx_fifo_rd_en      : std_logic;
    signal tx_fifo_rd_data    : std_logic_vector(d_width-1 downto 0);
    signal tx_fifo_empty      : std_logic;
    signal tx_fifo_full_sig   : std_logic;
    
    -- UART Signals
    signal uart_tx_ena        : std_logic;
    signal uart_tx_busy       : std_logic;
    
    signal rx_data_from_uart  : std_logic_vector(d_width-1 downto 0);
    signal rx_busy            : std_logic;
    signal rx_busy_delayed    : std_logic;
    signal rx_fifo_empty_sig  : std_logic;
    signal rx_fifo_full       : std_logic;
    signal rx_fifo_wr_en      : std_logic;

begin

    -- -------------------------------------------------------------------------
    -- 1. TX LOGIC: Continuous Streaming
    -- -------------------------------------------------------------------------
    -- We do not need a state machine here. 
    -- If FIFO has data (not empty) AND UART is free (not busy):
    --   1. Assert UART TX Enable
    --   2. Read from FIFO (to prepare next byte)
    -- The UART module latches data on the rising edge of clk when tx_ena is '1'.
    -- It immediately raises tx_busy on the next cycle, which kills this enable 
    -- signal, creating a perfect 1-cycle pulse.
    
    uart_tx_ena   <= '1' when (tx_fifo_empty = '0' and uart_tx_busy = '0') else '0';
    tx_fifo_rd_en <= uart_tx_ena; -- Read FIFO same time we start UART TX

    -- Instantiate TX FIFO
    tx_fifo: entity work.fifo(Behavioral)
    generic map (
      g_WIDTH => d_width,
      g_DEPTH => tx_fifo_depth -- [cite: 5]
    )
    port map (
      i_rst_sync => reset,
      i_clk      => clk,
      i_wr_en    => tx_ena and not tx_fifo_full_sig, -- Protect against overflow
      i_wr_data  => tx_data,
      o_full     => tx_fifo_full_sig,
      i_rd_en    => tx_fifo_rd_en,
      o_rd_data  => tx_fifo_rd_data,
      o_empty    => tx_fifo_empty
    );

    tx_fifo_full <= tx_fifo_full_sig;

    -- -------------------------------------------------------------------------
    -- 2. RX LOGIC
    -- -------------------------------------------------------------------------
    rx_data_ready <= not rx_fifo_empty_sig;

    -- Detect falling edge of UART RX Busy to write to FIFO
    rx_capture_process: process(clk) is
    begin
        if rising_edge(clk) then
            if reset = '1' then
                rx_busy_delayed <= '0';
            else
                rx_busy_delayed <= rx_busy;
            end if;
        end if;
    end process;
    
    -- Write on falling edge of busy (reception complete)
    rx_fifo_wr_en <= not rx_fifo_full and (not rx_busy and rx_busy_delayed);

    -- Instantiate RX FIFO
    rx_fifo: entity work.fifo(Behavioral)
    generic map (
      g_WIDTH => d_width,
      g_DEPTH => rx_fifo_depth
    )
    port map (
      i_rst_sync => reset,
      i_clk      => clk,
      i_wr_en    => rx_fifo_wr_en,
      i_wr_data  => rx_data_from_uart,
      o_full     => rx_fifo_full,
      i_rd_en    => rx_data_read,
      o_rd_data  => rx_data,
      o_empty    => rx_fifo_empty_sig
    );

    -- -------------------------------------------------------------------------
    -- 3. UART CORE INSTANTIATION
    -- -------------------------------------------------------------------------
    uart_inst: entity work.uart(Behavioral)
    generic map(
        clk_freq  => clk_freq,
        baud_rate => baud_rate,
        os_rate   => os_rate,
        d_width   => d_width,
        parity    => parity,
        parity_eo => parity_eo
    )
    port map(
        clk      => clk,         
        reset_n  => not reset,   
        tx_ena   => uart_tx_ena,      
        tx_data  => tx_fifo_rd_data,     
        rx       => rx,         
        rx_busy  => rx_busy,        
        rx_error => open,        
        rx_data  => rx_data_from_uart,        
        tx_busy  => uart_tx_busy,     
        tx       => tx           
    );

end Behavioral;