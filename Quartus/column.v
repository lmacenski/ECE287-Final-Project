// column.v - Single column that manages one tile with miss detection
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
    
    // Check if tile is in hit zone (based on BOTTOM of tile)
    wire [9:0] tile_bottom = tile_y + TILE_HEIGHT;
    assign in_hit_zone = active && 
                         tile_bottom >= (SCREEN_HEIGHT - TILE_HEIGHT - 20) &&
                         tile_bottom <= (SCREEN_HEIGHT - TILE_HEIGHT + 20);
    
    // Detect miss - tile goes past the hit zone without being hit
    reg was_in_zone;
    reg miss_detected;
    assign miss = miss_detected;
    
    // Tile logic
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            tile_y <= 10'd0;
            active <= 0;
            was_in_zone <= 0;
            miss_detected <= 0;
        end
        else if (frame_tick) begin
            // Clear miss signal after one frame
            miss_detected <= 0;
            
            // Spawn new tile
            if (spawn && !active) begin
                tile_y <= 10'd0;
                active <= 1;
                was_in_zone <= 0;
            end
            // Move tile down
            else if (active) begin
                tile_y <= tile_y + FALL_SPEED;
                
                // Detect the moment we leave the hit zone after being in it
                if (was_in_zone && !in_hit_zone) begin
                    miss_detected <= 1;  // Trigger miss for one frame only
                end
                
                // Track if tile is currently in the hit zone
                if (in_hit_zone)
                    was_in_zone <= 1;
                
                // Reset when off screen
                if (tile_y >= SCREEN_HEIGHT) begin
                    active <= 0;
                    was_in_zone <= 0;
                end
            end
            
            // Handle button press (successful hit)
            if (button_press && in_hit_zone) begin
                active <= 0;
                was_in_zone <= 0;
            end
        end
    end
    
    // Hit detection
    assign hit = button_press && in_hit_zone;
    
    // Pixel rendering
    wire in_column = (pixel_x >= col_x_start) && (pixel_x < col_x_end);
    wire in_tile = (pixel_y >= tile_y) && (pixel_y < tile_y + TILE_HEIGHT);
    assign pixel_on = active && in_column && in_tile;
    
endmodule