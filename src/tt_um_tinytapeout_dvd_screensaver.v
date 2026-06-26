/*
 * Combined: DVD Bouncing Flag Screensaver + PILIPINAS 7-Segment Display
 * SPDX-License-Identifier: Apache-2.0
 * Developed by Alexander Co Abad
 */

`default_nettype none

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

    parameter LOGO_WIDTH    = 128;
    parameter LOGO_HEIGHT   = 64;
    parameter DISPLAY_WIDTH  = 640;
    parameter DISPLAY_HEIGHT = 480;

    // -------------------------------------------------------
    // VGA Sync Generator (shared)
    // -------------------------------------------------------
    wire hsync;
    wire vsync;
    wire video_active;
    wire [9:0] pix_x;
    wire [9:0] pix_y;

    vga_sync_generator vga_sync_gen (
        .clk(clk),
        .reset(~rst_n),
        .hsync(hsync),
        .vsync(vsync),
        .display_on(video_active),
        .hpos(pix_x),
        .vpos(pix_y)
    );

    // -------------------------------------------------------
    // DVD BOUNCING FLAG LOGIC WITH TRUE S-CURVE EDGES
    // -------------------------------------------------------
    wire [9:0] logo_x = pix_x - logo_left;
    
    // Convert to explicit 12-bit signed ints to avoid any mixed-sign comparison traps
    wire signed [11:0] current_y = $signed({2'b0, pix_y});
    wire signed [11:0] current_top = $signed({2'b0, logo_top});
    wire signed [11:0] logo_y = current_y - current_top;

    // Single Sine Wave Engine - logo_x[6:1] stretches the wave period over 128 pixels
    reg [5:0] wave_timer;
    wire [5:0] wave_index = logo_x[6:1] + wave_timer;
    reg signed [4:0] sine_offset;
    reg signed [11:0] extended_sine;

    always @(*) begin
        case (wave_index[5:0])
            // Positive Half-Cycle (Crest)
            6'd0,  6'd32:     sine_offset =  5'sb00000; // 0
            6'd1,  6'd31:     sine_offset =  5'sb00001; // 1
            6'd2,  6'd30:     sine_offset =  5'sb00001; // 1
            6'd3,  6'd29:     sine_offset =  5'sb00010; // 2
            6'd4,  6'd28:     sine_offset =  5'sb00011; // 3
            6'd5,  6'd27:     sine_offset =  5'sb00011; // 3
            6'd6,  6'd26:     sine_offset =  5'sb00100; // 4
            6'd7,  6'd25:     sine_offset =  5'sb00100; // 4
            6'd8,  6'd24:     sine_offset =  5'sb00101; // 5
            6'd9,  6'd23:     sine_offset =  5'sb00101; // 5
            6'd10, 6'd22:     sine_offset =  5'sb00110; // 6
            6'd11, 6'd21:     sine_offset =  5'sb00110; // 6
            6'd12, 6'd20:     sine_offset =  5'sb00110; // 6
            6'd13, 6'd19:     sine_offset =  5'sb00111; // 7
            6'd14, 6'd18:     sine_offset =  5'sb00111; // 7
            6'd15, 6'd17:     sine_offset =  5'sb00111; // 7
            6'd16:            sine_offset =  5'sb00111; // 7
            
            // Negative Half-Cycle (Trough)
            6'd33, 6'd63:     sine_offset = -5'sb00001; // -1
            6'd34, 6'd62:     sine_offset = -5'sb00001; // -1
            6'd35, 6'd61:     sine_offset = -5'sb00010; // -2
            6'd36, 6'd60:     sine_offset = -5'sb00011; // -3
            6'd37, 6'd59:     sine_offset = -5'sb00011; // -3
            6'd38, 6'd58:     sine_offset = -5'sb00100; // -4
            6'd39, 6'd57:     sine_offset = -5'sb00100; // -4
            6'd40, 6'd56:     sine_offset = -5'sb00101; // -5
            6'd41, 6'd55:     sine_offset = -5'sb00101; // -5
            6'd42, 6'd54:     sine_offset = -5'sb00110; // -6
            6'd43, 6'd53:     sine_offset = -5'sb00110; // -6
            6'd44, 6'd52:     sine_offset = -5'sb00110; // -6
            6'd45, 6'd51:     sine_offset = -5'sb00111; // -7
            6'd46, 6'd50:     sine_offset = -5'sb00111; // -7
            6'd47, 6'd49:     sine_offset = -5'sb00111; // -7
            6'd48:            sine_offset = -5'sb00111; // -7
            
            default:          sine_offset =  5'sb00000;
        endcase
        extended_sine = sine_offset; 
    end

    wire signed [11:0] true_wave_y = logo_y - extended_sine;

    // Hard clamp the value to 0-63 to stop the ROM address from going out of bounds
    wire [5:0] safe_rom_y = (true_wave_y < 0) ? 6'd0 : 
                            (true_wave_y >= 64) ? 6'd63 : 
                            true_wave_y[5:0];

    // Evaluates inside a guaranteed signed domain context to clear up horizontal tearing artifacting
    wire logo_region = (pix_x >= logo_left) && (pix_x < logo_left + LOGO_WIDTH) &&
                       (true_wave_y >= 0) && (true_wave_y < 64) &&
                       (logo_y >= -16) && (logo_y < 80);

    wire [1:0] pixel_color;
    bitmap_rom rom1 (
        .x(logo_x[6:0]),
        .y(safe_rom_y),
        .pixel_color(pixel_color)
    );

    // Flag RGB
    reg flag_r, flag_g, flag_b;
    always @(*) begin
        if (!video_active || !logo_region) begin
            flag_r = 0; flag_g = 0; flag_b = 0;
        end else begin
            case (pixel_color)
                2'b01: begin flag_r = 1; flag_g = 1; flag_b = 1; end          // White
                2'b10: begin                                                    // Blue / Red halves
                    if (safe_rom_y < 32) begin
                        flag_r = 0; flag_g = 0; flag_b = 1;
                    end else begin
                        flag_r = 1; flag_g = 0; flag_b = 0;
                    end
                end
                2'b11: begin flag_r = 1; flag_g = 1; flag_b = 0; end          // Gold
                default: begin flag_r = 0; flag_g = 0; flag_b = 0; end
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
                
                // Keep safe headroom padding so the peak wave crests do not clip into screen edges
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
    reg [11:0] seg_counter;
    wire [3:0] current_stage = seg_counter[6:3];
    wire       show_full_word = (current_stage >= 4'd9);

    always @(posedge vsync, negedge rst_n) begin
        if (~rst_n) seg_counter <= 0;
        else        seg_counter <= seg_counter + 1;
    end

    // -------------------------------------------------------
    // 7-SEGMENT GEOMETRY
    // -------------------------------------------------------
    localparam TEXT_Y0  = 10'd390;
    localparam TEXT_Y1  = 10'd480;
    localparam CELL     = 10'd70;
    localparam MARGIN   = 10'd5;

    wire in_y_range     = (pix_y >= TEXT_Y0) && (pix_y < TEXT_Y1);
    wire in_x_range     = (pix_x >= MARGIN)  && (pix_x < MARGIN + 9*CELL);
    wire display_window = in_x_range && in_y_range;

    wire [3:0] digit_select =
        (pix_x < MARGIN +   CELL) ? 4'd0 :
        (pix_x < MARGIN + 2*CELL) ? 4'd1 :
        (pix_x < MARGIN + 3*CELL) ? 4'd2 :
        (pix_x < MARGIN + 4*CELL) ? 4'd3 :
        (pix_x < MARGIN + 5*CELL) ? 4'd4 :
        (pix_x < MARGIN + 6*CELL) ? 4'd5 :
        (pix_x < MARGIN + 7*CELL) ? 4'd6 :
        (pix_x < MARGIN + 8*CELL) ? 4'd7 : 4'd8;

    wire [9:0] xo = MARGIN + digit_select * CELL;

    wire [9:0]  rx_raw = pix_x - xo;
    wire [9:0]  ry_raw = pix_y - TEXT_Y0;

    wire [11:0] rx = (rx_raw << 2) + (rx_raw >> 1) + (rx_raw >> 4) + 191;
    wire [11:0] ry = (ry_raw * 5) + (ry_raw >> 2) + (ry_raw >> 4) + 7;

    // Combinational lookup map for character segment values
    reg [7:0] character_bits;
    always @(*) begin
        case (digit_select)
            4'd0:    character_bits = 8'b01110011; // P
            4'd1:    character_bits = 8'b00000110; // I
            4'd2:    character_bits = 8'b00111000; // L
            4'd3:    character_bits = 8'b00000110; // I
            4'd4:    character_bits = 8'b01110011; // P
            4'd5:    character_bits = 8'b00000110; // I
            4'd6:    character_bits = 8'b00110111; // N
            4'd7:    character_bits = 8'b01110111; // A
            4'd8:    character_bits = 8'b01101101; // S
            default: character_bits = 8'b00000000;
        endcase
    end

    // Sequential text visibility builder stage
    wire [7:0] slot_led = (show_full_word || (current_stage >= digit_select))
                          ? character_bits
                          : 8'b00000000;

    localparam GAP = 12;

    wire j_a1  = rx < ry + 392 - GAP;
    wire j_a4  = rx > ry + 185 + GAP;
    wire j_a5  = rx > 247 - ry + GAP;
    wire j_a2  = 454 - rx > ry + GAP;
    wire j_b2  = 662 - rx > ry + GAP;
    wire j_b5  = 455 - rx < ry - GAP;
    wire j_c0  = rx < ry + 184 - GAP;
    wire j_c3  = rx + 23 > ry + GAP;
    wire j_c2  = 872 - rx > ry + GAP;
    wire j_c5  = 663 - rx < ry - GAP;
    wire j_d1  = ry > rx + 24 + GAP;

    wire seg_a = (ry > 3) & j_a1 & j_a2 & (ry < 62) & j_a4 & j_a5;
    wire seg_b = j_a1 & (rx < 448) & j_b2 & j_a4 & (rx > 399) & j_b5;
    wire seg_c = j_c0 & (rx < 448) & j_c2 & j_c3 & (rx > 399) & j_c5;
    wire seg_d = (ry > 418) & j_d1 & j_c2 & (ry < 477) & (rx > ry - 232) & j_c5;
    wire seg_e = j_d1 & (rx < 240) & j_b2 & (rx > ry - 232) & (rx > 191) & j_b5;
    wire seg_f = j_c0 & (rx < 240) & j_a2 & j_c3 & (rx > 191) & j_a5;
    wire seg_g = (ry > 210) & j_c0 & j_b2 & (ry < 267) & j_c3 & j_b5;

    wire text_pixel = display_window &&
                      ((seg_a & slot_led) | (seg_b & slot_led[1]) |
                       (seg_c & slot_led[2]) | (seg_d & slot_led[3]) |
                       (seg_e & slot_led[4]) | (seg_f & slot_led[5]) |
                       (seg_g & slot_led[6]));

    // -------------------------------------------------------
    // PIXEL COMPOSITOR
    // -------------------------------------------------------
    wire [5:0] green = 6'b001100;

    wire r_out = text_pixel ? 1'b0 : flag_r;
    wire g_out = text_pixel ? green[3] : flag_g;
    wire b_out = text_pixel ? 1'b0 : flag_b;

    assign uo_out  = {hsync, b_out, g_out, r_out, vsync, b_out, g_out, r_out};
    assign uio_out = 8'b00000000;
    assign uio_oe  = 8'b00000000;

    wire _unused_ok = &{ena, ui_in, uio_in};

endmodule
