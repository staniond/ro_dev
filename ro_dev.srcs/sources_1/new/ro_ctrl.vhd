----------------------------------------------------------------------------------
-- Company: FIT CTU
-- Engineer: Ondrej Stanicek
--
-- Module Name: ro_ctrl - rtl
-- Description:
--   UART command interface for the ring oscillators: enables one RO and sets the
--   number of prescaler stages for its output.
--
--   Command, 3 bytes:  [stages] [id_hi] [id_lo]
--     stages = 0..MAX_STAGES : run RO id (big-endian) through that many /2 stages
--     stages = 0xFF          : stop, no RO enabled (id ignored)
--   Reply, 3 bytes, after the command took effect:
--     valid   : the same 3 bytes
--     invalid : 0xEE id_hi id_lo, nothing changed
--               (stages not in 0..MAX_STAGES / 0xFF, or id >= N_RO)
--   If more than TIMEOUT_CYCLES pass between two bytes, a partial command is
--   dropped, so a lost byte can't shift all later commands.
--
--   At most one RO is ever enabled: every en(i) is decoded from the one stored
--   id (en(i) = running and sel = i). Switching to a different RO first turns
--   all ROs off for STOP_CYCLES (break-before-make), so the old ring has stopped
--   before the new one starts. After reset all ROs are off.
--
--   Byte interface = the user side of uart_fifo (FWFT rx FIFO, tx FIFO).
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity ro_ctrl is
    Generic (
        N_RO           : positive;                     -- number of ROs (ids 0..N_RO-1)
        MAX_STAGES     : natural  := 8;                -- prescaler stages available
        TIMEOUT_CYCLES : positive := 1_000_000;        -- max gap between bytes (10 ms @ 100 MHz)
        STOP_CYCLES    : positive := 16                -- all-off time when switching ROs
    );
    Port (
        clk           : in  STD_LOGIC;
        reset         : in  STD_LOGIC;
        -- uart_fifo user interface
        rx_data       : in  STD_LOGIC_VECTOR(7 downto 0);
        rx_data_ready : in  STD_LOGIC;
        rx_data_read  : out STD_LOGIC;
        tx_ena        : out STD_LOGIC;
        tx_data       : out STD_LOGIC_VECTOR(7 downto 0);
        tx_fifo_full  : in  STD_LOGIC;
        -- RO control
        en            : out STD_LOGIC_VECTOR(N_RO-1 downto 0);  -- one-hot (or all '0')
        running       : out STD_LOGIC;                          -- a RO is enabled
        stages        : out natural range 0 to MAX_STAGES       -- prescaler stages to output
    );
end ro_ctrl;

architecture rtl of ro_ctrl is
    constant STOP_CMD  : unsigned(7 downto 0) := x"FF";
    constant ERROR_RPL : std_logic_vector(7 downto 0) := x"EE";

    type t_state is (RECEIVING, EXECUTE, SWITCH_OFF, SENDING);
    signal state : t_state := RECEIVING;

    type t_bytes is array (0 to 2) of std_logic_vector(7 downto 0);
    signal cmd   : t_bytes := (others => (others => '0'));  -- received command
    signal reply : t_bytes := (others => (others => '0'));

    signal byte_idx  : natural range 0 to 2 := 0;
    signal gap_cnt   : natural range 0 to TIMEOUT_CYCLES-1 := 0;
    signal stop_cnt  : natural range 0 to STOP_CYCLES-1 := 0;

    signal run_r     : std_logic := '0';
    signal sel_r     : natural range 0 to N_RO-1 := 0;
    -- sel_r/run_r fan out to the decoder of every RO. MAX_FANOUT limits each net
    -- to 32 loads, so synthesis builds the decode as a small tree (or replicates
    -- these registers) instead of one huge net. The timed path sel_r -> decode ->
    -- en_r then stays short and local to this module; the long part is the
    -- en_r -> RO wire, which isn't timed (false path to the RO's toggle-FF clear,
    -- see ro_place.tcl). Any replicas load the same value on the same edge, so
    -- the decode stays one-hot.
    attribute MAX_FANOUT : integer;
    attribute MAX_FANOUT of run_r, sel_r : signal is 32;
    signal stages_r  : natural range 0 to MAX_STAGES := 0;
    signal new_sel   : natural range 0 to N_RO-1 := 0;      -- id of a pending switch
    signal new_stg   : natural range 0 to MAX_STAGES := 0;

    signal en_r      : std_logic_vector(N_RO-1 downto 0) := (others => '0');
begin
    -- Pop a byte in the same cycle it's captured (FWFT rx FIFO), and write a
    -- reply byte in the same cycle the FIFO is seen not full.
    rx_data_read <= '1' when state = RECEIVING and rx_data_ready = '1' else '0';
    tx_ena       <= '1' when state = SENDING and tx_fifo_full = '0' else '0';

    p_fsm: process(clk)
        variable stg : unsigned(7 downto 0);
        variable id  : unsigned(15 downto 0);
    begin
        if rising_edge(clk) then
            if reset = '1' then
                state    <= RECEIVING;
                byte_idx <= 0;
                gap_cnt  <= 0;
                run_r    <= '0';
                sel_r    <= 0;
                stages_r <= 0;
            else
                case state is
                    when RECEIVING =>
                        if rx_data_ready = '1' then
                            cmd(byte_idx) <= rx_data;
                            gap_cnt <= 0;
                            if byte_idx = 2 then
                                byte_idx <= 0;
                                state    <= EXECUTE;
                            else
                                byte_idx <= byte_idx + 1;
                            end if;
                        elsif byte_idx /= 0 then
                            -- partial command: drop it if the next byte doesn't come in time
                            if gap_cnt = TIMEOUT_CYCLES-1 then
                                byte_idx <= 0;
                                gap_cnt  <= 0;
                            else
                                gap_cnt <= gap_cnt + 1;
                            end if;
                        end if;

                    when EXECUTE =>
                        stg := unsigned(cmd(0));
                        id  := unsigned(cmd(1)) & unsigned(cmd(2));
                        reply <= cmd;                      -- valid: echo
                        state <= SENDING;
                        if stg = STOP_CMD then
                            run_r <= '0';
                        elsif stg <= MAX_STAGES and id < N_RO then
                            if run_r = '1' and sel_r /= to_integer(id) then
                                -- break-before-make: all off first, then the new RO
                                run_r    <= '0';
                                new_sel  <= to_integer(id);
                                new_stg  <= to_integer(stg);
                                stop_cnt <= 0;
                                state    <= SWITCH_OFF;
                            else
                                sel_r    <= to_integer(id);
                                stages_r <= to_integer(stg);
                                run_r    <= '1';
                            end if;
                        else
                            reply(0) <= ERROR_RPL;         -- invalid: nothing changes
                        end if;

                    when SWITCH_OFF =>
                        if stop_cnt = STOP_CYCLES-1 then
                            sel_r    <= new_sel;
                            stages_r <= new_stg;
                            run_r    <= '1';
                            state    <= SENDING;
                        else
                            stop_cnt <= stop_cnt + 1;
                        end if;

                    when SENDING =>
                        if tx_fifo_full = '0' then         -- tx_ena is '1' this cycle
                            if byte_idx = 2 then
                                byte_idx <= 0;
                                state    <= RECEIVING;
                            else
                                byte_idx <= byte_idx + 1;
                            end if;
                        end if;
                end case;
            end if;
        end if;
    end process;

    tx_data <= reply(byte_idx);

    -- Enable decode, registered: en(i) = running and (sel = i). One stored id,
    -- so at most one en(i) is '1'.
    p_en: process(clk)
    begin
        if rising_edge(clk) then
            en_r <= (others => '0');
            if run_r = '1' then
                en_r(sel_r) <= '1';                -- last assignment wins
            end if;
            if reset = '1' then
                en_r <= (others => '0');
            end if;
        end if;
    end process;

    en      <= en_r;
    running <= run_r;
    stages  <= stages_r;

end rtl;
