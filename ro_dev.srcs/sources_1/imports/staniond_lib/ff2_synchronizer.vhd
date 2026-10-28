----------------------------------------------------------------------------------
-- Company: FIT CTU
-- Engineer: Ondrej Stanicek
-- 
-- Create Date: 07/25/2022 09:43:04 PM
-- Design Name: 
-- Module Name: counter - Behavioral
-- Project Name: 
-- Target Devices: 
-- Tool Versions: 
-- Description: 
-- 
-- Dependencies: 
-- 
-- Revision:
-- Revision 0.01 - File Created
-- Additional Comments:
-- 
----------------------------------------------------------------------------------


library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use ieee.math_real.all;

-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
--use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx leaf cells in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

entity ff2_synchronizer is
  Port (
    output_clock: in std_logic;
    input: in std_logic;
    output: out std_logic
  );
end ff2_synchronizer;

architecture Behavioral of ff2_synchronizer is
    signal inputFF: std_logic;
    signal inputFF2: std_logic;
	
	    
    attribute ASYNC_REG : string;
    attribute ASYNC_REG of inputFF : signal is "TRUE";
    attribute ASYNC_REG of inputFF2 : signal is "TRUE";
begin

    process (output_clock)
    begin
       if rising_edge(output_clock) then
          inputFF  <= input;
          inputFF2 <= inputFF;
       end if;
    end process;
    
    output <= inputFF2;

end Behavioral;
