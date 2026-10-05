library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity counter_10bit is
    port (
        CLK  : in  std_logic;
        FUNC : in  std_logic_vector(3 downto 0);
        LOAD : in  std_logic_vector(9 downto 0);
        LED  : out std_logic_vector(9 downto 0);
        DIG3 : out std_logic_vector(6 downto 0);
        DIG2 : out std_logic_vector(6 downto 0);
        DIG1 : out std_logic_vector(6 downto 0);
        DIG0 : out std_logic_vector(6 downto 0)
    );
end entity counter_10bit;

architecture rtl of counter_10bit is
    -- clock division to lower clock frequency
    signal clk_cnt: unsigned(25 downto 0) := (others => '0');
    signal tick: std_logic;

    -- falling edge detection for toggle buttons
    signal pb1_sync, pb2_sync: std_logic_vector(2 downto 0) := (others => '0');
    signal pb1_press, pb2_press: std_logic;

    -- 10-bit counter (0 to 1023)
    signal count: unsigned(9 downto 0) := (others => '0');
    signal start_state: std_logic := '1';   -- stop = '0', start = '1'
    signal dir_state: std_logic := '0';     -- up = '0', down = '1'

    -- 7-segment display lookup
    function seven_seg(digit : unsigned(3 downto 0)) return std_logic_vector is
        variable seg: std_logic_vector(6 downto 0);
    begin
        case to_integer(digit) is
            when 0 => seg := "1000000";
            when 1 => seg := "1111001";
            when 2 => seg := "0100100";
            when 3 => seg := "0110000";
            when 4 => seg := "0011001";
            when 5 => seg := "0010010";
            when 6 => seg := "0000010";
            when 7 => seg := "1111000";
            when 8 => seg := "0000000";
            when 9 => seg := "0010000";
            when others => seg := "1111111";
        end case;
        return seg;
    end function;

begin
    -- clock divider
    process(CLK)
    begin
        if rising_edge(CLK) then
            if clk_cnt = 50_000_000 then
                clk_cnt <= (others => '0');
            else
                clk_cnt <= clk_cnt + 1;
            end if;
        end if;
    end process;

    tick <= '1' when clk_cnt = 0 else '0';

    -- synchronize + edge-detect toggle buttons
    process(CLK)
    begin
        if rising_edge(CLK) then
            pb1_sync <= pb1_sync(1 downto 0) & FUNC(1);
            pb2_sync <= pb2_sync(1 downto 0) & FUNC(2);
        end if;
    end process;

    pb1_press <= '1' when pb1_sync(2 downto 1) = "10" else '0';
    pb2_press <= '1' when pb2_sync(2 downto 1) = "10" else '0';

    -- main counter logic
    process(CLK)
    begin
        if rising_edge(CLK) then
            if pb1_press = '1' then
                start_state <= not start_state;
            end if;
            if pb2_press = '1' then
                dir_state <= not dir_state;
            end if;

            if FUNC(0) = '0' then
                count <= (others => '0');
            elsif FUNC(3) = '0' then
                count <= unsigned(LOAD);
            elsif start_state = '1' and tick = '1' then
                if dir_state = '1' then
                    count <= count - 1;
                else
                    count <= count + 1;
                end if;
            end if;
        end if;
    end process;

    -- display on 7-segment displays and LEDs
    process(count)
        variable value : integer;
    begin
        value := to_integer(count);
        DIG0 <= seven_seg(to_unsigned(value mod 10, 4));
        DIG1 <= seven_seg(to_unsigned((value / 10) mod 10, 4));
        DIG2 <= seven_seg(to_unsigned((value / 100) mod 10, 4));
        DIG3 <= seven_seg(to_unsigned((value / 1000) mod 10, 4));
        LED <= std_logic_vector(count);
    end process;
end architecture rtl;


library ieee;
use ieee.std_logic_1164.all;

entity activity3b is
    port (
        CLOCK_50    : in  std_logic;
        PB          : in  std_logic_vector(3 downto 0);
        SW          : in  std_logic_vector(9 downto 0);
        LEDR        : out std_logic_vector(9 downto 0);
        HEX3        : out std_logic_vector(6 downto 0);
        HEX2        : out std_logic_vector(6 downto 0);
        HEX1        : out std_logic_vector(6 downto 0);
        HEX0        : out std_logic_vector(6 downto 0)
    );
end entity activity3b;

architecture structural of activity3b is
begin
    cnt : entity work.counter_10bit
        port map (
            CLK  => CLOCK_50,
            FUNC => PB,
            LOAD => SW,
            LED  => LEDR,
            DIG3 => HEX3,
            DIG2 => HEX2,
            DIG1 => HEX1,
            DIG0 => HEX0
        );

end architecture structural;