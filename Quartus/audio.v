module audio(
    input CLOCK_50,
    input reset_n,
    input [3:0] buttons,        // 4 buttons for 4 columns (active high)
    output AUD_ADCDAT,
    inout AUD_BCLK,
    inout AUD_ADCLRCK,
    inout AUD_DACLRCK,
    output AUD_DACDAT,
    output AUD_XCK,
    inout FPGA_I2C_SDAT,
    output FPGA_I2C_SCLK
);

    // Audio clock generation (18.432 MHz for audio codec)
    wire audio_clk;
    audio_pll pll_inst(
        .refclk(CLOCK_50),
        .rst(~reset_n),
        .outclk_0(audio_clk)
    );

    assign AUD_XCK = audio_clk;

    // Key synchronization
    reg [3:0] button_reg1, button_reg2;
    wire [3:0] button_sync;
    
    always @(posedge CLOCK_50) begin
        button_reg1 <= buttons;
        button_reg2 <= button_reg1;
    end
    
    assign button_sync = button_reg2;

    // Note selection based on buttons
    // Button[3] (KEY3) = Leftmost Column = C4 (lowest)
    // Button[2] (KEY2) = E4
    // Button[1] (KEY1) = G4
    // Button[0] (KEY0) = Rightmost Column = C5 (highest)
    reg [1:0] note_sel;
    wire any_button_pressed;
    
    assign any_button_pressed = |button_sync;
    
    // Priority encoder for note selection
    always @(*) begin
        casex(button_sync)
            4'b1xxx: note_sel = 2'b00; // Button 3 - C4 (leftmost/lowest)
            4'b01xx: note_sel = 2'b01; // Button 2 - E4
            4'b001x: note_sel = 2'b10; // Button 1 - G4
            4'b0001: note_sel = 2'b11; // Button 0 - C5 (rightmost/highest)
            default: note_sel = 2'b00;
        endcase
    end

    // Tone generator
    reg [31:0] tone_counter;
    reg [31:0] tone_period;
    reg tone_out;
    
    // Set tone periods for each note
    always @(*) begin
        case(note_sel)
			2'b00: tone_period = 32'd75844;  // E4
            2'b01: tone_period = 32'd60199;  // G#4
            2'b10: tone_period = 32'd50621;  // B4
            2'b11: tone_period = 32'd45097;  // C#5
        endcase
    end
    
    // Generate square wave tone
    always @(posedge CLOCK_50 or negedge reset_n) begin
        if (~reset_n) begin
            tone_counter <= 32'd0;
            tone_out <= 1'b0;
        end else if (any_button_pressed) begin
            if (tone_counter >= tone_period) begin
                tone_counter <= 32'd0;
                tone_out <= ~tone_out;
            end else begin
                tone_counter <= tone_counter + 1'd1;
            end
        end else begin
            tone_counter <= 32'd0;
            tone_out <= 1'b0;
        end
    end
    wire signed [15:0] audio_sample;
    assign audio_sample = any_button_pressed ? (tone_out ? 16'h4000 : 16'hC000) : 16'h0000;

    // Audio codec interface
    wire aud_init_done;
    
    audio_and_video_config cfg_inst(
        .clk(CLOCK_50),
        .reset(~reset_n),
        .I2C_SDAT(FPGA_I2C_SDAT),
        .I2C_SCLK(FPGA_I2C_SCLK),
        .init_done(aud_init_done)
    );

    audio_codec codec_inst(
        .clk(CLOCK_50),
        .reset(~reset_n),
        .audio_sample(audio_sample),
        .AUD_BCLK(AUD_BCLK),
        .AUD_DACLRCK(AUD_DACLRCK),
        .AUD_DACDAT(AUD_DACDAT)
    );

endmodule

// Audio PLL module
module audio_pll(
    input refclk,
    input rst,
    output outclk_0
);
    // Generate this using Quartus IP Catalog (ALTPLL)
    // Input: 50 MHz, Output: 18.432 MHz
    assign outclk_0 = refclk; // Placeholder
endmodule

// I2C Controller for WM8731 Configuration
module audio_and_video_config(
    input clk,
    input reset,
    inout I2C_SDAT,
    output I2C_SCLK,
    output init_done
);

    parameter CLK_FREQ = 50000000;
    parameter I2C_FREQ = 20000;
    
    reg [15:0] clk_div;
    reg i2c_clk;
    
    // Generate I2C clock (20 kHz)
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            clk_div <= 16'd0;
            i2c_clk <= 1'b0;
        end else begin
            if (clk_div >= (CLK_FREQ / (I2C_FREQ * 2) - 1)) begin
                clk_div <= 16'd0;
                i2c_clk <= ~i2c_clk;
            end else begin
                clk_div <= clk_div + 1'd1;
            end
        end
    end

    // I2C state machine
    localparam IDLE = 0, START = 1, ADDR = 2, WRITE = 3, ACK = 4, STOP = 5, DONE = 6;
    reg [3:0] state;
    reg [4:0] bit_count;
    reg [7:0] reg_count;
    reg sda_out;
    reg sda_oe;
    
    assign I2C_SDAT = sda_oe ? sda_out : 1'bz;
    assign I2C_SCLK = (state == IDLE || state == DONE) ? 1'b1 : i2c_clk;
    assign init_done = (state == DONE);

    // WM8731 Configuration data
    reg [15:0] config_data;
    wire [6:0] device_addr = 7'h34;
    
    always @(*) begin
        case(reg_count)
            8'd0:  config_data = 16'h0C17; // Reset
            8'd1:  config_data = 16'h0817; // Left line in
            8'd2:  config_data = 16'h0A17; // Right line in
            8'd3:  config_data = 16'h0E79; // Left headphone out
            8'd4:  config_data = 16'h1079; // Right headphone out
            8'd5:  config_data = 16'h1212; // Analog audio path
            8'd6:  config_data = 16'h1400; // Digital audio path
            8'd7:  config_data = 16'h1602; // Power management
            8'd8:  config_data = 16'h1842; // Digital interface format (I2S)
            8'd9:  config_data = 16'h1A00; // Sampling rate (48kHz)
            8'd10: config_data = 16'h1C01; // Active control
            default: config_data = 16'h0000;
        endcase
    end

    reg [23:0] shift_reg;
    reg [1:0] i2c_clk_prev;
    wire i2c_clk_posedge = (i2c_clk_prev == 2'b01);
    wire i2c_clk_negedge = (i2c_clk_prev == 2'b10);

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state <= IDLE;
            bit_count <= 5'd0;
            reg_count <= 8'd0;
            sda_out <= 1'b1;
            sda_oe <= 1'b0;
            shift_reg <= 24'd0;
            i2c_clk_prev <= 2'b11;
        end else begin
            i2c_clk_prev <= {i2c_clk_prev[0], i2c_clk};
            
            case(state)
                IDLE: begin
                    if (reg_count < 11) begin
                        state <= START;
                        shift_reg <= {device_addr, 1'b0, config_data};
                        bit_count <= 5'd0;
                    end else begin
                        state <= DONE;
                    end
                end
                
                START: begin
                    if (i2c_clk_negedge) begin
                        sda_oe <= 1'b1;
                        sda_out <= 1'b0; // Start condition
                        state <= ADDR;
                    end
                end
                
                ADDR, WRITE: begin
                    if (i2c_clk_negedge) begin
                        if (bit_count < 24) begin
                            sda_out <= shift_reg[23];
                            shift_reg <= {shift_reg[22:0], 1'b0};
                            bit_count <= bit_count + 1'd1;
                            if (bit_count == 7 || bit_count == 15 || bit_count == 23) begin
                                state <= ACK;
                            end else begin
                                state <= (bit_count < 8) ? ADDR : WRITE;
                            end
                        end
                    end
                end
                
                ACK: begin
                    if (i2c_clk_negedge) begin
                        sda_oe <= 1'b0; // Release SDA for ACK
                    end else if (i2c_clk_posedge) begin
                        if (bit_count == 24) begin
                            state <= STOP;
                        end else begin
                            state <= WRITE;
                        end
                    end
                end
                
                STOP: begin
                    if (i2c_clk_negedge) begin
                        sda_oe <= 1'b1;
                        sda_out <= 1'b0;
                    end else if (i2c_clk_posedge) begin
                        sda_out <= 1'b1; // Stop condition
                        reg_count <= reg_count + 1'd1;
                        state <= IDLE;
                    end
                end
                
                DONE: begin
                    sda_oe <= 1'b0;
                    sda_out <= 1'b1;
                end
            endcase
        end
    end

endmodule

// I2S Audio Codec Interface
module audio_codec(
    input clk,
    input reset,
    input signed [15:0] audio_sample,
    inout AUD_BCLK,
    inout AUD_DACLRCK,
    output reg AUD_DACDAT
);

    // Generate bit clock and LR clock
    reg [9:0] bclk_count;
    reg bclk;
    reg lrclk;
    
    // Generate BCLK (bit clock) - approximately 1.536 MHz
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            bclk_count <= 10'd0;
            bclk <= 1'b0;
        end else begin
            if (bclk_count >= 10'd16) begin // 50MHz / 32 ≈ 1.5625 MHz
                bclk_count <= 10'd0;
                bclk <= ~bclk;
            end else begin
                bclk_count <= bclk_count + 1'd1;
            end
        end
    end
    
    assign AUD_BCLK = bclk;
    
    // Generate LRCLK (left/right clock) - 48 kHz
    reg [5:0] bit_counter;
    
    always @(posedge bclk or posedge reset) begin
        if (reset) begin
            bit_counter <= 6'd0;
            lrclk <= 1'b0;
        end else begin
            if (bit_counter >= 6'd31) begin
                bit_counter <= 6'd0;
                lrclk <= ~lrclk;
            end else begin
                bit_counter <= bit_counter + 1'd1;
            end
        end
    end
    
    assign AUD_DACLRCK = lrclk;
    
    // Shift out audio data
    reg [15:0] shift_data;
    reg [4:0] shift_count;
    
    always @(negedge bclk or posedge reset) begin
        if (reset) begin
            AUD_DACDAT <= 1'b0;
            shift_data <= 16'd0;
            shift_count <= 5'd0;
        end else begin
            if (bit_counter == 6'd0) begin
                shift_data <= audio_sample;
                shift_count <= 5'd0;
            end
            
            if (shift_count < 5'd16) begin
                AUD_DACDAT <= shift_data[15];
                shift_data <= {shift_data[14:0], 1'b0};
                shift_count <= shift_count + 1'd1;
            end else begin
                AUD_DACDAT <= 1'b0;
            end
        end
    end

endmodule
