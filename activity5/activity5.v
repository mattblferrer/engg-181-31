module digital_clock #(
    parameter CLK_FREQ = 50_000_000     // clock cycles per second
)(
    input CLK,
    input [3:0] SW,
    input [3:0] PB,
    output [9:0] LEDR,
    output [7:0] LEDG,
    output reg [6:0] DIG3, DIG2, DIG1, DIG0
);
    // SW[0] = set time, SW[1] = show mm:ss, SW[2] = alarm on, SW[3] = set alarm
    // PB[0] = master reset, PB[1] = hour up, PB[2] = minute up, PB[3] = minute down
    wire show_sec  = SW[1];
    wire alarm_on  = SW[2];
    wire set_alarm = SW[3];
    wire set_time  = SW[0] & ~SW[3];

    // clock division to 1 Hz tick
    reg [25:0] clk_cnt = 26'd0;
    wire tick  = (clk_cnt == CLK_FREQ - 1);
    wire blink = (clk_cnt < CLK_FREQ / 2);     // on for the first half of each second

    // falling edge detection for push buttons (active low)
    reg [2:0] pb1_sync = 3'b111, pb2_sync = 3'b111, pb3_sync = 3'b111;
    wire pb1_press, pb2_press, pb3_press;

    always @(posedge CLK) begin
        pb1_sync <= {pb1_sync[1:0], PB[1]};
        pb2_sync <= {pb2_sync[1:0], PB[2]};
        pb3_sync <= {pb3_sync[1:0], PB[3]};
    end
    assign pb1_press = (pb1_sync[2:1] == 2'b10);
    assign pb2_press = (pb2_sync[2:1] == 2'b10);
    assign pb3_press = (pb3_sync[2:1] == 2'b10);

    // current time (24-hour) and alarm time
    reg [4:0] hours   = 5'd0;
    reg [5:0] minutes = 6'd0;
    reg [5:0] seconds = 6'd0;
    reg [4:0] alarm_hours   = 5'd0;
    reg [5:0] alarm_minutes = 6'd0;

    // time keeping and time setting
    always @(posedge CLK) begin
        if (!PB[0]) begin
            clk_cnt <= 26'd0;
            hours   <= 5'd0;
            minutes <= 6'd0;
            seconds <= 6'd0;
        end
        else begin
            if (tick) clk_cnt <= 26'd0;
            else clk_cnt <= clk_cnt + 1'b1;

            if (set_time) begin
                // clock is paused at :00 while setting
                seconds <= 6'd0;
                if (pb1_press) hours <= (hours == 5'd23) ? 5'd0 : hours + 1'b1;
                if (pb2_press) minutes <= (minutes == 6'd59) ? 6'd0 : minutes + 1'b1;
                else if (pb3_press) minutes <= (minutes == 6'd0) ? 6'd59 : minutes - 1'b1;
            end
            else if (tick) begin
                if (seconds == 6'd59) begin
                    seconds <= 6'd0;
                    if (minutes == 6'd59) begin
                        minutes <= 6'd0;
                        hours   <= (hours == 5'd23) ? 5'd0 : hours + 1'b1;
                    end
                    else minutes <= minutes + 1'b1;
                end
                else seconds <= seconds + 1'b1;
            end
        end
    end

    // alarm setting
    always @(posedge CLK) begin
        if (!PB[0]) begin
            alarm_hours   <= 5'd0;
            alarm_minutes <= 6'd0;
        end
        else if (set_alarm) begin
            if (pb1_press) alarm_hours <= (alarm_hours == 5'd23) ? 5'd0 : alarm_hours + 1'b1;
            if (pb2_press) alarm_minutes <= (alarm_minutes == 6'd59) ? 6'd0 : alarm_minutes + 1'b1;
            else if (pb3_press) alarm_minutes <= (alarm_minutes == 6'd0) ? 6'd59 : alarm_minutes - 1'b1;
        end
    end

    // alarm: all LEDs blink every second for the whole minute where TIME = ALARM
    wire ringing = alarm_on && (hours == alarm_hours) && (minutes == alarm_minutes);
    assign LEDR = {10{ringing & blink}};
    assign LEDG = {8{ringing & blink}};

    // display on 7-segment display
    function [6:0] seven_seg;
        input [3:0] digit;
        begin
            case (digit)
                4'd0: seven_seg = 7'b1000000;
                4'd1: seven_seg = 7'b1111001;
                4'd2: seven_seg = 7'b0100100;
                4'd3: seven_seg = 7'b0110000;
                4'd4: seven_seg = 7'b0011001;
                4'd5: seven_seg = 7'b0010010;
                4'd6: seven_seg = 7'b0000010;
                4'd7: seven_seg = 7'b1111000;
                4'd8: seven_seg = 7'b0000000;
                4'd9: seven_seg = 7'b0010000;
                default: seven_seg = 7'b1111111;
            endcase
        end
    endfunction

    integer left, right;
    always @(*) begin
        if (set_alarm) begin            // alarm hh:mm
            left  = alarm_hours;
            right = alarm_minutes;
        end
        else if (set_time) begin        // time hh:mm
            left  = hours;
            right = minutes;
        end
        else if (show_sec) begin        // time mm:ss
            left  = minutes;
            right = seconds;
        end
        else begin                      // time hh:mm
            left  = hours;
            right = minutes;
        end
        DIG0 = seven_seg(right % 10);
        DIG1 = seven_seg(right / 10);
        DIG2 = seven_seg(left % 10);
        DIG3 = seven_seg(left / 10);
    end
endmodule

module activity5(
    input CLOCK_50,
    input [3:0] SW,
    input [3:0] PB,
    output [9:0] LEDR,
    output [7:0] LEDG,
    output [6:0] HEX3, HEX2, HEX1, HEX0
);
    digital_clock clock_dut(CLOCK_50, SW, PB, LEDR, LEDG, HEX3, HEX2, HEX1, HEX0);
endmodule
