----------------------------------------------------------------------------------
-- Company: FIT CTU
-- Engineer: Ondrej Stanicek
--
-- Module Name: por - rtl
-- Description:
--   Power-on reset: holds rst asserted for 2^CNT_WIDTH clocks after
--   configuration, then releases it for good. Guarantees a clean startup reset
--   (defined tx idle-high, etc.) without needing the physical pushbutton, and
--   gives sim/hardware parity. Relies on the FPGA's register initial values
--   (rst starts at '1', the counter at 0).
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity por is
    Generic (
        CNT_WIDTH : positive := 8           -- reset lasts 2^CNT_WIDTH clocks (default 256)
    );
    Port (
        clk : in  STD_LOGIC;
        rst : out STD_LOGIC                 -- '1' after configuration, then '0'
    );
end por;

architecture rtl of por is
    signal cnt   : unsigned(CNT_WIDTH-1 downto 0) := (others => '0');
    signal rst_r : std_logic := '1';
    -- Terminal count = all-ones for cnt's width; tracks the width automatically.
    constant CNT_MAX : unsigned(cnt'range) := (others => '1');
begin
    -- Count up to CNT_MAX once, then deassert rst.
    p_por: process(clk)
    begin
        if rising_edge(clk) then
            if cnt = CNT_MAX then
                rst_r <= '0';
            else
                cnt <= cnt + 1;
            end if;
        end if;
    end process;

    rst <= rst_r;

end rtl;
