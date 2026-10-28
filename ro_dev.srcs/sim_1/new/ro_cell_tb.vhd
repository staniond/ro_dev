library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity ro_cell_tb is
end ro_cell_tb;

architecture Behavioral of ro_cell_tb is
    signal en     : std_logic := '0';
    signal ro_out : std_logic;
    signal edges  : natural := 0;   -- rising edges of ro_out
begin

    uut: entity work.ro_cell(sim)
        port map (en => en, ro_out => ro_out);

    p_count: process(ro_out)
    begin
        if rising_edge(ro_out) then
            edges <= edges + 1;
        end if;
    end process;

    p_stim: process
        variable edges_start : natural;
    begin
        -- Disabled: output held in reset
        wait for 100 ns;
        assert ro_out = '0' report "ro_out not '0' while disabled" severity error;
        assert edges = 0 report "ro_out toggled while disabled" severity error;

        -- Enabled: must oscillate
        en <= '1';
        edges_start := edges;
        wait for 1 us;
        assert edges > edges_start + 10
            report "ro_out does not toggle while enabled" severity error;
        report "edges in 1 us: " & integer'image(edges - edges_start);

        -- Disabled again: asynchronous clear, then quiet
        en <= '0';
        wait for 10 ns;
        assert ro_out = '0' report "ro_out not cleared after disable" severity error;
        edges_start := edges;
        wait for 100 ns;
        assert edges = edges_start report "ro_out toggled after disable" severity error;

        report "ro_cell_tb finished" severity note;
        wait;
    end process;

end Behavioral;
