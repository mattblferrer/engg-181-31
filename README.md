# ENGG 181.31

Quartus projects for the Altera DE1 board (Cyclone II EP2C20F484C7). Each activity has its own folder with a `.qpf`/`.qsf` project and HDL source, and `pins.tcl` holds the DE1 default pin assignments.

## Activities

- **Activity 1** (`activity1/activity1.v`): A 4-input majority function on `SW[3:0]` and a 2-bit ALU with 16 arithmetic (`M=0`) and 16 logic (`M=1`) operations selected by `S`. Includes a testbench, `tb_activity1`, that sweeps every input combination.

- **Activity 2** (`activity2/activity2.v`): A 10-bit counter (0–1023) that steps once per second and shows its value on the LEDs and in decimal on the 7-segment displays. The push buttons reset it, load a value from the switches, start/stop it, and toggle the count direction.

- **Activity 3** (`activity3/activity3.v`): A sequential circuit that cycles 0-1-3-7-15-7-3-1-0 once per second. The value is shown on `LEDR[3:0]` and the 7-segment displays.

- **Activity 3B** (`activity3b/activity3b.vhd`): A VHDL port of the Activity 2 10-bit counter. It has the same behavior and pinout.

- **Activity 4** (`activity4/activity4.v`): A two-player ping-pong game in which the ball travels across the 10 red LEDs and players hit it back with `PB[0]` and `PB[1]`. `SW[2:1]` sets the base speed, `SW[0]` resets the game, and the scores appear on the 7-segment displays.

- **Activity 5** (`activity5/activity5.v`): A 24-hour digital clock that shows hh:mm (or mm:ss with `SW[1]`) and has time-setting and alarm-setting modes controlled by the switches and push buttons. When the alarm time is reached, all LEDs blink for that minute.
