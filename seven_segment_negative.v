module seven_segment_negative(
    input is_neg,
    output reg [6:0] seg
);

always @(*) begin
    if (is_neg)
        seg = 7'b0111111;
    else
        seg = 7'b1111111;
end

endmodule
