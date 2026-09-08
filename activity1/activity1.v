module maj_4module(input A, B, C, D, output OUT);
	assign OUT = (A & B & C) | (A & B & D) | (B & C & D) | (A & C & D);
endmodule

module alu_2bitmodule(input M, input [3:0]S, input [1:0]A, input [1:0]B, output reg[2:0] OUT);
	always @(S, M, A, B) begin
		case(M)
		0: begin
			case(S) 
				4'b0000: OUT = A;
				4'b0001: OUT = A | B;
				4'b0010: OUT = A | (~B);
				4'b0011: OUT = -1;
				4'b0100: OUT = A + (A & (~B));
				4'b0101: OUT = (A | B) + (A & (~B));
				4'b0110: OUT = A - B;
				4'b0111: OUT = A | (~B) - 1;
				4'b1000: OUT = A + (A & B);
				4'b1001: OUT = A + B + 1;
				4'b1010: OUT = (A | (~B)) + (A & B);
				4'b1011: OUT = (A & B) + 1;
				4'b1100: OUT = A + A;
				4'b1101: OUT = (A | B) + A;
				4'b1110: OUT = (A | (~B)) + A;
				4'b1111: OUT = A - 1;
			endcase
		end
		1: begin
			case(S) 
				4'b0000: OUT = ~A;
				4'b0001: OUT = ~(A | B);
				4'b0010: OUT = (~A) & B;
				4'b0011: OUT = 0;
				4'b0100: OUT = ~(A & B);
				4'b0101: OUT = ~B;
				4'b0110: OUT = A ^ B;
				4'b0111: OUT = A & (~B);
				4'b1000: OUT = (~A) | B;
				4'b1001: OUT = ~(A ^ B);
				4'b1010: OUT = B;
				4'b1011: OUT = A & B;
				4'b1100: OUT = 1;
				4'b1101: OUT = A | (~B);
				4'b1110: OUT = A | B;
				4'b1111: OUT = A;
			endcase
		end
		endcase
	end
endmodule
	
module activity1(input [9:0]SW, output [0:0]LEDR, output [2:0]LEDG);
	maj_4module maj_4(SW[0], SW[1], SW[2], SW[3], LEDR[0]);
	alu_2bitmodule alu_2bit(SW[6], SW[3:0], SW[5:4], SW[9:8], LEDG[2:0]);
endmodule

module tb_activity1();
	integer m, s, a, b, c, d;
	reg [9:0] sw;	
	wire [0:0] ledr;
	wire [2:0] ledg;
	
	activity1 ac1(sw[9:0], ledr, ledg[2:0]);
	
	initial begin
		// Part 1
		for (a = 0; a < 2; a = a + 1) begin
			for (b = 0; b < 2; b = b + 1) begin
				for (c = 0; c < 2; c = c + 1) begin
					for (d = 0; d < 2; d = d + 1) begin
						sw[0] = a; 
						sw[1] = b; 
						sw[2] = c; 
						sw[3] = d;
						
						$display("A=%b B=%b C=%b D=%b OUT=%b", sw[0], sw[1], sw[2], sw[3], ledr[0]);
						#10;
					end
				end
			end
		end
		
		// Part 2
		for (m = 0; m < 2; m = m + 1) begin
			for (s = 0; s < 16; s = s + 1) begin
				for (a = 0; a < 4; a = a + 1) begin
					for (b = 0; b < 4; b = b + 1) begin
						sw[6] = m;
						sw[3:0] = s; 
						sw[5:4] = a; 
						sw[9:8] = b;
						$display("M=%b S=%b A=%b B=%b OUT=%b", sw[6], sw[3:0], sw[5:4], sw[9:8], ledg[2:0]);
						#10;
					end
				end
			end
		end
	end
endmodule	