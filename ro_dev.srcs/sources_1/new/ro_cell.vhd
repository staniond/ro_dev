----------------------------------------------------------------------------------
-- Company: FIT CTU
-- Engineer: Ondrej Stanicek
--
-- Module Name: ro_cell - rtl
-- Target Devices: Artix-7 (xc7a100t)
-- Description:
--   3-stage ring oscillator with enable and toggle-FF output buffer, after
--   Hesselbarth et al., "Large Scale RO PUF Analysis ..." (HOST 2018), Fig. 1.
--
--             +---------------------------------------------+
--             |                                             |
--   en --+--[NAND]--ring0--[INV]--ring1--[INV]--ring2--+----+--> FF.C
--        |   B6LUT          A6LUT         C6LUT
--        +--[INV]--en_n--> FF.CLR      (held in reset while en = '0')
--            B5LUT
--                       q --[INV]--d--> FF.D     ro_out = q = f_RO / 2
--                           D6LUT        DFF
--
--   Every gate is an instantiated LUT primitive with DONT_TOUCH, so synthesis
--   cannot merge or remove the inverters. The whole cell fits in ONE slice;
--   the BEL assignment above is applied by ro_place.tcl (implementation only),
--   which also fixes the slice (LOC) and the LUT pin mapping (LOCK_PINS).
--
--   Simulation: the zero-delay UNISIM LUTs form a delta-cycle loop, so
--   behavioral testbenches must use architecture "sim" (sim_1/new/ro_cell_sim.vhd).
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

library UNISIM;
use UNISIM.VComponents.all;

entity ro_cell is
    Port (
        en     : in  STD_LOGIC;   -- '1' = oscillate, '0' = stop and clear ro_out
        ro_out : out STD_LOGIC    -- toggle-FF output, half the RO frequency
    );
end ro_cell;

architecture rtl of ro_cell is
    signal ring0 : std_logic;     -- NAND output
    signal ring1 : std_logic;     -- 1st inverter output
    signal ring2 : std_logic;     -- 2nd inverter output: feedback + FF clock
    signal en_n  : std_logic;     -- FF asynchronous clear
    signal q     : std_logic;     -- toggle FF state
    signal d     : std_logic;     -- not q

    -- Keep every cell and net exactly as written; names are used by the Tcl scripts.
    attribute DONT_TOUCH : string;
    attribute DONT_TOUCH of ring0, ring1, ring2, en_n, q, d : signal is "TRUE";
    attribute DONT_TOUCH of lut_nand, lut_clr, lut_inv1, lut_inv2, lut_tog, ff : label is "TRUE";
begin

    -- B LUT, O6: ring0 = not (en and ring2)   (I0 = en, I1 = ring2)
    lut_nand: LUT2
        generic map (INIT => "0111")
        port map (O => ring0, I0 => en, I1 => ring2);

    -- B LUT, O5: en_n = not en   (shares the en input pin with lut_nand)
    lut_clr: LUT1
        generic map (INIT => "01")
        port map (O => en_n, I0 => en);

    -- A LUT: ring1 = not ring0
    lut_inv1: LUT1
        generic map (INIT => "01")
        port map (O => ring1, I0 => ring0);

    -- C LUT: ring2 = not ring1
    lut_inv2: LUT1
        generic map (INIT => "01")
        port map (O => ring2, I0 => ring1);

    -- D LUT: d = not q, feeds DFF.D through the slice-internal path (no routing)
    lut_tog: LUT1
        generic map (INIT => "01")
        port map (O => d, I0 => q);

    -- Toggle FF clocked by the ring, cleared while en = '0'
    ff: FDCE
        generic map (INIT => '0')
        port map (Q => q, C => ring2, CE => '1', CLR => en_n, D => d);

    ro_out <= q;

end rtl;
