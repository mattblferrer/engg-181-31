module sequential(
    input CLK,
    output reg [3:0] LED, 
    output reg [6:0] DIG3, DIG2, DIG1, DIG0
);
    // clock division to lower clock frequency
    reg [25:0] clk_cnt = 26'd0;
    wire tick;
    always @(posedge CLK) begin
        if (clk_cnt == 26'd50_000_000) clk_cnt <= 26'd0;
        else clk_cnt <= clk_cnt + 1'b1;
    end
    assign tick = (clk_cnt == 26'd0);
    
    // sequential circuit 0-1-3-7-15-7-3-1-0
    reg [3:0] count = 4'd0;
    reg state = 1'b0;  // 0 = increasing, 1 = decreasing
    always @(posedge tick) begin
        case (state)
            1'b0: begin  // increasing
                case (count) 
                    4'd0: count = 4'd1;
                    4'd1: count = 4'd3;
                    4'd3: count = 4'd7;
                    4'd7: begin
                        count = 4'd15;
                        state = 1;
                    end
                    default: count = 4'd0;
                endcase
            end
            1'b1: begin  // decreasing
                case (count) 
                    4'd1: begin
                        count = 4'd0;
                        state = 0;
                    end
                    4'd3: count = 4'd1;
                    4'd7: count = 4'd3;
                    4'd15: count = 4'd7;
                    default: count = 4'd0;
                endcase
            end
        endcase
    end
    
    // display on 7-segment display and LEDs
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
    
    integer value;
    always @(*) begin
        value = count;
        DIG0 = seven_seg(value % 10);
        DIG1 = seven_seg((value / 10) % 10);
        DIG2 = seven_seg(0);
        DIG3 = seven_seg(0);
        LED = count;
    end
endmodule

module activity3(
    input CLOCK_50,
    output [3:0] LEDR,
    output [6:0] HEX3, HEX2, HEX1, HEX0
);
    sequential seq_dut(CLOCK_50, LEDR, HEX3, HEX2, HEX1, HEX0);
endmodule