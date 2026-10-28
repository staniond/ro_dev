----------------------------------------------------------------------------------
-- Company: FIT CTU
-- Engineer: Ondrej Stanicek
--
-- Module Name: ro_select - rtl
-- Description:
--   Combines the outputs of N ring oscillators into one signal: the output of
--   the one RO that is enabled.
--
--   A stopped RO holds its ro_out at '0' (its toggle FF is cleared while
--   en = '0'), and ro_ctrl enables at most one RO at a time, so the OR of all
--   ro_out IS the selected RO's output. Unlike a N:1 mux, no select lines have
--   to reach every input, which matters for thousands of ROs.
--
--   The result passes through an instantiated LUT1 buffer u_root (DONT_TOUCH):
--   a fixed pin, <inst>/u_root/O, on which ro_place.tcl declares the clock of
--   the selected RO signal (FF outputs carry no clock, so this is where the
--   measurement path's clock starts).
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

library UNISIM;
use UNISIM.VComponents.all;

entity ro_select is
    Generic (
        N : positive                                  -- number of ROs
    );
    Port (
        ro_out  : in  STD_LOGIC_VECTOR(N-1 downto 0); -- ro_out of every ro_cell
        sel_out : out STD_LOGIC                       -- ro_out of the enabled RO
    );
end ro_select;

architecture rtl of ro_select is
    signal any_ro : std_logic;

    attribute DONT_TOUCH : string;
    attribute DONT_TOUCH of u_root : label is "TRUE";
begin
    p_or: process(ro_out)
        variable v : std_logic;
    begin
        v := '0';
        for i in ro_out'range loop
            v := v or ro_out(i);
        end loop;
        any_ro <= v;
    end process;

    -- buffer: sel_out = any_ro
    u_root: LUT1
        generic map (INIT => "10")
        port map (O => sel_out, I0 => any_ro);

end rtl;
