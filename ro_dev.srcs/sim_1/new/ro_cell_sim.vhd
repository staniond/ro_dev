----------------------------------------------------------------------------------
-- Module Name: ro_cell - sim
-- Description:
--   Behavioral model of ro_cell for simulation only (sim_1 fileset).
--   Same structure as architecture rtl, but every gate has a delay so the
--   ring actually oscillates instead of hitting the simulator's delta limit.
--   GATE_DELAY is a rough guess (~LUT + local route), not a frequency prediction;
--   use post-route timing simulation for that.
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

architecture sim of ro_cell is
    constant GATE_DELAY : time := 500 ps;

    signal ring0 : std_logic := '1';
    signal ring1 : std_logic := '0';
    signal ring2 : std_logic := '1';
    signal en_n  : std_logic;
    signal q     : std_logic := '0';
begin
    ring0 <= not (en and ring2) after GATE_DELAY;
    ring1 <= not ring0          after GATE_DELAY;
    ring2 <= not ring1          after GATE_DELAY;
    en_n  <= not en;

    p_ff: process(ring2, en_n)
    begin
        if en_n = '1' then
            q <= '0';
        elsif rising_edge(ring2) then
            q <= not q;
        end if;
    end process;

    ro_out <= q;

end sim;
