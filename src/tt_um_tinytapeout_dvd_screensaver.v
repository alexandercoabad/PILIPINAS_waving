/*
 * Combined: DVD Bouncing Flag Screensaver + PILIPINAS 7-Segment Display
 * SPDX-License-Identifier: Apache-2.0
 * Developed by Alexander Co Abad
 *
 * GF180 timing fixes (all passes):
 *  1. Sine LUT output registered (breaks wave‚ÜíROM‚Üíflag comb path)
 *  2. wave_index pre-registered before feeding the sine case block
 *  3. ry_raw * 5 replaced with shift-add (no multiplier cell)
 *  4. digit_select * CELL replaced with case lookup table
 *  5. seg_counter moved off vsync clock; edge-detect on main clk
 *  6. Full 2-stage pixel pipeline for 7-segment geometry:
 *       Stage 1 (comb): digit_select ‚Üí xo ‚Üí rx_raw/ry_raw ‚Üí rx/ry/slot_led
 *       Stage 1‚Üí2 (reg): rx_r, ry_r, slot_led_r, display_window_r + sync delay
 *       Stage 2 (comb): j_* ‚Üí seg_* ‚Üí text_pixel ‚Üí uo_out
 *     This cuts the deepest path in half and resolves MaxSlew/MaxCap on
 *     tt_025C_3v30 and ss_125C_3v00 corners.
 *  7. flag_r/g/b registered at Stage-1 boundary to match pipeline depth.
 *  8. hsync/vsync/video_active delayed 1 cycle to stay aligned with
 *     the registered pixel data.
 */

`default_nettype none

parameter LOGO_WIDTH     = 128;
parameter LOGO_HEIGHT    = 64;
parameter DISPLAY_WIDTH  = 640;
parameter DISPLAY_HEIGHT = 480;

module tt_um_combined (
    input  wire [7:0] ui_in,
    output wire [7:0] uo_out,
    input  wire [7:0] uio_in,
    output wire [7:0] uio_out,
    output wire [7:0] uio_oe,
    input  wire       ena,
    input  wire       clk,
    input  wire       rst_n
);

    // -------------------------------------------------------
    // VGA Sync Generator (shared)
    // -------------------------------------------------------
    wire hsync_raw;
    wire vsync_raw;
    wire video_active_raw;
    wire [9:0] pix_x;
    wire [9:0] pix_y;

    vga_sync_generator vga_sync_gen (
        .clk(clk),
        .reset(~rst_n),
        .hsync(hsync_raw),
        .vsync(vsync_raw),
        .display_on(video_active_raw),
        .hpos(pix_x),
        .vpos(pix_y)
    );

    // -------------------------------------------------------
    // FIX 8: Delay sync signals 1 cycle to match pipeline stage
    // -------------------------------------------------------
    reg hsync_d, vsync_d, video_active_d;
    always @(posedge clk) begin
        hsync_d        <= hsync_raw;
        vsync_d        <= vsync_raw;
        video_active_d <= video_active_raw;
    end

    // -------------------------------------------------------
    // DVD BOUNCING FLAG LOGIC WITH TRUE S-CURVE EDGES
    // -------------------------------------------------------
    wire [9:0] logo_x = pix_x - logo_left;

    wire signed [11:0] current_y   = $signed({2'b0, pix_y});
    wire signed [11:0] current_top = $signed({2'b0, logo_top});
    wire signed [11:0] logo_y      = current_y - current_top;

    // -------------------------------------------------------
    // FIX 1 & 2: Pre-register wave_index; register sine LUT output
    // Breaks: wave_index ‚Üí 64-case comb ‚Üí extended_sine ‚Üí true_wave_y
    //         ‚Üí safe_rom_y ‚Üí pixel_color ‚Üí flag_rgb ‚Üí uo_out
    // -------------------------------------------------------
    reg [5:0] wave_timer;

    reg [5:0] wave_index_reg;
    always @(posedge clk)
        wave_index_reg <= logo_x[6:1] + wave_timer;

    reg signed [11:0] extended_sine;
    always @(posedge clk) begin
        case (wave_index_reg[5:0])
            // Positive Half-Cycle (Crest)
            6'd0,  6'd32: extended_sine <=  12'sd0;
            6'd1,  6'd31: extended_sine <=  12'sd1;
            6'd2,  6'd30: extended_sine <=  12'sd1;
            6'd3,  6'd29: extended_sine <=  12'sd2;
            6'd4,  6'd28: extended_sine <=  12'sd3;
            6'd5,  6'd27: extended_sine <=  12'sd3;
            6'd6,  6'd26: extended_sine <=  12'sd4;
            6'd7,  6'd25: extended_sine <=  12'sd4;
            6'd8,  6'd24: extended_sine <=  12'sd5;
            6'd9,  6'd23: extended_sine <=  12'sd5;
            6'd10, 6'd22: extended_sine <=  12'sd6;
            6'd11, 6'd21: extended_sine <=  12'sd6;
            6'd12, 6'd20: extended_sine <=  12'sd6;
            6'd13, 6'd19: extended_sine <=  12'sd7;
            6'd14, 6'd18: extended_sine <=  12'sd7;
            6'd15, 6'd17: extended_sine <=  12'sd7;
            6'd16:        extended_sine <=  12'sd7;
            // Negative Half-Cycle (Trough)
            6'd33, 6'd63: extended_sine <= -12'sd1;
            6'd34, 6'd62: extended_sine <= -12'sd1;
            6'd35, 6'd61: extended_sine <= -12'sd2;
            6'd36, 6'd60: extended_sine <= -12'sd3;
            6'd37, 6'd59: extended_sine <= -12'sd3;
            6'd38, 6'd58: extended_sine <= -12'sd4;
            6'd39, 6'd57: extended_sine <= -12'sd4;
            6'd40, 6'd56: extended_sine <= -12'sd5;
            6'd41, 6'd55: extended_sine <= -12'sd5;
            6'd42, 6'd54: extended_sine <= -12'sd6;
            6'd43, 6'd53: extended_sine <= -12'sd6;
            6'd44, 6'd52: extended_sine <= -12'sd6;
            6'd45, 6'd51: extended_sine <= -12'sd7;
            6'd46, 6'd50: extended_sine <= -12'sd7;
            6'd47, 6'd49: extended_sine <= -12'sd7;
            6'd48:        extended_sine <= -12'sd7;
            default:      extended_sine <=  12'sd0;
        endcase
    end

    wire signed [11:0] true_wave_y = logo_y - extended_sine;

    wire [5:0] safe_rom_y = (true_wave_y < 0)  ? 6'd0  :
                            (true_wave_y >= 64) ? 6'd63 :
                             true_wave_y[5:0];

    wire logo_region = (pix_x >= logo_left) && (pix_x < logo_left + LOGO_WIDTH) &&
                       (true_wave_y >= 0)   && (true_wave_y < 64) &&
                       (logo_y >= -16)      && (logo_y < 80);

    wire [1:0] pixel_color;
    bitmap_rom rom1 (
        .x(logo_x[6:0]),
        .y(safe_rom_y),
        .pixel_color(pixel_color)
    );

    // FIX 7: Register flag RGB to match pipeline stage boundary
    reg flag_r, flag_g, flag_b;
    always @(posedge clk) begin
        if (!video_active_raw || !logo_region) begin
            flag_r <= 0; flag_g <= 0; flag_b <= 0;
        end else begin
            case (pixel_color)
                2'b01: begin flag_r <= 1; flag_g <= 1; flag_b <= 1; end   // White
                2'b10: begin                                               // Blue/Red
                    if (safe_rom_y < 32) begin
                        flag_r <= 0; flag_g <= 0; flag_b <= 1;
                    end else begin
                        flag_r <= 1; flag_g <= 0; flag_b <= 0;
                    end
                end
                2'b11: begin flag_r <= 1; flag_g <= 1; flag_b <= 0; end   // Gold
                default: begin flag_r <= 0; flag_g <= 0; flag_b <= 0; end
            endcase
        end
    end

    // Bouncing position state
    reg [9:0] logo_left, logo_top;
    reg       dir_x, dir_y;
    reg [9:0] prev_y;

    always @(posedge clk) begin
        if (~rst_n) begin
            logo_left  <= 200;
            logo_top   <= 100;
            dir_x      <= 1;
            dir_y      <= 0;
            wave_timer <= 0;
            prev_y     <= 0;
        end else begin
            prev_y <= pix_y;
            if (pix_y == 0 && prev_y != pix_y) begin
                wave_timer <= wave_timer + 1;

                logo_left <= logo_left + (dir_x ? 1 : -1);
                logo_top  <= logo_top  + (dir_y ? 1 : -1);

                if (logo_left <= 1 && !dir_x)
                    dir_x <= 1;
                if (logo_left >= (DISPLAY_WIDTH - LOGO_WIDTH - 1) && dir_x)
                    dir_x <= 0;

                if (logo_top <= 12 && !dir_y)
                    dir_y <= 1;
                if (logo_top >= (390 - LOGO_HEIGHT - 12) && dir_y)
                    dir_y <= 0;
            end
        end
    end

    // -------------------------------------------------------
    // PILIPINAS 7-SEGMENT TEXT LOGIC
    // -------------------------------------------------------

    // FIX 5: seg_counter on main clock with vsync rising-edge detect
    reg [11:0] seg_counter;
    reg        vsync_prev;

    always @(posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            vsync_prev  <= 0;
            seg_counter <= 0;
        end else begin
            vsync_prev <= vsync_raw;
            if (vsync_raw && !vsync_prev)
                seg_counter <= seg_counter + 1;
        end
    end

    wire [3:0] current_stage  = seg_counter[6:3];
    wire       show_full_word = (current_stage >= 4'd9);

    reg [7:0] countdown [8:0];
    initial begin
        countdown[0] = 8'b01110011; // P
        countdown[1] = 8'b00000110; // I
        countdown[2] = 8'b00111000; // L
        countdown[3] = 8'b00000110; // I
        countdown[4] = 8'b01110011; // P
        countdown[5] = 8'b00000110; // I
        countdown[6] = 8'b00110111; // N
        countdown[7] = 8'b01110111; // A
        countdown[8] = 8'b01101101; // S
    end

    // -------------------------------------------------------
    // 7-SEGMENT GEOMETRY ‚Äî FIX 6: 2-Stage Pipeline
    // -------------------------------------------------------
    localparam TEXT_Y0 = 10'd390;
    localparam TEXT_Y1 = 10'd480;
    localparam CELL    = 10'd70;
    localparam MARGIN  = 10'd5;

    // ---------- STAGE 1 (combinational) ----------
    wire in_y_range_s1     = (pix_y >= TEXT_Y0) && (pix_y < TEXT_Y1);
    wire in_x_range_s1     = (pix_x >= MARGIN)  && (pix_x < MARGIN + 9*CELL);
    wire display_window_s1 = in_x_range_s1 && in_y_range_s1;

    wire [3:0] digit_select_s1 =
        (pix_x < MARGIN +   CELL) ? 4'd0 :
        (pix_x < MARGIN + 2*CELL) ? 4'd1 :
        (pix_x < MARGIN + 3*CELL) ? 4'd2 :
        (pix_x < MARGIN + 4*CELL) ? 4'd3 :
        (pix_x < MARGIN + 5*CELL) ? 4'd4 :
        (pix_x < MARGIN + 6*CELL) ? 4'd5 :
        (pix_x < MARGIN + 7*CELL) ? 4'd6 :
        (pix_x < MARGIN + 8*CELL) ? 4'd7 : 4'd8;

    // FIX 4: case lookup instead of multiplier
    reg [9:0] xo_s1;
    always @(*) begin
        case (digit_select_s1)
            4'd0:    xo_s1 = MARGIN + 10'd0;
            4'd1:    xo_s1 = MARGIN + 10'd70;
            4'd2:    xo_s1 = MARGIN + 10'd140;
            4'd3:    xo_s1 = MARGIN + 10'd210;
            4'd4:    xo_s1 = MARGIN + 10'd280;
            4'd5:    xo_s1 = MARGIN + 10'd350;
            4'd6:    xo_s1 = MARGIN + 10'd420;
            4'd7:    xo_s1 = MARGIN + 10'd490;
            default: xo_s1 = MARGIN + 10'd560;
        endcase
    end

    wire [9:0]  rx_raw_s1 = pix_x - xo_s1;
    wire [9:0]  ry_raw_s1 = pix_y - TEXT_Y0;

    // Scaled coordinates (combinational, stage 1)
    wire [11:0] rx_s1 = (rx_raw_s1 << 2) + (rx_raw_s1 >> 1) + (rx_raw_s1 >> 4) + 191;
    // FIX 3: shift-add for *5 (ry_raw*5 = ry_raw<<2 + ry_raw)
    wire [11:0] ry_s1 = (ry_raw_s1 << 2) + ry_raw_s1 + (ry_raw_s1 >> 2) + (ry_raw_s1 >> 4) + 7;

    wire [7:0] slot_led_s1 = show_full_word
                             ? countdown[digit_select_s1]
                             : (current_stage == digit_select_s1)
                               ? countdown[current_stage]
                               : 8'b00000000;

    // ---------- Stage 1‚Üí2 pipeline registers ----------
    reg [11:0] rx_r, ry_r;
    reg [7:0]  slot_led_r;
    reg        display_window_r;

    always @(posedge clk) begin
        rx_r             <= rx_s1;
        ry_r             <= ry_s1;
        slot_led_r       <= slot_led_s1;
        display_window_r <= display_window_s1;
    end

    // ---------- STAGE 2 (combinational, short paths only) ----------
    localparam GAP = 12;

    wire j_a1 = rx_r < ry_r + 392 - GAP;
    wire j_a4 = rx_r > ry_r + 185 + GAP;
    wire j_a5 = rx_r > 247 - ry_r + GAP;
    wire j_a2 = 454 - rx_r > ry_r + GAP;
    wire j_b2 = 662 - rx_r > ry_r + GAP;
    wire j_b5 = 455 - rx_r < ry_r - GAP;
    wire j_c0 = rx_r < ry_r + 184 - GAP;
    wire j_c3 = rx_r + 23 > ry_r + GAP;
    wire j_c2 = 872 - rx_r > ry_r + GAP;
    wire j_c5 = 663 - rx_r < ry_r - GAP;
    wire j_d1 = ry_r > rx_r + 24 + GAP;

    wire seg_a = (ry_r > 3)   & j_a1 & j_a2 & (ry_r < 62)  & j_a4 & j_a5;
    wire seg_b = j_a1 & (rx_r < 448) & j_b2 & j_a4 & (rx_r > 399) & j_b5;
    wire seg_c = j_c0 & (rx_r < 448) & j_c2 & j_c3 & (rx_r > 399) & j_c5;
    wire seg_d = (ry_r > 418) & j_d1 & j_c2 & (ry_r < 477) & (rx_r > ry_r - 232) & j_c5;
    wire seg_e = j_d1 & (rx_r < 240) & j_b2 & (rx_r > ry_r - 232) & (rx_r > 191) & j_b5;
    wire seg_f = j_c0 & (rx_r < 240) & j_a2 & j_c3 & (rx_r > 191) & j_a5;
    wire seg_g = (ry_r > 210) & j_c0 & j_b2 & (ry_r < 267) & j_c3 & j_b5;

    wire text_pixel = display_window_r &&
                      ((seg_a & slot_led_r[0]) | (seg_b & slot_led_r[1]) |
                       (seg_c & slot_led_r[2]) | (seg_d & slot_led_r[3]) |
                       (seg_e & slot_led_r[4]) | (seg_f & slot_led_r[5]) |
                       (seg_g & slot_led_r[6]));

    // -------------------------------------------------------
    // PIXEL COMPOSITOR
    // Uses 1-cycle-delayed sync signals to match pipeline depth
    // -------------------------------------------------------
    wire [5:0] green = 6'b001100;

    wire r_out = text_pixel ? 1'b0     : flag_r;
    wire g_out = text_pixel ? green[3] : flag_g;
    wire b_out = text_pixel ? 1'b0     : flag_b;

    assign uo_out  = {hsync_d, b_out, g_out, r_out, vsync_d, b_out, g_out, r_out};
    assign uio_out = 8'b00000000;
    assign uio_oe  = 8'b00000000;

    wire _unused_ok = &{ena, ui_in, uio_in};

endmodule

