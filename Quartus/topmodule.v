module topmodule(
	input clk,
	input rst,
	input start_btn,
	input select_btn,
	input up_btn,
	input down_btn,
	input [3:0] lane_btn,
	
	output hsync,
	output vsync,
	output [3:0] vga_r,
	output [3:0] vga_g,
	output [3:0] vga_b
);
	
	//FSM GAME STATES
	localparam START = 3'd0;
	localparam SELECT = 3'd1;
	localparam GAME = 3'd2;
	localparam GAME_OVER = 3'd3;
	
	//DEFINE STATE REGISTERS
	reg[2:0] state;
	reg[2:0] next;
	
	
	always@(posedge clk or negedge rst) begin
		if (rst)
			state <= START;
		else
			state <= next;
	end
	
	
	
	

endmodule