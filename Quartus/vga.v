module vga_controller(
    input clk,              // 25 MHz pixel clock
    input reset_n,          // Active low reset
    output reg hsync,       // Horizontal sync
    output reg vsync,       // Vertical sync
    output video_on,        // Video on signal
    output [9:0] x,         // X coordinate
    output [9:0] y          // Y coordinate
);

    // VGA timing constants
    parameter H_DISPLAY = 640;
    parameter H_FRONT = 16;
    parameter H_SYNC = 96;
    parameter H_BACK = 48;
    parameter H_TOTAL = 800;
    
    parameter V_DISPLAY = 480;
    parameter V_FRONT = 10;
    parameter V_SYNC = 2;
    parameter V_BACK = 33;
    parameter V_TOTAL = 525;
    
    // Counters
    reg [9:0] h_count;
    reg [9:0] v_count;
    
    // Horizontal counter
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n)
            h_count <= 0;
        else if (h_count == H_TOTAL - 1)
            h_count <= 0;
        else
            h_count <= h_count + 1;
    end
    
    // Vertical counter
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n)
            v_count <= 0;
        else if (h_count == H_TOTAL - 1) begin
            if (v_count == V_TOTAL - 1)
                v_count <= 0;
            else
                v_count <= v_count + 1;
        end
    end
    
    // Sync signals
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            hsync <= 1;
            vsync <= 1;
        end
        else begin
            hsync <= (h_count >= (H_DISPLAY + H_FRONT)) && 
                     (h_count < (H_DISPLAY + H_FRONT + H_SYNC));
            vsync <= (v_count >= (V_DISPLAY + V_FRONT)) && 
                     (v_count < (V_DISPLAY + V_FRONT + V_SYNC));
        end
    end
    
    // Video on and pixel coordinates
    assign video_on = (h_count < H_DISPLAY) && (v_count < V_DISPLAY);
    assign x = (h_count < H_DISPLAY) ? h_count : 10'd0;
    assign y = (v_count < V_DISPLAY) ? v_count : 10'd0;
    
endmodule

