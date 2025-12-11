module game(
    input clk,
    input reset_n,
    input [3:0] buttons,
    input [9:0] x,
    input [9:0] y,
    input video_on,
    output reg [7:0] red,
    output reg [7:0] green,
    output reg [7:0] blue,
    output reg signed [7:0] score
);

    parameter COL_WIDTH = 160;  // 640/4 = 160
    parameter TILE_HEIGHT = 80;
    parameter SCREEN_HEIGHT = 480;
    
    // Frame tick generator (60 Hz)
    reg [31:0] frame_counter;
    reg frame_tick;
    
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            frame_counter <= 0;
            frame_tick <= 0;
        end
        else begin
            if (frame_counter >= 32'd833333) begin  // 50MHz / 60Hz
                frame_counter <= 0;
                frame_tick <= 1;
            end
            else begin
                frame_counter <= frame_counter + 1;
                frame_tick <= 0;
            end
        end
    end
    
    // Spawn control
    reg [31:0] spawn_timer;
    reg [1:0] next_col;
    wire [3:0] spawn_signals;
    
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            spawn_timer <= 0;
            next_col <= 0;
        end
        else if (frame_tick) begin
            spawn_timer <= spawn_timer + 1;
            if (spawn_timer >= 32'd60) begin  // Spawn every 60 frames (1 second)
                spawn_timer <= 0;
                next_col <= next_col + 1;
            end
        end
    end
    
    assign spawn_signals[0] = (spawn_timer == 0 && next_col == 2'd0);
    assign spawn_signals[1] = (spawn_timer == 0 && next_col == 2'd1);
    assign spawn_signals[2] = (spawn_timer == 0 && next_col == 2'd2);
    assign spawn_signals[3] = (spawn_timer == 0 && next_col == 2'd3);
    
    // Button edge detection
    reg [3:0] button_prev;
    wire [3:0] button_pressed;
    
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n)
            button_prev <= 4'b0000;
        else
            button_prev <= buttons;
    end
    
    assign button_pressed = buttons & ~button_prev;
    
    // Column instances
    wire [9:0] tile_y_0, tile_y_1, tile_y_2, tile_y_3;
    wire active_0, active_1, active_2, active_3;
    wire hit_0, hit_1, hit_2, hit_3;
    wire miss_0, miss_1, miss_2, miss_3;
    wire pixel_0, pixel_1, pixel_2, pixel_3;
    wire in_zone_0, in_zone_1, in_zone_2, in_zone_3;
    
    column col0(
        .clk(clk),
        .reset_n(reset_n),
        .frame_tick(frame_tick),
        .spawn(spawn_signals[0]),
        .button_press(button_pressed[3]),  // Flipped: rightmost button
        .button_held(buttons[3]),
        .pixel_x(x),
        .pixel_y(y),
        .col_x_start(10'd0),
        .col_x_end(COL_WIDTH),
        .tile_y(tile_y_0),
        .active(active_0),
        .hit(hit_0),
        .miss(miss_0),
        .pixel_on(pixel_0),
        .in_hit_zone(in_zone_0)
    );
    
    column col1(
        .clk(clk),
        .reset_n(reset_n),
        .frame_tick(frame_tick),
        .spawn(spawn_signals[1]),
        .button_press(button_pressed[2]),  // Flipped
        .button_held(buttons[2]),
        .pixel_x(x),
        .pixel_y(y),
        .col_x_start(COL_WIDTH),
        .col_x_end(2 * COL_WIDTH),
        .tile_y(tile_y_1),
        .active(active_1),
        .hit(hit_1),
        .miss(miss_1),
        .pixel_on(pixel_1),
        .in_hit_zone(in_zone_1)
    );
    
    column col2(
        .clk(clk),
        .reset_n(reset_n),
        .frame_tick(frame_tick),
        .spawn(spawn_signals[2]),
        .button_press(button_pressed[1]),  // Flipped
        .button_held(buttons[1]),
        .pixel_x(x),
        .pixel_y(y),
        .col_x_start(2 * COL_WIDTH),
        .col_x_end(3 * COL_WIDTH),
        .tile_y(tile_y_2),
        .active(active_2),
        .hit(hit_2),
        .miss(miss_2),
        .pixel_on(pixel_2),
        .in_hit_zone(in_zone_2)
    );
    
    column col3(
        .clk(clk),
        .reset_n(reset_n),
        .frame_tick(frame_tick),
        .spawn(spawn_signals[3]),
        .button_press(button_pressed[0]),  // Flipped: leftmost button
        .button_held(buttons[0]),
        .pixel_x(x),
        .pixel_y(y),
        .col_x_start(3 * COL_WIDTH),
        .col_x_end(4 * COL_WIDTH),
        .tile_y(tile_y_3),
        .active(active_3),
        .hit(hit_3),
        .miss(miss_3),
        .pixel_on(pixel_3),
        .in_hit_zone(in_zone_3)
    );
    
    
	 // Score tracking - add on hit, subtract on miss
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n)
            score <= 8'd0;
        else begin
            // Add point for hits
            if (hit_0 || hit_1 || hit_2 || hit_3)
                score <= score + 1;
            // Subtract point for misses
            else if (miss_0 || miss_1 || miss_2 || miss_3)
               score <= score - 8'd1;
        end
    end
    
    // Determine which column the current pixel is in
    wire [1:0] current_col = (x < COL_WIDTH) ? 2'd0 :
                              (x < 2*COL_WIDTH) ? 2'd1 :
                              (x < 3*COL_WIDTH) ? 2'd2 : 2'd3;
    
    // Check if current pixel's tile is in hit zone and button state
    wire tile_in_zone = (current_col == 2'd0 && in_zone_0 && pixel_0) ||
                        (current_col == 2'd1 && in_zone_1 && pixel_1) ||
                        (current_col == 2'd2 && in_zone_2 && pixel_2) ||
                        (current_col == 2'd3 && in_zone_3 && pixel_3);
    
    wire button_for_pixel = (current_col == 2'd0) ? buttons[3] :
                            (current_col == 2'd1) ? buttons[2] :
                            (current_col == 2'd2) ? buttons[1] : buttons[0];
    
    // Rendering with color feedback
    wire any_tile = pixel_0 || pixel_1 || pixel_2 || pixel_3;
    wire divider = (x % COL_WIDTH) < 2;
    wire target_zone = (y >= (SCREEN_HEIGHT - TILE_HEIGHT - 20)) && 
                       (y < (SCREEN_HEIGHT - TILE_HEIGHT + 20));
    
    always @(*) begin
        if (!video_on) begin
            red = 8'd0;
            green = 8'd0;
            blue = 8'd0;
        end
        else if (any_tile) begin
            // Tile is in hit zone and button pressed -> GREEN
            if (tile_in_zone && button_for_pixel) begin
                red = 8'd0;
                green = 8'd255;
                blue = 8'd0;
            end
            // Tile is in hit zone but button NOT pressed -> RED
            else if (tile_in_zone && !button_for_pixel) begin
                red = 8'd255;
                green = 8'd0;
                blue = 8'd0;
            end
            // Normal tile -> Dark Blue to Match with Start
            else begin
                red   = 8'd22;
                green = 8'd5;
                blue  = 8'd128;
            end
        end
        else if (divider) begin //Dark Grey for clear seperation
            red   = 8'd15;
            green = 8'd15;
            blue  = 8'd20;
        end
        else if (target_zone) begin //Target Zone
            red = 8'd53;
            green = 8'd42;
            blue = 8'd242;
        end
        else begin // Backrground nice light blue
            red   = 8'd214;
            green = 8'd232;
            blue  = 8'd255;
        end
    end
    
endmodule