module topmodule(
	 //Basic Input Output Devices
    input CLOCK_50,           // 50 MHz clock
    input [3:0] KEY,          // Input Keys for Tile Columns
    input [9:0] SW,           // Input Switches for rst and Testing
    output [6:0] HEX0,        // 7-segment display ones
    output [6:0] HEX1,        // 7-segment display tens
    output [6:0] HEX2,        // 7-segment display hundreds
    output [6:0] HEX3,        // 7-segment display negative

    //Outputs Required for VGA Module
    output VGA_CLK,           // Clock
    output VGA_HS,            // Horizontal sync
    output VGA_VS,            // Vertical sync
    output VGA_BLANK_N,       // Blank
    output VGA_SYNC_N,        // Sync
    output [7:0] VGA_R,       // Red
    output [7:0] VGA_G,       // Green
    output [7:0] VGA_B,       // Blue

	 // Ins and Outs Required for Audio Module
    output AUD_ADCDAT,
    inout AUD_BCLK,
	 inout AUD_ADCLRCK,
	 inout AUD_DACLRCK,
	 output AUD_DACDAT,
	 output AUD_XCK,
	 inout FPGA_I2C_SDAT,
	 output FPGA_I2C_SCLK
);
    
	 //Define FSM States
    localparam STATE_START_MENU = 4'd0;   // Start Menu (Initial State)
	 localparam START_WAIT_3 = 4'd1;       // Begin Countdown timer, Show 3 on screen
	 localparam START_WAIT_2 = 4'd2;       // Continue Countdown timer, Show 2 on screen
	 localparam START_WAIT_1 = 4'd3;       // Finish Countdown timer, Show 1 on screen and transition to playing
    localparam STATE_PLAYING = 4'd4;      // Playing state (vga control is handed off to game.v)
	 localparam STATE_GAME_WON = 4'd5;     // Win State (Score > 10)
	 localparam STATE_GAME_OVER = 4'd6;    // Lose State (Score < -10)
	 //localparam STATE_GAME_PAUSED = 4'd7;  // Paused Game State
    
	 //Define Current and Next State
    reg [3:0] game_state = STATE_START_MENU;
    reg [3:0] next_state;
	 reg gurt;
    
    // Assign Pertinent Buttons on FPGA
    wire reset_n = SW[9];       // Set SW9 to rst
    wire [3:0] buttons = ~KEY;  // Invert buttons for ease of code
	 
	 // Define Signals for 1s Wait
	 localparam ONE_SECOND = 50_000_000 - 1;
	 reg [25:0] wait_counter = 0;
	 reg wait_done = 0;
	 reg waiting;
	 
    // Button Edge Detection 
    reg [3:0] buttons_prev = 0;                           // Create Register that will Hold the Previous Cycles Button States
    wire any_button_pressed = |(buttons & ~buttons_prev); // Any button pressed (for use in transition to START_MENU to START_WAIT)
    
	 // Either Reset or Assign the Values from buttons to buttons_prev
    always @(posedge CLOCK_50 or negedge reset_n) begin
        if (!reset_n)
            buttons_prev <= 0;
        else
            buttons_prev <= buttons;
    end
    
	 // FSM State Register
    always @(posedge CLOCK_50 or negedge reset_n) begin
        if (!reset_n)
            game_state <= STATE_START_MENU; // Assign First State After Reset
        else
            game_state <= next_state;       // Assign next_state
    end
	 
	
	 always @(posedge CLOCK_50 or negedge reset_n) begin
		  if (!reset_n) begin
			  gurt <= 0;
		  end else begin
			   // Latch gurt once wait_done goes high
			   if (wait_done)
					 gurt <= 1;
			   // Clear gurt when leaving GAME_WON or GAME_OVER
			   else if (game_state == STATE_START_MENU)
			 		 gurt <= 0;
		  end
	 end

    
	 // FSM Next State Logic
    always @(*) begin
        next_state = game_state;
        waiting = 0;
		  
        case (game_state)
		  
				// Start Menu
            STATE_START_MENU: begin
					 if (any_button_pressed)
                    next_state = START_WAIT_3;
            end
				// Countdown 3
				START_WAIT_3: begin
					waiting = 1;
					if (wait_done)
						next_state = START_WAIT_2;
				end
				
				// Countdown 2
				START_WAIT_2: begin
					waiting = 1;
					if (wait_done)
						next_state = START_WAIT_1;
				end
				
				// Countdown 1
				START_WAIT_1: begin
					waiting = 1;
					if (wait_done)
						next_state = STATE_PLAYING;
				end
            
				// Game Begins
            STATE_PLAYING: begin
                if (score < -9)
						next_state = STATE_GAME_OVER;
					 if (score > 9)
						next_state = STATE_GAME_WON;
            end
            
				// Game Won State
            STATE_GAME_WON: begin
               waiting = 1;
					if (gurt && any_button_pressed)
						next_state = STATE_START_MENU;
            end
				
				// Game Over State
            STATE_GAME_OVER: begin
               waiting = 1;
					if (gurt && any_button_pressed)
						next_state = STATE_START_MENU;
            end
				
            // Default Case
            default: next_state = STATE_START_MENU;
        endcase
    end	 
	 
    // Control signal for game - only active during playing state
    wire game_active = (game_state == STATE_PLAYING);
    
    // VGA signals
    wire clk_25MHz;
    wire [9:0] x, y;
    wire video_on;
    wire [7:0] red_game, green_game, blue_game;
    
    // Score
    wire signed [7:0] score;
    
    // 25 MHz clock divider
    reg clk_div;
    always @(posedge CLOCK_50 or negedge reset_n) begin
        if (!reset_n)
            clk_div <= 0;
        else
            clk_div <= ~clk_div;
				
		  if (!reset_n) begin
				wait_counter <= 0;
				wait_done <= 0;
		  end else begin
				if (waiting) begin
					if (wait_counter == ONE_SECOND) begin
						wait_done <= 1;
						wait_counter <= 0;
					end else begin
						wait_done <= 0;
						wait_counter <= wait_counter + 1;
					end
				end else begin
					wait_done <= 0;
					wait_counter <= 0;
				end
			end
    end
	 
    assign clk_25MHz = clk_div;
    assign VGA_CLK = clk_25MHz;
    
    // VGA controller signals
    vga_controller vga(
        .clk(clk_25MHz),
        .reset_n(reset_n),
        .hsync(VGA_HS),
        .vsync(VGA_VS),
        .video_on(video_on),
        .x(x),
        .y(y)
    );
    
	// Game logic
    game game(
        .clk(CLOCK_50),
        .reset_n(reset_n && game_active), // Reset game when not playing
        .buttons(buttons),
        .x(x),
        .y(y),
        .video_on(video_on),
        .red(red_game),
        .green(green_game),
        .blue(blue_game),
        .score(score)
    );
	 
	 // Audio controller instantiation
    audio audio_inst(
    .CLOCK_50(CLOCK_50),
    .reset_n(reset_n),
    .buttons(buttons),  // Your 4 buttons signal
    .AUD_ADCDAT(AUD_ADCDAT),
    .AUD_BCLK(AUD_BCLK),
    .AUD_ADCLRCK(AUD_ADCLRCK),
    .AUD_DACLRCK(AUD_DACLRCK),
    .AUD_DACDAT(AUD_DACDAT),
    .AUD_XCK(AUD_XCK),
    .FPGA_I2C_SDAT(FPGA_I2C_SDAT),
    .FPGA_I2C_SCLK(FPGA_I2C_SCLK)
);
    
    // 7-segment display for score
    three_decimal_vals_w_neg score_display(
        .val(score),
        .seg7_dig0(HEX0),
        .seg7_dig1(HEX1),
        .seg7_dig2(HEX2),
        .seg7_neg_sign(HEX3)
    );
    
    
	 // VGA Output Multiplexer
    reg [7:0] red_out, green_out, blue_out;
    
    always @(*) begin
        case (game_state)
            STATE_START_MENU: begin
				//START MENU CODE BEGIN =====================================================================================
				 if (!video_on) begin
                    red_out   = 8'h00;
                    green_out = 8'h00;
                    blue_out  = 8'h00;
                end else begin
                    // ---------- Base background (dark blue) ----------
                    red_out   = 8'h00;
                    green_out = 8'h00;
                    blue_out  = 8'h60;

                    // ---------- Checkerboard border (brighter blue) ----------
                    if ( (x < 20) || (x > 620) || (y < 20) || (y > 460) ) begin
                        if (x[4] ^ y[4]) begin
                            red_out   = 8'h00;
                            green_out = 8'hA0;
                            blue_out  = 8'hFF;
                        end else begin
                            red_out   = 8'h00;
                            green_out = 8'h40;
                            blue_out  = 8'hC0;
                        end
                    end

                    // ---------- Big title bar background ----------
                    if (y >= 40 && y <= 120 && x >= 60 && x <= 580) begin
                        red_out   = 8'h20;
                        green_out = 8'h20;
                        blue_out  = 8'h40;
                    end

                    // ---------- "L&P PIANO TILES" Text (Large, Pixelated Style) ----------
                    // L
                    if ((y >= 60 && y <= 100) && ((x >= 80 && x <= 90) || (y >= 90 && x >= 80 && x <= 110))) begin
                        red_out = 8'hFF; green_out = 8'hFF; blue_out = 8'hFF;
                    end
                    
                    // &
                    if (y >= 60 && y <= 100) begin
                        if ((y >= 65 && y <= 75 && x >= 120 && x <= 140) ||
                            (y >= 75 && y <= 85 && x >= 115 && x <= 125) ||
                            (y >= 85 && y <= 95 && x >= 120 && x <= 145) ||
                            (x >= 135 && x <= 145 && y >= 70 && y <= 90)) begin
                            red_out = 8'hFF; green_out = 8'hFF; blue_out = 8'hFF;
                        end
                    end
                    
                    // P
                    if ((y >= 60 && y <= 100 && x >= 155 && x <= 165) ||
                        (y >= 60 && y <= 70 && x >= 155 && x <= 180) ||
                        (y >= 75 && y <= 85 && x >= 155 && x <= 180) ||
                        (x >= 175 && x <= 180 && y >= 60 && y <= 85)) begin
                        red_out = 8'hFF; green_out = 8'hFF; blue_out = 8'hFF;
                    end

                    // Space between L&P and PIANO

                    // P (second)
                    if ((y >= 60 && y <= 100 && x >= 210 && x <= 220) ||
                        (y >= 60 && y <= 70 && x >= 210 && x <= 235) ||
                        (y >= 75 && y <= 85 && x >= 210 && x <= 235) ||
                        (x >= 230 && x <= 235 && y >= 60 && y <= 85)) begin
                        red_out = 8'hFF; green_out = 8'hFF; blue_out = 8'hFF;
                    end
                    
                    // I
                    if ((y >= 60 && y <= 100 && x >= 248 && x <= 258)) begin
                        red_out = 8'hFF; green_out = 8'hFF; blue_out = 8'hFF;
                    end
                    
                    // A
                    if ((y >= 60 && y <= 100 && x >= 270 && x <= 280) ||
                        (y >= 60 && y <= 100 && x >= 290 && x <= 300) ||
                        (y >= 60 && y <= 70 && x >= 270 && x <= 300) ||
                        (y >= 78 && y <= 82 && x >= 270 && x <= 300)) begin
                        red_out = 8'hFF; green_out = 8'hFF; blue_out = 8'hFF;
                    end
                    
                    // N
                    if ((y >= 60 && y <= 100 && x >= 312 && x <= 322) ||
                        (y >= 60 && y <= 100 && x >= 337 && x <= 347) ||
                        ((y - 60) == (x - 322) && x >= 322 && x <= 337 && y >= 60 && y <= 100)) begin
                        red_out = 8'hFF; green_out = 8'hFF; blue_out = 8'hFF;
                    end
                    
                    // O
                    if ((y >= 60 && y <= 100 && (x >= 360 && x <= 370 || x >= 380 && x <= 390)) ||
                        (y >= 60 && y <= 70 && x >= 360 && x <= 390) ||
                        (y >= 90 && y <= 100 && x >= 360 && x <= 390)) begin
                        red_out = 8'hFF; green_out = 8'hFF; blue_out = 8'hFF;
                    end

                    // Space before TILES

                    // T
                    if ((y >= 60 && y <= 70 && x >= 415 && x <= 445) ||
                        (y >= 60 && y <= 100 && x >= 427 && x <= 437)) begin
                        red_out = 8'hFF; green_out = 8'hFF; blue_out = 8'hFF;
                    end
                    
                    // I
                    if ((y >= 60 && y <= 100 && x >= 455 && x <= 465)) begin
                        red_out = 8'hFF; green_out = 8'hFF; blue_out = 8'hFF;
                    end
                    
                    // L
                    if ((y >= 60 && y <= 100 && x >= 477 && x <= 487) ||
                        (y >= 90 && y <= 100 && x >= 477 && x <= 505)) begin
                        red_out = 8'hFF; green_out = 8'hFF; blue_out = 8'hFF;
                    end
                    
                    // E
                    if ((y >= 60 && y <= 100 && x >= 517 && x <= 527) ||
                        (y >= 60 && y <= 70 && x >= 517 && x <= 545) ||
                        (y >= 78 && y <= 82 && x >= 517 && x <= 540) ||
                        (y >= 90 && y <= 100 && x >= 517 && x <= 545)) begin
                        red_out = 8'hFF; green_out = 8'hFF; blue_out = 8'hFF;
                    end
                    
                    // S
                    if ((y >= 60 && y <= 70 && x >= 555 && x <= 575) ||
                        (y >= 78 && y <= 82 && x >= 555 && x <= 575) ||
                        (y >= 90 && y <= 100 && x >= 555 && x <= 575) ||
                        (x >= 555 && x <= 565 && y >= 60 && y <= 82) ||
                        (x >= 565 && x <= 575 && y >= 78 && y <= 100)) begin
                        red_out = 8'hFF; green_out = 8'hFF; blue_out = 8'hFF;
                    end

                    // ---------- Colored vertical "piano tiles" in middle ----------
                    if (y >= 150 && y <= 320) begin
                        if      (x >= 100 && x < 180) begin
                            red_out   = 8'h20;
                            green_out = 8'hFF;
                            blue_out  = 8'hFF;
                        end else if (x >= 180 && x < 260) begin
                            red_out   = 8'hFF;
                            green_out = 8'h80;
                            blue_out  = 8'hC0;
                        end else if (x >= 260 && x < 340) begin
                            red_out   = 8'h50;
                            green_out = 8'h70;
                            blue_out  = 8'hFF;
                        end else if (x >= 340 && x < 420) begin
                            red_out   = 8'hFF;
                            green_out = 8'h20;
                            blue_out  = 8'hD0;
                        end else if (x >= 420 && x < 500) begin
                            red_out   = 8'h20;
                            green_out = 8'hFF;
                            blue_out  = 8'h90;
                        end
                    end

                    // ---------- Button background for "PRESS ANY KEY TO START" ----------
                    if (y >= 340 && y <= 390 && x >= 80 && x <= 560) begin
                        red_out   = 8'h30;
                        green_out = 8'h30;
                        blue_out  = 8'h30;
                    end

                    // ---------- "PRESS ANY KEY TO START" Text (Smaller) ----------
                    // P
                    if ((y >= 350 && y <= 380 && x >= 130 && x <= 135) ||
                        (y >= 350 && y <= 355 && x >= 130 && x <= 145) ||
                        (y >= 362 && y <= 367 && x >= 130 && x <= 145) ||
                        (x >= 140 && x <= 145 && y >= 350 && y <= 367)) begin
                        red_out = 8'h00; green_out = 8'hFF; blue_out = 8'h00;
                    end
                    // R
                    if ((y >= 350 && y <= 380 && x >= 150 && x <= 155) ||
                        (y >= 350 && y <= 355 && x >= 150 && x <= 165) ||
                        (y >= 362 && y <= 367 && x >= 150 && x <= 165) ||
                        (x >= 160 && x <= 165 && y >= 350 && y <= 367) ||
                        ((y - 367) * 2 == (x - 155) && x >= 155 && x <= 165 && y >= 367 && y <= 380)) begin
                        red_out = 8'h00; green_out = 8'hFF; blue_out = 8'h00;
                    end
                    // E
                    if ((y >= 350 && y <= 380 && x >= 170 && x <= 175) ||
                        (y >= 350 && y <= 355 && x >= 170 && x <= 185) ||
                        (y >= 362 && y <= 367 && x >= 170 && x <= 183) ||
                        (y >= 375 && y <= 380 && x >= 170 && x <= 185)) begin
                        red_out = 8'h00; green_out = 8'hFF; blue_out = 8'h00;
                    end
                    // S
                    if ((y >= 350 && y <= 355 && x >= 190 && x <= 203) ||
                        (y >= 362 && y <= 367 && x >= 190 && x <= 203) ||
                        (y >= 375 && y <= 380 && x >= 190 && x <= 203) ||
                        (x >= 190 && x <= 195 && y >= 350 && y <= 367) ||
                        (x >= 198 && x <= 203 && y >= 362 && y <= 380)) begin
                        red_out = 8'h00; green_out = 8'hFF; blue_out = 8'h00;
                    end
                    // S (second)
                    if ((y >= 350 && y <= 355 && x >= 208 && x <= 221) ||
                        (y >= 362 && y <= 367 && x >= 208 && x <= 221) ||
                        (y >= 375 && y <= 380 && x >= 208 && x <= 221) ||
                        (x >= 208 && x <= 213 && y >= 350 && y <= 367) ||
                        (x >= 216 && x <= 221 && y >= 362 && y <= 380)) begin
                        red_out = 8'h00; green_out = 8'hFF; blue_out = 8'h00;
                    end
                    
                    // Space
                    
                    // A
                    if ((y >= 350 && y <= 380 && x >= 235 && x <= 240) ||
                        (y >= 350 && y <= 380 && x >= 248 && x <= 253) ||
                        (y >= 350 && y <= 355 && x >= 235 && x <= 253) ||
                        (y >= 363 && y <= 367 && x >= 235 && x <= 253)) begin
                        red_out = 8'h00; green_out = 8'hFF; blue_out = 8'h00;
                    end
                    // N
                    if ((y >= 350 && y <= 380 && x >= 258 && x <= 263) ||
                        (y >= 350 && y <= 380 && x >= 271 && x <= 276) ||
                        ((y - 350) == (x - 263) && x >= 263 && x <= 271 && y >= 350 && y <= 380)) begin
                        red_out = 8'h00; green_out = 8'hFF; blue_out = 8'h00;
                    end
                    // Y
                    if ((y >= 350 && y <= 365 && x >= 281 && x <= 286) ||
                        (y >= 350 && y <= 365 && x >= 294 && x <= 299) ||
                        (y >= 365 && y <= 380 && x >= 287 && x <= 292) ||
                        ((y - 350) == (x - 281) && x >= 281 && x <= 287 && y >= 350 && y <= 365) ||
                        ((y - 350) == -(x - 299) + 15 && x >= 292 && x <= 299 && y >= 350 && y <= 365)) begin
                        red_out = 8'h00; green_out = 8'hFF; blue_out = 8'h00;
                    end
                    
                    // Space
                    
                    // K
                    if ((y >= 350 && y <= 380 && x >= 313 && x <= 318) ||
                        (x >= 323 && x <= 328 && y >= 350 && y <= 365) ||
                        ((y - 365) * 2 == (x - 318) && x >= 318 && x <= 328 && y >= 365 && y <= 380) ||
                        ((y - 350) * -2 == (x - 318) - 30 && x >= 318 && x <= 328 && y >= 350 && y <= 365)) begin
                        red_out = 8'h00; green_out = 8'hFF; blue_out = 8'h00;
                    end
                    // E
                    if ((y >= 350 && y <= 380 && x >= 333 && x <= 338) ||
                        (y >= 350 && y <= 355 && x >= 333 && x <= 348) ||
                        (y >= 362 && y <= 367 && x >= 333 && x <= 346) ||
                        (y >= 375 && y <= 380 && x >= 333 && x <= 348)) begin
                        red_out = 8'h00; green_out = 8'hFF; blue_out = 8'h00;
                    end
                    // Y (second)
                    if ((y >= 350 && y <= 365 && x >= 353 && x <= 358) ||
                        (y >= 350 && y <= 365 && x >= 366 && x <= 371) ||
                        (y >= 365 && y <= 380 && x >= 359 && x <= 364) ||
                        ((y - 350) == (x - 353) && x >= 353 && x <= 359 && y >= 350 && y <= 365) ||
                        ((y - 350) == -(x - 371) + 18 && x >= 364 && x <= 371 && y >= 350 && y <= 365)) begin
                        red_out = 8'h00; green_out = 8'hFF; blue_out = 8'h00;
                    end
                    
                    // Space
                    
                    // T
                    if ((y >= 350 && y <= 355 && x >= 385 && x <= 400) ||
                        (y >= 350 && y <= 380 && x >= 390 && x <= 395)) begin
                        red_out = 8'h00; green_out = 8'hFF; blue_out = 8'h00;
                    end
                    // O
                    if ((y >= 350 && y <= 380 && (x >= 405 && x <= 410 || x >= 418 && x <= 423)) ||
                        (y >= 350 && y <= 355 && x >= 405 && x <= 423) ||
                        (y >= 375 && y <= 380 && x >= 405 && x <= 423)) begin
                        red_out = 8'h00; green_out = 8'hFF; blue_out = 8'h00;
                    end
                    
                    // Space
                    
                    // S
                    if ((y >= 350 && y <= 355 && x >= 437 && x <= 450) ||
                        (y >= 362 && y <= 367 && x >= 437 && x <= 450) ||
                        (y >= 375 && y <= 380 && x >= 437 && x <= 450) ||
                        (x >= 437 && x <= 442 && y >= 350 && y <= 367) ||
                        (x >= 445 && x <= 450 && y >= 362 && y <= 380)) begin
                        red_out = 8'h00; green_out = 8'hFF; blue_out = 8'h00;
                    end
                    // T
                    if ((y >= 350 && y <= 355 && x >= 455 && x <= 470) ||
                        (y >= 350 && y <= 380 && x >= 460 && x <= 465)) begin
                        red_out = 8'h00; green_out = 8'hFF; blue_out = 8'h00;
                    end
                    // A
                    if ((y >= 350 && y <= 380 && x >= 475 && x <= 480) ||
                        (y >= 350 && y <= 380 && x >= 488 && x <= 493) ||
                        (y >= 350 && y <= 355 && x >= 475 && x <= 493) ||
                        (y >= 363 && y <= 367 && x >= 475 && x <= 493)) begin
                        red_out = 8'h00; green_out = 8'hFF; blue_out = 8'h00;
                    end
                    // R
                    if ((y >= 350 && y <= 380 && x >= 498 && x <= 503) ||
                        (y >= 350 && y <= 355 && x >= 498 && x <= 513) ||
                        (y >= 362 && y <= 367 && x >= 498 && x <= 513) ||
                        (x >= 508 && x <= 513 && y >= 350 && y <= 367) ||
                        ((y - 367) * 2 == (x - 503) && x >= 503 && x <= 513 && y >= 367 && y <= 380)) begin
                        red_out = 8'h00; green_out = 8'hFF; blue_out = 8'h00;
                    end
                    // T
                    if ((y >= 350 && y <= 355 && x >= 518 && x <= 533) ||
                        (y >= 350 && y <= 380 && x >= 523 && x <= 528)) begin
                        red_out = 8'h00; green_out = 8'hFF; blue_out = 8'h00;
                    end

                    // Border outline on button
                    if (y >= 340 && y <= 345 && x >= 80 && x <= 560) begin
                        red_out   = 8'h00;
                        green_out = 8'h00;
                        blue_out  = 8'h00;
                    end
                    if (y >= 385 && y <= 390 && x >= 80 && x <= 560) begin
                        red_out   = 8'h00;
                        green_out = 8'h00;
                        blue_out  = 8'h00;
                    end
                    if (x >= 80 && x <= 85 && y >= 340 && y <= 390) begin
                        red_out   = 8'h00;
                        green_out = 8'h00;
                        blue_out  = 8'h00;
                    end
                    if (x >= 555 && x <= 560 && y >= 340 && y <= 390) begin
                        red_out   = 8'h00;
                        green_out = 8'h00;
                        blue_out  = 8'h00;
                    end
                end
                // START MENU CODE END =======================================================================================
            end				
				
				START_WAIT_3: begin
					 // Default background: black
                red_out   = 8'h00;
                green_out = 8'h00;
                blue_out  = 8'h00;

                // Big red "3"
                // Top horizontal bar
                if ((y >= 100 && y <= 140 && x >= 200 && x <= 440) ||
                // Middle horizontal bar
                    (y >= 220 && y <= 260 && x >= 200 && x <= 440) ||
                // Bottom horizontal bar
                    (y >= 340 && y <= 380 && x >= 200 && x <= 440) ||
                // Right vertical bar
                    (y >= 100 && y <= 380 && x >= 400 && x <= 440))
                begin
                    red_out   = 8'hFF;
                    green_out = 8'h00;
                    blue_out  = 8'h00;
                end
				end
				
				START_WAIT_2: begin
					 // Default background: black
                red_out   = 8'h00;
                green_out = 8'h00;
                blue_out  = 8'h00;

                // Big yellow "2"
                // Top horizontal bar
                if ((y >= 100 && y <= 140 && x >= 200 && x <= 440) ||
                // Middle horizontal bar
                    (y >= 220 && y <= 260 && x >= 200 && x <= 440) ||
                // Bottom horizontal bar
                    (y >= 340 && y <= 380 && x >= 200 && x <= 440) ||
                // Top-right vertical bar
                    (y >= 100 && y <= 220 && x >= 400 && x <= 440) ||
                // Bottom-left vertical bar
                    (y >= 260 && y <= 380 && x >= 200 && x <= 240))
                begin
                    red_out   = 8'hFF;
                    green_out = 8'hFF;
                    blue_out  = 8'h00;
                end
				end
				
				START_WAIT_1: begin
					 // Default background: black
                red_out   = 8'h00;
                green_out = 8'h00;
                blue_out  = 8'h00;

                // Big green "1" with top slant, main vertical bar, and long bottom base
                if (
                    // Main vertical bar
                    (y >= 100 && y <= 380 && x >= 320 && x <= 360) ||

                    // Top slant
                    (y >= 100 && y <= 140 && x >= 300 && x <= 320) ||

                    // Bottom base (extended longer)
                    (y >= 360 && y <= 380 && x >= 280 && x <= 400)
                )
                begin
                    red_out   = 8'h00;
                    green_out = 8'hFF;
                    blue_out  = 8'h00;
                end
				end
				
            STATE_PLAYING: begin
                // Display game
                red_out = red_game;
                green_out = green_game;
                blue_out = blue_game;
            end
            
				STATE_GAME_WON: begin
				    // Default background: black
                red_out   = 8'h00;
                green_out = 8'h00;
                blue_out  = 8'h00;

                // Trophy base - brown
                if ((y >= 360 && y <= 380 && x >= 280 && x <= 560)) begin
                    red_out   = 8'h8B;  // brown
                    green_out = 8'h45;
                    blue_out  = 8'h00;
                end

                // Trophy stem - gold
                if ((y >= 220 && y <= 360 && x >= 360 && x <= 480)) begin
                    red_out   = 8'hFF;  // gold
                    green_out = 8'hD7;
                    blue_out  = 8'h00;
                end

                // Trophy cup - gold with handles
                if (
                    (y >= 100 && y <= 220 && x >= 320 && x <= 520) || // main cup
                    (y >= 120 && y <= 200 && x >= 280 && x <= 320) || // left handle
                    (y >= 120 && y <= 200 && x >= 520 && x <= 560)    // right handle
                ) begin
                    red_out   = 8'hFF;  // gold
                    green_out = 8'hD7;
                    blue_out  = 0;
                end

                // Decorations - red jewel
                if ((y >= 160 && y <= 180 && x >= 390 && x <= 410)) begin
                    red_out   = 8'hFF;
                    green_out = 8'h00;
                    blue_out  = 8'h00;
                end

                // Decorations - blue jewel
                if ((y >= 160 && y <= 180 && x >= 430 && x <= 450)) begin
                    red_out   = 0;
                    green_out = 0;
                    blue_out  = 8'hFF;
                end

                // Decorations - green jewel
                if ((y >= 200 && y <= 220 && x >= 410 && x <= 430)) begin
                    red_out   = 0;
                    green_out = 8'hFF;
                    blue_out  = 0;
                end
				end
				
            STATE_GAME_OVER: begin
                // Game Over Screen Drawing Block

                if (!video_on) begin
                    red_out   = 8'h00;
                    green_out = 8'h00;
                    blue_out  = 8'h00;
                end else begin
                    // ---------- Base background (dark red tint for game over) ----------
                    red_out   = 8'h40;
                    green_out = 8'h00;
                    blue_out  = 8'h00;

                    // ---------- Checkerboard border (red themed) ----------
                    if ( (x < 20) || (x > 620) || (y < 20) || (y > 460) ) begin
                        if (x[4] ^ y[4]) begin
                            red_out   = 8'hFF;
                            green_out = 8'h20;
                            blue_out  = 8'h20;
                        end else begin
                            red_out   = 8'hA0;
                            green_out = 8'h10;
                            blue_out  = 8'h10;
                        end
                    end

                    // ---------- "GAME OVER" Title Bar ----------
                    if (y >= 80 && y <= 160 && x >= 100 && x <= 540) begin
                        red_out   = 8'h60;
                        green_out = 8'h10;
                        blue_out  = 8'h10;
                    end

                    // ---------- "GAME OVER" Text (Large, White) ----------
                    // G
                    if ((y >= 95 && y <= 145 && x >= 120 && x <= 130) ||
                        (y >= 95 && y <= 105 && x >= 120 && x <= 155) ||
                        (y >= 135 && y <= 145 && x >= 120 && x <= 155) ||
                        (y >= 118 && y <= 145 && x >= 145 && x <= 155) ||
                        (y >= 118 && y <= 128 && x >= 135 && x <= 155)) begin
                        red_out = 8'hFF; green_out = 8'hFF; blue_out = 8'hFF;
                    end
                    
                    // A
                    if ((y >= 95 && y <= 145 && x >= 165 && x <= 175) ||
                        (y >= 95 && y <= 145 && x >= 190 && x <= 200) ||
                        (y >= 95 && y <= 105 && x >= 165 && x <= 200) ||
                        (y >= 118 && y <= 123 && x >= 165 && x <= 200)) begin
                        red_out = 8'hFF; green_out = 8'hFF; blue_out = 8'hFF;
                    end
                    
                    // M
                    if ((y >= 95 && y <= 145 && x >= 210 && x <= 220) ||
                        (y >= 95 && y <= 145 && x >= 250 && x <= 260) ||
                        (y >= 95 && y <= 145 && x >= 230 && x <= 240) ||
                        (y >= 95 && y <= 115 && x >= 220 && x <= 230) ||
                        (y >= 95 && y <= 115 && x >= 240 && x <= 250)) begin
                        red_out = 8'hFF; green_out = 8'hFF; blue_out = 8'hFF;
                    end
                    
                    // E
                    if ((y >= 95 && y <= 145 && x >= 270 && x <= 280) ||
                        (y >= 95 && y <= 105 && x >= 270 && x <= 305) ||
                        (y >= 118 && y <= 123 && x >= 270 && x <= 300) ||
                        (y >= 135 && y <= 145 && x >= 270 && x <= 305)) begin
                        red_out = 8'hFF; green_out = 8'hFF; blue_out = 8'hFF;
                    end

                    // Space between GAME and OVER

                    // O
                    if ((y >= 95 && y <= 145 && (x >= 330 && x <= 340 || x >= 360 && x <= 370)) ||
                        (y >= 95 && y <= 105 && x >= 330 && x <= 370) ||
                        (y >= 135 && y <= 145 && x >= 330 && x <= 370)) begin
                        red_out = 8'hFF; green_out = 8'hFF; blue_out = 8'hFF;
                    end
                    
                    // V
                    if ((y >= 95 && y <= 130 && x >= 380 && x <= 390) ||
                        (y >= 95 && y <= 130 && x >= 405 && x <= 415) ||
                        ((y - 130) * 2 == (x - 390) && x >= 390 && x <= 397 && y >= 130 && y <= 145) ||
                        ((y - 130) * -2 == (x - 405) - 30 && x >= 398 && x <= 405 && y >= 130 && y <= 145)) begin
                        red_out = 8'hFF; green_out = 8'hFF; blue_out = 8'hFF;
                    end
                    
                    // E (second)
                    if ((y >= 95 && y <= 145 && x >= 425 && x <= 435) ||
                        (y >= 95 && y <= 105 && x >= 425 && x <= 460) ||
                        (y >= 118 && y <= 123 && x >= 425 && x <= 455) ||
                        (y >= 135 && y <= 145 && x >= 425 && x <= 460)) begin
                        red_out = 8'hFF; green_out = 8'hFF; blue_out = 8'hFF;
                    end
                    
                    // R
                    if ((y >= 95 && y <= 145 && x >= 470 && x <= 480) ||
                        (y >= 95 && y <= 105 && x >= 470 && x <= 500) ||
                        (y >= 118 && y <= 123 && x >= 470 && x <= 500) ||
                        (x >= 490 && x <= 500 && y >= 95 && y <= 123) ||
                        ((y - 123) * 2 == (x - 480) && x >= 480 && x <= 500 && y >= 123 && y <= 145)) begin
                        red_out = 8'hFF; green_out = 8'hFF; blue_out = 8'hFF;
                    end

                    // ---------- Score display area (optional - placeholder) ----------
                    if (y >= 200 && y <= 250 && x >= 220 && x <= 420) begin
                        red_out   = 8'h30;
                        green_out = 8'h10;
                        blue_out  = 8'h10;
                    end
                    
                    // "YOUR SCORE" text could go here - simplified version
                    // You can add actual score display later

                    // ---------- "TRY AGAIN" Button ----------
                    if (y >= 320 && y <= 380 && x >= 150 && x <= 490) begin
                        red_out   = 8'h20;
                        green_out = 8'h60;
                        blue_out  = 8'h20;
                    end

                    // ---------- "TRY AGAIN" Text ----------
                    // T
                    if ((y >= 335 && y <= 342 && x >= 180 && x <= 205) ||
                        (y >= 335 && y <= 365 && x >= 190 && x <= 197)) begin
                        red_out = 8'hFF; green_out = 8'hFF; blue_out = 8'hFF;
                    end
                    
                    // R
                    if ((y >= 335 && y <= 365 && x >= 212 && x <= 219) ||
                        (y >= 335 && y <= 342 && x >= 212 && x <= 235) ||
                        (y >= 348 && y <= 353 && x >= 212 && x <= 235) ||
                        (x >= 228 && x <= 235 && y >= 335 && y <= 353) ||
                        ((y - 353) * 2 == (x - 219) && x >= 219 && x <= 235 && y >= 353 && y <= 365)) begin
                        red_out = 8'hFF; green_out = 8'hFF; blue_out = 8'hFF;
                    end
                    
                    // Y
                    if ((y >= 335 && y <= 350 && x >= 242 && x <= 249) ||
                        (y >= 335 && y <= 350 && x >= 259 && x <= 266) ||
                        (y >= 350 && y <= 365 && x >= 250 && x <= 257) ||
                        ((y - 335) == (x - 242) && x >= 242 && x <= 250 && y >= 335 && y <= 350) ||
                        ((y - 335) == -(x - 266) + 24 && x >= 257 && x <= 266 && y >= 335 && y <= 350)) begin
                        red_out = 8'hFF; green_out = 8'hFF; blue_out = 8'hFF;
                    end

                    // Space

                    // A
                    if ((y >= 335 && y <= 365 && x >= 290 && x <= 297) ||
                        (y >= 335 && y <= 365 && x >= 310 && x <= 317) ||
                        (y >= 335 && y <= 342 && x >= 290 && x <= 317) ||
                        (y >= 349 && y <= 353 && x >= 290 && x <= 317)) begin
                        red_out = 8'hFF; green_out = 8'hFF; blue_out = 8'hFF;
                    end
                    
                    // G
                    if ((y >= 335 && y <= 365 && x >= 324 && x <= 331) ||
                        (y >= 335 && y <= 342 && x >= 324 && x <= 350) ||
                        (y >= 358 && y <= 365 && x >= 324 && x <= 350) ||
                        (y >= 348 && y <= 365 && x >= 343 && x <= 350) ||
                        (y >= 348 && y <= 353 && x >= 337 && x <= 350)) begin
                        red_out = 8'hFF; green_out = 8'hFF; blue_out = 8'hFF;
                    end
                    
                    // A (second)
                    if ((y >= 335 && y <= 365 && x >= 357 && x <= 364) ||
                        (y >= 335 && y <= 365 && x >= 377 && x <= 384) ||
                        (y >= 335 && y <= 342 && x >= 357 && x <= 384) ||
                        (y >= 349 && y <= 353 && x >= 357 && x <= 384)) begin
                        red_out = 8'hFF; green_out = 8'hFF; blue_out = 8'hFF;
                    end
                    
                    // I
                    if ((y >= 335 && y <= 365 && x >= 391 && x <= 398)) begin
                        red_out = 8'hFF; green_out = 8'hFF; blue_out = 8'hFF;
                    end
                    
                    // N
                    if ((y >= 335 && y <= 365 && x >= 405 && x <= 412) ||
                        (y >= 335 && y <= 365 && x >= 428 && x <= 435) ||
                        ((y - 335) == (x - 412) && x >= 412 && x <= 428 && y >= 335 && y <= 365)) begin
                        red_out = 8'hFF; green_out = 8'hFF; blue_out = 8'hFF;
                    end

                    // ---------- "PRESS ANY BUTTON" subtitle ----------
                    // Smaller text below TRY AGAIN
                    if (y >= 400 && y <= 415 && x >= 210 && x <= 430) begin
                        // Simple text representation
                        if ((x >= 215 && x <= 218) || (x >= 232 && x <= 235) || 
                            (x >= 250 && x <= 253) || (x >= 268 && x <= 271) ||
                            (x >= 286 && x <= 289) || (x >= 304 && x <= 307) ||
                            (x >= 322 && x <= 325) || (x >= 340 && x <= 343) ||
                            (x >= 358 && x <= 361) || (x >= 376 && x <= 379) ||
                            (x >= 394 && x <= 397) || (x >= 412 && x <= 415)) begin
                            red_out = 8'hAA; green_out = 8'hFF; blue_out = 8'hAA;
                        end
                    end

                    // Button border
                    if ((y >= 320 && y <= 325 && x >= 150 && x <= 490) ||
                        (y >= 375 && y <= 380 && x >= 150 && x <= 490) ||
                        (x >= 150 && x <= 155 && y >= 320 && y <= 380) ||
                        (x >= 485 && x <= 490 && y >= 320 && y <= 380)) begin
                        red_out   = 8'h00;
                        green_out = 8'hFF;
                        blue_out  = 8'h00;
                    end
                end
            end
        
        endcase
    end
    
    // VGA outputs
    assign VGA_R = red_out;
    assign VGA_G = green_out;
    assign VGA_B = blue_out;
    assign VGA_BLANK_N = video_on;
    assign VGA_SYNC_N = 1'b0;
    
endmodule