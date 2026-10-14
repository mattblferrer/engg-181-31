module ping_pong(
    input wire 	clk,
    input wire 	[2:0] SW,
    input wire 	[1:0] PB,
    output wire [9:0] LED,
    output reg 	[6:0] DIG3, DIG2, DIG1, DIG0
);
    // step time (clock cycles) per speed
    function [31:0] step_cycles;
        input [2:0] spd;
        begin
            case (spd)
                2'd0:		step_cycles = 25_000_000;
                2'd1:    	step_cycles = 12_000_000;
                2'd2:    	step_cycles = 6_000_000;
                2'd3:    	step_cycles = 3_000_000;
                default: 	step_cycles = 25_000_000;
            endcase
        end
    endfunction
 
    // synchronize inputs + rising-edge detection
    reg [1:0] pb0_s, pb1_s;
    reg pb0_d, pb1_d;
    always @(posedge clk) begin
        pb0_s <= {pb0_s[0], PB[0]};
        pb1_s <= {pb1_s[0], PB[1]};
        pb0_d <= pb0_s[1];
        pb1_d <= pb1_s[1];
    end
    wire p1_press = pb0_s[1] & ~pb0_d;
    wire p2_press = pb1_s[1] & ~pb1_d;
 
    // initialize game state
    localparam S_SERVE = 1'b0, S_PLAY = 1'b1;
 
    reg state;
    reg dir;      // 0 = towards Player 1, 1 = towards Player 2
    reg server;   // 0 = Player 1 serves, 1 = Player 2 serves
    reg [3:0] pos;      // ball position 0 to 9
    reg [1:0] speed;    // current ball speed 1 to 4
    reg [31:0] cnt;      // step timer
    wire [1:0] base_speed = SW[2:1];
    wire [1:0] fast_speed = (base_speed == 2'd3) ? 2'd3 : base_speed + 1;
    wire tick = (cnt >= step_cycles(speed) - 1);
 
    // ball LED and scores
    assign LED = 10'd1 << pos;
    integer Score1 = 0;
    integer Score2 = 0;
 
    always @(posedge clk) begin
        if (SW[0]) begin
            // reset scores and restart game
            Score1 <= 4'd0;
            Score2 <= 4'd0;
            state  <= S_SERVE;
            server <= 1'b0;
            dir    <= 1'b1;
            pos    <= 4'd0;
            speed  <= base_speed;
            cnt    <= 32'd0;
        end else begin
            case (state)
                S_SERVE: begin
                    pos   <= server ? 4'd9 : 4'd0;
                    speed <= base_speed;
                    cnt   <= 32'd0;
                    if (!server && p1_press) begin
                        dir   <= 1'b1;
                        state <= S_PLAY;
                    end else if (server && p2_press) begin
                        dir   <= 1'b0;
                        state <= S_PLAY;
                    end
                end
                S_PLAY: begin
                    cnt <= cnt + 1'b1;
 
                    // Player 1 returns the ball
                    if (dir == 1'b0 && p1_press && pos <= 4'd1) begin
                        dir   <= 1'b1;
                        speed <= (pos == 4'd0) ? base_speed : fast_speed;
                        cnt   <= 32'd0;
                    end
                    // Player 2 returns the ball
                    else if (dir == 1'b1 && p2_press && pos >= 4'd8) begin
                        dir   <= 1'b0;
                        speed <= (pos == 4'd9) ? base_speed : fast_speed;
                        cnt   <= 32'd0;
                    end
                    // move the ball one LED
                    else if (tick) begin
                        cnt <= 32'd0;
                        if (dir == 1'b0) begin
                            if (pos == 4'd0) begin          // P1 missed
                                if (Score2 != 99) Score2 <= Score2 + 1'b1;
                                server <= 1'b0;             // P1 serves next
                                state  <= S_SERVE;
                            end else
                                pos <= pos - 1'b1;
                        end else begin
                            if (pos == 4'd9) begin          // P2 missed
                                if (Score1 != 99) Score1 <= Score1 + 1'b1;
                                server <= 1'b1;             // P2 serves next
                                state  <= S_SERVE;
                            end else
                                pos <= pos + 1'b1;
                        end
                    end
                end
            endcase
        end
    end
    
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
    
    always @(*) begin
        DIG0 = seven_seg(Score1 % 10);
        DIG1 = seven_seg((Score1 / 10) % 10);
        DIG2 = seven_seg(Score2 % 10);
        DIG3 = seven_seg((Score2 / 10) % 10);
    end
endmodule

module activity4(
    input CLOCK_50,
    input [2:0] SW,
    input [1:0] PB,
    output [9:0] LEDR,
    output [6:0] HEX3, HEX2, HEX1, HEX0
);
    ping_pong dut(CLOCK_50, SW, PB, LEDR, HEX3, HEX2, HEX1, HEX0);
endmodule