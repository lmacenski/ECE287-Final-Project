// column.v - Single column that manages one tile with forgiving hold mechanics
module column(
    input clk,
    input reset_n,
    input frame_tick,
    input spawn,
    input button_press,
    input button_held,
    input [9:0] pixel_x,
    input [9:0] pixel_y,
    input [9:0] col_x_start,
    input [9:0] col_x_end,
    output reg [9:0] tile_y,
    output reg active,
    output hit,
    output miss,
    output pixel_on,
    output in_hit_zone
);
    parameter TILE_HEIGHT = 80;
    parameter SCREEN_HEIGHT = 480;
    parameter FALL_SPEED = 2;
    
    // Check if tile is in hit zone (based on overlap)
    wire [9:0] tile_bottom = tile_y + TILE_HEIGHT;
    wire [9:0] zone_top = SCREEN_HEIGHT - TILE_HEIGHT - 20;
    wire [9:0] zone_bottom = SCREEN_HEIGHT - TILE_HEIGHT + 20;
    wire [9:0] zone_middle = (zone_top + zone_bottom) / 2;  // Halfway point
    
    assign in_hit_zone = active && 
                         tile_bottom >= zone_top &&      // Bottom of tile reached top of zone
                         tile_y <= zone_bottom;          // Top of tile hasn't passed bottom of zone
    
    // Check if tile is in the lower half of hit zone (more forgiving timing)
    wire in_lower_half = active && 
                         tile_y >= zone_middle &&        // Past the halfway point
                         tile_y <= zone_bottom;
    
    // Detect miss and hit
    reg was_in_zone;
    reg was_held_in_lower_half;  // Track if button was held in lower half
    reg miss_pulse;
    reg hit_pulse;
    
    assign miss = miss_pulse;
    assign hit = hit_pulse;
    
    // Tile logic
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            tile_y <= 10'd0;
            active <= 0;
            was_in_zone <= 0;
            was_held_in_lower_half <= 0;
            miss_pulse <= 0;
            hit_pulse <= 0;
        end
        else begin
            miss_pulse <= 0;  // Always clear pulse every clock cycle
            hit_pulse <= 0;   // Always clear pulse every clock cycle
            
            // Track if button is held during lower half of zone
            if (in_lower_half && button_held) begin
                was_held_in_lower_half <= 1;
            end
            
            if (frame_tick) begin
                // Spawn new tile
                if (spawn && !active) begin
                    tile_y <= 10'd0;
                    active <= 1;
                    was_in_zone <= 0;
                    was_held_in_lower_half <= 0;
                end
                // Move tile down
                else if (active) begin
                    // Detect when leaving the hit zone
                    if (was_in_zone && !in_hit_zone) begin
                        // Check if button was held at any point in lower half
                        if (was_held_in_lower_half) begin
                            hit_pulse <= 1;  // Success!
                        end else begin
                            miss_pulse <= 1;  // Failed
                        end
                        active <= 0;
                        was_in_zone <= 0;
                        was_held_in_lower_half <= 0;
                    end
                    else begin
                        // Only move if still active
                        tile_y <= tile_y + FALL_SPEED;
                        
                        // Track if tile is currently in the hit zone
                        if (in_hit_zone)
                            was_in_zone <= 1;
                        
                        // Reset when off screen
                        if (tile_y >= SCREEN_HEIGHT) begin
                            active <= 0;
                            was_in_zone <= 0;
                            was_held_in_lower_half <= 0;
                        end
                    end
                end
            end
        end
    end
    
    // Pixel rendering
    wire in_column = (pixel_x >= col_x_start) && (pixel_x < col_x_end);
    wire in_tile = (pixel_y >= tile_y) && (pixel_y < tile_y + TILE_HEIGHT);
    assign pixel_on = active && in_column && in_tile;
    
endmodule