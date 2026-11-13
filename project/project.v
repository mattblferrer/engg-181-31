// =============================================================================
// FRET RUSH - a 4-lane rhythm game for the Altera DE1 (Cyclone II EP2C20F484C7)
//
// Clock domains
//   CLOCK_50  : game logic, VGA (25 MHz pixel enable = 50 MHz / 2), I2C
//   CLOCK_24A : audio (12 MHz codec MCLK = 24 MHz / 2, 48 kHz = 24 MHz / 500)
//   game tick : start of VGA vertical blanking (~60 Hz), so state changes
//               between frames and never tears mid-frame
//
// Controls
//   lanes (left to right) : KEY3 KEY2 KEY1 KEY0
//   any KEY               : start from the menu / leave the results screen
//   SW[0]   reset to menu       SW[2:1] scroll speed (00 slow .. 11 fast)
//   SW[3]   no-fail mode        SW[4]   pause (up = paused)
//
// Outputs
//   VGA     640x480 @ 60 Hz highway, notes, score, streak, multiplier, rock meter
//   audio   line-out: bass + drums + lead notes from the chart; the lead track
//           mutes after a miss until the next hit, and a miss plays a low buzz
//   HEX3    multiplier      HEX2-0  streak
//   LEDR    rock meter      LEDG3-0 lanes, LEDG4 playing, LEDG5 paused,
//                           LEDG6 codec configured, LEDG7 lead track on
//
// Pins not in pins.tcl (DE1 default assignments):
//   VGA_R[0..3]  D9 C9 A7 B7      VGA_G[0..3] B8 C10 B9 A8
//   VGA_B[0..3]  A9 D11 A10 B10   VGA_HS A11  VGA_VS B11
//   AUD_ADCLRCK A6  AUD_DACLRCK A5  AUD_DACDAT B5  AUD_XCK B4  AUD_BCLK A4
//   I2C_SCLK A3  I2C_SDAT B3
// =============================================================================

module project(
    input        CLOCK_50,
    input        CLOCK_24A,
    input  [3:0] PB,
    input  [9:0] SW,
    output [9:0] LEDR,
    output [7:0] LEDG,
    output [6:0] HEX3, HEX2, HEX1, HEX0,
    output [3:0] VGA_R, VGA_G, VGA_B,
    output       VGA_HS, VGA_VS,
    output       AUD_XCK, AUD_BCLK, AUD_DACLRCK, AUD_DACDAT, AUD_ADCLRCK,
    output       I2C_SCLK,
    inout        I2C_SDAT
);
    // reset and pause switch synchronizers
    reg [1:0] rst_sync = 2'b11, pause_sync = 2'b00;
    always @(posedge CLOCK_50) begin
        rst_sync   <= {rst_sync[0], SW[0]};
        pause_sync <= {pause_sync[0], SW[4]};
    end
    wire rst   = rst_sync[1];
    wire pause = pause_sync[1];

    // 25 MHz pixel enable
    reg pix_en = 1'b0;
    always @(posedge CLOCK_50) pix_en <= ~pix_en;

    // VGA timing
    wire [9:0] hc, vc;
    wire hs, vs, frame_tick;
    vga_timing vga(
        .clk(CLOCK_50), .pix_en(pix_en),
        .hc(hc), .vc(vc), .hs(hs), .vs(vs), .frame_tick(frame_tick)
    );

    // push buttons
    wire [3:0] lane_press, lane_held;
    input_ctrl inp(
        .clk(CLOCK_50), .PB(PB), .lane_press(lane_press), .lane_held(lane_held)
    );

    // game state machine, hit detection and scoring
    wire [1:0]  state, judge;
    wire [15:0] song_px, press_glow, hit_glow;
    wire [8:0]  next_close;
    wire [31:0] hit;
    wire [23:0] score_bcd;
    wire [11:0] streak_bcd, aud_pkt;
    wire [2:0]  mult;
    wire [5:0]  meter, judge_timer;
    wire lead_on, failed, aud_tgl;
    game_core game(
        .clk(CLOCK_50), .rst(rst), .frame_tick(frame_tick),
        .lane_press(lane_press), .pause(pause),
        .speed_sel(SW[2:1]), .no_fail(SW[3]),
        .state(state), .song_px(song_px), .next_close(next_close), .hit(hit),
        .score_bcd(score_bcd), .streak_bcd(streak_bcd), .mult(mult), .meter(meter),
        .lead_on(lead_on), .failed(failed), .judge(judge), .judge_timer(judge_timer),
        .press_glow(press_glow), .hit_glow(hit_glow),
        .aud_pkt(aud_pkt), .aud_tgl(aud_tgl)
    );

    wire [3:0] lane_glow = {press_glow[15:12] != 0, press_glow[11:8] != 0,
                            press_glow[7:4]   != 0, press_glow[3:0]  != 0};

    // VGA renderer
    renderer gfx(
        .clk(CLOCK_50), .en(pix_en), .hc(hc), .vc(vc), .hs_in(hs), .vs_in(vs),
        .state(state), .song_px(song_px), .next_close(next_close), .hit(hit),
        .score_bcd(score_bcd), .streak_bcd(streak_bcd), .mult(mult), .meter(meter),
        .judge(judge), .judge_on(judge_timer != 0), .failed(failed),
        .lane_glow(lane_glow), .lane_held(lane_held), .hit_glow(hit_glow),
        .r(VGA_R), .g(VGA_G), .b(VGA_B), .hs(VGA_HS), .vs(VGA_VS)
    );

    // audio synthesizer + codec serial interface (24 MHz domain)
    audio_engine snd(
        .clk(CLOCK_24A), .pkt(aud_pkt), .pkt_tgl(aud_tgl),
        .xck(AUD_XCK), .bclk(AUD_BCLK), .lrck(AUD_DACLRCK), .dacdat(AUD_DACDAT)
    );
    assign AUD_ADCLRCK = AUD_DACLRCK;

    // WM8731 codec setup over I2C
    wire codec_ready;
    wm8731_config codec(
        .clk(CLOCK_50), .scl(I2C_SCLK), .sda(I2C_SDAT), .done(codec_ready)
    );

    // board displays
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

    assign HEX3 = seven_seg({1'b0, mult});
    assign HEX2 = seven_seg(streak_bcd[11:8]);
    assign HEX1 = seven_seg(streak_bcd[7:4]);
    assign HEX0 = seven_seg(streak_bcd[3:0]);

    // rock meter as a 10-LED bar graph
    genvar i;
    generate
        for (i = 0; i < 10; i = i + 1) begin : meter_leds
            assign LEDR[i] = ({4'd0, meter} * 10'd10) > (i * 64);
        end
    endgenerate

    assign LEDG[3:0] = lane_held | lane_glow;
    assign LEDG[4]   = (state == 2'd1);
    assign LEDG[5]   = (state == 2'd2);
    assign LEDG[6]   = codec_ready;
    assign LEDG[7]   = lead_on;
endmodule


// =============================================================================
// 640x480 @ 60 Hz VGA timing (25 MHz pixel enable)
// =============================================================================
module vga_timing(
    input        clk,
    input        pix_en,
    output [9:0] hc, vc,
    output       hs, vs,
    output       frame_tick
);
    localparam H_VIS = 640, H_FP = 16, H_SYNC = 96, H_TOT = 800;
    localparam V_VIS = 480, V_FP = 10, V_SYNC = 2,  V_TOT = 525;

    reg [9:0] h = 10'd0, v = 10'd0;
    always @(posedge clk) begin
        if (pix_en) begin
            if (h == H_TOT - 1) begin
                h <= 10'd0;
                v <= (v == V_TOT - 1) ? 10'd0 : v + 1'b1;
            end
            else h <= h + 1'b1;
        end
    end

    assign hc = h;
    assign vc = v;
    assign hs = ~(h >= H_VIS + H_FP && h < H_VIS + H_FP + H_SYNC);   // active low
    assign vs = ~(v >= V_VIS + V_FP && v < V_VIS + V_FP + V_SYNC);   // active low
    assign frame_tick = pix_en && (h == 10'd0) && (v == V_VIS);       // start of vblank
endmodule


// =============================================================================
// push buttons -> lane presses (one-cycle pulses); lane 0 is the leftmost lane
// =============================================================================
module input_ctrl(
    input        clk,
    input  [3:0] PB,            // active low, debounced on the DE1
    output [3:0] lane_press,
    output [3:0] lane_held
);
    reg [3:0] pb_s1 = 4'hF, pb_s2 = 4'hF, pb_prev = 4'hF;
    always @(posedge clk) begin
        pb_s1   <= PB;
        pb_s2   <= pb_s1;
        pb_prev <= pb_s2;
    end
    wire [3:0] pb_fall = pb_prev & ~pb_s2;

    // KEY3 (leftmost on the board) drives lane 0
    assign lane_press = {pb_fall[0], pb_fall[1], pb_fall[2], pb_fall[3]};
    assign lane_held  = ~{pb_s2[0], pb_s2[1], pb_s2[2], pb_s2[3]};
endmodule


// =============================================================================
// note chart: 256 eighth-note steps (32 bars x 8 steps), one lane mask per step
// steps >= 256 are empty
// =============================================================================
module chart_rom(
    input  [9:0] step,
    output [3:0] mask
);
    reg [3:0]  pat_id;
    reg [31:0] pat;

    always @(*) begin
        // song arrangement: pattern used by each bar
        case (step[7:3])
            5'd0:  pat_id = 4'd0;   // lead-in
            5'd1:  pat_id = 4'd1;
            5'd2:  pat_id = 4'd2;
            5'd3:  pat_id = 4'd3;
            5'd4:  pat_id = 4'd3;   // verse
            5'd5:  pat_id = 4'd4;
            5'd6:  pat_id = 4'd3;
            5'd7:  pat_id = 4'd10;
            5'd8:  pat_id = 4'd7;
            5'd9:  pat_id = 4'd8;
            5'd10: pat_id = 4'd7;
            5'd11: pat_id = 4'd12;
            5'd12: pat_id = 4'd6;   // chorus
            5'd13: pat_id = 4'd9;
            5'd14: pat_id = 4'd6;
            5'd15: pat_id = 4'd11;
            5'd16: pat_id = 4'd5;
            5'd17: pat_id = 4'd5;
            5'd18: pat_id = 4'd12;
            5'd19: pat_id = 4'd4;
            5'd20: pat_id = 4'd13;  // bridge
            5'd21: pat_id = 4'd13;
            5'd22: pat_id = 4'd10;
            5'd23: pat_id = 4'd10;
            5'd24: pat_id = 4'd6;   // final chorus
            5'd25: pat_id = 4'd9;
            5'd26: pat_id = 4'd7;
            5'd27: pat_id = 4'd8;
            5'd28: pat_id = 4'd12;
            5'd29: pat_id = 4'd12;
            5'd30: pat_id = 4'd14;  // ending chord
            default: pat_id = 4'd0;
        endcase

        // bar patterns: one hex digit per step (first step = leftmost digit),
        // bit 0 = lane 0 (green) ... bit 3 = lane 3 (blue)
        case (pat_id)
            4'd1:  pat = 32'h1010_1010;
            4'd2:  pat = 32'h1020_4020;
            4'd3:  pat = 32'h1020_4080;
            4'd4:  pat = 32'h8040_2010;
            4'd5:  pat = 32'h1122_4488;
            4'd6:  pat = 32'h3000_C000;
            4'd7:  pat = 32'h1214_1814;
            4'd8:  pat = 32'h8482_8184;
            4'd9:  pat = 32'h5050_A0A0;
            4'd10: pat = 32'h1240_1240;
            4'd11: pat = 32'h9000_6000;
            4'd12: pat = 32'h1248_8421;
            4'd13: pat = 32'h2424_8181;
            4'd14: pat = 32'h9000_0000;
            default: pat = 32'h0000_0000;
        endcase
    end

    assign mask = (step[9:8] != 2'b00) ? 4'b0000 : pat[28 - 4 * step[2:0] +: 4];
endmodule


// =============================================================================
// game core: FSM, song position, hit detection, score / streak / multiplier
// =============================================================================
module game_core(
    input             clk,
    input             rst,
    input             frame_tick,
    input      [3:0]  lane_press,
    input             pause,         // SW[4] level, synchronized
    input      [1:0]  speed_sel,
    input             no_fail,
    output reg [1:0]  state,
    output reg [15:0] song_px,       // pixels scrolled since the song started
    output reg [8:0]  next_close,    // oldest step whose hit window is still open
    output reg [31:0] hit,           // ring of 8 steps x 4 lanes: note was hit
    output reg [23:0] score_bcd,     // score / 10, six BCD digits
    output reg [11:0] streak_bcd,
    output reg [2:0]  mult,
    output reg [5:0]  meter,         // rock meter 0..63
    output reg        lead_on,       // lead track audible
    output reg        failed,
    output reg [1:0]  judge,
    output reg [5:0]  judge_timer,
    output reg [15:0] press_glow,    // 4 x 4-bit frame timers
    output reg [15:0] hit_glow,
    output reg [11:0] aud_pkt,       // {run, step_trig, step[2:0], chord[1:0], lead[3:0], miss}
    output reg        aud_tgl
);
    localparam S_MENU = 2'd0, S_PLAY = 2'd1, S_PAUSE = 2'd2, S_OVER = 2'd3;
    localparam J_PERFECT = 2'd1, J_GOOD = 2'd2, J_MISS = 2'd3;
    localparam NUM_STEPS = 9'd256;
    localparam [15:0] END_PX = 16'd16640;      // 260 steps x 64 px

    reg [8:0] next_play;       // next step whose audio has not been triggered
    reg [2:0] speed;           // scroll speed in px per frame (3..6)
    reg [3:0] mult_cnt;
    reg [3:0] pend;            // queued lane presses
    reg [7:0] pend_tens;       // score still to be added, in tens
    reg       miss_pend;
    reg       send;
    reg [5:0] hold;            // game-over screen input lockout

    initial begin
        state = S_MENU; song_px = 0; next_close = 0; hit = 0;
        score_bcd = 0; streak_bcd = 0; mult = 3'd1; meter = 6'd40;
        lead_on = 1'b1; failed = 1'b0; judge = 0; judge_timer = 0;
        press_glow = 0; hit_glow = 0; aud_pkt = 0; aud_tgl = 0;
        next_play = 0; speed = 3'd4; mult_cnt = 0; pend = 0; pend_tens = 0;
        miss_pend = 0; send = 0; hold = 0;
    end

    // hit window: +-5 frames, perfect: +-2 frames (in pixels, so it scales with speed)
    wire [4:0] win  = {speed, 2'b00} + speed;
    wire [4:0] perf = {speed, 1'b0};

    // nearest step to the target line and distance from it
    wire [5:0] d6     = song_px[5:0];
    wire       late   = ~d6[5];
    wire [9:0] near   = song_px[15:6] + {9'd0, ~late};
    wire [5:0] adelta = late ? d6 : (6'd0 - d6);
    wire       in_win = (adelta <= win) && (near < 10'd256);

    wire [3:0] m_near, m_close, m_play;
    chart_rom c_near (.step(near),                .mask(m_near));
    chart_rom c_close(.step({1'b0, next_close}),  .mask(m_close));
    chart_rom c_play (.step({1'b0, next_play}),   .mask(m_play));

    wire [3:0] hit_close = hit[{next_close[2:0], 2'b00} +: 4];
    wire [3:0] hit_play  = hit[{next_play[2:0],  2'b00} +: 4];
    wire [2:0] clr_slot  = next_close[2:0] + 3'd4;
    wire [4:0] mult5     = {mult, 2'b00} + mult;

    // lowest queued lane
    reg [1:0] pl;
    always @(*) begin
        casez (pend)
            4'b???1: pl = 2'd0;
            4'b??10: pl = 2'd1;
            4'b?100: pl = 2'd2;
            default: pl = 2'd3;
        endcase
    end

    function [23:0] bcd_inc6;
        input [23:0] v;
        integer k;
        reg c;
        reg [23:0] r;
        begin
            r = v;
            c = 1'b1;
            for (k = 0; k < 6; k = k + 1) begin
                if (c) begin
                    if (r[4*k +: 4] == 4'd9) r[4*k +: 4] = 4'd0;
                    else begin
                        r[4*k +: 4] = r[4*k +: 4] + 4'd1;
                        c = 1'b0;
                    end
                end
            end
            bcd_inc6 = r;
        end
    endfunction

    function [11:0] bcd_inc3;
        input [11:0] v;
        reg [23:0] t;
        begin
            t = bcd_inc6({12'd0, v});
            bcd_inc3 = t[11:0];
        end
    endfunction

    reg       do_hit, do_miss, is_perf, step_trig;
    reg [1:0] ev_lane;
    reg [2:0] meter_dec;
    reg [3:0] pend_n, lead_mask;
    reg [7:0] pt;
    integer i;

    always @(posedge clk) begin
        do_hit    = 1'b0;
        do_miss   = 1'b0;
        is_perf   = 1'b0;
        step_trig = 1'b0;
        ev_lane   = 2'd0;
        meter_dec = 3'd0;
        lead_mask = 4'd0;
        pend_n    = pend | lane_press;
        pt        = pend_tens;

        // audio packet toggle lags the packet by one cycle
        if (send) aud_tgl <= ~aud_tgl;
        send <= 1'b0;

        // add pending score one ten at a time
        if (pt != 0) begin
            pt = pt - 1'b1;
            score_bcd <= bcd_inc6(score_bcd);
        end

        // per-frame timers and silent audio packet (overridden while playing)
        if (frame_tick) begin
            for (i = 0; i < 4; i = i + 1) begin
                if (press_glow[4*i +: 4] != 0) press_glow[4*i +: 4] <= press_glow[4*i +: 4] - 1'b1;
                if (hit_glow[4*i +: 4]   != 0) hit_glow[4*i +: 4]   <= hit_glow[4*i +: 4] - 1'b1;
            end
            if (judge_timer != 0) judge_timer <= judge_timer - 1'b1;
            if (hold != 0) hold <= hold - 1'b1;
            aud_pkt <= 12'd0;
            send    <= 1'b1;
        end
        for (i = 0; i < 4; i = i + 1)
            if (lane_press[i]) press_glow[4*i +: 4] <= 4'd8;

        if (rst) begin
            state      <= S_MENU;
            song_px    <= 16'd0;
            next_close <= 9'd0;
            next_play  <= 9'd0;
            hit        <= 32'd0;
            score_bcd  <= 24'd0;
            streak_bcd <= 12'd0;
            mult       <= 3'd1;
            mult_cnt   <= 4'd0;
            meter      <= 6'd40;
            lead_on    <= 1'b1;
            failed     <= 1'b0;
            miss_pend  <= 1'b0;
            pend_n     = 4'd0;
            pt         = 8'd0;
        end
        else begin
            case (state)
                S_MENU: begin
                    pend_n = 4'd0;
                    if (lane_press != 0) begin                  // new game
                        state      <= S_PLAY;
                        song_px    <= 16'd0;
                        next_close <= 9'd0;
                        next_play  <= 9'd0;
                        hit        <= 32'd0;
                        score_bcd  <= 24'd0;
                        streak_bcd <= 12'd0;
                        mult       <= 3'd1;
                        mult_cnt   <= 4'd0;
                        meter      <= 6'd40;
                        lead_on    <= 1'b1;
                        failed     <= 1'b0;
                        miss_pend  <= 1'b0;
                        speed      <= {1'b0, speed_sel} + 3'd3;
                        pt         = 8'd0;
                    end
                end

                S_PLAY: begin
                    if (frame_tick) begin
                        song_px <= song_px + speed;

                        // close the oldest step once its window has passed; unhit notes are misses
                        if (next_close < NUM_STEPS && song_px > {next_close, 6'd0} + win) begin
                            if ((m_close & ~hit_close) != 4'd0) begin
                                do_miss   = 1'b1;
                                meter_dec = 3'd3;
                            end
                            for (i = 0; i < 8; i = i + 1)
                                if (clr_slot == i) hit[4*i +: 4] <= 4'b0000;
                            next_close <= next_close + 1'b1;
                        end

                        // trigger music for the step reaching the target line
                        if (next_play < NUM_STEPS && song_px >= {next_play, 6'd0}) begin
                            step_trig = 1'b1;
                            lead_mask = m_play & (lead_on ? 4'hF : hit_play);
                            next_play <= next_play + 1'b1;
                        end
                        aud_pkt   <= {1'b1, step_trig, next_play[2:0], next_play[4:3],
                                      lead_mask, miss_pend | do_miss};
                        miss_pend <= 1'b0;

                        if (song_px >= END_PX) begin
                            state <= S_OVER;
                            hold  <= 6'd60;
                        end
                        else if (meter == 0 && !no_fail) begin
                            state  <= S_OVER;
                            failed <= 1'b1;
                            hold   <= 6'd60;
                        end
                    end
                    else if (pause) begin
                        state  <= S_PAUSE;
                        pend_n = 4'd0;
                    end
                    else if (pend != 0) begin
                        // judge one queued lane press per cycle
                        ev_lane = pl;
                        pend_n  = pend_n & ~(4'b0001 << pl);
                        if (in_win && m_near[pl] && !hit[{near[2:0], pl}]) begin
                            do_hit  = 1'b1;
                            is_perf = (adelta <= perf);
                        end
                        else begin                         // strum with no note
                            do_miss   = 1'b1;
                            meter_dec = 3'd2;
                        end
                    end
                end

                S_PAUSE: begin
                    pend_n = 4'd0;
                    if (!pause) state <= S_PLAY;
                end

                S_OVER: begin
                    pend_n = 4'd0;
                    if (hold == 0 && lane_press != 0) begin
                        state      <= S_MENU;
                        song_px    <= 16'd0;
                        next_close <= 9'd0;
                        next_play  <= 9'd0;
                        hit        <= 32'd0;
                    end
                end
            endcase

            if (do_hit) begin
                for (i = 0; i < 32; i = i + 1)
                    if ({near[2:0], ev_lane} == i) hit[i] <= 1'b1;
                for (i = 0; i < 4; i = i + 1)
                    if (ev_lane == i) hit_glow[4*i +: 4] <= 4'd12;
                pt = pt + (is_perf ? {2'b00, mult5, 1'b0} : {3'b000, mult5});   // 100 / 50 pts x mult
                if (streak_bcd != 12'h999) streak_bcd <= bcd_inc3(streak_bcd);
                if (mult != 3'd4) begin
                    if (mult_cnt == 4'd9) begin
                        mult     <= mult + 1'b1;
                        mult_cnt <= 4'd0;
                    end
                    else mult_cnt <= mult_cnt + 1'b1;
                end
                if (meter != 6'd63) meter <= meter + 1'b1;
                lead_on     <= 1'b1;
                judge       <= is_perf ? J_PERFECT : J_GOOD;
                judge_timer <= 6'd30;
            end

            if (do_miss) begin
                streak_bcd  <= 12'd0;
                mult        <= 3'd1;
                mult_cnt    <= 4'd0;
                lead_on     <= 1'b0;
                judge       <= J_MISS;
                judge_timer <= 6'd30;
                meter       <= (meter > meter_dec) ? meter - meter_dec : 6'd0;
                if (!frame_tick) miss_pend <= 1'b1;   // misses on a tick go out in this frame's packet
            end
        end

        pend      <= pend_n;
        pend_tens <= pt;
    end
endmodule


// =============================================================================
// VGA renderer: 3-stage pipeline on the 25 MHz pixel enable
//   stage 1: geometry, stage 2: chart / font lookups, stage 3: colour
// =============================================================================
module renderer(
    input             clk,
    input             en,
    input      [9:0]  hc, vc,
    input             hs_in, vs_in,
    input      [1:0]  state,
    input      [15:0] song_px,
    input      [8:0]  next_close,
    input      [31:0] hit,
    input      [23:0] score_bcd,
    input      [11:0] streak_bcd,
    input      [2:0]  mult,
    input      [5:0]  meter,
    input      [1:0]  judge,
    input             judge_on,
    input             failed,
    input      [3:0]  lane_glow,
    input      [3:0]  lane_held,
    input      [15:0] hit_glow,
    output reg [3:0]  r, g, b,
    output reg        hs, vs
);
    localparam S_MENU = 2'd0, S_PLAY = 2'd1, S_PAUSE = 2'd2, S_OVER = 2'd3;
    localparam TARGET_Y = 420;     // target line; highway lanes are 80 px wide from x = 160

    initial begin
        r = 0; g = 0; b = 0; hs = 1; vs = 1;
    end

    // ---------------- stage 1: geometry ----------------
    reg [9:0] x1, y1;
    reg       act1, hs1, vs1, hw1, neg1;
    reg [1:0] lane1;
    reg [6:0] lx1;          // x inside the lane
    reg [8:0] n1;           // chart step under this pixel
    reg [5:0] off1;         // position inside the step (gem drawn for off < 16)

    // pixel row y shows song position song_px + TARGET_Y - y; +8 centres the gem
    wire [16:0] pos = {1'b0, song_px} + 17'd428 - {7'd0, vc};

    always @(posedge clk) begin
        if (en) begin
            x1   <= hc;
            y1   <= vc;
            act1 <= (hc < 10'd640) && (vc < 10'd480);
            hs1  <= hs_in;
            vs1  <= vs_in;
            hw1  <= (hc >= 10'd160) && (hc < 10'd480);
            if (hc < 10'd240)      begin lane1 <= 2'd0; lx1 <= hc - 10'd160; end
            else if (hc < 10'd320) begin lane1 <= 2'd1; lx1 <= hc - 10'd240; end
            else if (hc < 10'd400) begin lane1 <= 2'd2; lx1 <= hc - 10'd320; end
            else                   begin lane1 <= 2'd3; lx1 <= hc - 10'd400; end
            n1   <= pos[14:6];
            off1 <= pos[5:0];
            neg1 <= pos[16];
        end
    end

    // ---------------- stage 2: lookups ----------------
    wire [3:0] cmask;
    chart_rom chart(.step({1'b0, n1}), .mask(cmask));

    wire [8:0] rel      = n1 - next_close + 9'd4;
    wire       hidden   = (rel < 9'd8) && hit[{n1[2:0], lane1}];
    wire [3:0] hg       = hit_glow[{lane1, 2'b00} +: 4];
    wire [9:0] flame_top = 10'd406 - {4'd0, hg, 2'b00};
    wire [9:0] meter_h  = {2'b00, meter, 2'b00} + {4'd0, meter};

    reg act2, hs2, vs2, hw2, gem2, gem_miss2, gem_hl2, gem_edge2, beat2, bar2;
    reg rail2, div2, target2, fret_out2, fret_in2, pressed2, flame2;
    reg mframe2, minside2, mfill2, dim2;
    reg [1:0] lane2;

    always @(posedge clk) begin
        if (en) begin
            act2      <= act1;
            hs2       <= hs1;
            vs2       <= vs1;
            hw2       <= hw1;
            lane2     <= lane1;
            gem2      <= hw1 && !neg1 && off1 < 6'd16 && lx1 >= 7'd8 && lx1 < 7'd72 &&
                         cmask[lane1] && !hidden && state != S_MENU;
            gem_miss2 <= n1 < next_close;
            gem_hl2   <= off1 >= 6'd13;
            gem_edge2 <= off1 < 6'd2 || lx1 < 7'd10 || lx1 >= 7'd70;
            beat2     <= hw1 && !neg1 && (off1 == 6'd8 || off1 == 6'd9) && !n1[0];
            bar2      <= n1[2:0] == 3'd0;
            rail2     <= (x1 >= 10'd156 && x1 < 10'd160) || (x1 >= 10'd480 && x1 < 10'd484);
            div2      <= hw1 && lx1 == 7'd0;
            target2   <= hw1 && y1 >= TARGET_Y - 2 && y1 < TARGET_Y + 2;
            fret_out2 <= hw1 && y1 >= TARGET_Y - 13 && y1 < TARGET_Y + 14 && lx1 >= 7'd12 && lx1 < 7'd68;
            fret_in2  <= hw1 && y1 >= TARGET_Y - 8  && y1 < TARGET_Y + 9  && lx1 >= 7'd17 && lx1 < 7'd63;
            pressed2  <= lane_held[lane1] | lane_glow[lane1];
            flame2    <= hw1 && hg != 4'd0 && y1 < 10'd406 && y1 >= flame_top && lx1 >= 7'd26 && lx1 < 7'd54;
            mframe2   <= x1 >= 10'd508 && x1 < 10'd548 && y1 >= 10'd68 && y1 < 10'd396;
            minside2  <= x1 >= 10'd512 && x1 < 10'd544 && y1 >= 10'd72 && y1 < 10'd392;
            mfill2    <= y1 >= 10'd392 - meter_h;
            dim2      <= state != S_PLAY && x1 >= 10'd128 && x1 < 10'd512 && y1 >= 10'd110 && y1 < 10'd310;
        end
    end

    // text overlays (2-stage latency, aligned with stage 2)
    wire [55:0] judge_str = (judge == 2'd1) ? "PERFECT" : (judge == 2'd2) ? "  GOOD " : "  MISS ";
    wire [87:0] result_str = failed ? "SONG FAILED" : "SONG CLEAR!";
    wire [55:0] score_str = {4'h3, score_bcd[23:20], 4'h3, score_bcd[19:16], 4'h3, score_bcd[15:12],
                             4'h3, score_bcd[11:8],  4'h3, score_bcd[7:4],   4'h3, score_bcd[3:0], "0"};
    wire [23:0] streak_str = {4'h3, streak_bcd[11:8], 4'h3, streak_bcd[7:4], 4'h3, streak_bcd[3:0]};
    wire [15:0] mult_str   = {"X", 5'b00110, mult};

    wire t_score_l, t_score, t_streak_l, t_streak, t_mult, t_rock;
    wire t_title, t_press, t_keys, t_result, t_pause, t_judge;

    text_box #(.X0(16),  .Y0(40),  .S(1), .LEN(5))  tb0 (clk, en, hc, vc, 1'b1, "SCORE",  t_score_l);
    text_box #(.X0(16),  .Y0(64),  .S(1), .LEN(7))  tb1 (clk, en, hc, vc, 1'b1, score_str, t_score);
    text_box #(.X0(16),  .Y0(110), .S(1), .LEN(6))  tb2 (clk, en, hc, vc, 1'b1, "STREAK", t_streak_l);
    text_box #(.X0(16),  .Y0(134), .S(1), .LEN(3))  tb3 (clk, en, hc, vc, 1'b1, streak_str, t_streak);
    text_box #(.X0(16),  .Y0(176), .S(2), .LEN(2))  tb4 (clk, en, hc, vc, 1'b1, mult_str, t_mult);
    text_box #(.X0(496), .Y0(40),  .S(1), .LEN(4))  tb5 (clk, en, hc, vc, 1'b1, "ROCK",   t_rock);
    text_box #(.X0(176), .Y0(130), .S(2), .LEN(9))  tb6 (clk, en, hc, vc, state == S_MENU, "FRET RUSH", t_title);
    text_box #(.X0(232), .Y0(230), .S(1), .LEN(11)) tb7 (clk, en, hc, vc, state == S_MENU || state == S_OVER,
                                                         "PRESS START", t_press);
    text_box #(.X0(224), .Y0(270), .S(1), .LEN(12)) tb8 (clk, en, hc, vc, state == S_MENU, "KEYS D F J K", t_keys);
    text_box #(.X0(144), .Y0(150), .S(2), .LEN(11)) tb9 (clk, en, hc, vc, state == S_OVER, result_str, t_result);
    text_box #(.X0(224), .Y0(190), .S(2), .LEN(6))  tb10(clk, en, hc, vc, state == S_PAUSE, "PAUSED", t_pause);
    text_box #(.X0(264), .Y0(340), .S(1), .LEN(7))  tb11(clk, en, hc, vc, state == S_PLAY && judge_on,
                                                         judge_str, t_judge);

    // ---------------- stage 3: colour ----------------
    function [11:0] lane_rgb;
        input [1:0] l;
        begin
            case (l)
                2'd0:    lane_rgb = 12'h0F0;   // green
                2'd1:    lane_rgb = 12'hF00;   // red
                2'd2:    lane_rgb = 12'hFF0;   // yellow
                default: lane_rgb = 12'h26F;   // blue
            endcase
        end
    endfunction

    function [11:0] half;
        input [11:0] c;
        half = {1'b0, c[11:9], 1'b0, c[7:5], 1'b0, c[3:1]};
    endfunction

    wire [11:0] lc = lane_rgb(lane2);
    wire [11:0] meter_rgb = (meter < 6'd16) ? 12'hF00 : (meter < 6'd40) ? 12'hFC0 : 12'h0F0;
    wire any_text = t_score_l | t_score | t_streak_l | t_streak | t_mult | t_rock |
                    t_title | t_press | t_keys | t_result | t_pause | t_judge;

    reg [11:0] c;
    always @(*) begin
        if (!act2)                    c = 12'h000;
        else if (t_title)             c = 12'hFC0;
        else if (t_result)            c = failed ? 12'hF22 : 12'h2F4;
        else if (t_press | t_pause)   c = 12'hFFF;
        else if (t_keys)              c = 12'hAAA;
        else if (t_judge)             c = (judge == 2'd1) ? 12'h0FF : (judge == 2'd2) ? 12'h4F4 : 12'hF22;
        else if (t_score_l | t_streak_l | t_rock) c = 12'h99A;
        else if (t_score | t_streak)  c = 12'hFFF;
        else if (t_mult)              c = 12'hFC0;
        else if (flame2)              c = 12'hFF8;
        else if (gem2)                c = gem_miss2 ? (gem_edge2 ? 12'h333 : 12'h555)
                                        : gem_hl2   ? (lc | 12'h888)
                                        : gem_edge2 ? half(lc) : lc;
        else if (fret_out2 && !fret_in2) c = pressed2 ? lc : half(lc);
        else if (fret_in2)            c = pressed2 ? half(lc) : 12'h111;
        else if (target2)             c = 12'hCCC;
        else if (rail2)               c = 12'h888;
        else if (div2)                c = 12'h333;
        else if (beat2)               c = bar2 ? 12'h556 : 12'h334;
        else if (hw2)                 c = 12'h112;
        else if (minside2)            c = mfill2 ? meter_rgb : 12'h111;
        else if (mframe2)             c = 12'h666;
        else                          c = 12'h000;

        // darken the area behind menu / pause / results text
        if (dim2 && !any_text) c = {2'b00, c[11:10], 2'b00, c[7:6], 2'b00, c[3:2]};
    end

    always @(posedge clk) begin
        if (en) begin
            {r, g, b} <= c;
            hs <= hs2;
            vs <= vs2;
        end
    end
endmodule


// =============================================================================
// one line of text: 5x7 glyphs in 8x8 cells scaled by 2^S, 2-cycle latency
// str holds ASCII, leftmost character in the top byte
// =============================================================================
module text_box #(
    parameter X0 = 0, Y0 = 0, S = 1, LEN = 1
)(
    input              clk,
    input              en,
    input  [9:0]       x, y,
    input              show,
    input  [8*LEN-1:0] str,
    output reg         pix
);
    localparam CELL = 8 << S;

    wire [9:0] rx = x - X0;
    wire [9:0] ry = y - Y0;
    wire in_box = (x >= X0) && (x < X0 + LEN * CELL) && (y >= Y0) && (y < Y0 + CELL);
    wire [9:0] idx = rx >> (3 + S);
    wire [8*LEN-1:0] shifted = str << (8 * idx);

    reg       in_a = 1'b0;
    reg [7:0] ch_a = 8'd32;
    reg [2:0] col_a = 3'd0, row_a = 3'd0;
    wire [4:0] bits;
    font_rom font(.ch(ch_a), .row(row_a), .bits(bits));

    initial pix = 1'b0;

    always @(posedge clk) begin
        if (en) begin
            in_a  <= show && in_box;
            ch_a  <= shifted[8*LEN-1 -: 8];
            col_a <= rx[S+2:S];
            row_a <= ry[S+2:S];
            pix   <= in_a && (col_a < 3'd5) && bits[3'd4 - col_a];
        end
    end
endmodule


// =============================================================================
// 5x7 font: digits, A-Z, space, '!'
// =============================================================================
module font_rom(
    input  [7:0] ch,
    input  [2:0] row,
    output [4:0] bits
);
    reg [34:0] gl;
    always @(*) begin
        case (ch)
            "0": gl = 35'b01110_10001_10011_10101_11001_10001_01110;
            "1": gl = 35'b00100_01100_00100_00100_00100_00100_01110;
            "2": gl = 35'b01110_10001_00001_00010_00100_01000_11111;
            "3": gl = 35'b11111_00010_00100_00010_00001_10001_01110;
            "4": gl = 35'b00010_00110_01010_10010_11111_00010_00010;
            "5": gl = 35'b11111_10000_11110_00001_00001_10001_01110;
            "6": gl = 35'b00110_01000_10000_11110_10001_10001_01110;
            "7": gl = 35'b11111_00001_00010_00100_01000_01000_01000;
            "8": gl = 35'b01110_10001_10001_01110_10001_10001_01110;
            "9": gl = 35'b01110_10001_10001_01111_00001_00010_01100;
            "A": gl = 35'b01110_10001_10001_11111_10001_10001_10001;
            "B": gl = 35'b11110_10001_10001_11110_10001_10001_11110;
            "C": gl = 35'b01110_10001_10000_10000_10000_10001_01110;
            "D": gl = 35'b11100_10010_10001_10001_10001_10010_11100;
            "E": gl = 35'b11111_10000_10000_11110_10000_10000_11111;
            "F": gl = 35'b11111_10000_10000_11110_10000_10000_10000;
            "G": gl = 35'b01110_10001_10000_10111_10001_10001_01111;
            "H": gl = 35'b10001_10001_10001_11111_10001_10001_10001;
            "I": gl = 35'b01110_00100_00100_00100_00100_00100_01110;
            "J": gl = 35'b00111_00010_00010_00010_00010_10010_01100;
            "K": gl = 35'b10001_10010_10100_11000_10100_10010_10001;
            "L": gl = 35'b10000_10000_10000_10000_10000_10000_11111;
            "M": gl = 35'b10001_11011_10101_10101_10001_10001_10001;
            "N": gl = 35'b10001_10001_11001_10101_10011_10001_10001;
            "O": gl = 35'b01110_10001_10001_10001_10001_10001_01110;
            "P": gl = 35'b11110_10001_10001_11110_10000_10000_10000;
            "Q": gl = 35'b01110_10001_10001_10001_10101_10010_01101;
            "R": gl = 35'b11110_10001_10001_11110_10100_10010_10001;
            "S": gl = 35'b01111_10000_10000_01110_00001_00001_11110;
            "T": gl = 35'b11111_00100_00100_00100_00100_00100_00100;
            "U": gl = 35'b10001_10001_10001_10001_10001_10001_01110;
            "V": gl = 35'b10001_10001_10001_10001_10001_01010_00100;
            "W": gl = 35'b10001_10001_10001_10101_10101_10101_01010;
            "X": gl = 35'b10001_10001_01010_00100_01010_10001_10001;
            "Y": gl = 35'b10001_10001_01010_00100_00100_00100_00100;
            "Z": gl = 35'b11111_00001_00010_00100_01000_10000_11111;
            "!": gl = 35'b00100_00100_00100_00100_00100_00000_00100;
            default: gl = 35'd0;
        endcase
    end
    assign bits = (row == 3'd7) ? 5'd0 : gl[34 - 5 * row -: 5];
endmodule


// =============================================================================
// audio engine (24 MHz): synth voices + left-justified 16-bit serial output
//   MCLK 12 MHz, BCLK 2.4 MHz, LRCK 48 kHz (codec in USB mode, 250 fs)
// =============================================================================
module audio_engine(
    input        clk,          // CLOCK_24
    input [11:0] pkt,          // from the 50 MHz domain, stable around pkt_tgl edges
    input        pkt_tgl,
    output reg   xck,
    output reg   bclk,
    output reg   lrck,
    output reg   dacdat
);
    initial begin
        xck = 0; bclk = 0; lrck = 0; dacdat = 0;
    end

    // ---------------- clock domain crossing ----------------
    reg [2:0]  tg = 3'b000;
    reg [11:0] p = 12'd0;
    reg        evt = 1'b0;
    always @(posedge clk) begin
        tg  <= {tg[1:0], pkt_tgl};
        evt <= tg[2] ^ tg[1];
        if (tg[2] ^ tg[1]) p <= pkt;
    end
    wire       p_run   = p[11];
    wire       p_step  = p[10];
    wire [2:0] p_pos   = p[9:7];     // step inside the bar
    wire [1:0] p_chord = p[6:5];     // C, G, Am, F
    wire [3:0] p_lead  = p[4:1];
    wire       p_miss  = p[0];

    // ---------------- serial interface ----------------
    reg [3:0]  ph = 4'd0;            // 10 clocks per BCLK
    reg [5:0]  bitn = 6'd0;          // 50 BCLKs per sample frame
    reg [15:0] out_sample = 16'd0;
    wire       sample_en = (ph == 4'd9) && (bitn == 6'd49);
    wire [5:0] k = (bitn < 6'd25) ? bitn : bitn - 6'd25;

    always @(posedge clk) begin
        xck <= ~xck;
        if (ph == 4'd9) begin
            ph   <= 4'd0;
            bitn <= (bitn == 6'd49) ? 6'd0 : bitn + 1'b1;
        end
        else ph <= ph + 1'b1;

        bclk   <= (ph >= 4'd5);                          // data changes while BCLK is low
        lrck   <= (bitn < 6'd25);                        // high = left
        dacdat <= (k < 6'd16) ? out_sample[4'd15 - k[3:0]] : 1'b0;
    end

    // ---------------- synth ----------------
    function [19:0] lead_inc;        // phase increments for 2^24 / 48 kHz
        input [1:0] chord;
        input [1:0] lane;
        begin
            case ({chord, lane})
                4'h0: lead_inc = 20'd182890;   // C5
                4'h1: lead_inc = 20'd230426;   // E5
                4'h2: lead_inc = 20'd274025;   // G5
                4'h3: lead_inc = 20'd365779;   // C6
                4'h4: lead_inc = 20'd137012;   // G4
                4'h5: lead_inc = 20'd172625;   // B4
                4'h6: lead_inc = 20'd205287;   // D5
                4'h7: lead_inc = 20'd274025;   // G5
                4'h8: lead_inc = 20'd153791;   // A4
                4'h9: lead_inc = 20'd182890;   // C5
                4'hA: lead_inc = 20'd230426;   // E5
                4'hB: lead_inc = 20'd307582;   // A5
                4'hC: lead_inc = 20'd122064;   // F4
                4'hD: lead_inc = 20'd153791;   // A4
                4'hE: lead_inc = 20'd182890;   // C5
                default: lead_inc = 20'd244128; // F5
            endcase
        end
    endfunction

    function [19:0] bass_inc;
        input [1:0] chord;
        begin
            case (chord)
                2'd0:    bass_inc = 20'd45722;  // C3
                2'd1:    bass_inc = 20'd34253;  // G2
                2'd2:    bass_inc = 20'd38448;  // A2
                default: bass_inc = 20'd30516;  // F2
            endcase
        end
    endfunction

    reg [23:0] lph [0:3];
    reg [19:0] linc [0:3];
    reg [15:0] lamp [0:3];
    reg [23:0] bph = 0, kph = 0, zph = 0;
    reg [19:0] binc = 0;
    reg [15:0] bamp = 0, kamp = 0, samp = 0, hamp = 0, zamp = 0;
    reg [15:0] lfsr = 16'hACE1;
    reg [6:0]  env_div = 0;
    reg        running = 0;
    integer i;

    initial begin
        for (i = 0; i < 4; i = i + 1) begin
            lph[i]  = 24'd0;
            linc[i] = 20'd0;
            lamp[i] = 16'd0;
        end
    end

    always @(posedge clk) begin
        if (sample_en) begin
            env_div <= env_div + 1'b1;
            lfsr    <= {lfsr[14:0], lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10]};
            for (i = 0; i < 4; i = i + 1) lph[i] <= lph[i] + linc[i];
            bph <= bph + binc;
            kph <= kph + 24'd19224 + {kamp[15:8], 7'd0} + {kamp[15:8], 4'd0};   // 55..160 Hz sweep
            zph <= zph + 24'd28803;                                             // 82 Hz buzz
            if (env_div == 0) begin                                              // every 128 samples
                for (i = 0; i < 4; i = i + 1) lamp[i] <= lamp[i] - (lamp[i] >> 6);
                bamp <= bamp - (bamp >> 6);
                kamp <= kamp - (kamp >> 4);
                samp <= samp - (samp >> 4);
                hamp <= hamp - (hamp >> 3);
                zamp <= zamp - (zamp >> 5);
            end
        end

        if (!running) begin
            for (i = 0; i < 4; i = i + 1) lamp[i] <= 16'd0;
            bamp <= 0; kamp <= 0; samp <= 0; hamp <= 0; zamp <= 0;
        end

        if (evt) begin
            running <= p_run;
            if (p_run && p_step) begin
                bamp <= 16'hFFFF;
                binc <= bass_inc(p_chord);
                hamp <= p_pos[0] ? 16'h6000 : 16'hA000;
                if (p_pos[1:0] == 2'd0) kamp <= 16'hFFFF;     // kick on beats 1 and 3
                if (p_pos[1:0] == 2'd2) samp <= 16'hFFFF;     // snare on beats 2 and 4
                for (i = 0; i < 4; i = i + 1) begin
                    if (p_lead[i]) begin
                        lamp[i] <= 16'hFFFF;
                        linc[i] <= lead_inc(p_chord, i[1:0]);
                    end
                end
            end
            if (p_run && p_miss) zamp <= 16'hFFFF;
        end
    end

    // ---------------- mixer ----------------
    function signed [16:0] vmul;     // signed 8-bit wave x 8-bit amplitude
        input [7:0] w;
        input [7:0] a;
        vmul = $signed(w) * $signed({1'b0, a});
    endfunction

    function [7:0] tri_wave;          // triangle, offset binary -> signed
        input [23:0] phs;
        reg [7:0] t;
        begin
            t = phs[23] ? ~phs[22:15] : phs[22:15];
            tri_wave = {~t[7], t[6:0]};
        end
    endfunction

    wire signed [16:0] v_l0 = vmul({~lph[0][23], lph[0][22:16]}, lamp[0][15:8]);   // sawtooth leads
    wire signed [16:0] v_l1 = vmul({~lph[1][23], lph[1][22:16]}, lamp[1][15:8]);
    wire signed [16:0] v_l2 = vmul({~lph[2][23], lph[2][22:16]}, lamp[2][15:8]);
    wire signed [16:0] v_l3 = vmul({~lph[3][23], lph[3][22:16]}, lamp[3][15:8]);
    wire signed [16:0] v_b  = vmul(tri_wave(bph), bamp[15:8]);
    wire signed [16:0] v_k  = vmul(tri_wave(kph), kamp[15:8]);
    wire signed [16:0] v_s  = vmul(lfsr[7:0], samp[15:8]);
    wire signed [16:0] v_h  = vmul(lfsr[15:8], hamp[15:8]);
    wire signed [16:0] v_z  = vmul(zph[23] ? 8'd100 : 8'd156, zamp[15:8]);           // +-100 square

    wire signed [19:0] mix = ((v_l0 >>> 1) + (v_l1 >>> 1) + (v_l2 >>> 1) + (v_l3 >>> 1) +
                              (v_b >>> 2) + (v_k >>> 1) + (v_s >>> 2) + (v_h >>> 3) +
                              (v_z >>> 1)) >>> 1;

    always @(posedge clk) begin
        if (sample_en) begin
            if (mix > 20'sd32767)       out_sample <= 16'h7FFF;
            else if (mix < -20'sd32768) out_sample <= 16'h8000;
            else                        out_sample <= mix[15:0];
        end
    end
endmodule


// =============================================================================
// WM8731 setup over I2C (write-only, ~50 kHz SCL), runs once after power-up
// =============================================================================
module wm8731_config(
    input      clk,
    output reg scl,
    inout      sda,
    output reg done
);
    localparam W_WAIT = 3'd0, W_START = 3'd1, W_BITS = 3'd2, W_STOP = 3'd3, W_DONE = 3'd4;
    localparam LAST = 4'd8;

    function [15:0] cfg_word;            // {register[6:0], data[8:0]}
        input [3:0] n;
        begin
            case (n)
                4'd0:    cfg_word = 16'h1E00;   // R15 reset
                4'd1:    cfg_word = 16'h0180;   // R0  line in muted (both channels)
                4'd2:    cfg_word = 16'h0579;   // R2  headphone 0 dB (both channels)
                4'd3:    cfg_word = 16'h0812;   // R4  DAC to output, mic muted
                4'd4:    cfg_word = 16'h0A00;   // R5  DAC soft mute off
                4'd5:    cfg_word = 16'h0C07;   // R6  power down line in, mic, ADC
                4'd6:    cfg_word = 16'h0E01;   // R7  slave, 16-bit, left justified
                4'd7:    cfg_word = 16'h1001;   // R8  USB mode, 12 MHz MCLK, 48 kHz
                default: cfg_word = 16'h1201;   // R9  activate
            endcase
        end
    endfunction

    reg [2:0]  st = W_WAIT;
    reg [21:0] delay = 22'd0;           // ~84 ms power-up wait
    reg [7:0]  qdiv = 8'd0;
    reg [1:0]  q = 2'd0;
    reg [4:0]  bitn = 5'd0;
    reg [3:0]  widx = 4'd0;
    reg [26:0] frame = 27'd0;
    reg        sda_o = 1'b1;

    initial begin
        scl  = 1'b1;
        done = 1'b0;
    end

    assign sda = sda_o ? 1'bz : 1'b0;

    wire [15:0] w     = cfg_word(widx);
    wire        qtick = (qdiv == 8'd249);   // quarter of an SCL period

    always @(posedge clk) begin
        qdiv <= qtick ? 8'd0 : qdiv + 1'b1;
        case (st)
            W_WAIT: begin
                delay <= delay + 1'b1;
                if (&delay) begin
                    st <= W_START;
                    q  <= 2'd0;
                end
            end
            W_DONE: done <= 1'b1;
            default: if (qtick) begin
                q <= q + 1'b1;
                case (st)
                    W_START: case (q)
                        2'd0: begin
                            sda_o <= 1'b1;
                            scl   <= 1'b1;
                            frame <= {8'h34, 1'b1, w[15:8], 1'b1, w[7:0], 1'b1};   // 1 = release for ACK
                        end
                        2'd1: sda_o <= 1'b0;                                       // START
                        2'd2: scl   <= 1'b0;
                        2'd3: begin
                            st   <= W_BITS;
                            bitn <= 5'd26;
                        end
                    endcase
                    W_BITS: case (q)
                        2'd0: sda_o <= frame[bitn];
                        2'd1: scl   <= 1'b1;
                        2'd2: ;
                        2'd3: begin
                            scl <= 1'b0;
                            if (bitn == 5'd0) st <= W_STOP;
                            else bitn <= bitn - 1'b1;
                        end
                    endcase
                    W_STOP: case (q)
                        2'd0: sda_o <= 1'b0;
                        2'd1: scl   <= 1'b1;
                        2'd2: sda_o <= 1'b1;                                       // STOP
                        2'd3: begin
                            if (widx == LAST) st <= W_DONE;
                            else begin
                                widx <= widx + 1'b1;
                                st   <= W_START;
                            end
                        end
                    endcase
                    default: ;
                endcase
            end
        endcase
    end
endmodule
