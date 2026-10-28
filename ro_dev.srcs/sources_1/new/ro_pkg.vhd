----------------------------------------------------------------------------------
-- Company: FIT CTU
-- Engineer: Ondrej Stanicek
--
-- Package Name: ro_pkg
-- Description:
--   Helpers shared by the RO modules. In a package so they can also be used in
--   port declarations (e.g. a port width that depends on a generic).
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

package ro_pkg is
    -- floor(log2(n)): number of /2 stages in a power-of-two divider
    function log2(n : positive) return natural;
end package ro_pkg;

package body ro_pkg is
    function log2(n : positive) return natural is
        variable v : positive := n;
        variable r : natural  := 0;
    begin
        while v > 1 loop
            v := v / 2;
            r := r + 1;
        end loop;
        return r;
    end function;
end package body ro_pkg;
