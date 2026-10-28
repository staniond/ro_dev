----------------------------------------------------------------------------------
-- Company: FIT CTU
-- Engineer: Ondrej Stanicek
--
-- Module Name: ro_prescaler - rtl
-- Description:
--   Divides a fast clock-like signal (e.g. a RO output, ~100-350 MHz) by DIVIDE,
--   so it can be observed on a pin with slow equipment:
--       f_out = f_in / DIVIDE
--
--   Ripple divider: a chain of toggle flip-flops, each clocked by the previous
--   stage's output. Only the first stage runs at f_in, so there is no wide
--   counter to meet timing at RO speed. DIVIDE must be a power of two (each
--   stage divides by 2).
--
--   taps(i) is the output of stage i (clk_in / 2^(i+1)), so a mux after the
--   prescaler can pick the division at run time. clk_out = taps(last).
--
--   Timing: every stage output is used as a clock, so it needs a generated
--   clock; constrs_1/new/ro_prescaler.tcl creates them for every instance.
--   The stage outputs are not synchronous to anything else and the phase is
--   arbitrary (no reset), which doesn't matter for frequency measurement.
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

use work.ro_pkg.all;

entity ro_prescaler is
    Generic (
        DIVIDE : positive := 256      -- division factor, power of two >= 2
    );
    Port (
        clk_in  : in  STD_LOGIC;      -- signal to divide (e.g. ro_out of a ro_cell)
        clk_out : out STD_LOGIC;      -- clk_in / DIVIDE, 50 % duty cycle
        taps    : out STD_LOGIC_VECTOR(log2(DIVIDE)-1 downto 0)  -- taps(i) = clk_in / 2^(i+1)
    );
end ro_prescaler;

architecture rtl of ro_prescaler is
    -- number of /2 stages (log2 from ro_pkg)
    constant STAGES : natural := log2(DIVIDE);

    -- DIVIDE must be a power of two >= 2. If it isn't, this constant gets the
    -- value 0, outside its range 1 to 1, and elaboration stops with an error in
    -- both simulation and synthesis (Vivado synthesis ignores `assert` by default).
    constant DIVIDE_IS_POWER_OF_TWO : integer range 1 to 1 :=
        boolean'pos(DIVIDE >= 2 and 2**STAGES = DIVIDE);

    signal stage_clk : std_logic_vector(STAGES-1 downto 0);  -- clock of stage i
    signal stage     : std_logic_vector(STAGES-1 downto 0) := (others => '0');
begin
    stage_clk(0) <= clk_in;
    gen_clk: for i in 1 to STAGES-1 generate
        stage_clk(i) <= stage(i-1);
    end generate;

    -- flip-flop names: gen_stage[i].stage_reg[i] (ro_prescaler.tcl relies on them)
    gen_stage: for i in 0 to STAGES-1 generate
        p_stage: process(stage_clk(i))
        begin
            if rising_edge(stage_clk(i)) then
                stage(i) <= not stage(i);
            end if;
        end process;
    end generate;

    clk_out <= stage(STAGES-1);
    taps    <= stage;

end rtl;
