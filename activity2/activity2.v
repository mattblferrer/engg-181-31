module counter_10bit(
    input CLK,
    input [3:0] FUNC,
    input [9:0] LOAD,
    output reg [9:0] LED,
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
    
    // falling edge detection for toggle buttons
    reg [2:0] pb1_sync, pb2_sync;
    wire pb1_press, pb2_press;
 
    always @(posedge CLK) begin
        pb1_sync <= {pb1_sync[1:0], FUNC[1]};
        pb2_sync <= {pb2_sync[1:0], FUNC[2]};
    end
    assign pb1_press = (pb1_sync[2:1] == 2'b10); 
    assign pb2_press = (pb2_sync[2:1] == 2'b10);
 
    // 10-bit counter (0 to 1023)
    reg [9:0] count = 10'd0;
    reg start_state = 1'b1;   // stop = 0, start = 1
    reg dir_state   = 1'b0;   // up = 0, down = 1
 
    always @(posedge CLK) begin
        if (pb1_press) start_state <= ~start_state;
        if (pb2_press) dir_state <= ~dir_state;
        if (!FUNC[0]) begin
            count <= 10'd0;
        end 
        else if (!FUNC[3]) begin
            count <= LOAD;
        end 
        else if (start_state && tick) begin
            if (dir_state) count <= count - 1'b1;
            else count <= count + 1'b1;
        end
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
        DIG2 = seven_seg((value / 100) % 10);
        DIG3 = seven_seg((value / 1000) % 10);
        LED = count;
    end
 endmodule
    
module activity2(
    input CLOCK_50,
    input [3:0] PB,
    input [9:0] SW,
    output [9:0] LEDR,
    output [6:0] HEX3, HEX2, HEX1, HEX0
);
	counter_10bit cnt(CLOCK_50, PB, SW, LEDR, HEX3, HEX2, HEX1, HEX0);
endmodule