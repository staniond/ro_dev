----------------------------------------------------------------------------------
-- Testbench for ro_ctrl: drives its byte interface directly (no UART bit timing).
-- Checks: run, change of stages, switch with all-off gap, stop, invalid stages,
-- invalid id, resync after an incomplete command. On every clock: at most one
-- en bit is '1'.
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity ro_ctrl_tb is
end ro_ctrl_tb;

architecture Behavioral of ro_ctrl_tb is
    constant CLK_PERIOD : time    := 10 ns;
    constant N_RO       : integer := 5;
    constant TIMEOUT    : integer := 50;    -- cycles between bytes before a partial command is dropped
    constant STOP       : integer := 16;

    signal clk   : std_logic := '0';
    signal reset : std_logic := '1';

    -- rx side (models the FWFT rx FIFO with a single byte slot)
    signal rx_data       : std_logic_vector(7 downto 0) := (others => '0');
    signal rx_data_ready : std_logic := '0';
    signal rx_data_read  : std_logic;
    -- tx side
    signal tx_ena        : std_logic;
    signal tx_data       : std_logic_vector(7 downto 0);
    signal tx_fifo_full  : std_logic := '0';

    signal en      : std_logic_vector(N_RO-1 downto 0);
    signal running : std_logic;
    signal stages  : natural range 0 to 8;

    type t_bytes is array (natural range <>) of std_logic_vector(7 downto 0);
    signal tx_log   : t_bytes(0 to 2) := (others => (others => '0'));
    signal tx_count : natural := 0;

    signal off_cycles   : natural := 0;       -- clock cycles with all en = '0'
    signal done         : boolean := false;

    function ones(v : std_logic_vector) return natural is
        variable n : natural := 0;
    begin
        for i in v'range loop
            if v(i) = '1' then n := n + 1; end if;
        end loop;
        return n;
    end function;
begin
    clk <= not clk after CLK_PERIOD/2 when not done;

    uut: entity work.ro_ctrl
        generic map (N_RO => N_RO, MAX_STAGES => 8, TIMEOUT_CYCLES => TIMEOUT, STOP_CYCLES => STOP)
        port map (
            clk => clk, reset => reset,
            rx_data => rx_data, rx_data_ready => rx_data_ready, rx_data_read => rx_data_read,
            tx_ena => tx_ena, tx_data => tx_data, tx_fifo_full => tx_fifo_full,
            en => en, running => running, stages => stages);

    -- every clock: never two ROs enabled; remember when all are off
    p_onehot: process(clk)
    begin
        if rising_edge(clk) then
            assert ones(en) <= 1 report "more than one en bit set: " & integer'image(ones(en)) severity error;
            if ones(en) = 0 then off_cycles <= off_cycles + 1; end if;
        end if;
    end process;

    -- collect reply bytes (last 3)
    p_tx: process(clk)
    begin
        if rising_edge(clk) then
            if tx_ena = '1' then
                tx_log(tx_count mod 3) <= tx_data;
                tx_count <= tx_count + 1;
            end if;
        end if;
    end process;

    p_stim: process
        variable n_before : natural;
        variable off_before : natural;

        procedure send_byte(b : integer) is
        begin
            rx_data <= std_logic_vector(to_unsigned(b, 8));
            rx_data_ready <= '1';
            wait until rising_edge(clk) and rx_data_read = '1';
            rx_data_ready <= '0';
            wait until rising_edge(clk);
        end procedure;

        -- send a command and wait for its 3-byte reply
        procedure command(s, hi, lo : integer) is
            variable n0 : natural;
        begin
            n0 := tx_count;
            send_byte(s); send_byte(hi); send_byte(lo);
            wait until rising_edge(clk) and tx_count = n0 + 3;
            wait until rising_edge(clk);
        end procedure;

        procedure check_reply(b0, b1, b2 : integer; what : string) is
        begin
            assert tx_log(0) = std_logic_vector(to_unsigned(b0, 8)) and
                   tx_log(1) = std_logic_vector(to_unsigned(b1, 8)) and
                   tx_log(2) = std_logic_vector(to_unsigned(b2, 8))
                report what & ": wrong reply" severity error;
        end procedure;

        procedure check_en(id : integer; st : integer; what : string) is
        begin
            if id < 0 then
                assert ones(en) = 0 and running = '0' report what & ": expected all ROs off" severity error;
            else
                assert en(id) = '1' and ones(en) = 1 and running = '1'
                    report what & ": expected only RO " & integer'image(id) & " on" severity error;
                assert stages = st report what & ": wrong stages" severity error;
            end if;
        end procedure;
    begin
        wait for 5 * CLK_PERIOD;
        reset <= '0';
        wait until rising_edge(clk);
        check_en(-1, 0, "after reset");

        command(8, 0, 2);   check_reply(8, 0, 2, "run RO 2 /256");    check_en(2, 8, "run RO 2");
        command(3, 0, 2);   check_reply(3, 0, 2, "same RO, stages 3"); check_en(2, 3, "stages 3");

        off_before := off_cycles;
        command(0, 0, 4);   check_reply(0, 0, 4, "switch to RO 4");   check_en(4, 0, "switch");
        assert off_cycles >= off_before + STOP
            report "switch: expected >= " & integer'image(STOP) & " all-off cycles, got "
                   & integer'image(off_cycles - off_before) severity error;
        report "switch: " & integer'image(off_cycles - off_before) & " cycles with all ROs off";

        command(255, 0, 0); check_reply(255, 0, 0, "stop");           check_en(-1, 0, "stop");
        command(1, 0, 1);   check_reply(1, 0, 1, "run RO 1");         check_en(1, 1, "run RO 1");

        command(9, 0, 3);   check_reply(16#EE#, 0, 3, "stages 9");    check_en(1, 1, "stages 9 ignored");
        command(2, 0, 5);   check_reply(16#EE#, 0, 5, "id 5");        check_en(1, 1, "id 5 ignored");
        command(2, 1, 0);   check_reply(16#EE#, 1, 0, "id 256");      check_en(1, 1, "id 256 ignored");

        -- incomplete command, then a pause longer than the timeout: dropped
        send_byte(5); send_byte(0);
        wait for (TIMEOUT + 10) * CLK_PERIOD;
        command(4, 0, 3);   check_reply(4, 0, 3, "after resync");     check_en(3, 4, "after resync");

        -- tx FIFO full: reply waits, no byte lost
        tx_fifo_full <= '1';
        n_before := tx_count;
        send_byte(255); send_byte(0); send_byte(0);
        wait for 20 * CLK_PERIOD;
        assert tx_count = n_before report "reply written while FIFO full" severity error;
        tx_fifo_full <= '0';
        wait until rising_edge(clk) and tx_count = n_before + 3;
        wait until rising_edge(clk);
        check_reply(255, 0, 0, "stop after FIFO full");               check_en(-1, 0, "stop after FIFO full");

        report "ro_ctrl_tb finished" severity note;
        done <= true;
        wait;
    end process;
end Behavioral;
